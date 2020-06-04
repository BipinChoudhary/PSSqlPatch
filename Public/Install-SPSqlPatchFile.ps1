function Install-SPSqlPatchFile {  
    <#
	.SYNOPSIS
	This script is used to upload and apply a SQL Server patch file to a given server.

	.DESCRIPTION
    The function accepts a server name and instance name to check for the patch level. It compares the patch level of the given patch executable against the instance name given, and will apply the patch if the instance version is lower than the patchfile version.


	.EXAMPLE
    Install-SPSqlPatchFile -TargetServer "Server1" -InstanceName "SQLDEV01" -SourcePatchFile "C:\SqlPatches\SQL 2017\CU20\SQLServer2017-KB4541283-x64.exe"

    This command will check the patch level of the executable passed and compare it against the patch level of the SQLDEV01 instance on Server1. If the file patch level is higher, it will apply the patch. If it's the same or lower, it will skip it.
    
	.NOTES
	Author : Patrick Cull
	Date : 2019-01-01
    #> 
    
    [Cmdletbinding()]
    param(    
        #The server to be patched.
        [Parameter(ValueFromPipeline, Mandatory)]
        [string] $TargetServer,

        #The instance name to check on the server for current patch level. Note: all SQL isntances on the server will be patched,  this is just for checking the current patch level.
        [string] $InstanceName = 'MSSQLSERVER',

        #Source Patch file. 
        [Parameter(Mandatory)]
        [string] $SourcePatchFile,
       
        
        #Path of the file to log the output to.
        [string] $LogFile,

        #Skip the confirmation prompts.
        [switch] $Force
    )

    if (!$Logfile) {
        $LogFileDirectory = "C:\Users\$env:UserName\AppData\Local\PSSqlPatch\logs\Install-SPSqlPatchFile"
        if (!(Test-Path $LogFileDirectory)) { mkdir $LogFileDirectory -Force -ErrorAction Stop }   
        $LogDate = Get-Date -UFormat "%Y%m%d_%H%M"
        $LogFile = "$LogFileDirectory\${TargetServer}_${LogDate}.log"
    }

    if($SourcePatchFile -notlike '*.exe') {
        Write-SPUpdate "SourcePatchFile parameter must be full path to source patch exe file." -UpdateType Error -Logfile $LogFile
        break 0
    }
    if(!(Test-Path $SourcePatchFile)) {
        Write-SPUpdate "$SourcePatchFile does not exist or is inaccessible." -UpdateType Error -Logfile $LogFile
        break 0
    }


    #Get the patch level of the file passed.
    $PatchFileInfo = Get-SPPatchFileInfo $SourcePatchFile
    $PatchFileVersion = $PatchFileInfo.PatchFileVersion
    $PatchFileName = $PatchFileInfo.PatchFileName
    $SourcePatchDirectory = $PatchFileInfo.PatchFileDirectory

    #Set target instance - we don't include the MSSQLServer part if it's a non default 
    if ($InstanceName -eq "MSSQLSERVER") {
        $TargetInstance = $TargetServer
    }
    else {
        $TargetInstance = "$TargetServer\$InstanceName"
    }

    # Test the server is accessible.
    if (!(Test-Connection -ComputerName $TargetServer -Count 1)) {
        Write-SPUpdate "$TargetServer does not exist or is inaccessible. Check spelling and retry." -UpdateType Error -Logfile $LogFile
        break
    }   
    
    #Remove the .exe part of the file name to be used for folder naming.
    $PatchFileFolderName = $PatchFileName -replace '.exe'

    $InstancePatchDetails = Get-SPInstancePatchDetails -SqlInstance $TargetInstance
    $InstancePatchLevel = $InstancePatchDetails.PatchVersion

    if($InstancePatchLevel) {
        Write-SPUpdate "Instance patch version is $InstancePatchLevel" -UpdateType Normal -Logfile $LogFile
    }
    else {
        Write-SPUpdate "Could not get the instance patch level of instance $InstanceName from the $TargetServer registry. Ensure the instance name is correct." -UpdateType Error -Logfile $LogFile
        break 0
    }


    Write-SPUpdate "Patchfile version is $PatchFileVersion" -UpdateType Normal -Logfile $LogFile

    #If patch file passed is greater than the patch on the instance, we apply it.
    if($PatchFileVersion -eq $InstancePatchLevel) {
        Write-SPUpdate "Patch $PatchFileFolderName is already installed on $TargetInstance" -UpdateType Success -Logfile $LogFile
    }
    elseif ($PatchFileVersion -lt $InstancePatchLevel) {
        Write-SPUpdate "Newer patch is already installed on $TargetInstance" -UpdateType Success -Logfile $LogFile
    }
    else {

        # Check server has enough space for the patch.
        $PatchFileSizeGB = $PatchFileInfo.PatchFileSizeMB/1024
    
        $DriveWithEnoughSpace = Get-SPDriveWithSpace -TargetServer $TargetServer -SpaceNeededGB $PatchFileSizeGB
    
        if($DriveWithEnoughSpace) {
            $TargetDrive = $DriveWithEnoughSpace[0]
            Write-SPUpdate "Using the $TargetDrive drive to upload the patch to." -UpdateType Normal -Logfile $LogFile
        }
        else {
            Write-SPUpdate "Target does not have enough space on any drive for the patch." -UpdateType Error -Logfile $LogFile
            break
        }

        # Set file and folder path for patch installer .exe
        $PatchFilesDestination = "\\$TargetServer\${TargetDrive}`$\Sources\Patches\$PatchFileFolderName"

        $NetworkFilePath = "$PatchFilesDestination\$PatchFileName"
        
        $LocalFilePath = "${TargetDrive}:\Sources\Patches\$PatchFileFolderName\$PatchFileName"
        $ExtractFolder = "${TargetDrive}:\Sources\Patches\$PatchFileFolderName\Extracted"

        #Check if the instance is in a high availability group - these need to be done manually.
        $TargetAvailabilityGroups = Invoke-Command -ComputerName $TargetServer -ScriptBlock {
            [Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null  
             
            $TargetInstanceObject = New-Object Microsoft.SqlServer.Management.Smo.Server("$Using:TargetInstance")
        
            if($TargetInstanceObject.AvailabilityGroups.Count -gt 0) {
                return $TargetInstanceObject.AvailabilityGroups | Select-Object AvailabilityReplicas,AvailabilityDatabases | Format-List
            }
            else {
                return $false
            }
        }

        if($TargetAvailabilityGroups) {
            Write-SPUpdate "$TargetServer is in an availability group , needs to be done manually." -UpdateType Normal -Logfile $LogFile
            $TargetAvailabilityGroups | Format-Table | Out-String | Write-SPUpdate -Logfile $LogFile -NoTimeStamp
            break 0
        }

        if (!(Test-Path $PatchFilesDestination)) { mkdir $PatchFilesDestination -Force}

        #Check if reboot needs to be done before carring out the patch
        $IsRebootPending = (Get-PendingReboot $TargetServer).RebootPending

        if ($IsRebootPending -eq 'True') {
            #Add a check before the reboot if force is not specified.
            if (!$Force) {
                Read-Host "$TargetServer has a reboot pending and needs to be rebooted before installing patch. Press enter to do this now, or stop this script to cancel."
            } 

            Write-SPUpdate "Rebooting $TargetServer now ..." -UpdateType Normal -Logfile $LogFile
        
            try {
                Restart-Computer -ComputerName $TargetServer -Wait -For PowerShell -Timeout 900 -Delay 10 -Force -ErrorAction Stop
                Write-SPUpdate  "$TargetServer rebooted before install." -UpdateType Success -Logfile $LogFile
            }
        
            catch {
                Write-SPUpdate  "$TargetServer could not be rebooted. Do it manually then rerun this script, or the following command:" -UpdateType Error -Logfile $LogFile
                Write-SPUpdate  "Install-SPSqlPatchFile -TargetServer $TargetServer -InstanceName $InstanceName -SourcePatchFile $SourcePatchFile" -UpdateType Normal -Logfile $LogFile
                break
            }
        }

        #Check if R Services is on the server. If it is, it requires CAB files.
        $RServices = Get-Service -ComputerName $TargetServer | Where-Object Name -like 'MSSQLLaunchpad*'

        if($RServices) {
            Write-SPUpdate "R Services is installed on $TargetServer." -UpdateType Info -Logfile $Logfile

            $CabFileDirectory = "$SourcePatchDirectory\MLCabFiles\"
            if(Test-Path $CabFileDirectory) {
                Write-SPUpdate "R Services is installed on $TargetServer - copying CAB files from $CabFileDirectory to the temp folder on $TargetServer" -UpdateType Info -Logfile $Logfile

                $TargetTempFolder = Invoke-Command -ComputerName $TargetServer -ScriptBlock {$env:TMP}
                $NetworkTargetTempFolder = "\\$TargetServer\$TargetTempFolder" -replace ':', '$'

                $MLCabFiles = Get-ChildItem $CabFileDirectory -Filter '*.cab'

                if($MLCabFiles) {
                    Write-SPUpdate "Copying cab files:" -UpdateType Normal -Logfile $LogFile
                    $MLCabFiles.FullName | Write-SPUpdate -UpdateType Normal -Logfile $LogFile
                    try {
                        #Exclude any files that are already copied.
                        $ExcludeItems = Get-ChildItem $NetworkTargetTempFolder -ErrorAction SilentlyContinue                       
                        Copy-item $MLCabFiles.FullName -Destination $NetworkTargetTempFolder -ErrorAction Stop -ErrorVariable CopyCabError -Exclude $ExcludeItems

                        Write-SPUpdate "Files copied. Continuing with patching." -UpdateType Success -Logfile $LogFile
                    }
                    catch {
                        Write-SPUpdate "Issue copying cab files to $NetworkTargetTempFolder , not proceeding with patch." -UpdateType Error -Logfile $LogFile
                        $CopyCabError | Out-String | Write-SPUpdate -UpdateType Error -Logfile $Logfile
                        break 0
                    }
                }

                else {
                    Write-SPUpdate "No cab files found in $CabFileDirectory" -UpdateType Error -Logfile $LogFile
                    break 0
                }
            }
            else {
                Write-SPUpdate "$CabFileDirectory directory does not exist. Create it and put the required cab files for this CU in there, then retry this script." -UpdateType Error -Logfile $LogFile
                break 0
            }
        }
        
        #If patch file is not there upload it.
        if (!(Test-Path $NetworkFilePath)) {
            
            Write-SPUpdate "Patch file not found, uploading $SourcePatchFile to server." -UpdateType Normal -Logfile $Logfile
            
            Copy-Item -Path $SourcePatchFile -Destination $PatchFilesDestination

            if (!(Test-Path $NetworkFilePath)) { 
                Write-SPUpdate "Issue uploading the patch file to $NetworkFilePath. View logs and re-run script or install the patch manually." -UpdateType Error -Logfile $LogFile
                break
            }
            else {
                Write-SPUpdate "Patch uploaded successfully" -UpdateType Success -Logfile $LogFile
            }
        }
    
        #Update the MaxMemoryPerShell on the target. This is set low on older servers which prevents patching.
        $MaxMemoryUpdate = Set-SPMaxMemoryPerShellMB -TargetServer $TargetServer -MaxMemoryPerShellMB "0"
        if($MaxMemoryUpdate.ValueType -contains 'NewValue') {
            Write-SPUpdate "Updated MaxMemoryPerShellMB" -UpdateType Normal -Logfile $LogFile
            $MaxMemoryUpdate | Format-Table | Out-String | Write-SPUpdate -Logfile $LogFile -NoTimeStamp
        }

        Write-SPUpdate "Beginning $PatchFileName install, this may take a while..." -UpdateType Info -Logfile $Logfile
        

        $InstallPatchJobName = "${TargetServer}_Patch_setup.exe"
        Invoke-Command -ComputerName $TargetServer -ArgumentList $TargetServer, $LocalFilePath, $ExtractFolder -AsJob -JobName $InstallPatchJobName -ScriptBlock {
            param($TargetServer, $LocalFilePath, $ExtractFolder)

            Write-Output "Extracting patch to $ExtractFolder ..."
            $ExtractParams = "/X:$ExtractFolder" 
            & "$LocalFilePath" $ExtractParams

            # Need to wait for the exe to be extracted. Using the Out-Null trick to wait on the extract process causes it to hang indefinitely, so we wait for the required directories and files to be extracted.
            # While any of these folders do not exist, we wait. 
            While (!(Test-Path "$ExtractFolder\setup.exe") -or !(Test-Path "$ExtractFolder\resources\") -or !(Test-Path "$ExtractFolder\x64\setup")) {
                Write-Output "Waiting for extract to complete ..."
                Start-Sleep 10
            }

            $SqlInstallLogDirectory = Get-ChildItem "\\$TargetServer\C`$\Program Files\Microsoft SQL Server\*\Setup Bootstrap\Log\" | Sort-Object LastWriteTime | Select-Object -Last 1 -ExpandProperty FullName
            
            Write-Output "Applying the patch now. You can check $SqlInstallLogDirectory for progress."

            Set-Location $ExtractFolder
            $Parms = "/q", "/IAcceptSQLServerLicenseTerms", "/Action=Patch", "/AllInstances"
            & ".\setup.exe" $Parms | Out-Null
            Write-Output "Setup.exe completed."
        }

        #Timeout after an hour (3600 seconds)
        Wait-Job -Name $InstallPatchJobName -Timeout 3600
        Stop-Job -Name $InstallPatchJobName
        
        $SetupJobOutput = Receive-Job -Name $InstallPatchJobName

        #If the setup.exe completed, this string will be found in the job output. Provide the user with a snippet of the summary log, which is updated after the setup.exe completes.
        if($SetupJobOutput -like '*Setup.exe completed.*') {
            #Get any log file created in the last hour and get the latest one
            $CurrentDateTime = Get-Date
            $LastHour = $CurrentDateTime.AddHours(-1)

            #Check the default Summary.txt file at the toot of the log folder to see if it has been updated within the last hour. if it has we use that for the logfile snippet.
            $SqlRootSummaryFile = Get-ChildItem "\\$TargetServer\C`$\Program Files\Microsoft SQL Server\*\Setup Bootstrap\Log\Summary.txt" | Sort-Object LastWriteTime | Select-Object -Last 1

            if($SqlRootSummaryFile.CreationTime -gt $LastHour) {
                $SqlInstallLogFile = $SqlRootSummaryFile.FullName
            }
            else {
                $SqlInstallLogFile = Get-ChildItem "\\$TargetServer\C$\Program Files\Microsoft SQL Server\*\Setup Bootstrap\Log\*\Summary*.txt" | Where-Object CreationTime -gt $LastHour | Sort-Object CreationTime | Select-Object -Last 1 -ExpandProperty FullName
            }

            if($SqlInstallLogFile) {
                Write-SPUpdate "Log file located at $SqlInstallLogFile." -UpdateType Normal -Logfile $LogFile
                Write-SPUpdate "Logfile snippet: " -UpdateType Info -Logfile $LogFile
                Get-Content $SqlInstallLogFile -First 14 | Out-String | Write-SPUpdate -Logfile $LogFile -NoTimeStamp
            }
            else {
                Write-SPUpdate "No summary log created in the last hour, may have been an issue with patching. " -UpdateType Warning -Logfile $LogFile
            }
        }
        #Otherwise log the fact setup.exe never completed. 
        else {
            Write-SPUpdate "Setup.exe never completed before timeout of 60 minutes." -UpdateType Error -Logfile $LogFile
        }

        #Check if update was installed successfully.
        $InstancePatchDetails = Get-SPInstancePatchDetails -SqlInstance $TargetInstance
        $InstancePatchLevel = $InstancePatchDetails.PatchVersion

        if ($PatchFileVersion -eq $InstancePatchLevel) {
            Write-SPUpdate "Latest patch $PatchFileName successfully installed on $TargetInstance" -UpdateType Success -Logfile $LogFile
            ($InstancePatchDetails | Format-Table | Out-String).Trim() | Write-SPUpdate -Logfile $Logfile

            Write-SPUpdate "Removing extracted patch folder..." -UpdateType Normal -Logfile $LogFile
            $NetworkExtractFolder = "\\$TargetServer\" + ($ExtractFolder -replace ':', '$')
            Remove-Item $NetworkExtractFolder -Recurse

            Write-SPUpdate "Removing patch .exe file..." -UpdateType Normal -Logfile $LogFile
            Remove-Item $NetworkFilePath
        }
        else {
            Write-SPUpdate "Patch was not installed. You may need to do it manually. Run $LocalFilePath on the server." -UpdateType Error -Logfile $LogFile
            break
        }            

        Write-SPUpdate "Server needs to be rebooted after the SQLServer patch install. Doing this now..." -UpdateType Normal -Logfile $LogFile
    
        try {
            Restart-Computer -ComputerName $TargetServer -Wait -For PowerShell -Timeout 900 -Delay 10 -Force -ErrorAction Stop
            Write-SPUpdate  "$TargetServer rebooted after install." -UpdateType Success -Logfile $LogFile
        }
    
        catch {
            Write-SPUpdate  "$TargetServer could not be rebooted after the patch install. You mau have to do it manually. " -UpdateType Error -Logfile $LogFile
            break
        }
        
    }
}# End Install-SPSqlPatchFile
