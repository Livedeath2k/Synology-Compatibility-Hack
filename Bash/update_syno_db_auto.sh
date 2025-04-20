#!/bin/bash

# Exit on any error (safer) and treat unset variables as an error
set -eu -o pipefail

# --- Configuration ---
DEFAULT_TEMP_DIR="/tmp"
REMOTE_DB_BASE_DIR="/var/lib/disk-compatibility"
REMOTE_HOME_DIR="~" # User's home directory on NAS

# --- Helper Functions ---
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error_exit() {
    log "ERROR: $1" >&2
    # Clean up temporary directory if it exists
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        log "Cleaning up temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
    exit 1
}

# --- Argument Parsing ---
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <nas_user> <nas_host> [temp_dir]" >&2
    echo "  nas_user:  Username for SSH/sudo on the Synology NAS (must have sudo rights)." >&2
    echo "  nas_host:  IP address or hostname of the Synology NAS." >&2
    echo "  temp_dir: (Optional) Local temporary directory. Defaults to $DEFAULT_TEMP_DIR." >&2
    exit 1
fi

NAS_USER="$1"
NAS_HOST="$2"
LOCAL_TEMP_BASE="${3:-$DEFAULT_TEMP_DIR}"

# --- Prerequisite Check ---
if ! command -v jq &> /dev/null; then
    error_exit "'jq' command not found. Please install jq (e.g., 'sudo apt install jq' or 'brew install jq')."
fi
if ! command -v ssh &> /dev/null; then
    error_exit "'ssh' command not found. Please install OpenSSH client."
fi
if ! command -v scp &> /dev/null; then
    error_exit "'scp' command not found. Please install OpenSSH client."
fi

# --- Create Secure Temporary Directory ---
TEMP_DIR=$(mktemp -d "${LOCAL_TEMP_BASE}/syno_update_XXXXXX")
# Setup trap to clean up temp directory on exit (normal or error)
trap 'error_exit "Script interrupted. Cleaning up temp directory $TEMP_DIR."' INT TERM HUP
trap 'log "Cleaning up temporary directory: $TEMP_DIR"; rm -rf "$TEMP_DIR"' EXIT
log "Using temporary directory: $TEMP_DIR"

# --- Define NAS Commands ---
GET_MODEL_CMD="awk -F'\"' '/^unique=/ {print \$2}' /etc.defaults/synoinfo.conf"
GET_DISKS_CMD='for f in /sys/block/sd*/device/model /sys/block/nvme*n*/device/model; do if [ -f "$f" ]; then model=$(cat "$f" | tr -d "\0"); printf "%s\n" "$model"; fi; done 2>/dev/null | sed "s/ *$//"' # Get models, trim trailing spaces

# --- 1. Get NAS Model ---
log "Getting NAS Model from $NAS_HOST..."
NAS_MODEL=$(ssh -T -o ConnectTimeout=10 -o BatchMode=yes "${NAS_USER}@${NAS_HOST}" "$GET_MODEL_CMD" 2>"$TEMP_DIR/ssh_error.log")
SSH_EXIT_CODE=$?
if [[ $SSH_EXIT_CODE -ne 0 || -z "$NAS_MODEL" ]]; then
    error_exit "Failed to retrieve NAS model. SSH exit code: $SSH_EXIT_CODE. Error log: $(cat "$TEMP_DIR/ssh_error.log" 2>/dev/null || echo 'empty')"
fi
log "Detected NAS Model: $NAS_MODEL"
REMOTE_DB_FILENAME="${NAS_MODEL}_host_v7.db"
REMOTE_DB_FULLPATH="${REMOTE_DB_BASE_DIR}/${REMOTE_DB_FILENAME}"
LOCAL_DB_PATH="${TEMP_DIR}/${REMOTE_DB_FILENAME}"
MODIFIED_LOCAL_DB_PATH="${TEMP_DIR}/${NAS_MODEL}_host_v7_MODIFIED.db"

# --- 2. Get Physical Disk Models ---
log "Getting physical disk models from $NAS_HOST..."
# Use process substitution and readarray to populate the array
readarray -t PHYSICAL_DISKS < <(ssh -T -o ConnectTimeout=10 -o BatchMode=yes "${NAS_USER}@${NAS_HOST}" "$GET_DISKS_CMD" 2>"$TEMP_DIR/ssh_error.log")
SSH_EXIT_CODE=$?
if [[ $SSH_EXIT_CODE -ne 0 ]]; then
    log "WARNING: SSH command to get disk models finished with exit code $SSH_EXIT_CODE. Error log: $(cat "$TEMP_DIR/ssh_error.log" 2>/dev/null || echo 'empty'). Proceeding without adding disks."
    PHYSICAL_DISKS=() # Ensure array is empty if command failed
else
    log "Detected ${#PHYSICAL_DISKS[@]} physical disk models:"
    printf "  - %s\n" "${PHYSICAL_DISKS[@]}"
fi

# --- 3. Download Current DB File ---
log "Downloading current DB file: $REMOTE_DB_FULLPATH -> $LOCAL_DB_PATH"
scp -T -o ConnectTimeout=10 "${NAS_USER}@${NAS_HOST}:${REMOTE_DB_FULLPATH}" "$LOCAL_DB_PATH" > "$TEMP_DIR/scp_stdout.log" 2>"$TEMP_DIR/scp_error.log"
SCP_EXIT_CODE=$?
if [[ $SCP_EXIT_CODE -ne 0 ]]; then
    error_exit "Failed to download DB file. SCP exit code: $SCP_EXIT_CODE. Error log: $(cat "$TEMP_DIR/scp_error.log" 2>/dev/null || echo 'empty')"
fi
if [[ ! -f "$LOCAL_DB_PATH" ]]; then
    error_exit "DB file '$LOCAL_DB_PATH' not found locally after SCP reported success."
fi
log "DB file downloaded successfully."

# --- 4. Read/Parse and 5. Modify DB File ---
log "Parsing downloaded DB file and checking for missing disks..."
cp "$LOCAL_DB_PATH" "$MODIFIED_LOCAL_DB_PATH" # Start with a copy
CHANGES_MADE=false

# Get existing disk models from the JSON DB
mapfile -t DB_DISK_MODELS < <(jq -r '.disk_compatbility_info | keys | .[]' "$LOCAL_DB_PATH" 2>"$TEMP_DIR/jq_error.log")
JQ_EXIT_CODE=$?
if [[ $JQ_EXIT_CODE -ne 0 ]]; then
    error_exit "Failed to parse existing keys from DB file '$LOCAL_DB_PATH'. jq error: $(cat "$TEMP_DIR/jq_error.log")"
fi

if [[ ${#PHYSICAL_DISKS[@]} -gt 0 ]]; then
    for disk_model in "${PHYSICAL_DISKS[@]}"; do
        # Check if the physical disk model is already in the DB list
        found=false
        for db_model in "${DB_DISK_MODELS[@]}"; do
            if [[ "$disk_model" == "$db_model" ]]; then
                found=true
                break
            fi
        done

        if ! $found; then
            log "Adding missing disk model to DB: '$disk_model'"
            # Use jq to add the missing disk model with default support structure
            jq --arg disk "$disk_model" \
               '.disk_compatbility_info[$disk] = {"default":{"compatibility_interval":[{"compatibility":"support"}]}}' \
               "$MODIFIED_LOCAL_DB_PATH" > "$MODIFIED_LOCAL_DB_PATH.tmp" 2>"$TEMP_DIR/jq_error.log"
            JQ_MOD_EXIT_CODE=$?
            if [[ $JQ_MOD_EXIT_CODE -ne 0 ]]; then
                error_exit "jq command failed while adding disk '$disk_model'. Error: $(cat "$TEMP_DIR/jq_error.log")"
            fi
            # Replace the original modified file with the newly updated one
            mv "$MODIFIED_LOCAL_DB_PATH.tmp" "$MODIFIED_LOCAL_DB_PATH"
            CHANGES_MADE=true
            # Add the newly added key to our list to avoid duplicate adds if drive appears twice in physical list somehow
            DB_DISK_MODELS+=("$disk_model")
        fi
    done
    if $CHANGES_MADE; then
      log "Finished adding missing disks."
    else
      log "No missing physical disks found in the DB file."
    fi
else
    log "Skipping disk comparison as no physical disks were detected."
fi

# --- 6. Upload Modified DB File ---
# Upload even if no changes were made by this script, file might have been modified manually before run
log "Uploading updated DB file: $MODIFIED_LOCAL_DB_PATH -> ${NAS_USER}@${NAS_HOST}:${REMOTE_HOME_DIR}/${REMOTE_DB_FILENAME}"
REMOTE_TEMP_PATH="${REMOTE_HOME_DIR}/${REMOTE_DB_FILENAME}" # Target in home dir
scp -T -o ConnectTimeout=10 "$MODIFIED_LOCAL_DB_PATH" "${NAS_USER}@${NAS_HOST}:${REMOTE_TEMP_PATH}" > "$TEMP_DIR/scp_stdout.log" 2>"$TEMP_DIR/scp_error.log"
SCP_EXIT_CODE=$?
if [[ $SCP_EXIT_CODE -ne 0 ]]; then
    error_exit "Failed to upload modified DB file. SCP exit code: $SCP_EXIT_CODE. Error log: $(cat "$TEMP_DIR/scp_error.log" 2>/dev/null || echo 'empty')"
fi
log "Modified DB file uploaded to temporary location on NAS."

# --- 7. Move Uploaded File on NAS using Sudo ---
log "Moving uploaded file on NAS using sudo: $REMOTE_TEMP_PATH -> $REMOTE_DB_FULLPATH"
log ">>> IMPORTANT: This step requires an interactive terminal for the 'sudo' password prompt. <<<"
log ">>> You will likely be prompted for the SSH password AND THEN the sudo password for '$NAS_USER'. <<<"
REMOTE_MOVE_CMD="sudo mv -f '${REMOTE_TEMP_PATH}' '${REMOTE_DB_FULLPATH}'"

# CRITICAL: Use -t to allocate a pseudo-terminal for the sudo password prompt
ssh -t -o ConnectTimeout=10 "${NAS_USER}@${NAS_HOST}" "$REMOTE_MOVE_CMD"
SSH_MV_EXIT_CODE=$?

log "-------------------------------------"
if [[ $SSH_MV_EXIT_CODE -eq 0 ]]; then
    log "Operation Completed Successfully."
    if $CHANGES_MADE; then
        log "The disk compatibility database was updated with missing physical disks and uploaded."
    else
        log "No missing physical disks were detected by the script. The downloaded/existing DB file was uploaded."
    fi
else
    log "ERROR: Failed to move '$REMOTE_DB_FILENAME' to its final destination on the NAS using sudo." >&2
    log "ERROR: SSH (sudo mv) exit code: $SSH_MV_EXIT_CODE." >&2
    log "ERROR: Check sudo password, permissions on '$REMOTE_DB_BASE_DIR', or if the source file existed in the home directory." >&2
    log "WARNING: The uploaded file might still be in '$REMOTE_TEMP_PATH'. Manual cleanup may be required." >&2
    # Exit with error code to indicate failure
    exit 1
fi

# --- Final Cleanup is handled by trap ---
log "Script finished."
exit 0
