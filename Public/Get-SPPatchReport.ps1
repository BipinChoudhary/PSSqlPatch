function Get-SPPatchReport {  
    <#
	.SYNOPSIS
	This function is used to check if a given SQL server is patched to the latest applicable patch in a given patch file directory.

	.DESCRIPTION
    The function accepts a server name and the patch directory which stores the SQL Server patches, and then checks to see if a newer applicable patch is available in the patch file directory.

	.EXAMPLE
    Get-SPPatchReport -TargetServer "Server1", "Server2", "Server3" -SoftwareRootDirectory "C:\SqlPatches\"
    
    This will check the current version of SQL installed on Server1 on an automatically retrieved instance name, compare it with the latest applicable patch availble within C:\SqlPatches\ and it's subfolders, and then apply it if it's not already patched to that level.

    .EXAMPLE
    Get-Content serverlist.txt | Get-SPPatchReport -PatchFileObject $PatchFileList
    
    This does the same as the first example, but instead of scanning a directory for patches, it uses the $PatchFileObject to get the latest applicable patch from. The $PatchFileObject object can be created with the Get-SPPatchFileInfo function.

	.NOTES
	Author : Patrick Cull
	Date : 2019-09-01
	#> 
    [Cmdletbinding(DefaultParameterSetName = 'PatchDirectory')]
    param(    
        #The servers to check
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]] $TargetServer,

        #Directory that contains the patch files. This directory will be scanned recursively for SQL Server patch files. Mutually exclusive of the $PatchFileObject parameter.
        [Parameter(ParameterSetName = 'PatchDirectory', Mandatory)]
        [string]$PatchFileDirectory,

        #Patch object that is returned by the function Get-SPPatchFileInfo. Mutually exclusive of the $PatchFileDirectory parameter.
        [Parameter(ParameterSetName = 'PatchObject', Mandatory)]
        [object[]]$PatchFileObject
    )

    begin {
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

        #If a PatchFileObject has not been passed, create one by passing the PatchFileDirectory to the Get-SPPatchFileInfo function.
        if(!$PatchFileObject) {
            $PatchFileInfo = Get-SPPatchFileInfo -Path $PatchFileDirectory
        }
        else {
            $PatchFileInfo = $PatchFileObject
        }
    }


    process {
        
        foreach($server in $TargetServer) {
            #Get an instance to check the patchlevel.
            $InstanceList = Get-SPSqlInstanceList $server -InstanceNamesOnly -RunningOnly

            if(!$InstanceList) {
                Write-Warning "Could not get SQL instance list on $server. There are no running instances or server is inaccessible."
            }

            else {
                #If there are more than 1 instances, we use the first one. Otherwise the single instance is used.
                if($InstanceList.Count -gt 1) {
                    $InstanceName = $InstanceList[0]
                }
                else {
                    $InstanceName = $InstanceList
                }

                Write-Verbose "Using instance $InstanceName to check the patch number of $server"

                #Set target instance - we don't include the MSSQLServer part if it's a default 
                if ($InstanceName -eq "MSSQLSERVER") {
                    $TargetInstance = $server
                }
                else {
                    $TargetInstance = "$server\$InstanceName"
                }

                $InstancePatchDetails = Get-SPInstancePatchDetails -SqlInstance $TargetInstance

                $SqlVersion = $InstancePatchDetails.SqlVersion
                $ApplicablePathes = $PatchFileInfo | Where-Object SqlVersion -eq $SqlVersion

                $HighestPatchAvailable = ($ApplicablePathes.PatchFileVersion | Measure-Object -Maximum).Maximum

                $InstancePatchVersion = $InstancePatchDetails.PatchVersion

                if($HighestPatchAvailable -gt $InstancePatchVersion) {
                    $PatchRequired = $true
                }
                else {
                    $PatchRequired = $false
                }

                [PSCustomObject][Ordered] @{
                    ServerName = $server
                    InstanceChecked = $InstanceName
                    InstancePatchVersion = $InstancePatchVersion
                    LatestPatchVersion = $HighestPatchAvailable
                    PatchRequired = $PatchRequired
                }
            }
        }#end foreach server

    }#end process

}#end Get-SPPatchReport