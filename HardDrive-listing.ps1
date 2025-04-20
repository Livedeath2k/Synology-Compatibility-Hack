<#
.SYNOPSIS
Connects via SSH to a Synology NAS, reads the model numbers
of the installed hard drives, and saves the list to a file.

.DESCRIPTION
This script uses the built-in Windows OpenSSH client (ssh.exe)
to establish a connection to a specified Synology NAS. It executes a
command on the NAS that reads the model information for SATA and NVMe drives
from the /sys filesystem. The output is collected and written to the file
C:\Temp\Listing.txt on the local Windows machine.
The C:\Temp directory will be created if it doesn't exist.

.NOTES
- Ensure that the OpenSSH Client is installed on your Windows system
  (Default in recent Windows 10/11 versions). Check under
  Settings > Apps > Optional features.
- The SSH service must be enabled on the Synology NAS (Control Panel > Terminal & SNMP).
- You will be prompted for the SSH password for the NAS user during script execution.
- Password input happens directly in the PowerShell window and is invisible.

.PARAMETER NasUser
The username for the SSH login on the Synology NAS (must be part of the 'administrators' group).

.PARAMETER NasHost
The IP address or hostname of the Synology NAS.

.EXAMPLE
.\Get-SynologyDiskModels.ps1 -NasUser "admin" -NasHost "192.168.1.100"

.EXAMPLE
.\Get-SynologyDiskModels.ps1 -NasUser "myAdmin" -NasHost "diskstation.local"
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$NasUser,

    [Parameter(Mandatory=$true)]
    [string]$NasHost
)

# --- Configuration ---
$outputFile = "C:\Temp\Listing.txt" # Target file on the local Windows machine

# The command executed on the Synology NAS to read disk models
$remoteCommand = 'for f in /sys/block/sd*/device/model /sys/block/nvme*n*/device/model; do if [ -f "$f" ]; then printf "%s: %s\n" "$(basename $(dirname $(dirname $f)))" "$(cat "$f")"; fi; done 2>/dev/null'

# --- Script Logic ---

# Ensure the target directory exists
$outputDir = Split-Path -Path $outputFile -Parent
if (-not (Test-Path -Path $outputDir -PathType Container)) {
    Write-Host "Creating directory: $outputDir"
    try {
        New-Item -ItemType Directory -Path $outputDir -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "Error creating directory '$outputDir'. Stopping script."
        Write-Error $_.Exception.Message
        exit 1 # Stop script
    }
}

Write-Host "Attempting SSH connection to '$NasHost' as user '$NasUser'..."
Write-Host "You might be prompted for the password."
Write-Host "The following command will be executed on the NAS: $remoteCommand"

# Execute SSH command and collect output
# ssh.exe is called directly. The password prompt will be interactive in the terminal.
# -T disables pseudo-terminal allocation, which is recommended for non-interactive commands.
try {
    # Execute ssh.exe and redirect standard output and standard error.
    # Important: Errors from ssh.exe (e.g., connection errors, authentication failures)
    # often go to the error stream (stderr), not as PowerShell exceptions.
    $sshProcess = Start-Process ssh.exe -ArgumentList "$($NasUser)@$($NasHost)", "-T", $remoteCommand -NoNewWindow -PassThru -RedirectStandardOutput "$outputFile.tmp" -RedirectStandardError "$outputFile.err.tmp"
    $sshProcess | Wait-Process

    # Check the exit code of ssh.exe
    if ($sshProcess.ExitCode -ne 0) {
        Write-Warning "ssh.exe finished with Exit Code $($sshProcess.ExitCode). An error might have occurred."
        if (Test-Path "$outputFile.err.tmp") {
            $sshError = Get-Content "$outputFile.err.tmp" -Raw
            if ($sshError) {
                Write-Warning "SSH Error Messages:"
                Write-Warning $sshError
            }
        }
         Write-Warning "Check hostname/IP, username, password, and if SSH is enabled on the NAS."
         # Partial output might exist despite the error, we still try to process it.
    }

    # Read the temporary output file
    if (Test-Path "$outputFile.tmp") {
        $sshOutput = Get-Content "$outputFile.tmp" -Raw
    } else {
        $sshOutput = $null
    }

} catch {
    # Mainly catches PowerShell errors when *starting* ssh.exe
    Write-Error "Error executing ssh.exe:"
    Write-Error $_.Exception.Message
    # Remove temporary files on severe error
    if (Test-Path "$outputFile.tmp") { Remove-Item "$outputFile.tmp" -Force }
    if (Test-Path "$outputFile.err.tmp") { Remove-Item "$outputFile.err.tmp" -Force }
    exit 1 # Stop script
}

# Check if output exists and write to the target file
if ($sshOutput -ne $null -and $sshOutput.Trim().Length -gt 0) {
    Write-Host "SSH command executed successfully. Writing output to '$outputFile'..."
    try {
        # Write the content to the final file (overwrites if it exists)
        Set-Content -Path $outputFile -Value $sshOutput -Encoding UTF8 -Force -ErrorAction Stop
        Write-Host "Script completed successfully. Results saved in '$outputFile'."
    } catch {
        Write-Error "Error writing the output file '$outputFile'."
        Write-Error $_.Exception.Message
    }
} else {
    # If ssh was successful (ExitCode 0) but returned no output (e.g., no disks found)
    if ($sshProcess.ExitCode -eq 0) {
         Write-Warning "The SSH command executed but returned no disk models."
         Write-Warning "Perhaps there are no supported drives (/dev/sd* or /dev/nvme*) or the command found no models."
         # Write a message to the file to reflect the result
         Set-Content -Path $outputFile -Value "No disk models found." -Encoding UTF8 -Force
    } else {
        # If ssh failed AND returned no output
         Write-Error "No output received from SSH command AND ssh.exe reported an error (see messages above)."
         Write-Error "The file '$outputFile' was not created or might be incomplete."
    }
}

# Cleaning up temporary files
if (Test-Path "$outputFile.tmp") { Remove-Item "$outputFile.tmp" -Force }
if (Test-Path "$outputFile.err.tmp") { Remove-Item "$outputFile.err.tmp" -Force }