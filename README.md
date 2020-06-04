# PSSqlPatch
PowerShell module used for everything related to SQL Server patching. It contains functions to check for and download SQL patches directly from Microsoft, as well as functions to apply the patches and check patch levels. The functions that access servers require admin access on the remote server, and that the server drives are accessible via UNC. *(i.e. \\\\Servername\\d$\\foldername\ )*

# Functions
* [Get-SPSqlPatch](#get-spsqlpatch)
* [Save-SPSqlPatch](#save-spsqlpatch)
* [Get-SPSqlMLCabFile](#get-spsqlmlcabfile)
* [Save-SPSqlMLCabFile](#save-spsqlmlcabfile)
* [Get-SPPatchFileInfo](#get-sppatchfileinfo)
* [Get-SPInstancePatchDetails](#get-spinstancepatchdetails)
* [Get-SPPatchReport](#get-sppatchreport)
* [Install-SPSqlPatchFile](#install-spsqlpatchfile)
* [Install-SPLatestSqlPatch](#install-splatestsqlpatch)
* [Install-SPMultipleSqlPatches](#install-spmultiplesqlpatches)


### Get-SPSqlPatch
Uses the Microsoft page https://technet.microsoft.com/en-us/library/ff803383.aspx to check for new SQL Server updates and returns it in a PSObject.

### Save-SPSqlPatch
Uses the output from **Get-SPSqlPatch** to download the latest SQL Server updates and save them in a structured folder layout. The *DownloadDirectory* parameter is mandatory, this is where the files are downloaded to. User can specify the *SqlVersion* to download the patch for. If not specified it downloads the latest available patch for every SQL Server version. The folder structure it creates is;
* For versions that don't have Service Packs (2017 and newer) 
   * **$DownloadDirectory\\SQL $SqlVersion\\$CUNumber**
* For versions that have Service Packs (2016 and older)
    * **$DownloadDirectory\\SQL $SqlVersion\\$SPNumber\\$SPandCUName**

If you do not want to create the folder structure, you can use the *DoNotCreateFolderStructure* switch, and the file will be downloaded directly to the *DownloadDirectory*.

### Get-SPSqlMLCabFile
Uses the Microsoft page https://docs.microsoft.com/en-us/sql/advanced-analytics/install/sql-ml-cab-downloads which displays the cab files required to patch the Machine Learning services of SQL Server. The function then parses the page for cab files and converts it into a PSObject, with members such as Cumlative Update and Service Pack download links.

### Save-SPSqlMLCabFile
This function uses the **Get-SPSqlMLCabFile** function to download the Machine Learning cab files and save them in a structured folder layout. User can specify the *SQLVersion* or *CumulativeUpdate* to download the cab files for. The files are downloaded into the following folder structure;
 * For versions that don't have Service Packs (2017 and newer) 
    * **$DownloadDirectory\\SQL $SqlVersion\\$CUNumber\\MLCabFiles**
  * For versions that have Service Packs (2016 and older) 
    * **$DownloadDirectory\\SQL $SqlVersion\\$SPNumber\\$SPandCUName\\MLCabFiles**
    
If you do not want to create the folder structure, you can use the *DoNotCreateFolderStructure* switch, and the file will be downloaded directly to the *DownloadDirectory*.

### Get-SPPatchFileInfo
This function accepts a *Path* parameter which it then scans for SQL Server patch files. The function then returns relevant patch info in an object array.

### Get-SPInstancePatchDetails
This function gets relevant patch information for a given *SqlInstance*. It does this by checking the registry on the server, as well as the SQL Server ERROR logfile, which contains more patch level information.

### Get-SPPatchReport
This function is used to check the given SQL Servers are patched to the latest applicable patch in a given patch file directory. The user needs to pass a *PatchFileDirectory* or a *PatchFileObject (the output of **Get-SPPatchFileInfo**)*. This function will then run **Get-SPInstancePatchDetails** against an automatically obtained instance on each *TargetServer* and return a PowerShell object that contains the instance patch level, the latest applicable patch for that instance, and whether or not a newer patch is available for it. This allows a user to check their SQL Server estate to see if it has been patched to the latest version available on the given fileshare.

### Install-SPSqlPatchFile
This function is used to upload and install a SQL Server patch file on a specified server. The function accepts the *TargetServer*, *InstanceName* and *SourcePatchFile* parameters. The *InstanceName* is only used to check the current patch level of SQL on the *TargetServer*. All instances will be patched. The *SourcePatchFile* is the path to the patch file you want to apply.

### Install-SPLatestSqlPatch
This function uses a *PatchFileDirectory* or a *PatchFileObject* to determine the latest applicable SQL Server patch for a given TargetServer. It uses the **Get-SPPatchFileInfo** and **Install-SPSqlPatchFile** functions to do this. If the *PatchFileDirectory* parameter is passed, the function will use **Get-SPPatchFileInfo** with that directory to get the patch file object, which will then be used to check for the latest applicable patch. Alternatively, you can pass the object returned by **Get-SPPatchFileInfo** directly to the function using the *PatchFileObject* parameter. 

### Install-SPMultipleSqlPatches
This function patches multiple servers concurrently. It accepts a list of servers and calls **Install-SPLatestSqlPatch** against each of them. By default it will have 5 jobs running at the same time as it iterates through the server list, but this can be changed using the *JobLimit* parameter. the function also generates a summary log file and optionally sends the report and all log files to an email address if the *SMTPServer* and *ToEmail* parameters are set. This function can be easily set up to run in a Windows scheduled task with a large list of servers, and all logs will be sent to the set email address when it's finished.

