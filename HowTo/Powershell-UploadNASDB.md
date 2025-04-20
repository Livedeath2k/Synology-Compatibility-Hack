# How to Use the Upload-SynologyDb PowerShell Script

This script uploads a specified `.db` file from your local `C:\Temp` directory to `/var/lib/disk-compatibility/` on a Synology NAS. It requires `sudo` permissions on the NAS for the final step.

## Prerequisites

* **Windows OpenSSH Client:** Ensure `ssh.exe` and `scp.exe` are installed and available in your system's PATH (`Settings` > `Apps` > `Optional features`).
* **SSH Enabled on NAS:** The SSH service must be running on the target Synology NAS (`Control Panel` > `Terminal & SNMP`).
* **NAS User with `sudo`:** The NAS username provided (`-NasUser`) **must** have `sudo` privileges configured on the NAS. Standard admin users usually do, but verify if you encounter issues.
* **Local DB File:** The database file you want to upload must exist in your local `C:\Temp` directory.

## 1. Save the Script

* Copy the entire PowerShell script code above.
* Paste it into a plain text editor.
* **Save** the file with a `.ps1` extension, for example, `Upload-SynologyDb.ps1`.

## 2. Set PowerShell Execution Policy (One-time Setup, if needed)

If you haven't already, you might need to allow PowerShell to run local scripts:
1.  Open `PowerShell` **as Administrator**.
2.  Run: `Set-ExecutionPolicy RemoteSigned`
3.  Confirm with `Y`.

## 3. Run the Script

1.  Open a **regular** `PowerShell` window.
2.  Navigate (`cd`) to the directory where you saved `Upload-SynologyDb.ps1`.
3.  Execute the script, providing the NAS username, NAS host (IP or name), and the **exact filename** of the `.db` file in `C:\Temp`:

    ```powershell
    .\Upload-SynologyDb.ps1 -NasUser "YOUR_NAS_SUDO_USER" -NasHost "YOUR_NAS_IP_OR_HOSTNAME" -DbFileName "FILENAME_IN_C_TEMP.db"
    ```

    **Example:**
    ```powershell
    .\Upload-SynologyDb.ps1 -NasUser "admin" -NasHost "192.168.1.100" -DbFileName "DS920+_host_v7.db"
    ```

## 4. Interact with Prompts

* **SSH Password(s):** You'll likely be prompted for the SSH password for `YOUR_NAS_SUDO_USER` at least once (for `scp`) and possibly again (for `ssh`). Enter the password (it won't be displayed) and press Enter.
* **`sudo` Password:** During Stage 2 (the `ssh -t ... sudo mv` command), you will see a `[sudo] password for YOUR_NAS_SUDO_USER:` prompt directly in your PowerShell window. Enter the user's password **again** (this authorizes the `sudo` command) and press Enter. This password is often the same as the login password for admin users.

## 5. Check the Result

* The script will print `[SUCCESS]` or `[FAILED]` messages for each stage.
* If both stages succeed, the file will be located at `/var/lib/disk-compatibility/` on the NAS.
* If Stage 2 fails (the `sudo mv` step), the script will report an error, and the uploaded file will likely still be in the user's home directory (`~`) on the NAS (e.g., `/var/services/homes/YOUR_NAS_SUDO_USER/FILENAME_IN_C_TEMP.db`). You may need to manually connect via SSH to clean it up or investigate the `sudo` failure. Check the error messages printed by the script.
