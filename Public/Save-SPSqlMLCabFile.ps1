function Save-SPSqlMLCabFile {  
    <#
    .SYNOPSIS
    This function downloads cab files required for patching Machine Learning services in SQL Server

    .DESCRIPTION
    This function uses the Get-SPSqlMLCabFile function to get the latest available patches for SQL Server. 
    
    If the DoNotCreateFolderStructure is not set, it then uses the DownloadLink property to save the files to a special folder structure;
    - For versions that don't have Service Packs (2017 and newer) 
      - $DownloadDirectory\SQL $SqlVersion\$CUNumber\MLCabFiles
    - For versions that have Service Packs (2016 and older) 
      - $DownloadDirectory\SQL $SqlVersion\$SPNumber\$SPandCUName\MLCabFiles

    If FullDownloadDirectory is specified, it downloads the files directly into that folder instead.

    .EXAMPLE
    PS C:\> Save-SPSqlMLCabFile -RootDownloadDirectory "C:\SqlPatches"
    
    Downloads the latest available cabs for the default SQL version 2017 into a structured folder layout within "C:\SqlPatches".

    .EXAMPLE
    PS C:\> Save-SPSqlMLCabFile -SqlVersion "2019" -FullDownloadDirectory "C:\test\"

    Downloads the latest available cabs for SQL 2019 and places them directly into the "C:\test" folder. 

    .EXAMPLE
    PS C:\> Save-SPSqlMLCabFile -SqlVersion "2017" -CumulativeUpdate CU17 -RootDownloadDirectory "C:\SqlPatches"

    Downloads the cabs for CU17 for SQL 2017 into a structured folder layout within "C:\SqlPatches" folder.

    .EXAMPLE
    PS C:\> Save-SPSqlMLCabFile -SqlVersion "2019" -RootDownloadDirectory "C:\SqlPatches" -LatestCabOnly:$false

    Downloads ALL available cabs for each CU for SQL 2017, into a structured folder layout within "C:\SqlPatches"

    .NOTES
    Author: Patrick Cull
    Date: 2020-03-26
    #>
    [Cmdletbinding()] 
    param(    

        #Directory to download the cab file to.
        [Parameter(Mandatory)]
        [string]$DownloadDirectory,

        #The SQL version download the files for.
        [ValidateRange(2016,2100)]
        [int] $SqlVersion,

        #The cumulative Update to download the cab files for.
        [string] $CumulativeUpdate,
        
        #The Service Pack to download the cab files for. Only to be used when SqlVersion is 2016 (SQL Server older than 2016 do not have Machine Learning cab files, newer has no CumulativeUpdate)
        [string] $ServicePack,

        [switch] $DoNotCreateFolderStructure,


        #By default it will only download the latest cab file. IF this is set to false it will download every cab file available.
        [switch]$LatestCabOnly=$true
    )

    if($SqlVersion -ne "2016" -and $ServicePack) {
        Throw "ServicePack can only be specified with SQL Server 2016"
    }

    if($SqlVersion -eq "2016" -and !$DoNotCreateFolderStructure) {
        Write-Warning "Due to the variable CU listings on the MS website for SQL Server 2016 cab files, folder structure may be different. e.g. One instance of the CU column is 'CU1-CU5' so a folder with that name will be created. "
    }

    #Setup proxy credentials in case they're needed.
    $browser = New-Object System.Net.WebClient
    $browser.Proxy.Credentials =[System.Net.CredentialCache]::DefaultNetworkCredentials 

    $MLCabFiles = Get-SPSqlMLCabFile

    $AllCUGroups = $MLCabFiles | Where-Object SqlVersion -like "*$SqlVersion" | Group-Object -Property CumulativeUpdate

    #If user has specified a CumulativeUpdate number, we use that. 
    if($CumulativeUpdate) {
        Write-Verbose "Getting cab files for $CumulativeUpdate"
        $CUGroups = $AllCUGroups | Where-Object Name -eq $CumulativeUpdate
    }

    #Otherwise we either get the cabs for the latest CU (Default), or get all available for all CU's, if the user has set "LatestCabOnly=$false"
    else {
        if($LatestCabOnly) {
            $CUGroups = $AllCUGroups[0]
        }
        else {
            $CUGroups = $AllCUGroups
        }
    }

    #If user has specified a service pack, we only download files for that one.
    if($ServicePack) {
        $CUGroups = $CUGroups | Where-Object {$_.Group.ServicePack -eq $ServicePack}
    }

    if(!$CUGroups) {
        Write-Warning "No cab files found for the given search criteria. Use Get-SPSqlMLCabFile to list available cab files."
    }

    foreach($Group in $CUGroups) {

        foreach($CabFile in $Group.Group) {
            $version = $CabFile.SqlVersion
            $CUNumber = $CabFile.CumulativeUpdate
            $SPNumber = $CabFile.ServicePack

            $ShortSqlVersion = ($version -split " ")[2]

            #We do this for folder naming. 
            if($CUNumber.Length -eq 3) {
                $CUNumber = $CUNumber -replace "CU", "CU0"
            }
            
            $FileName = $CabFile.CabName
            $link = $CabFile.DownloadLink

            if(!$DoNotCreateFolderStructure) {
                if($SPNumber) {
                    $SPandCUNumber = $SPNumber + $CUNumber
                    $DownloadPath = "$DownloadDirectory\SQL $ShortSqlVersion\$SPNumber\$SPandCUNumber\$CUNumber\MLCabFiles"                  
                }
                else {
                    $DownloadPath = "$DownloadDirectory\SQL $ShortSqlVersion\$CUNumber\MLCabFiles"
                }
            }
            else {
                $DownloadPath = $DownloadDirectory
            }

            $FilePath = "$DownloadPath\$FileName"

            mkdir $DownloadPath -Force | Out-Null

            if(!(Test-Path $FilePath)) {
                Write-Verbose "Downloading $Filename to $DownloadPath"

                Write-Progress -Activity "Downloading $FilePath" -Id 1
                (New-Object Net.WebClient).DownloadFile($link, $FilePath)
                Write-Progress -Activity "Downloading $FilePath" -Id 1 -Completed

                if((Test-Path $FilePath)) {
                    Write-Verbose "$Filepath downloaded successfully."
                    $DownloadStatus = "Success"
                }
                else {
                    Write-Verbose "$Filepath download failed."
                    $DownloadStatus = "Error"
                }
            }

            else {
                Write-Verbose "$Filepath already exists, skipping download."
                $DownloadStatus = "AlreadyDownloaded"
            }

            [PSCustomObject][Ordered] @{
                SqlVersion = $version
                CumulativeUpdate = $CUNumber
                FilePath = $FilePath
                DownloadStatus = $DownloadStatus
            }
        }
    }
}
