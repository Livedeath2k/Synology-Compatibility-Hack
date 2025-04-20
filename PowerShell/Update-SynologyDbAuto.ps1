<#
.SYNOPSIS
Automates the process of updating the Synology disk compatibility database (.db file).
It retrieves physical disk models, downloads the current DB, adds missing physical disks
to the DB data, and uploads the modified DB back to the NAS using sudo.

.DESCRIPTION
This script performs a sequence of operations to automatically update the Synology disk compatibility database:
1. Connects via SSH to get the NAS model identifier (e.g., DS920+).
2. Connects via SSH to get the list of currently installed physical disk models (SATA/NVMe).
3. Downloads the current disk compatibility database file '/var/lib/disk-compatibility/<NASModel>_host_v7.db'
   from the NAS to the local 'C:\Temp\' directory using SCP.
4. Reads the downloaded .db file (JSON format).
5. Compares the detected physical disk models against the models listed in the .db file.
6. If any physical disk models are missing from the .db file, they are automatically added
   to the data structure with a default "support" compatibility status.
7. Saves the potentially modified data to a new local .db file in 'C:\Temp\'.
8. Uploads the modified local .db file back to the NAS user's home directory using SCP.
9. Connects via SSH (using -t for interactivity) and executes 'sudo mv' to move the uploaded file
   from the home directory to the final destination '/var/lib/disk-compatibility/', replacing the old file.

.NOTES
- Requires Windows OpenSSH Client (ssh.exe, scp.exe) to be installed and in PATH.
- SSH service must be enabled on the Synology NAS (Control Panel > Terminal & SNMP).
- The specified NAS user MUST have sudo privileges configured on the NAS for the 'mv' command.
- You will be prompted for the SSH password multiple times (unless using key-based auth) and
  likely the sudo password during execution.
- The sudo password prompt requires interaction in the PowerShell window where the script is run.
- If any critical step fails (like getting NAS model, downloading DB), the script may abort.
- If the 'sudo mv' step fails, the modified file may remain in the user's home directory on the NAS.
- Always back up original data before running potentially destructive scripts. Use with caution.

.PARAMETER NasUser
The username for SSH/sudo on the Synology NAS (must have sudo rights).

.PARAMETER NasHost
The IP address or hostname of the Synology NAS.

.PARAMETER TempPath
(Optional) The local temporary directory path. Defaults to "C:\Temp".

.EXAMPLE
.\Update-SynologyDbAuto.ps1 -NasUser "admin" -NasHost "192.168.1.100"

.EXAMPLE
.\Update-SynologyDbAuto.ps1 -NasUser "mySudoAdmin" -NasHost "diskstation.local" -TempPath "D:\SynoTemp"
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$NasUser,

    [Parameter(Mandatory=$true)]
    [string]$NasHost,

    [Parameter(Mandatory=$false)]
    [string]$TempPath = "C:\Temp"
)

# --- Configuration ---
$outputDir = $TempPath
$diskListFile = Join-Path $outputDir "DetectedDisks_Listing.txt" # File for raw disk models list
$defaultSupportEntry = @{ compatibility_interval = @( @{ compatibility = 'support' } ) } # Standard entry for new disks

# Remote paths on the NAS
$remoteDbBaseDir = "/var/lib/disk-compatibility"
$remoteHomeDir = "~" # User's home directory

# Commands executed on the NAS
$getDiskModelsCommand = 'for f in /sys/block/sd*/device/model /sys/block/nvme*n*/device/model; do if [ -f "$f" ]; then printf "%s: %s\n" "$(basename $(dirname $(dirname $f)))" "$(cat "$f")"; fi; done 2>/dev/null'
$getModelCommand = "awk -F'\"' '/^unique=/ {print \$2}' /etc.defaults/synoinfo.conf" # Get 'unique' identifier (often the model)

# --- Function to Run SSH Command and Get Output ---
function Invoke-SshCommand {
    param(
        [string]$User,
        [string]$Host,
        [string]$Command,
        [string]$Purpose # For logging
    )
    Write-Host "Attempting SSH ($Purpose) to '$Host' as '$User'..."
    Write-Host "Executing on NAS: $Command"
    $tempOutputFile = Join-Path $outputDir "ssh_output_$(Get-Date -Format 'yyyyMMddHHmmssfff').tmp"
    $tempErrorFile = Join-Path $outputDir "ssh_error_$(Get-Date -Format 'yyyyMMddHHmmssfff').tmp"
    $stdOut = $null
    $exitCode = -1

    try {
        $sshProcess = Start-Process ssh.exe -ArgumentList "$($User)@$($Host)", "-T", $Command -NoNewWindow -PassThru -RedirectStandardOutput $tempOutputFile -RedirectStandardError $tempErrorFile
        $sshProcess | Wait-Process
        $exitCode = $sshProcess.ExitCode

        if ($exitCode -ne 0) {
            Write-Warning "ssh.exe ($Purpose) finished with Exit Code $exitCode. An error might have occurred."
            if (Test-Path $tempErrorFile) {
                 $errMsg = Get-Content $tempErrorFile -Raw
                 if ($errMsg) { Write-Warning "SSH Error Messages: $errMsg" }
            }
        }

        if (Test-Path $tempOutputFile) {
            $stdOut = Get-Content $tempOutputFile -Raw
        }
    } catch {
        Write-Error "Error executing ssh.exe ($Purpose): $_"
        # Ensure exit code reflects failure
        $exitCode = -1
    } finally {
        if (Test-Path $tempOutputFile) { Remove-Item $tempOutputFile -Force -ErrorAction SilentlyContinue }
        if (Test-Path $tempErrorFile) { Remove-Item $tempErrorFile -Force -ErrorAction SilentlyContinue }
    }

    # Return both stdout and exit code
    return [PSCustomObject]@{
        StdOut   = $stdOut
        ExitCode = $exitCode
    }
}

# --- Function to Run SCP ---
function Invoke-Scp {
    param(
        [string]$User,
        [string]$Host,
        [string]$Source, # Can be local or remote path
        [string]$Destination, # Can be local or remote path
        [string]$Direction, # 'download' or 'upload'
        [string]$Purpose # For logging
    )
    Write-Host "Attempting SCP ($Purpose)..."
    Write-Host "Source: $Source"
    Write-Host "Destination: $Destination"
    $tempErrorFile = Join-Path $outputDir "scp_error_$(Get-Date -Format 'yyyyMMddHHmmssfff').tmp"
    $exitCode = -1

    # Construct arguments based on direction
    $scpArgs = @("-T") # Disable pseudo-terminal
    if ($Direction -eq 'download') {
        $scpArgs += "$($User)@$($Host):$Source", $Destination
    } elseif ($Direction -eq 'upload') {
        $scpArgs += $Source, "$($User)@$($Host):$Destination"
    } else {
        Write-Error "Invalid SCP direction specified: '$Direction'"
        return -1 # Indicate failure
    }

    try {
        $scpProcess = Start-Process scp.exe -ArgumentList $scpArgs -NoNewWindow -PassThru -Wait -RedirectStandardError $tempErrorFile
        $exitCode = $scpProcess.ExitCode

        if ($exitCode -ne 0) {
            Write-Error "scp.exe ($Purpose) failed with Exit Code $exitCode."
            if (Test-Path $tempErrorFile) {
                $scpError = Get-Content $tempErrorFile -Raw
                if ($scpError) { Write-Error "SCP Error Message: $scpError" }
                 # Check specifically for permission denied error on download
                 if ($Direction -eq 'download' -and ($scpError -match 'permission denied' -or $scpError -match 'scp:')) {
                    Write-Error "This often indicates the user '$User' lacks permissions to read '$Source' on the NAS."
                 }
            }
            # Clean up potentially incomplete downloaded file if scp download failed
            if ($Direction -eq 'download' -and (Test-Path $Destination)) { Remove-Item $Destination -Force -ErrorAction SilentlyContinue }
        } else {
            Write-Host "SCP ($Purpose) completed successfully."
        }
    } catch {
        Write-Error "Error executing scp.exe ($Purpose): $_"
        # Clean up potentially incomplete downloaded file if exception occurred during download
        if ($Direction -eq 'download' -and (Test-Path $Destination)) { Remove-Item $Destination -Force -ErrorAction SilentlyContinue }
        $exitCode = -1 # Indicate failure
    } finally {
        if (Test-Path $tempErrorFile) { Remove-Item $tempErrorFile -Force -ErrorAction SilentlyContinue }
    }
    return $exitCode
}


# --- Script Main Logic ---

# 0. Ensure Output Directory Exists
if (-not (Test-Path -Path $outputDir -PathType Container)) {
    Write-Host "Creating directory: $outputDir"
    try {
        New-Item -ItemType Directory -Path $outputDir -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "FATAL: Error creating directory '$outputDir'. Stopping script."
        Write-Error $_.Exception.Message
        exit 1 # Stop script
    }
}

# 1. Get NAS Model
$modelResult = Invoke-SshCommand -User $NasUser -Host $NasHost -Command $getModelCommand -Purpose "Get NAS Model"
if ($modelResult.ExitCode -ne 0 -or -not $modelResult.StdOut) {
    Write-Error "FATAL: Failed to retrieve NAS model. Cannot determine DB filename. Stopping script."
    exit 1
}
$nasModel = $modelResult.StdOut.Trim()
Write-Host "Detected NAS Model: $nasModel"
$remoteDbFileName = "$($nasModel)_host_v7.db"
$remoteDbFullPath = "$remoteDbBaseDir/$remoteDbFileName" # Path on the NAS
$localDbPath = Join-Path $outputDir $remoteDbFileName # Local destination path for download/modification base

# 2. Get Physical Disk Models
$disksResult = Invoke-SshCommand -User $NasUser -Host $NasHost -Command $getDiskModelsCommand -Purpose "Get Physical Disks"
$physicalDisks = @()
if ($disksResult.ExitCode -eq 0 -and $disksResult.StdOut) {
    $diskOutputLines = $disksResult.StdOut -split [System.Environment]::NewLine | Where-Object { $_ -match ':' }
    foreach ($line in $diskOutputLines) {
        $model = ($line -split ':', 2)[1].Trim()
        if ($model) {
            $physicalDisks += $model
        }
    }
    Write-Host "Detected $($physicalDisks.Count) physical disk models:"
    $physicalDisks | ForEach-Object { Write-Host "- $_" }
    # Save raw output for reference
    try { Set-Content -Path $diskListFile -Value $disksResult.StdOut -Encoding UTF8 -Force } catch {}
} else {
    Write-Warning "Could not reliably retrieve physical disk models via SSH. Proceeding without adding new disks."
    # Save whatever was returned (maybe error messages)
    try { Set-Content -Path $diskListFile -Value $disksResult.StdOut -Encoding UTF8 -Force } catch {}
}

# 3. Download Current DB File
$downloadExitCode = Invoke-Scp -User $NasUser -Host $NasHost -Source $remoteDbFullPath -Destination $localDbPath -Direction 'download' -Purpose "Download DB"
if ($downloadExitCode -ne 0) {
    Write-Error "FATAL: Failed to download the current database file '$remoteDbFullPath'. Stopping script."
    exit 1
}
if (-not (Test-Path $localDbPath)) {
     Write-Error "FATAL: DB file '$localDbPath' was not found locally after supposed successful download. Stopping script."
     exit 1
}

# 4. Read and Parse Downloaded DB File
Write-Host "Reading and parsing downloaded DB file: $localDbPath"
$dbData = $null
$changesMade = $false
try {
    $dbData = Get-Content -Path $localDbPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    # Basic structure check
    if (-not $dbData.PSObject.Properties.Name -contains 'disk_compatbility_info' -or -not $dbData.PSObject.Properties.Name -contains 'nas_model') {
         throw "JSON structure is missing 'disk_compatbility_info' or 'nas_model'."
    }
} catch {
    Write-Error "FATAL: Failed to read or parse the downloaded JSON DB file '$localDbPath'. Error: $_"
    exit 1
}
Write-Host "DB file parsed successfully."

# 5. Compare and Add Missing Physical Disks
if ($physicalDisks.Count -gt 0) {
    Write-Host "Comparing physical disks with DB entries..."
    $dbDiskModels = $dbData.disk_compatbility_info.PSObject.Properties.Name
    $missingDisks = $physicalDisks | Where-Object { $dbDiskModels -notcontains $_ }

    if ($missingDisks.Count -gt 0) {
        Write-Host "Found $($missingDisks.Count) physical disk models missing from the DB file. Adding them..."
        foreach ($diskToAdd in $missingDisks) {
            Write-Host "- Adding '$diskToAdd' with default support entry."
            # Add the model with the default support structure
            # Ensure the property name (disk model) is treated correctly
            $diskCompatObject = $dbData.disk_compatbility_info
            if ($diskCompatObject.$diskToAdd -eq $null) { # Check if Add-Member is needed or if it's already there somehow
                 $diskCompatObject | Add-Member -MemberType NoteProperty -Name $diskToAdd -Value $defaultSupportEntry -Force
                 # Alternative direct assignment (usually works, Add-Member is robust for complex names):
                 # $dbData.disk_compatbility_info.$diskToAdd = $defaultSupportEntry
            } else {
                 Write-Warning "Disk '$diskToAdd' seemed missing but was found during add attempt? Skipping."
            }
            $changesMade = $true
        }
        Write-Host "Finished adding missing disks."
    } else {
        Write-Host "All detected physical disks are already listed in the DB file."
    }
} else {
    Write-Host "Skipping disk comparison as no physical disks were reliably detected."
}

# 6. Save Modified DB File Locally
$modifiedLocalDbPath = Join-Path $outputDir "$($nasModel)_host_v7_MODIFIED.db"
if ($changesMade) {
    Write-Host "Saving modified data to local file: $modifiedLocalDbPath"
    try {
        ConvertTo-Json -InputObject $dbData -Depth 10 | Out-File -FilePath $modifiedLocalDbPath -Encoding UTF8 -Force -ErrorAction Stop
        Write-Host "Modified DB file saved successfully."
    } catch {
        Write-Error "FATAL: Failed to save the modified DB file locally to '$modifiedLocalDbPath'. Error: $_"
        exit 1
    }
} else {
    Write-Host "No changes were made to the DB data. Using the original downloaded file for potential upload."
    # Point to the original downloaded file if no changes were made
    $modifiedLocalDbPath = $localDbPath
}

# 7. Upload Modified DB File to NAS Home Directory
$remoteTempPath = "$remoteHomeDir/$remoteDbFileName" # Use original filename in home dir
$uploadExitCode = Invoke-Scp -User $NasUser -Host $NasHost -Source $modifiedLocalDbPath -Destination $remoteTempPath -Direction 'upload' -Purpose "Upload Modified DB"
if ($uploadExitCode -ne 0) {
    Write-Error "FATAL: Failed to upload the modified database file '$modifiedLocalDbPath' to NAS temp location '$remoteTempPath'. Stopping script."
    exit 1
}

# 8. Move Uploaded File on NAS using Sudo
Write-Host "Attempting to move file on NAS using sudo: '$remoteTempPath' -> '$remoteDbFullPath'"
Write-Warning "IMPORTANT: This step requires an interactive terminal for the 'sudo' password prompt."
Write-Warning "You will likely be prompted for the SSH password for '$NasUser' (if not cached) AND THEN the 'sudo' password."

# Construct the remote command. Using single quotes handles most standard cases.
$remoteMoveCommand = "sudo mv -f '$remoteTempPath' '$remoteDbFullPath'"

Write-Host "Executing on NAS via interactive SSH: $remoteMoveCommand"
$sshMoveProcess = $null
$moveSuccess = $false
try {
     # CRITICAL: Use -t to force pseudo-terminal allocation for sudo password prompt
     $sshArgs = @(
         "-t", # FORCE pseudo-terminal
         "$($NasUser)@$($NasHost)",
         $remoteMoveCommand
     )
    # Start the process and wait. Interaction happens in the current window.
    $sshMoveProcess = Start-Process ssh.exe -ArgumentList $sshArgs -NoNewWindow -PassThru -Wait

    # Check exit code AFTER the process finishes.
    if ($sshMoveProcess.ExitCode -eq 0) {
         Write-Host "[SUCCESS] File successfully moved to final destination '$remoteDbFullPath' on NAS using sudo."
         $moveSuccess = $true
    } else {
         Write-Error "[FAILED] ssh.exe (sudo mv) failed with Exit Code $($sshMoveProcess.ExitCode)."
         Write-Error "Check sudo password, permissions on '$remoteDbBaseDir', or if the source file '$remoteTempPath' existed in the home directory."
         Write-Warning "The uploaded file might still be in '$remoteTempPath'. Manual cleanup may be required."
    }
} catch {
     Write-Error "[FAILED] Error executing ssh.exe for sudo mv command: $_"
     Write-Warning "The uploaded file might still be in '$remoteTempPath'. Manual cleanup may be required."
}

# --- Final Summary ---
Write-Host "-------------------------------------"
if ($moveSuccess) {
    Write-Host "Operation Completed Successfully."
    if ($changesMade) {
        Write-Host "The disk compatibility database was updated with missing physical disks and uploaded."
    } else {
        Write-Host "No missing physical disks were detected. The original DB file was re-uploaded."
    }
} else {
    Write-Error "Operation Failed: Could not move '$remoteDbFileName' to its final destination on the NAS."
    Write-Error "Review the error messages above. Manual intervention on the NAS might be required."
}
Write-Host "Script finished."

# Optional: Remove the _MODIFIED file if it wasn't the original (and upload was successful)?
# if ($changesMade -and $moveSuccess -and (Test-Path $modifiedLocalDbPath)) {
#     Write-Host "Removing local modified file: $modifiedLocalDbPath"
#     Remove-Item $modifiedLocalDbPath -Force -ErrorAction SilentlyContinue
# }
