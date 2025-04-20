<#
.SYNOPSIS
Uploads a specified disk compatibility database file (.db) from the local C:\Temp
directory to /var/lib/disk-compatibility/ on a Synology NAS, using sudo for the final placement.

.DESCRIPTION
This script performs a two-step operation to upload a database file to a privileged location on a Synology NAS:
1. Uploads the specified local .db file to the NAS user's home directory using SCP.
2. Connects via SSH (using -t for interactivity) and executes 'sudo mv' to move the file
   from the home directory to the final destination '/var/lib/disk-compatibility/'.

.NOTES
- Requires Windows OpenSSH Client (ssh.exe, scp.exe) to be installed and in PATH.
- SSH service must be enabled on the Synology NAS.
- The specified NAS user MUST have sudo privileges configured on the NAS.
- You will be prompted for the SSH password and likely the sudo password during execution.
- The sudo password prompt requires interaction in the PowerShell window where the script is run.
- If the 'sudo mv' step fails, the file may remain in the user's home directory on the NAS.

.PARAMETER NasUser
The username for SSH/sudo on the Synology NAS (must have sudo rights).

.PARAMETER NasHost
The IP address or hostname of the Synology NAS.

.PARAMETER DbFileName
The exact filename of the .db file located in C:\Temp to be uploaded (e.g., "DS920+_host_v7.db").

.EXAMPLE
.\Upload-SynologyDb.ps1 -NasUser "admin" -NasHost "192.168.1.100" -DbFileName "DS920+_host_v7.db"

.EXAMPLE
.\Upload-SynologyDb.ps1 -NasUser "mySudoAdmin" -NasHost "diskstation.local" -DbFileName "RS1221+_host_v7.db"
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$NasUser,

    [Parameter(Mandatory=$true)]
    [string]$NasHost,

    [Parameter(Mandatory=$true)]
    [string]$DbFileName
)

# --- Configuration ---
$LocalPathBase = "C:\Temp"
$localDbFullPath = Join-Path $LocalPathBase $DbFileName

# Remote paths on the NAS
$remoteTempDir = "~" # User's home directory (default temporary location)
$remoteTempPath = "$remoteTempDir/$DbFileName" # Using / for remote path, assumes simple filename
$remoteFinalDir = "/var/lib/disk-compatibility"
$remoteFinalPath = "$remoteFinalDir/$DbFileName"

# Temporary file for SCP errors
$tempErrorFile = Join-Path $LocalPathBase "upload_script_error_$(Get-Date -Format 'yyyyMMddHHmmss').tmp"

# --- Input Validation ---
if (-not (Test-Path $localDbFullPath -PathType Leaf)) {
    Write-Error "Local database file not found: '$localDbFullPath'. Please ensure the file exists in '$LocalPathBase'."
    exit 1
}
# Basic check on filename format
if ($DbFileName -notlike '*.db') {
     Write-Warning "Filename '$DbFileName' does not end with '.db'. Ensure this is the correct file."
}

# --- Stage 1: Upload file to temporary location using SCP ---
Write-Host "Stage 1: Attempting to upload '$localDbFullPath' to temporary location '$NasHost:$remoteTempPath'..."
Write-Host "You might be prompted for the SSH password for '$NasUser'."

$scpProcess = $null
$uploadSuccess = $false
try {
     $scpArgs = @(
         "-T", # Disable pseudo-terminal for non-interactive scp
         $localDbFullPath, # Source (Local)
         "$($NasUser)@$($NasHost):$remoteTempPath" # Destination (Remote Temp in home dir)
     )
    $scpProcess = Start-Process scp.exe -ArgumentList $scpArgs -NoNewWindow -PassThru -Wait -RedirectStandardError $tempErrorFile

    if ($scpProcess.ExitCode -eq 0) {
         Write-Host "[SUCCESS] File successfully uploaded to temporary location on NAS."
         $uploadSuccess = $true
    } else {
         Write-Error "[FAILED] scp.exe failed with Exit Code $($scpProcess.ExitCode). Upload failed."
         if (Test-Path $tempErrorFile) { Write-Error "SCP Error Message: $(Get-Content $tempErrorFile -Raw)" }
    }
} catch {
     Write-Error "[FAILED] Error executing scp.exe: $_"
} finally {
    # Clean up SCP error file
    if (Test-Path $tempErrorFile) { Remove-Item $tempErrorFile -Force }
}

# Exit script if upload failed
if (-not $uploadSuccess) {
    Write-Error "Aborting script because the initial file upload failed."
    exit 1
}

# --- Stage 2: Move file on NAS using 'sudo mv' via SSH ---
Write-Host "Stage 2: Attempting to move file on NAS using sudo: '$remoteTempPath' -> '$remoteFinalPath'"
Write-Warning "IMPORTANT: This step requires an interactive terminal for the 'sudo' password prompt."
Write-Warning "You will likely be prompted for the SSH password for '$NasUser' (if not cached) AND THEN the 'sudo' password."

# Construct the remote command. Using single quotes handles most standard cases.
$remoteMoveCommand = "sudo mv -f '$remoteTempPath' '$remoteFinalPath'"

Write-Host "Executing on NAS via interactive SSH: $remoteMoveCommand"
$sshMoveProcess = $null
$moveSuccess = $false
try {
     # CRITICAL: Use -t to force pseudo-terminal allocation for sudo password prompt
     # DO NOT redirect StandardInput/Output/Error when using -t for interactive sudo
     $sshArgs = @(
         "-t", # FORCE pseudo-terminal
         "$($NasUser)@$($NasHost)",
         $remoteMoveCommand
     )
    # Start the process and wait for it to complete. Interaction happens in the current window.
    $sshMoveProcess = Start-Process ssh.exe -ArgumentList $sshArgs -NoNewWindow -PassThru -Wait

    # Check exit code AFTER the process finishes.
    if ($sshMoveProcess.ExitCode -eq 0) {
         Write-Host "[SUCCESS] File successfully moved to final destination '$remoteFinalPath' on NAS using sudo."
         $moveSuccess = $true
    } else {
         # Exit code might be non-zero due to sudo failure OR mv failure
         Write-Error "[FAILED] ssh.exe (sudo mv) failed with Exit Code $($sshMoveProcess.ExitCode)."
         Write-Error "Possible reasons: Incorrect sudo password, user '$NasUser' lacks sudo rights,"
         Write-Error "permission issues writing to '$remoteFinalDir', or source file '$remoteTempPath' was not found (check Stage 1)."
         Write-Warning "The file might still be in the temporary location on the NAS: '$remoteTempPath'. Manual cleanup may be required."
    }
} catch {
     Write-Error "[FAILED] Error executing ssh.exe for sudo mv command: $_"
     Write-Warning "The file might still be in the temporary location on the NAS: '$remoteTempPath'. Manual cleanup may be required."
}

Write-Host "Script finished."

# Optional: Add check for $moveSuccess and provide final status summary
if ($moveSuccess) {
    Write-Host "Operation Complete: '$DbFileName' uploaded and moved successfully."
} else {
    Write-Error "Operation Failed: Could not move '$DbFileName' to '$remoteFinalPath'. Check errors above."
}
