function Save-SPSqlPatch {  
    <#
    .SYNOPSIS
    Function to download the latest available Service Packs and Cumulative Updates for SQL Server.

    .DESCRIPTION
    This function uses the Get-SPSqlPatch function from this module to get all available patches for SQL Server. It then gets the KB number from the resultset, and uses the Save-KBFile function to download the latest Service Pack and/or Cumulative Update, into a special folder structure within $DownloadDirectory. The folder structure is;
    - For versions that don't have Service Packs (2017 and newer) 
      - $DownloadDirectory\SQL $SqlVersion\$CUNumber
    - For versions that have Service Packs (2016 and older) 
      - $DownloadDirectory\SQL $SqlVersion\$SPNumber\$SPandCUName

    .PARAMETER SqlVersion
    Version of SQL to check and download patches for.

    .PARAMETER DownloadDirectory
    Where to download the files and create the special folder structure.

    .PARAMETER PatchAge
    Minimum age of the patch in days. Defaults to 28.

    .PARAMETER ServicePack
    The Service Pack number to download. Format is SPx - e.g. SP4

    .PARAMETER CumulativeUpdate
    The Cumulative Update to download. Format is CUx - e.g CU16, CU4

    .PARAMETER DoNotCreateFolderStructure
    By default the function will create a folder structure within the DownloadDirectory, if this switch is passed, the file(s) are downloaded directly into the DownloadDirectory instead.

    .EXAMPLE
    PS C:\> Save-SPSqlPatch -DownloadDirectory "C:\SqlPatches\"
    
    This will download all of the latest Cumulative Updates and Service Packs for every version into "C:\SqlPatches\" and create structured folders within.

    .EXAMPLE
    PS C:\> Save-SPSqlPatch -SqlVersion "2017", "2016" -DownloadDirectory "C:\SqlPatches\" -PatchAge 28 -DoNotCreateFolderStructure
    
    This will download all of the latest SQL Server 2016 and 2017, but only downloads the patch if it's older than 28 days. It will not create subfolders and the files will be saved directly into "C:\SqlPatches".

    .EXAMPLE
    PS C:\> Save-SPSqlPatch -SqlVersion "2016" -ServicePack SP2 -CumulativeUpdate CU2
    
    Downloads Cumulative Update 2 for Service Pack 2 for SQL Server 2016. It will also download Service Pack 2 if it hasn't already been downloaded.

    .NOTES
    Author: Patrick Cull
    
    This function uses the brilliant Save-KBFile to download the patches, which was taken from here https://gist.github.com/potatoqualitee/b5ed9d584c79f4b662ec38bd63e70a2d 
    I've slightly modified the Save-KBFile so it retries downloads if they fail, and made it only checks for english patchfiles so only one is returned.
    #>
    [Cmdletbinding()] 
    param(    

        [Parameter(Mandatory)]
        [string] $DownloadDirectory,

        [string[]] $SqlVersion = @("2008", "2008 R2", "2012", "2014", "2016", "2017", "2019"),

        [string] $ServicePack,

        [string] $CumulativeUpdate,

        [int]$PatchAge = 0,

        [switch] $DoNotCreateFolderStructure
    )

    if(!(Test-Path $DownloadDirectory)) {
        Throw "$DownloadDirectory not acccessible"
    }

    if(($SqlVersion.Count -gt 1) -and ($ServicePack -or $CumulativeUpdate)) {
        Throw "If more than one SQL Version is passed, you cannot specify ServicePack and CumulativeUpdate."
    }

    if($SqlVersion -gt 2016 -and $ServicePack) {
        Throw "There are no service packs for SQL Server 2017 and up."        
    }

    #Setup proxy credentials in case they're needed.
    $browser = New-Object System.Net.WebClient
    $browser.Proxy.Credentials =[System.Net.CredentialCache]::DefaultNetworkCredentials 

    #remove trailing slash if it exists.
    if($DownloadDirectory[-1] -eq '\') {
        $DownloadDirectory = $DownloadDirectory -replace "$"
    }

    $PatchInfo = Get-SPSqlPatch -SqlVersion $SqlVersion

    foreach($Version in $SqlVersion) {
        Write-Verbose "`r`n`r`n################################################`r`nSQL Server $Version`r`n################################################"

        $VersionPatchInfo = $PatchInfo | Where-Object SqlVersion -like "*$Version"

        #If not specifed, we get the latest available.
        if(!$ServicePack -and !$CumulativeUpdate) {
            Write-Verbose "No Service Pack or Cumulative Update passed, defaulting to latest patch available."
            $RequestedPatch = $VersionPatchInfo | Sort-Object ReleaseDate | Select-Object -Last 1
        }
        else {
            #If Cumulative update is not set, we only download the SP specified.
            if(!$CumulativeUpdate) {
                Write-Verbose "Service Pack $ServicePack specified."
                $RequestedPatch = $VersionPatchInfo | Where-Object {$_.PatchType -eq "Service Pack" -and $_.ServicePack -eq $ServicePack} | Sort-Object ReleaseDate | Select-Object -Last 1
            }
            else {
                if($SqlVersion -gt 2016) {
                    Write-Verbose "Cumulative update $CumulativeUpdate specifed."
                    $RequestedPatch =  $VersionPatchInfo | Where-Object {$_.PatchType -eq "Cumulative Update" -and $_.CumulativeUpdate -eq $CumulativeUpdate}
                }
                else {
                    Write-Verbose "Service Pack $ServicePack Cumulative update $CumulativeUpdate specifed."
                    $RequestedPatch =  $VersionPatchInfo | Where-Object {$_.PatchType -eq "Cumulative Update" -and $_.ServicePack -eq $ServicePack -and $_.CumulativeUpdate -eq $CumulativeUpdate}
                }
            }
        }

        $RequestedPatch | Format-list | Out-String | Write-Verbose
      
        #Check the patch is old enough before downloading.
        $MinimumPatchAge = (Get-Date).AddDays(-$PatchAge)

        if($RequestedPatch.ReleaseDate -lt $MinimumPatchAge) {

            $PatchesToDownload = @()
            $CUNumber = $RequestedPatch.CumulativeUpdate
            $SPNumber = $RequestedPatch.ServicePack

            #We do this for folder naming. 
            if($CUNumber.Length -eq 3) {
                $CUNumber = $CUNumber -replace "CU", "CU0"
            }

            #If there's a Service Pack to related to the requested patch, add it to download list (if the user has not specifically requested a Service Pack on it's own)
            if($SPNumber -and $RequestedPatch.PatchType -ne 'Service Pack') {
                $SPPatch = $VersionPatchInfo | Where-Object {$_.PatchType -eq "Service Pack" -and $_.ServicePack -eq $RequestedPatch.ServicePack}  | Sort-Object ReleaseDate | Select-Object -Last 1
                $PatchesToDownload += $SPPatch
            }

            $PatchesToDownload += $RequestedPatch

            foreach($patch in $PatchesToDownload) {

                $PatchKBNumber = $patch.KBNumber
                $PatchType = $patch.PatchType

                if($DoNotCreateFolderStructure) {
                    $PatchDownloadDirectory = "$DownloadDirectory"
                    Write-Verbose "Downloading patch for SQL $Version KB $PatchKBNumber"
                }
                
                elseif($PatchType -eq 'Service Pack') {
                    $PatchDownloadDirectory = "$DownloadDirectory\SQL $Version\$SPNumber"     
                    Write-Verbose "Downloading SP $SPNumber for SQL $Version KB $PatchKBNumber"
                }
                
                elseif($PatchType -ne 'Service Pack' -and $patch.SqlVersion -lt "SQL Server 2017") {
                    
                    if($PatchType -eq "Cumulative Update") {
                        $PatchDownloadDirectory = "$DownloadDirectory\SQL $Version\$SPNumber\${SPNumber}${CUNumber}"    
                        Write-Verbose "Downloading $CUNumber for SP $SPNumber SQL $Version KB $PatchKBNumber"
                    }
                    else {
                        $PatchDownloadDirectory = "$DownloadDirectory\SQL $Version\$SPNumber\$PatchType"
                        Write-Verbose "Downloading $PatchType for SP $SPNumber SQL $Version KB $PatchKBNumber"
                                                  
                    }
                }

                else {
                    $PatchDownloadDirectory = "$DownloadDirectory\SQL $Version\$CUNumber"
                    Write-Verbose "Downloading $CUNumber for SQL $Version KB $PatchKBNumber"
                }

                mkdir $PatchDownloadDirectory -Force | Out-Null

                $DownloadOutput = @()
                $DownloadOutput = Save-KBFile -Name $PatchKBNumber -Path $PatchDownloadDirectory -Architecture x64

                $DownloadResult = $DownloadOutput[0]
                $DownloadFile = $DownloadOutput[1]

                if($DownloadResult -eq "AlreadyDownloaded") {
                    Write-Verbose "$DownloadFile file already exists in $PatchDownloadDirectory, skipping download."
                    $DownloadStatus = "AlreadyDownloaded"
                }
                elseif($DownloadResult -eq "CantQueryWebsite") {
                    Write-Verbose "Error querying the microsoft website for the KBFile."
                    $DownloadStatus = "Error"
                }
                elseif($DownloadResult -eq "CantConnectToDownloadWebsite") {
                    Write-Error "Unable to connect to the download website http://download.windowsupdate.com - the file will have to be downloaded manually"
                }
                elseif($DownloadResult -eq "DownloadedSucessfully"){
                    Write-Verbose "$DownloadFile for SQL $Version successfully downloaded to $PatchDownloadDirectory"
                    $DownloadStatus = "Success"
                }
                else {
                    Write-Warning "Issue downloading $SPNumber for SQL $Version. Try downloading manually. "
                    $DownloadStatus = "Error"
                }


                [PSCustomObject][Ordered] @{
                    SqlVersion = $patch.SqlVersion
                    PatchType = $patch.PatchType
                    ServicePack = $patch.ServicePack
                    CumulativeUpdate = $patch.CumulativeUpdate
                    ReleaseDate = $patch.ReleaseDate                   
                    DownloadStatus = $DownloadStatus
                    FilePath = "$PatchDownloadDirectory\$DownloadFile"
                    Description = $patch.Description
                    Link = $patch.Link
                }
            
            }#end foreach patch      
        }
        else {
            Write-Warning "Patch has not been out for over $PatchAge days yet, skipping download. Change the -PatchAge parameter if needed."
        }    
    }#end foreach version.
}
