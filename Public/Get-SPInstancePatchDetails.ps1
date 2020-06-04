function Get-SPInstancePatchDetails { 
	<#
	.SYNOPSIS
	Function that gets the SQL patch level and details from a SQL instance.

    .EXAMPLE
	Get-SPInstancePatchDetails -SqlInstance "SERVER1\SQLDEV01"

	.EXAMPLE
	Get-SPPatchFileInfo "C:\SqlPatches\SQLServer2017-KB4535007-x64.exe"

	.NOTES
	Author : Patrick Cull
	Date : 2020-05-12
	#>
    [Cmdletbinding()]
    param(    
        #The server to be patched.
        [Parameter(ValueFromPipeline, Mandatory)]
        [string] $SqlInstance
    )

    #Get the target server and instance name from the SqlInstance passed.
    $InstanceNameParts = $SqlInstance -split '\\'
    $TargetServer = $InstanceNameParts[0]
    
    if($InstanceNameParts[1]) {
        $InstanceName = $InstanceNameParts[1]
    }
    else {
        $InstanceName = "MSSQLSERVER"
    }
    
    #Get the current patchlevel of the target instance along with the location of the SQL Server ERROR log - which we use to get more info about the instance.
    $InstancePatchInfo = Invoke-Command -ComputerName $TargetServer {
        $InstanceRegPath = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL").$Using:InstanceName
        $InstanceVersionInfo = (Get-ItemProperty -path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$InstanceRegPath\Setup")

        $InstanceParameters = (Get-ItemProperty -path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$InstanceRegPath\MSSQLServer\Parameters")
        $ErrorLogLocation = ($InstanceParameters.PSObject.properties | ForEach-Object {$_.Value} | Where-Object {$_ -like "*ERRORLOG"}) -replace '-e'
        
        $InstanceVersionInfo.PatchLevel, $ErrorLogLocation
    }

    if(!$InstancePatchInfo[0]) {
        Write-Warning "Issue getting patch info of $InstanceName on $TargetServer"
    }

    else {
        $InstancePatchLevel = $InstancePatchInfo[0]
        $ErrorLogLocation = $InstancePatchInfo[1]

        $InstancePatchLevelSplit = $InstancePatchLevel -split '\.'

        #Number after the second dot in the patch level indicates the Service Pack number.
        $SPNumber = $InstancePatchLevelSplit[1]
        if($SPNumber -eq "0") {
            $SPNumber = $null
        }
        #SQL 2008 R2 uses two numbers for the SP number, the second digit is the service pack number.
        elseif($SPNumber.Length -eq 2) {
            $SPNumber = $SPNumber[-1]
        }

        $NetworkSqlServiceLogPath = "\\$TargetServer\$ErrorLogLocation" -replace ':', '$'
        
        $SqlServiceLogContent = Get-Content $NetworkSqlServiceLogPath
        $VersionString = "Microsoft " + (($SqlServiceLogContent[0]) -split "Microsoft ")[1]

        # This returns the year of the SQL Server version. 
        $Version = ($VersionString.Split(" "))[3]

        if($Version -eq "2008") {
            #Check for R2 release
            $ReleaseNum = ($VersionString.Split(" "))[4]
            if($ReleaseNum -eq "R2") {
                $Version = $Version + " $ReleaseNum"
            }
        }

        $SqlVersion =  "SQL Server $Version"

        #Check for any string after "CU" to get the instance CU number, also remove the "-GDR" string if that's in the string.
        $CUPattern = "(CU.*?)\)"
        $CUNumber = ([regex]::match($VersionString, $CUPattern).Groups[1].Value) -replace '-GDR'

        $KBPattern = "(KB.*?)\)"
        $KBNumber = ([regex]::match($VersionString, $KBPattern).Groups[1].Value)
        
        [PSCustomObject][Ordered] @{
            SqlInstance = $SqlInstance
            SqlVersion = $SqlVersion
            PatchVersion = $InstancePatchLevel
            ServicePack = $SPNumber
            CumulativeUpdate = $CUNumber
            KBNumber = $KBNumber
        }
    }
}