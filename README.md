# PSSqlPatch
PowerShell module to check for and download latest SQL Server patches from Microsoft. 

## Functions

### Get-SPSqlPatch
Uses https://technet.microsoft.com/en-us/library/ff803383.aspx to check for new SQL Server updates and returns it in a PSObject.

### Save-SPSqlPatch
Uses the output from Get-SPSqlPatch to download the latest SQL Server updates and save them in a structured folder layout. The structure is;
* For versions that don't have Service Packs (2017 and newer) 
   * **$DownloadDirectory\\SQL $SqlVersion\Patches\\$CUNumber**
* For versions that have Service Packs (2016 and older)
    * **$DownloadDirectory\\SQL $SqlVersion\Patches\\$SPNumber\\$SPandCUName**

