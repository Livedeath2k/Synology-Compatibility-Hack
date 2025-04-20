# Automated Synology Disk Compatibility DB Update Script (`update_syno_db_auto.sh`)

This script automates the process of updating the Synology DiskStation Manager (DSM) disk compatibility database (`_host_v7.db`) file. It detects installed physical drives, checks if they are listed in the current database file downloaded from the NAS, adds any missing drives with a default "support" status, and uploads the modified file back to the NAS system directory.

## **IMPORTANT WARNINGS**

* **Use at Your Own Risk:** This script modifies system files on your Synology NAS. Incorrect use or unexpected errors could potentially lead to system instability or issues with DSM updates. **Proceed with caution.**
* **Backups:** Ensure you have **backups** of your NAS data and potentially the original `.db` file before running this script.
* **Sudo Required:** The script requires the specified NAS user to have `sudo` privileges to move the modified database file into the system directory (`/var/lib/disk-compatibility/`). You **will be prompted interactively** for the `sudo` password.
* **No Official Support:** This method modifies the official compatibility list. Synology does not support modified lists, and using drives not officially listed (even if added via this script) might void warranty or cause unexpected behavior.

## Prerequisites

1.  **Environment:** You need a Linux, macOS, or Windows Subsystem for Linux (WSL) environment with Bash shell.
2.  **`jq`:** The command-line JSON processor `jq` **must be installed**.
    * On Debian/Ubuntu: `sudo apt update && sudo apt install jq`
    * On Fedora/CentOS/RHEL: `sudo yum install jq` or `sudo dnf install jq`
    * On macOS (using Homebrew): `brew install jq`
3.  **OpenSSH Client:** `ssh` and `scp` commands must be installed and available in your system's PATH. (Usually installed by default on Linux/macOS).
4.  **Synology NAS Configuration:**
    * **SSH Service Enabled:** Enable SSH service on your NAS (Control Panel > Terminal & SNMP > Enable SSH service).
    * **User Account:** Use an account that is part of the `administrators` group on the NAS.
    * **Sudo Privileges:** The NAS user account **must have sudo privileges** configured to run the `mv` command. You might need to configure this manually on the NAS via SSH if not already done.

## Setup

1.  **Save the Script:** Copy the entire Bash script code provided previously and save it to a file named `update_syno_db_auto.sh` on your local machine (Linux, macOS, WSL).
2.  **Make Executable:** Open a terminal in the directory where you saved the file and make it executable:
    ```bash
    chmod +x update_syno_db_auto.sh
    ```

## Usage

Run the script from your terminal, providing the NAS username and hostname/IP address as arguments.

**Syntax:**

```bash
./update_syno_db_auto.sh <nas_user> <nas_host> [temp_dir]
