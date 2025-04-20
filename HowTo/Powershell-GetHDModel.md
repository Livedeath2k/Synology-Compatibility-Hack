# How to Use the Get-SynologyDiskModels PowerShell Script

This script connects to a Synology NAS via SSH, retrieves the model numbers of installed hard drives, and saves the list to `C:\Temp\Listing.txt` on your Windows machine.

## Prerequisites

* **Windows OpenSSH Client:** Ensure the OpenSSH Client is installed on your Windows system.
    * Check via: `Settings` > `Apps` > `Optional features`.
    * If not listed under "Installed features", click "View features" (next to "Add an optional feature"), search for `OpenSSH Client`, select it, and click "Next" > "Install".
* **SSH Enabled on Synology NAS:** SSH must be enabled on the target NAS.
    * Log in to Synology DSM web interface.
    * Go to `Control Panel` > `Terminal & SNMP` > `Terminal` tab.
    * Ensure **"Enable SSH service"** is checked.
    * Note the port number if it's not the default (`22`). This script assumes port `22`.
* **NAS Credentials:** You need the username and password for an account on the Synology NAS that belongs to the `administrators` group.

## 1. Download the Script

* Download the [script](https://github.com/Livedeath2k/Synology-Compatibility-Hack/PowerShell/Get-SynologyDiskModels.ps1)

## 2. Set PowerShell Execution Policy (One-time Setup, if needed)

PowerShell's security settings might prevent running local scripts by default. You may need to adjust this once.

1.  Open `PowerShell` **as Administrator**. (Right-click PowerShell icon -> "Run as administrator").
2.  Run the following command to allow running signed local scripts:
    ```powershell
    Set-ExecutionPolicy RemoteSigned
    ```
3.  Confirm by typing `Y` and pressing Enter.
4.  You can check the current policy anytime using `Get-ExecutionPolicy`.
5.  Close the Administrator PowerShell window.

## 3. Run the Script

1.  Open a **regular** `PowerShell` window (Administrator rights are usually not needed for this step).
2.  Navigate to the directory where you saved the script using the `cd` command. For example:
    ```powershell
    cd C:\Users\YourUsername\Scripts
    ```
3.  Execute the script using `.\` followed by the script name and provide the necessary parameters: `-NasUser` and `-NasHost`. Replace the placeholder values.

    ```powershell
    .\Get-SynologyDiskModels.ps1 -NasUser "YOUR_NAS_USERNAME" -NasHost "YOUR_NAS_IP_OR_HOSTNAME"
    ```

    **Examples:**

    * Using IP Address:
        ```powershell
        .\Get-SynologyDiskModels.ps1 -NasUser "admin" -NasHost "192.168.1.100"
        ```
    * Using Hostname:
        ```powershell
        .\Get-SynologyDiskModels.ps1 -NasUser "myadmin" -NasHost "diskstation.local"
        ```

## 4. Enter Password

* The script will initiate the SSH connection. PowerShell will prompt you for the password for the specified NAS user (e.g., `admin@192.168.1.100's password:`).
* Type the password and press **Enter**.
* **Note:** The password characters will **not** be displayed on the screen as you type. This is a standard security feature.

## 5. Check the Result

* If the script runs successfully, it will print completion messages in the PowerShell window.
* The output containing the list of disk drives and their model numbers will be saved to:
    `C:\Temp\Listing.txt`
* The script automatically creates the `C:\Temp` directory if it doesn't exist.
* If errors occur (e.g., connection failed, wrong password, SSH disabled), error messages or warnings will be displayed in the PowerShell window. Review these messages to troubleshoot the issue.
