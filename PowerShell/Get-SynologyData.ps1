<#
.SYNOPSIS
Connects via SSH to a Synology NAS, reads installed hard drive model numbers,
retrieves the NAS model name, and attempts to download the corresponding
disk compatibility database file.

.DESCRIPTION
This script uses the built-in Windows OpenSSH client (ssh.exe and scp.exe)
to connect to a specified Synology NAS.
1. It executes a command on the NAS to read model information for SATA/NVMe drives.
2. It retrieves the NAS model identifier (e.g., DS920+).
3. It attempts to download the disk compatibility file '/var/lib/disk-compatibility/<NASModel>_host_v7.db'
   from the NAS to the local 'C:\Temp\' directory.
The drive list output is saved to 'C:\Temp\Listing.txt'.
The C:\Temp directory will be created if it doesn't exist.

.NOTES
- Ensure OpenSSH Client (including ssh.exe and scp.exe) is installed on Windows
  (Settings > Apps > Optional features).
- SSH service must be enabled on the Synology NAS (Control Panel > Terminal & SNMP).
- You will be prompted for the SSH password for the NAS user.
- Password input is invisible in the PowerShell window.
- Downloading the database file from '/var/lib/disk-compatibility/' may require root privileges
  on the NAS, which the specified user might not have. Download may fail due to permissions.

.PARAMETER NasUser
The username for the SSH login on the Synology NAS (must be part of the 'administrators' group).

.PARAMETER NasHost
The IP address or hostname of the Synology NAS.

.EXAMPLE
.\Get-SynologyData.ps1 -NasUser "admin" -NasHost "192.168.1.100"

.EXAMPLE
.\Get-SynologyData.ps1 -NasUser "myAdmin" -NasHost "diskstation.local"
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$NasUser,

    [Parameter(Mandatory=$true)]
    [string]$NasHost
)

# --- Configuration ---
$outputDir = "C:\Temp"                       # Local output directory
$diskListFile = Join-Path $outputDir "Listing.txt" # Target file for disk models on local Windows machine

# Temporary file base names (extensions added dynamically)
$tempFileBase = Join-Path $outputDir "syno_script_temp_$(Get-Date -Format 'yyyyMMddHHmmss')"
$tempFileDiskOutput = "$($tempFileBase)_disks.tmp"
$tempFileModelOutput = "$($tempFileBase)_model.tmp"
$tempFileErrorOutput = "$($tempFileBase)_error.tmp" # Common error file

# Commands executed on the NAS
$getDiskModelsCommand = 'for f in /sys/block/sd*/device/model /sys/block/nvme*n*/device/model; do if [ -f "$f" ]; then printf "%s: %s\n" "$(basename $(dirname $(dirname $f)))" "$(cat "$f")"; fi; done 2>/dev/null'
$getModelCommand = "awk -F'\"' '/^unique=/ {print \$2}' /etc.defaults/synoinfo.conf" # Get 'unique' identifier (often the model)

# --- Script Logic ---

# Ensure the target directory exists
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

# --- 1. Get Disk Drive Models ---
Write-Host "Attempting SSH connection to '$NasHost' as user '$NasUser' to get disk models..."
Write-Host "You might be prompted for the password now."
Write-Host "Executing on NAS: $getDiskModelsCommand"

$diskModelsOutput = $null
$sshProcessDisks = $null
try {
    $sshProcessDisks = Start-Process ssh.exe -ArgumentList "$($NasUser)@$($NasHost)", "-T", $getDiskModelsCommand -NoNewWindow -PassThru -RedirectStandardOutput $tempFileDiskOutput -RedirectStandardError $tempFileErrorOutput
    $sshProcessDisks | Wait-Process

    if ($sshProcessDisks.ExitCode -ne 0) {
        Write-Warning "ssh.exe (get disk models) finished with Exit Code $($sshProcessDisks.ExitCode). An error might have occurred."
        if (Test-Path $tempFileErrorOutput) { Write-Warning "SSH Error Messages:" ; Write-Warning (Get-Content $tempFileErrorOutput -Raw) }
    }

    if (Test-Path $tempFileDiskOutput) {
        $diskModelsOutput = Get-Content $tempFileDiskOutput -Raw
    }

} catch {
    Write-Error "Error executing ssh.exe to get disk models:"
    Write-Error $_.Exception.Message
}

# Write Disk Models to File (even if subsequent steps fail)
if ($diskModelsOutput -ne $null -and $diskModelsOutput.Trim().Length -gt 0) {
    Write-Host "Writing disk model output to '$diskListFile'..."
    try {
        Set-Content -Path $diskListFile -Value $diskModelsOutput -Encoding UTF8 -Force -ErrorAction Stop
        Write-Host "Disk models saved."
    } catch {
        Write-Error "Error writing the disk model file '$diskListFile'."
        Write-Error $_.Exception.Message
    }
} else {
    if ($sshProcessDisks -and $sshProcessDisks.ExitCode -eq 0) {
        Write-Warning "The SSH command for disk models executed but returned no output."
        Set-Content -Path $diskListFile -Value "No disk models found via SSH command." -Encoding UTF8 -Force
    } else {
        Write-Error "Failed to retrieve disk models via SSH (see errors above)."
        Set-Content -Path $diskListFile -Value "Failed to retrieve disk models via SSH." -Encoding UTF8 -Force
    }
}
# Clear previous error file content before next command reusing it
if (Test-Path $tempFileErrorOutput) { Clear-Content $tempFileErrorOutput }


# --- 2. Get NAS Model ---
Write-Host "Attempting to retrieve NAS model from $NasHost..."
Write-Host "Executing on NAS: $getModelCommand"

$nasModel = $null
$sshProcessModel = $null
try {
    # May require password again if connection caching isn't active/working
    $sshProcessModel = Start-Process ssh.exe -ArgumentList "$($NasUser)@$($NasHost)", "-T", $getModelCommand -NoNewWindow -PassThru -RedirectStandardOutput $tempFileModelOutput -RedirectStandardError $tempFileErrorOutput
    $sshProcessModel | Wait-Process

    if ($sshProcessModel.ExitCode -ne 0) {
         Write-Warning "ssh.exe (get model) finished with Exit Code $($sshProcessModel.ExitCode)."
         if (Test-Path $tempFileErrorOutput) { Write-Warning "SSH Error Messages:" ; Write-Warning (Get-Content $tempFileErrorOutput -Raw) }
    } else {
         if (Test-Path $tempFileModelOutput) {
             $nasModel = (Get-Content $tempFileModelOutput -Raw).Trim()
             if ($nasModel) {
                 Write-Host "Detected NAS Model: $nasModel"
             } else {
                 Write-Warning "Could not determine NAS model from command output (Command returned empty)."
             }
         } else {
             Write-Warning "Could not determine NAS model (Output file not created)."
         }
    }
} catch {
    Write-Error "Error executing ssh.exe to get NAS model: $_"
}
# Clear previous error file content before next command reusing it
if (Test-Path $tempFileErrorOutput) { Clear-Content $tempFileErrorOutput }


# --- 3. Download Compatibility DB File ---
if ($nasModel) {
    $remoteDbFileName = "$($nasModel)_host_v7.db"
    $remoteDbFullPath = "/var/lib/disk-compatibility/$remoteDbFileName" # Path on the NAS
    $localDbPath = Join-Path $outputDir $remoteDbFileName # Local destination path (in C:\Temp)

    Write-Host "Attempting to download '$remoteDbFullPath' to '$localDbPath' using scp..."
    Write-Warning "Note: Downloading this file may fail due to NAS permission restrictions."

    $scpProcess = $null
    try {
        # Arguments for scp.exe: user@host:remotePath localPath
        $scpArgs = @(
            "-T", # Disable pseudo-terminal
            "$($NasUser)@$($NasHost):$remoteDbFullPath", # Remote source
            "$localDbPath" # Local destination
        )
        # Execute scp.exe
        $scpProcess = Start-Process scp.exe -ArgumentList $scpArgs -NoNewWindow -PassThru -Wait -RedirectStandardError $tempFileErrorOutput

        # Check scp exit code
        if ($scpProcess.ExitCode -eq 0) {
            Write-Host "Successfully downloaded '$remoteDbFileName' to '$localDbPath'."
        } else {
            Write-Error "scp.exe failed with Exit Code $($scpProcess.ExitCode). File download likely failed."
            if (Test-Path $tempFileErrorOutput) {
                 $scpError = Get-Content $tempFileErrorOutput -Raw
                 if ($scpError) { Write-Error "SCP Error Message: $scpError" }
                 # Check specifically for permission denied error
                 if ($scpError -match 'permission denied' -or $scpError -match 'scp:') {
                    Write-Error "This often indicates the user '$NasUser' lacks permissions to read '$remoteDbFullPath' on the NAS."
                 }
            }
            # Clean up potentially incomplete downloaded file if scp failed
            if (Test-Path $localDbPath) { Remove-Item $localDbPath -Force -ErrorAction SilentlyContinue }
        }
    } catch {
        Write-Error "Error executing scp.exe: $_"
        # Clean up potentially incomplete downloaded file if exception occurred
        if (Test-Path $localDbPath) { Remove-Item $localDbPath -Force -ErrorAction SilentlyContinue }
    }
} else {
     Write-Warning "Skipping database download because NAS model could not be determined."
}


# --- Final Cleanup ---
Write-Host "Cleaning up temporary files..."
if (Test-Path $tempFileDiskOutput) { Remove-Item $tempFileDiskOutput -Force -ErrorAction SilentlyContinue }
if (Test-Path $tempFileModelOutput) { Remove-Item $tempFileModelOutput -Force -ErrorAction SilentlyContinue }
if (Test-Path $tempFileErrorOutput) { Remove-Item $tempFileErrorOutput -Force -ErrorAction SilentlyContinue }

Write-Host "Script finished."
