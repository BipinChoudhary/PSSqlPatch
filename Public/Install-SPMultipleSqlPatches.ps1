function Install-SPMultipleSqlPatches { 
	<#
	.SYNOPSIS
	This script us used to patch multiple SQL Server instances simulatenously. 

	.DESCRIPTION
    The function accepts a server list, and then iterates through each and applying the latest applicable patch. It's multi threaded, with a default of 5 simulatenously. 
    This function calls the "Install-SPLatestSqlPatch" function to get the latest applicable patch and apply it.

	.EXAMPLE
    Install-SPMultipleSqlPatches -Servers "Server1", "Server2", "Server3" -PatchFileDirectory "C:\SQLPatchDir\"

    This command will patch the given servers with the latest applicable patches from "C:\SQLPatchDir\"

    .EXAMPLE
    Get-Content serverlist.txt | Install-SPMultipleSqlPatches -PatchFileDirectory "C:\SQLPatchDir\" -LogFileDirectory "C:\SqlPatchDir\logs"
    
    This example will patch all servers listed in the serverlist.txt file. It will create all patching logfiles within the "C:\SqlPatchDir\logs" directory.
    
    .EXAMPLE
    Install-SPMultipleSqlPatches -Servers "Server1", "Server2" -PatchFileDirectory "C:\SQLPatchDir\" -SMTPServer "SMTPHost.domain" -ToEmail "patch@example.com"
    
    This example will patch the given servers, and will also email a zipped copy of all logs generated to the "patch@domain.com" email via SMTP server "SMTPHost.domain". You need to give an SMTPServer as well as a ToEmail if you want the email to be sent. SMTPServer defaults to the preference variable $PSEmailServer.

	.NOTES
	Author : Patrick Cull
	Date : 2019-10-07
	#> 
    [Cmdletbinding()]
    param(    
        #The server names which host the SQL instances to be patched.
        [Parameter(ValueFromPipeline, Mandatory)]
        [string[]] $Servers,

        #Directory that contains the SQL Server patch files. This directory will be scanned recursively for SQL Server patch files.
        [Parameter(Mandatory)]
        [string]$PatchFileDirectory,

        #Limit for the amount of concurrent servers to be patched at the same time.
        [int]$JobLImit = 5,

        #Directory for all the patching log files to be created.
        [string]$LogFileDirectory = "C:\Users\$env:UserName\AppData\Local\PSSqlPatch\logs\Install-SPMultipleSqlPatches",

        #SMTP Server used to send the summary email. ToEmail variable also needs to be set for the mail to be sent.
        [string] $SMTPServer=$PSEmailServer,

        #Email address(es) to send the summary mail. SMTPServer variable also needs to be set for the mail to be sent.
        [string[]] $ToEmail,

        #Email address that summary mail is sent from.
        [string] $FromEmail = "sqlserver@noreply.com",

        #Removes all prompts.
        [switch]$Force
    )

    begin {
        #This will be used to import the module in each of the jobs created, which allows for multiple servers to be done at the same time.
        $SqlPatchModulePath = Split-Path -Parent $PSScriptRoot
        
        #Create a dated folder within the LogFileDirectory.
        $CurrentDateTimeString = Get-Date -UFormat "%Y%m%d_%H%M"
        $LogFileDirectory = "$LogFileDirectory\$CurrentDateTimeString"
        if (!(Test-Path $LogFileDirectory)) { mkdir $LogFileDirectory -Force -ErrorAction Stop } 

        #Check log files for success/error strings.
        $LogDate = Get-Date -UFormat "%Y%m%d_%H%M"
        $PatchingSummaryLogFile = "$LogFileDirectory\PatchingSummary_${LogDate}.log"

        #Will be used to time the patching.
        $StartDateTime = Get-Date 

        if(!$Force) {
            $ConfirmPatching = Read-Host "Script is about to loop through all servers passed and reboot as neccesary. Continue? (y/n)"
            if($ConfirmPatching -ne "y") {
                throw "User cancelled"
            }
        }

        Write-SPUpdate "Script started by $env:UserName" -UpdateType Normal -Logfile $PatchingSummaryLogFile
        Write-SPUpdate "Check $LogFileDirectory for patch logs" -UpdateType Normal -Logfile $PatchingSummaryLogFile

        Write-SPUpdate "Getting SQL Server patch files from $PatchFileDirectory" -UpdateType Normal -Logfile $PatchingSummaryLogFile
        $PatchFileInfo = Get-SPPatchFileInfo -Path $PatchFileDirectory

        if($PatchFileInfo) {
            Write-SPUpdate "Patches have been read from $PatchFileDirectory. Proceeding with patching the given servers." -UpdateType Normal -Logfile $PatchingSummaryLogFile
        }
        else {
            Write-SPUpdate "Issue getting patch file list from $PatchFileDirectory" -UpdateType Error -Logfile $PatchingSummaryLogFile
            break 0
        }
    }

    #If the server list was passed via the pipeline, we create the server array with what was passed. This lets us patch servers concurrently in the next step. Otherwise the servers would be processed sequentially. 
    process {
        $ServerArray += $Servers
    }

    end {
        #Make sure servers are not done twice.
        $ServerArray = $ServerArray | Select-Object -Unique

        foreach($Server in $ServerArray){
            # Variable to say we cannot add a new job, unless we check the current number running is less than the JobLimit
            $AddNextJob = $false

            # Get stuck in this loop until we can start a job with the current server in foreach loop.
            while ($AddNextJob -eq $false) {
                
                #Check the current jobs running count is less than the JobLimit variable. if it is, we start a new job, and then break out of the while loop to go onto the next server in the list.
                if ((Get-Job -State 'Running').Count -lt $JobLimit) {
                    
                    # Each job needs to re-import the module so it can access the functions.
                    $ScriptBlock = {
                        Import-Module "$Using:SqlPatchModulePath"
                        Install-SPLatestSqlPatch -TargetServer $Using:Server -PatchFileObject $Using:PatchFileInfo -LogFileDirectory $Using:LogFileDirectory -Force
                    }

                    Start-Job -Name "${Server}_patch" -ScriptBlock $ScriptBlock | Select-Object Name, PSBeginTime, JobStateInfo
                    $AddNextJob = $true #Jump out of the while loop to add the next server in the list and check the active job count again.

                }
                else {
                    Start-Sleep 1  #Only loop and check every second.
                }
            }
        }

        #Wait for all jobs to complete.
        Get-Job -Name '*_patch' | Wait-Job | Out-Null

        #Display job output
        #Get-Job -Name '*_patch' | Receive-Job

        #Clear up jobs
        Get-Job -Name '*_patch' | Remove-Job

        Write-SPUpdate "Patching complete. Checking logs for errors." -UpdateType Info -Logfile $PatchingSummaryLogFile

        Write-SPUpdate "Patching Status" -UpdateType Header -Logfile $PatchingSummaryLogFile

        $SqlExpressCount = 0
        $InaccessibleCount = 0
        $ErrorCount = 0
        $SuccessfulPatchCount = 0
        $AlreadyPatchedCount = 0
        $NoApplicablePatchCount = 0

        $PatchingLogFiles = Get-ChildItem $LogFileDirectory | Where-Object {$_.FullName -ne $PatchingSummaryLogFile}

        foreach($logfile in $PatchingLogFiles) {
            $LogFilePath = $LogFile.FullName
            $LogFileName = $LogFile.Name

            $LogContent = Get-Content $LogFilePath
            $ServerName = ($LogFileName -split '_')[0]
            
            #Check the log files for error strings.    
            if($LogContent -like '*is down or inaccessible.*') {
                Write-SPUpdate "$ServerName - Server is down or inaccessible." -UpdateType Error -Logfile $PatchingSummaryLogFile
                $InaccessibleCount++
            }
            elseif($LogContent -like '*is in an availability group*') {
                Write-SPUpdate "$ServerName - Server is in an availablity group and patching should be done manually, so it has been skipped." -UpdateType Warning -Logfile $PatchingSummaryLogFile
                $SqlExpressCount++
            } 
            elseif($LogContent -like '*Setup.exe never completed before timeout*') {
                Write-SPUpdate "$ServerName - Patch setup.exe timed out before completing, check logs." -UpdateType Error -Logfile $PatchingSummaryLogFile
                $ErrorCount++
            }
            elseif($LogContent -like '*failed to update the shared features*') {
                Write-SPUpdate "$ServerName - Could not update shared features." -UpdateType Error -Logfile $PatchingSummaryLogFile
                $ErrorCount++
            }
            elseif($LogContent -like ("*``[ERROR``]*")) {
                Write-SPUpdate "$ServerName - Error installing patch, check logs." -UpdateType Error -Logfile $PatchingSummaryLogFile
                $ErrorCount++
            }
            elseif($LogContent -like '*successfully installed on*') {
                Write-SPUpdate "$ServerName - Patched successfully." -UpdateType Success -Logfile $PatchingSummaryLogFile
                $SuccessfulPatchCount++
            }
            elseif($LogContent -like '*is already installed on*') {
                Write-SPUpdate "$ServerName - Already patched. No action taken." -UpdateType Success -Logfile $PatchingSummaryLogFile            
                $AlreadyPatchedCount++
            }
            elseif($LogContent -like '*No applicable*were found in*') {
                Write-SPUpdate "$ServerName - No applicable patches were found in the given patch directory." -UpdateType Warning -Logfile $PatchingSummaryLogFile            
                $NoApplicablePatchCount++
            }
            else {
                Write-SPUpdate "$ServerName - Issue with patch. No success string found. Check logfile $LogFilePath" -UpdateType Error -Logfile $PatchingSummaryLogFile
                $ErrorCount++
            } 
        }   

        $EndDateTime = Get-Date 
        $TimeTaken = $EndDateTime - $StartDateTime
        $HoursTaken = $TimeTaken.Hours
        $MinutesTaken = $TimeTaken.Minutes
        $SecondsTaken = $TimeTaken.Seconds
        
        #Add counts to the log files
        Write-SPUpdate "Summary" -UpdateType Header -Logfile $PatchingSummaryLogFile -NoTimeStamp
        Write-SPUpdate "SuccessfulPatchCount = $SuccessfulPatchCount" -UpdateType Normal -Logfile $PatchingSummaryLogFile -NoTimeStamp
        Write-SPUpdate "AlreadyPatchedCount = $AlreadyPatchedCount" -UpdateType Normal -Logfile $PatchingSummaryLogFile -NoTimeStamp
        Write-SPUpdate "ErrorCount = $ErrorCount" -UpdateType Normal -Logfile $PatchingSummaryLogFile -NoTimeStamp
        Write-SPUpdate "SQLExpressCount = $SqlExpressCount" -UpdateType Normal -Logfile $PatchingSummaryLogFile -NoTimeStamp
        Write-SPUpdate "InaccessibleCount = $InaccessibleCount" -UpdateType Normal -Logfile $PatchingSummaryLogFile -NoTimeStamp
        Write-SPUpdate "NoApplicablePatchCount = $NoApplicablePatchCount" -UpdateType Normal -Logfile $PatchingSummaryLogFile -NoTimeStamp

        Write-SPUpdate " " -UpdateType Normal -Logfile $PatchingSummaryLogFile -NoTimeStamp
        Write-SPUpdate "Start Time : $StartDateTime" -UpdateType Normal -Logfile $PatchingSummaryLogFile -NoTimeStamp
        Write-SPUpdate "End Time : $EndDateTime" -UpdateType Normal -Logfile $PatchingSummaryLogFile -NoTimeStamp
        Write-SPUpdate "Total Time Taken : $HoursTaken hours, $MinutesTaken minutes, $SecondsTaken seconds" -UpdateType Normal -Logfile $PatchingSummaryLogFile -NoTimeStamp


        Write-SPUpdate "Patching summary located at $PatchingSummaryLogFile" -UpdateType Info -Logfile $PatchingSummaryLogFile

        $LogSummaryContent = Get-Content $PatchingSummaryLogFile

        if($LogSummaryContent -like ("*``[ERROR``]*")) {
            $EmailSubject = "[ERROR] - Errors reported in SQL Server Patching Report $CurrentDateTimeString" 
        }
        elseif($LogSummaryContent -like ("*``[WARNING``]*")) {
            $EmailSubject = "[WARNING] - Warnings reported in SQL Server Patching Report $CurrentDateTimeString" 
        }
        else {
            $EmailSubject = "[SUCCESS] Successful SQL Server Patching Report $CurrentDateTimeString" 
        }

        #Send email with files created above attached.
        if($SMTPServer -and $ToEmail) {
            #Zip the log files they can be sent in the email.
            $ZippedLogFilePath = "$LogFileDirectory\Patchinglogs.zip"
            $PatchingLogFiles | Compress-Archive -DestinationPath $ZippedLogFilePath

            $MailBody = "Please see attached SQL Patching report. Log files located at $LogFileDirectory"

            Send-MailMessage  -Subject $EmailSubject -To $ToEmail -From $FromEmail -SmtpServer $SMTPServer -Body $MailBody -Attachments FileSystem::$PatchingSummaryLogFile, FileSystem::$ZippedLogFilePath
        }
    
    }#end end{}
}
