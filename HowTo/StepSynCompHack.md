# Step-By-Step Synology Compatibility Hack

1. Run [Get-SynologyData.ps1](/Powershell/Get-SynologyData.ps1), to get a list of your installed harddrives in your NAS, and the appropiate Database File of your NAS Model.  
The Manual can be found [here](/HowTo/Powershell-GetNASData.md)
3. Run [JSON-Tool](/JSON-Files/json-editor.html)
   * Load the database (.db) file into the website
   * Add the harddrive model you have installed
   * Download the New File
   * Backup the Old File to something like ds218+_host_v7_1.db.old
   * Replace the Old file with the New File.
4. Run [Upload-SynologyDb.ps1](/Powershell/Upload-SynologyDb.ps1) and Upload the new File to your NAS.
The Manual can be found [here](/HowTo/Powershell-UploadNASDB.md)
6. Reboot the NAS.

