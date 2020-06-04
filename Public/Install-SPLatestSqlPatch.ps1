function Install-SPLatestSqlPatch {  
    <#
	.SYNOPSIS
	This script is used to patch SQL Server to the latest applicable patch available in a specified share.

	.DESCRIPTION
    The function accepts a server name and the patch directory which stores the SQL Server patches, and then applies the latest applicable one if it's not already installed.
    The InstanceName parameter is the instance used to check the existing patch level. If not passed, it's automatically got from the server.
    ALL instances on the given servername will be patched. It does not only patch the InstanceName given.
    The function will apply the latest applicable service pack first if required.

	.EXAMPLE
    Install-SPLatestSqlPatch -TargetServer "Server1" -SoftwareRootDirectory "C:\SqlPatches\"
    
    This will check the current version of SQL installed on Server1 on an automatically retrieved instance name, compare it with the latest applicable patch availble within C:\SqlPatches\ and it's subfolders, and then apply it if it's not already patched to that level.

    .EXAMPLE
    Install-SPLatestSqlPatch -TargetServer "Server1" -PatchFileObject $PatchFileList
    
    This does the same as the first example, but instead of scanning a directory for patches, it uses the $PatchFileObject to get the latest applicable patch from. The $PatchFileObject object can be created with the Get-SPPatchFileInfo function.
	.NOTES
	Author : Patrick Cull
	Date : 2019-09-01
	#> 
    [Cmdletbinding(DefaultParameterSetName = 'PatchDirectory')]
    param(    
        #The server to be patched.
        [Parameter(Mandatory)]
        [string] $TargetServer,

        #Directory that contains the patch files. This directory will be scanned recursively for SQL Server patch files. Mutually exclusive of the $PatchFileObject parameter.
        [Parameter(ParameterSetName = 'PatchDirectory', Mandatory)]
        [string]$PatchFileDirectory,

        #Patch object that is returned by the function Get-SPPatchFileInfo. Mutually exclusive of the $PatchFileDirectory parameter.
        [Parameter(ParameterSetName = 'PatchObject', Mandatory)]
        [object[]]$PatchFileObject,

        #Instance that will be used to check the patch level. If this is not set, an instance name is automatically retrieved. All instances on the server will be patched, this is just used to check the patch level.
        [string] $InstanceName,

        #Location of logfile.
        [string] $LogFile,
        
        #Directory for the log files to be created.
        $LogFileDirectory = "C:\Users\$env:UserName\AppData\Local\PSSqlPatch\logs\Install-SPLatestSqlPatch",
        
        #If passed, user does not receive any prompts to confirm continue.
        [switch] $Force
    )
    
    if (!$Logfile) {
        if (!(Test-Path $LogFileDirectory)) { mkdir $LogFileDirectory -Force -ErrorAction Stop }   
        $LogDate = Get-Date -UFormat "%Y%m%d_%H%M"
        $LogFile = "$LogFileDirectory\${TargetServer}_${LogDate}.log"
        Write-SPUpdate "LogfilePath: $LogFile" -UpdateType Normal -Logfile $LogFile
    }    
    
    #If a patchfile object is passed, we need to ensure it's in the correct format.
    if($PatchFileObject) {
        $requiredProperties = @("SqlVersion","PatchFileVersion","PatchType","ServicePack","PatchFileDirectory","PatchFileName","PatchFileSizeMB")
        $PatchObjectMembers = Get-Member -InputObject $PatchFileObject[0] -MemberType NoteProperty
        
        if(!$PatchObjectMembers){
            Write-SPUpdate "Could not get object properties. Ensure a Get-SPPatchFileInfo object was passed." -UpdateType Error -Logfile $LogFile
            break 0
        }
        
        $missingProperties = Compare-Object -ReferenceObject $requiredProperties -DifferenceObject $PatchObjectMembers.Name -PassThru -ErrorAction SilentlyContinue
        if ($missingProperties){          
            Write-SPUpdate "-PatchFileObject not in the correct format." -UpdateType Error -Logfile $LogFile
            Write-SPUpdate "Expected object properties:" -UpdateType Error -Logfile $LogFile
            $requiredProperties | Out-String | Write-SPUpdate -Logfile $LogFile -NoTimeStamp
            Write-SPUpdate "Given object properties:" -UpdateType Error -Logfile $LogFile
            $PatchObjectMembers.Name | Out-String | Write-SPUpdate -Logfile $LogFile -NoTimeStamp
            Write-SPUpdate "You need to pass the requried output of Get-SPPatchFileInfo as the -PatchFileObject parameter" -UpdateType Error -Logfile $LogFile
            break 0
        }
    }
        
    #Check if the target is up. 
    if(!(Test-Connection -ComputerName $TargetServer -Count 1)) {
        Write-SPUpdate "$TargetServer is down or inaccessible." -UpdateType Error -Logfile $LogFile
        break 0
    }

    # If the user does not pass an instance name, we get the first instance on the server and use that to check patch number.
    if(!$InstanceName) {
        Write-SPUpdate "No specific instance name given. Getting instance from server" -UpdateType Normal -Logfile $LogFile

        $InstanceList = Get-SPSqlInstanceList $TargetServer -InstanceNamesOnly -RunningOnly

        if(!$InstanceList) {
            Write-SPUpdate "Could not get instance list on $TargetServer. There are no running instances or server is inaccessible." -UpdateType Error -Logfile $LogFile
            break 0
        }

        #If there are more than 1 instances, we use the first one. Otherwise the single instance is used.
        if($InstanceList.Count -gt 1) {
            $InstanceName = $InstanceList[0]
        }
        else {
            $InstanceName = $InstanceList
        }

        Write-SPUpdate "Using instance $InstanceName to check the patch number of the server." -UpdateType Normal -Logfile $LogFile
    }


    #Set target instance - we don't include the MSSQLServer part if it's a default 
    if ($InstanceName -eq "MSSQLSERVER") {
        $TargetInstance = $TargetServer
    }
    else {
        $TargetInstance = "$TargetServer\$InstanceName"
    }
    
    $InstancePatchDetails = Get-SPInstancePatchDetails -SqlInstance $TargetInstance

    Write-SPUpdate "Instance patch details;" -UpdateType Info -Logfile $LogFile
    ($InstancePatchDetails | Format-List | Out-String).Trim() | Write-SPUpdate -Logfile $Logfile

    if(!$InstancePatchDetails) {
        Write-SPUpdate "Unable to retrieve instance information." -UpdateType Error -Logfile $LogFile    
        break 0
    }

    
    #If a PatchFileObject has not been passed, create one by passing the PatchFileDirectory to the Get-SPPatchFileInfo function.
    if(!$PatchFileObject) {
        $PatchFileInfo = Get-SPPatchFileInfo -Path $PatchFileDirectory
    }
    else {
        $PatchFileInfo = $PatchFileObject
    }

    $SqlVersion = $InstancePatchDetails.SqlVersion
    $ApplicablePathes = $PatchFileInfo | Where-Object SqlVersion -eq $SqlVersion
    $LatestServicePackNumber = $null

    # With SQL 2016 and older we need to get latest Service Pack available.
    if($InstancePatchDetails.SqlVersion -le "SQL Server 2016") {
        #Get the highest numbered service pack available on the share. 
        $LatestServicePackNumber = ($ApplicablePathes.ServicePack | Measure-Object -Maximum).Maximum

        Write-SPUpdate "Latest available Service Pack is SP$LatestServicePackNumber" -UpdateType Normal -Logfile $LogFile

        if($LatestServicePackNumber) {
            if($LatestServicePackNumber -gt $InstancePatchDetails.ServicePack) {
                
                $LatestServicePackFile = $ApplicablePathes | Where-Object{$_.PatchType -eq "ServicePack" -and $_.ServicePack -eq $LatestServicePackNumber}
                $LatestSPLocation = $LatestCumlativeUpdate.$LatestServicePackFile + "\" + $LatestServicePackFile.PatchFileName
                Write-SPUpdate "Applying Service Pack SP$LatestServicePackNumber from $LatestSPLocation" -UpdateType Info -Logfile $LogFile
                Install-SPSqlPatchFile -TargetServer $TargetServer -InstanceName $InstanceName -SourcePatchFile $LatestSPLocation -Logfile $LogFile -Force:$Force
            
            }
            
            elseif ($LatestServicePackNumber -eq $InstancePatchDetails.ServicePack) {
                Write-SPUpdate "Latest service pack SP$LatestServicePackNumber is already installed on $TargetInstance." -UpdateType Success -Logfile $LogFile
            }
            
            elseif ($LatestServicePackNumber -lt $InstancePatchDetails.ServicePack) {
                Write-SPUpdate "A higher Service pack - SP$LatestServicePackNumber is already installed on $TargetInstance." -UpdateType Success -Logfile $LogFile
            }
        }
        else {
            Write-SPUpdate "No applicable service packs were found in $PatchFileDirectory or it's subdirectories." -UpdateType Warning -Logfile $LogFile
            #Set the servicepack number to the one that's on the instance.
            $LatestServicePackNumber = $InstancePatchDetails.ServicePack
        }
    } 
    
    # Now, regardless of SQL version, check for the latest Cumulative Update.
    $LatestCumlativeUpdate = $ApplicablePathes | Where-Object{$_.PatchType -eq "CumulativeUpdate" -and $_.ServicePack -eq $LatestServicePackNumber} | Sort-Object PatchFileVersion | Select-Object -Last 1    
    
    if($LatestCumlativeUpdate) {
        Write-SPUpdate "Latest applicable Cumulative Update details:" -UpdateType Info -Logfile $LogFile
        ($LatestCumlativeUpdate | Format-List | Out-String).Trim() | Write-SPUpdate -Logfile $Logfile
        
        $NewestCUVersion = $LatestCumlativeUpdate.PatchFileVersion
        if($NewestCUVersion -gt $InstancePatchDetails.PatchVersion) {
            
            $LatestCULocation = $LatestCumlativeUpdate.PatchFileDirectory + "\" + $LatestCumlativeUpdate.PatchFileName
            
            Write-SPUpdate "Applying patch number $NewestCUVersion from $LatestCULocation" -UpdateType Info -Logfile $LogFile
            Install-SPSqlPatchFile -TargetServer $TargetServer -InstanceName $InstanceName -SourcePatchFile $LatestCULocation -Logfile $LogFile -Force:$Force

        }
        
        elseif($NewestCUVersion -eq $InstancePatchDetails.PatchVersion) { 
            Write-SPUpdate "Latest patch from the share - $NewestCUVersion is already installed on $TargetInstance" -UpdateType Success -Logfile $LogFile
        }
        
        elseif($NewestCUVersion -lt $InstancePatchDetails.PatchVersion) {
            Write-SPUpdate "A higher patch version is already installed on $TargetInstance." -UpdateType Success -Logfile $LogFile
        }
    }
    else {
        Write-SPUpdate "No applicable Cumulative Updates were found in $PatchFileDirectory or it's subdirectories." -UpdateType Warning -Logfile $LogFile
    }
} #end Install-SPLatestSQLPatch
