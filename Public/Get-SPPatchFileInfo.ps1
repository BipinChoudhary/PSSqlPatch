function Get-SPPatchFileInfo { 
	<#
	.SYNOPSIS
	Function that gets the SQL version info from SQL Server patch files.  Can pass a directory or a full file path to the patch file.

    .EXAMPLE
	Get-SPPatchFileInfo "C:\SqlPatches\"

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
        [string[]] $Path
    )

    Get-ChildItem $Path -Recurse -Filter "*.exe" | ForEach-Object {

        $PatchFileInfo = $_
        $SqlServerVersion = ($PatchFileInfo.VersionInfo.ProductName -replace "Microsoft ") -replace  '\(64-bit\)'

        #If it is a sqlserver exe file, we get the patch related details of the file.
        if($SqlServerVersion -like "*SQL Server*") {
            
            $PatchFileSizeMB = [math]::Round(($PatchFileInfo.Length/1024/1024), 2)
            $PatchFileVersion = $PatchFileInfo.VersionInfo.FileVersion

            $PatchFileName = $PatchFileInfo.Name
            $SourcePatchDirectory = $PatchFileInfo.DirectoryName

            $PatchVersionSplit = $PatchFileVersion -split '\.'
            $SPNumber = $PatchVersionSplit[1]
            if($SPNumber -eq "0") {
                $SPNumber = $null
            }
            #SQL 2008 R2 uses two numbers for the SP number
            elseif($SPNumber.Length -eq 2) {
                $SPNumber = $SPNumber[-1]
            }

            #Checking the file description for the required strings makes sure the functionn returns only patch files.
            $PatchFileDescription = $PatchFileInfo.VersionInfo.FileDescription

            if($PatchFileDescription -like "*Service Pack*") {
                $PatchType = "ServicePack"
            }
            elseif($PatchFileDescription -like "*SQL Server Update*" -or $PatchFileDescription -like '*Hotfix pack*' ) {
                $PatchType = "CumulativeUpdate"
            }
            else {
                $PatchType = $null
            }

            #If the filename is in the default format, we extract the KB number as well.
            $KBNumber = $null
            if(($PatchFileName -split '-')[1] -like 'KB*') {
                $KBNumber = ($PatchFileName -split '-')[1]
            }

            #If there is a patch type we know it's a patch file, therefore we return the object.
            if($PatchType) {
                [PSCustomObject][Ordered] @{
                    SqlVersion = $SqlServerVersion.Trim()
                    PatchFileVersion = $PatchFileVersion
                    PatchType = $PatchType
                    ServicePack = $SPNumber
                    KBNumber = $KBNumber
                    PatchFileDirectory = $SourcePatchDirectory
                    PatchFileName = $PatchFileName
                    PatchFileSizeMB  = $PatchFileSizeMB              
                }
            }
        }
    }
}