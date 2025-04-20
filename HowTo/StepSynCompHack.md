# Step-By-Step Synology Compatibility Hack

1. Run [Get-SynologyDiskModels.ps1](/Powershell/Get-SynologyDiskModels.ps1) to get a list of your installed harddrives in your NAS.
2. Run [JSON-Tool](/JSON-Files/json-editor.html)
  * Load the appropiate database (.db) file into the website
  * Add the harddrive model you have installed
  * Download the New File
  * Backup the Old File to something like ds218+_host_v7_1.db.old
  * Replace the Old file with the New File.
3. Run [NasCompFixer.ps1](/Powershell/NasCompFixer.ps1) and Upload the new File to your NAS.
4. Reboot the NAS.
