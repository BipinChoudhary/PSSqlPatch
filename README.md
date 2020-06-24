![PSSqlPatch](/images/PSSqlPatch_logo.PNG)
PSSqlPatch is a PowerShell module used for everything related to SQL Server patching. It contains functions to check for and download SQL patches directly from Microsoft, as well as functions to apply the patches and check patch levels. The functions that access servers require admin access on the remote server, and that the server drives are accessible via UNC. *(i.e. \\\\Servername\\d$\\foldername\ )*

# Installation
Run the following command to install PSSqlPatch from the PowerShell Gallery:
```powershell
Install-Module PSSqlPatch
```

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


# Get-SPSqlPatch
The function accesses a google excel sheet provided by "https://sqlserverbuilds.blogspot.com" which contains a list of all SQL Server patches available for each SQL Version. The function then parses the result and converts it into a PSObject, with parameters such as Cumlative Update and Service Pack download links.

### Usage
```powershell
Get-SPSqlPatch -SqlVersion "2017", "2016"
```
Will return the latest available patches for SQL Server 2017 and SQL Server 2016.

### Output
![Get-SPSqlPatch example](/images/Get-SPSqlPatch_example.png)

# Save-SPSqlPatch
Uses the output from **Get-SPSqlPatch** to download the latest SQL Server updates and save them in a structured folder layout. The *DownloadDirectory* parameter is mandatory, this is where the files are downloaded to. User can specify the *SqlVersion* to download the patch for. If not specified it downloads the latest available patch for every SQL Server version. The folder structure it creates is;
* For versions that don't have Service Packs (2017 and newer) 
   * **$DownloadDirectory\\SQL $SqlVersion\\$CUNumber**
* For versions that have Service Packs (2016 and older)
    * **$DownloadDirectory\\SQL $SqlVersion\\$SPNumber\\$SPandCUName**

If you do not want to create the folder structure, you can use the *DoNotCreateFolderStructure* switch, and the file will be downloaded directly to the *DownloadDirectory*.

### Usage
```powershell
Save-SPSqlPatch -SqlVersion "2017", "2016" -DownloadDirectory "C:\SqlPatches"
```
This will download the latest available Service Packs and Cumulative Updates for SQL Server 2019, 2017 and 2016. if *SqlVersion* is not set the function will download the latest patch for every SQL Server version.

### Output
In the following example, the latest CU for SQL Server 2017 is already downloaded, so it's skipped. But the latest SP and CU have not been downloaded yet, so the download is started for both of those files. The function returns the location of the files downloaded. As you can see, the aforementioned structured directories are created as well.
![Save-SPSqlPatch example](/images/Save-SPSqlPatch_example.png)

# Get-SPSqlMLCabFile
Uses the Microsoft page https://docs.microsoft.com/en-us/sql/advanced-analytics/install/sql-ml-cab-downloads which displays the cab files required to patch the Machine Learning services of SQL Server. The function then parses the page for cab files and converts it into a PSObject, with members such as SQLVersion, ServicePack and CumulativeUpdate that the cab file is for, and a DownLoadLink for the cab file.

### Usage
```powershell
Get-SPSqlMLCabFile
```
Returns all cab files listed on the Microsoft page.

### Output
The function does not accept parameters, so the returned object should be filtered as needed.
![Get-SPSqlMLCabFile example](/images/Get-SPSqlMLCabFile_example.png)


# Save-SPSqlMLCabFile
This function uses the **Get-SPSqlMLCabFile** function to download the Machine Learning cab files and save them in a structured folder layout. User can specify the *SQLVersion* or *CumulativeUpdate* to download the cab files for. The files are downloaded into the following folder structure;
 * For versions that don't have Service Packs (2017 and newer) 
    * **$DownloadDirectory\\SQL $SqlVersion\\$CUNumber\\MLCabFiles**
  * For versions that have Service Packs (2016 and older) 
    * **$DownloadDirectory\\SQL $SqlVersion\\$SPNumber\\$SPandCUName\\MLCabFiles**
    
If you do not want to create the folder structure, you can use the *DoNotCreateFolderStructure* switch, and the file will be downloaded directly to the *DownloadDirectory*.

### Usage
```powershell
Save-SPSqlMLCabFile -SqlVersion "2017" -CumulativeUpdate CU19 -DownloadDirectory "C:\SqlPatches"
```
Downloads the cabs for CU19 for SQL 2017 into a structured folder layout within "C:\SqlPatches" folder. Make sure the CumulativeUpdate given has CAB files available, or this function will return an error.

### Output 
![Save-SPSqlMLCabFile_example example](/images/Save-SPSqlMLCabFile_example.png)


# Get-SPPatchFileInfo
This function accepts a *Path* parameter which it then scans recursively for SQL Server patch files. The function then returns relevant patch info in an object array.

### Usage
```powershell
Get-SPPatchFileInfo -Path "C:\SqlPatches" | Format-Table
```

### Output
![PSSqlPatch](/images/Get-SPPatchFileInfo_example.png)


# Get-SPInstancePatchDetails
This function gets relevant patch information for a given *SqlInstance*. It does this by checking the registry on the server, as well as the SQL Server ERROR logfile, which contains more patch level information.

### Usage
```powershell
Get-SPInstancePatchDetails -SqlInstance "SERVER1\SQLTEST01", "SERVER2" 
```
This gets the patch information on the given SQL Server instances.

### Output
*I've edited out the servernames in this screenshot*
![Get-SPInstancePatchDetails_output](/images/Get-SPInstancePatchDetails_example.png)


# Get-SPPatchReport
This function is used to check the given SQL Servers are patched to the latest applicable patch in a given patch file directory. The user needs to pass a *PatchFileDirectory* or a *PatchFileObject (the output of **Get-SPPatchFileInfo**)*. This function will then run **Get-SPInstancePatchDetails** against an automatically obtained instance on each *TargetServer* and return a PowerShell object that contains the instance patch level, the latest applicable patch for that instance, and whether or not a newer patch is available for it. This allows a user to check their SQL Server estate to see if it has been patched to the latest version available on the given fileshare.

### Usage
```powershell
Get-SPInstancePatchDetails -TargetServer "SERVER1", "SERVER2" -PatchFileDirectory "C:\SqlPatches\"
```
This gets the patch information on the given servers, and checks if there is a newer applicable patch available in the *C:\\SqlPatches\\* directory

### Output
*I've edited out the servernames in this screenshot*
![Get-SPPatchReport_output](/images/Get-SPPatchReport_example.png)

# Install-SPSqlPatchFile
This function is used to upload and install a SQL Server patch file on a specified server. The function accepts the *TargetServer* and *SourcePatchFile* parameters. The *InstanceName* is only used to check the current patch level of SQL Server on the *TargetServer*. All instances will be patched. *InstanceName* is optional and an instance on the server will be retrieved automatically if it is not passed to the function. The *SourcePatchFile* is the path to the patch file you want to apply, it can be a local directory in relation to where the script is executed, or a network share. If the target server is on the same or newer patch version than the patch file given, no action will be taken.

This function digresses from the standard of a PSObject being returned from a function, it instead creates logfiles and outputs messages to the user. By default, logfiles are created in *C:\\Users\\$env:UserName\\AppData\\Local\\PSSqlPatch\\logs\\Install-SPSqlPatchFile*, but the you can specify a different logfile location with *LogFile* parameter.

### Usage
```powershell
Install-SPSqlPatchFile -TargetServer Server1 -SourcePatchFile "C:\SqlPatches\SQL 2017\CU20\SQLServer2017-KB4541283-x64.exe"
```
This will check an automatically retrieved instance on *Server1* for the patch level of the server. It then checks the patch level of the given patch file. If the server is on a lower patch level than the given patch, the file will be uploaded and applied. The server will be rebooted before (if required) and after the patch is applied.

### Output
*I've edited out the servername in this screenshot*
![Install-SPSqlPatchFile_output](/images/Install-SPSqlPatchFile_example.png)

In the above example, the *-Force* switch was not passed, so the user is prompted to confirm the server restart. It also shows how the SQL Server patch log is checked to ensure there were no issues, and finally the instance patch level is checked again to ensure it matches the patch file. The function also removes the patch file if patching was successful. If there was an issue with the patch, it will leave the patch file on the server, so you can do the patching manually or retry the function without having to upload the patch again.

# Install-SPLatestSqlPatch
This function uses a *PatchFileDirectory* or a *PatchFileObject* to determine the latest applicable SQL Server patch for a given *TargetServer*. It uses the **Get-SPPatchFileInfo** and **Install-SPSqlPatchFile** functions to do this. If the *PatchFileDirectory* parameter is passed, the function will use **Get-SPPatchFileInfo** with that directory to get the patch file object, which will then be used to check for the latest applicable patch. Alternatively, you can pass the object returned by **Get-SPPatchFileInfo** directly to the function using the *PatchFileObject* parameter. 

### Usage
```powershell
Install-SPLatestSqlPatch -TargetServer Server1 -PatchFileDirectory "C:\sqlPatches"
```

This will check an automatically retrieved instance on *Server1* for the patch level of the server. It then scans the PatchFileDirectory for the latest patch available for the target server SQL Server version. If the server is on a lower patch level than the latest available patch, the file will be uploaded and applied. The server will be rebooted before (if required) and after the patch is applied.

### Output
The output below shows the function searching for the latest applicable patch for the given server, and then checking to see if it's already been applied. In this case it has been, so no action has been carried out. The output of the actual patching process can be seen in the output example of **Install-SPSqlPatchFile** above.

*Again, I've edited out the server name here*
![Install-SPLatestSqlPatch_output](/images/Install-SPLatestSqlPatch_example.png)


# Install-SPMultipleSqlPatches
This function patches multiple servers concurrently. It accepts a list of servers and calls **Install-SPLatestSqlPatch** against each of them. By default it will have 5 jobs running at the same time as it iterates through the server list, but this can be changed using the *JobLimit* parameter. the function also generates a summary log file and optionally sends the report and all log files to an email address if the *SMTPServer* and *ToEmail* parameters are set. This function can be easily set up to run in a Windows scheduled task with a large list of servers, and all logs will be sent to the set email address when it's finished.

### Usage
#### Simple example
```powershell
Install-SPMultipleSqlPatches -Servers "Server1", "Server2" -PatchFileDirectory "C:\SqlPatches"
```
This command will patch the given servers with the latest applicable patches from "C:\SQLPatchDir\"

#### Email example
```powershell
Get-Content C:\SqlServer\serverlist.txt | Install-SPMultipleSqlPatches -PatchFileDirectory "C:\SQLPatchDir\" -LogFileDirectory "C:\SqlPatchDir\logs" -SMTPServer "SMTPHost.domain" -ToEmail "patch@example.com"
```
This command will patch all servers that are listed in the *serverlist.txt* file, using the default *JobLimit* of 5 it will patch up to 5 servers concurrently as it iterates through the servers. Once it's finished, it will send an email to the *patch@example.com* email address given, using the *SMTPServer* given. *SMTPServer* defaults to the preference variable $PSEmailServer. The email sent will contain a patch summary, as well as a zipped folder containing the individual patching logs for each server. 

### Output 
An example of the summary logfile generated by the script is below. There were a total of 30 servers passed to the function. You can see 28 were patched successfully, and two were already patched so they were skipped. The script completed in around 34 minutes, as shown at the bottom. This was scheduled as a Windows Scheduled Task and ran at 6AM, so saved a huge amount of manual work.

*Again, I've edited out server names here*

![Install-SPMultipleSqlPatches_log](/images/Install-SPMultipleSqlPatches_log_example.png)
