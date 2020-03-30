# PSSqlPatch
PowerShell module to check for and download latest SQL Server patches from Microsoft. 

## Functions

### Get-SPSqlPatch
Uses the Microsoft page https://technet.microsoft.com/en-us/library/ff803383.aspx to check for new SQL Server updates and returns it in a PSObject.

### Save-SPSqlPatch
Uses the output from Get-SPSqlPatch to download the latest SQL Server updates and save them in a structured folder layout. The structure is;
* For versions that don't have Service Packs (2017 and newer) 
   * **$DownloadDirectory\\SQL $SqlVersion\Patches\\$CUNumber**
* For versions that have Service Packs (2016 and older)
    * **$DownloadDirectory\\SQL $SqlVersion\Patches\\$SPNumber\\$SPandCUName**

### Get-SPSqlMLCabFile
Uses the Microsoft page https://docs.microsoft.com/en-us/sql/advanced-analytics/install/sql-ml-cab-downloads which displays the cab files required to patch the Machine Learning services of SQL Server. The function then parses the page for cab files and converts it into a PSObject, with parameters such as Cumlative Update and Service Pack download links.

### Save-SPSqlMLCabFile
This function uses the Get-SPSqlMLCabFile function from to get the latest available patches for SQL Server. User can specify the SQLVersion or CumulativeUpdate to download the cab files for. If the user specifies the RootDownloadDirectory, files are downloaded into the following folder structure;
 * For versions that don't have Service Packs (2017 and newer) 
    * **$RootDownloadDirectory\\SQL $SqlVersion\\Patches\\$CUNumber\\MLCabFiles**
  * For versions that have Service Packs (2016 and older) 
    * **$RootDownloadDirectory\\SQL $SqlVersion\\Patches\\$SPNumber\\$SPandCUName\\MLCabFiles**
    
Alternatively the user can specify FullDownloadDirectory , in which case the required cab files are downloaded directly into that directory instead.
   
