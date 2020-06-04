function Save-SPSqlPatch {  
    <#
    .SYNOPSIS
    Function to download the latest available Service Packs and Cumulative Updates for SQL Server.

    .DESCRIPTION
    This function uses the Get-SPSqlPatch function from this module to get the latest available patches for SQL Server. It then gets the KB number from the resultset, and uses the Save-KBFile function to download the latest Service Pack and/or Cumulative Update, into a special folder structure within $DownloadDirectory. The folder structure is;
    - For versions that don't have Service Packs (2017 and newer) 
      - $DownloadDirectory\SQL $SqlVersion\$CUNumber
    - For versions that have Service Packs (2016 and older) 
      - $DownloadDirectory\SQL $SqlVersion\$SPNumber\$SPandCUName

    .PARAMETER SqlVersion
    Version of SQL to check and download patches for.

    .PARAMETER DownloadDirectory
    Where to download the files and create the special folder structure.

    .PARAMETER PatchAge
    Minimum age of the patch before it's downloaded.

    .EXAMPLE
    PS C:\> Save-SPSqlPatch -DownloadDirectory "C:\SqlPatches\"
    
    This will download all of the latest SQL Server patches for every version into "C:\SqlPatches\", 2008 and up.

    .EXAMPLE
    PS C:\> Save-SPSqlPatch -DownloadDirectory "C:\SqlPatches\" -PatchAge 28
    
    This will download all of the latest SQL Server patches for every version, but only downloads the patch if it's older than 28 days.

    .EXAMPLE
    PS C:\> Save-SPSqlPatch -SqlVersion "2017", "2016"
    
    Downloads the latest patches for SQL Version 2017 and 2016 and creates the special folder structure within the current directory.

    .NOTES
    Author: Patrick Cull
    
    This function uses the brilliant Save-KBFile to download the patches, which was taken from here https://gist.github.com/potatoqualitee/b5ed9d584c79f4b662ec38bd63e70a2d 
    I've slightly modified the Save-KBFile so it retries downloads if they fail, and made it only check for english patchfiles so only one is returned.
    #>
    [Cmdletbinding()] 
    param(    
        #Directory to download the patch to.
        [Parameter(Mandatory)]
        [string] $DownloadDirectory,

        #The server version(s) to download the patches for.
        [string[]] $SqlVersion = @("2008", "2008 R2", "2012", "2014", "2016", "2017", "2019"),

        #Minimum age in days the patch needs to be to download.
        [int]$PatchAge = 0,

        [switch] $DoNotCreateFolderStructure
    )

    #Setup proxy credentials in case they're needed.
    $browser = New-Object System.Net.WebClient
    $browser.Proxy.Credentials =[System.Net.CredentialCache]::DefaultNetworkCredentials 

    $LatestPatches = Get-SPSqlPatch

    foreach($Version in $SqlVersion) {
        Write-Verbose "`r`n`r`n################################################`r`nSQL Server $Version`r`n################################################"

        #Get the latest patch available for each version
        $LatestPatchInfo = $LatestPatches | Where-Object ProductVersions -like "*$Version" | Select-Object ProductVersions, LatestServicePack, LatestSPDownLoadLink, LatestCumulativeUpdate, LatestCUDownloadLink, CUReleaseDate -First 1

        Write-Verbose "Latest patch info:"
        $LatestPatchInfo | Out-String | Write-Verbose

        #If the release date is N/A, we download it.
        if($LatestPatchInfo.CUReleaseDate -eq "N/A") {
            [datetime]$CUReleaseDate = "01/01/2000" 
        }
        else {
            [datetime]$CUReleaseDate = $LatestPatchInfo.CUReleaseDate
        }
        
        #Check the patch is old enough before downloading.
        $MinimumPatchAge = (Get-Date).AddDays(-$PatchAge)

        if($CUReleaseDate -lt $MinimumPatchAge) {
            $SqlVersion = ($LatestPatchInfo.ProductVersions -split " ")[2]

            #Logic needed to split 2008 and 2008 R2
            if($SqlVersion -eq "2008") {
                #Check for R2 release
                $ReleaseNum = ($LatestPatchInfo.ProductVersions -split " ")[3]
                if($ReleaseNum -eq "R2") {
                    $SqlVersion = $SqlVersion + " $ReleaseNum"
                }
            }

            $CUNumber = $LatestPatchInfo.LatestCumulativeUpdate
            $SPNumber = $LatestPatchInfo.LatestServicePack

            #We do this for folder naming. 
            if($CUNumber.Length -eq 3) {
                $CUNumber = $CUNumber -replace "CU", "CU0"
            }

            $CUDownloadUrl = $LatestPatchInfo.LatestCUDownloadLink

            if(!$CUDownloadUrl) {
                $CUDownloadUrl = $LatestPatchInfo.LatestSPDownLoadLink
            }


            $CUKBNumber = ($CUDownloadUrl -split '/')[-1]

            $SPDownloadDirectory = $null
            $SPDownloadStatus = $null
            $CUDownloadDirectory = $null
            $CUDownloadStatus = $null

            #SQL 2017 and up do not have SPs
            if($SqlVersion -ge 2017) {
                if($DoNotCreateFolderStructure) {
                    $CUDownloadDirectory = "$DownloadDirectory"
                }
                else {
                    $CUDownloadDirectory = "$DownloadDirectory\SQL $SqlVersion\$CUNumber"
                }
            }

            #Else we check for SP files and download the latest.
            else {
                if($LatestPatchInfo.LatestSPDownLoadLink) {
                    $SPDownloadLink = $LatestPatchInfo.LatestSPDownLoadLink

                    #2012 latest download has different URL style
                    if($Version -eq 2012) {
                        $SPKBNumber = ($SPDownloadLink -split '/')[-2]      
                    }
                    else {
                        $SPKBNumber = ($SPDownloadLink -split '/')[-1]
                    }

                    Write-Verbose "Downloading $SPNumber for SQL $SqlVersion"

                    if($DoNotCreateFolderStructure) {
                        $SPDownloadDirectory = "$DownloadDirectory"
                    }
                    else {
                        $SPDownloadDirectory = "$DownloadDirectory\SQL $SqlVersion\$SPNumber\"
                    }


                    if(!(Test-Path $SPDownloadDirectory)) {mkdir $SPDownloadDirectory -Force | Out-Null}

                    $DownloadOutput = @()
                    $DownloadOutput = Save-KBFile -Name $SPKBNumber -Path $SPDownloadDirectory -Architecture x64

                    $DownloadResult = $DownloadOutput[0]
                    $DownloadFile = $DownloadOutput[1]

                    if($DownloadResult -eq "AlreadyDownloaded") {
                        Write-Verbose "$DownloadFile file already exists in $SPDownloadDirectory, skipping download."
                        $SPDownloadStatus = "AlreadyDownloaded"
                    }
                    elseif($DownloadResult -eq "CantQueryWebsite") {
                        Write-Verbose "Error querying the microsoft website for the KBFile."
                        $CUDownloadStatus = "Error."
                    }
                    elseif($DownloadResult -eq "CantConnectToDownloadWebsite") {
                        Write-Error "Unable to connect to the download website http://download.windowsupdate.com - the file will have to be downloaded manually"
                    }
                    elseif($DownloadResult -eq "DownloadedSucessfully"){
                        Write-Verbose "$DownloadFile for SQL $Version successfully downloaded to $SPDownloadDirectory"
                        $SPDownloadStatus = "Success"
                    }
                    else {
                        Write-Warning "Issue downloading $SPNumber for SQL $Version. Try downloading manually. "
                        $SPDownloadStatus = "Error"
                    }
                }

                $SPandCUName = $SPNumber + $CUNumber
                $CUDownloadDirectory = "$DownloadDirectory\SQL $SqlVersion\Patches\$SPNumber\$SPandCUName\"
            }

            #If a CU exists.
            if(($CUNumber -ne 'N/A') -and ($CUNumber)) {
                Write-Verbose "Downloading $CUNumber for SQL $SqlVersion from $CUDownloadUrl"

                if(!(Test-Path $CUDownloadDirectory)) {mkdir $CUDownloadDirectory -Force | Out-Null}


                $DownloadOutput = @()
                $DownloadOutput = Save-KBFile -Name $CUKBNumber -Path $CUDownloadDirectory -Architecture x64

                $DownloadResult = $DownloadOutput[0]
                $DownloadFile = $DownloadOutput[1]
  
                if($DownloadResult -eq "AlreadyDownloaded") {
                    Write-Verbose "$DownloadFile file already exists in $CUDownloadDirectory, skipping download."
                    $CUDownloadStatus = "AlreadyDownloaded"
                }
                elseif($DownloadResult -eq "CantQueryWebsite") {
                    Write-Verbose "Error querying the microsoft website for the KBFile."
                    $CUDownloadStatus = "Error."
                }
                elseif($DownloadResult -eq "CantConnectToDownloadWebsite") {
                    Write-Error "Unable to connect to the download website http://download.windowsupdate.com - the file will have to be downloaded manually"
                    $CUDownloadStatus = "Error"
                }
                elseif($DownloadResult -eq "DownloadedSucessfully"){
                    Write-Verbose "$CUNumber for SQL $Version successfully downloaded to $CUDownloadDirectory "
                    $CUDownloadStatus = "Success"
                }
                else {
                    Write-Verbose "Issue downloading $CUNumber for SQL $Version. Try downloading manually. "
                    $CUDownloadStatus = "Error"
                }
            }
        }

        else {
            Write-Warning "CU has not been out for over $PatchAge days yet, skipping download."
        }

        $LatestPatchInfo | Add-Member -NotePropertyName SPDownloadStatus -NotePropertyValue  $SPDownloadStatus
        $LatestPatchInfo | Add-Member -NotePropertyName SPDownloadDirectory -NotePropertyValue  $SPDownloadDirectory
        $LatestPatchInfo | Add-Member -NotePropertyName CUDownloadStatus -NotePropertyValue  $CUDownloadStatus
        $LatestPatchInfo | Add-Member -NotePropertyName CUDownloadDirectory -NotePropertyValue  $CUDownloadDirectory
        
        $LatestPatchInfo | Select-Object ProductVersions, LatestServicePack, LatestSPDownloadLink, SPDownloadDirectory, SPDownloadStatus, LatestCumulativeUpdate, CUReleaseDate, LatestCUDownloadLink, CUDownloadDirectory, CUDownloadStatus
    }
}
