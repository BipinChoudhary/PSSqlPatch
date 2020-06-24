function Get-SPSqlPatch {
    <#
    .SYNOPSIS
    This function is used to get SQL Server patches info and return it as a PSObject

    .DESCRIPTION
    The function accesses a google excel sheet provided by "https://sqlserverbuilds.blogspot.com" which contains a list of all SQL Server patches available for each SQL Version. The function then parses the table and converts it into a PSObject, with parameters such as Cumlative Update and Service Pack download links.

    .PARAMETER SqlVersion
    The SQL Version you want to search for. If not specified the function returns patches for default SQL Versions "2008", "2008 R2", "2012", "2014", "2016", "2017", "2019"

    .EXAMPLE
    PS C:\> Get-SPSqlPatch
    
    Returns all available patches listed on "https://sqlserverbuilds.blogspot.com" for default SQL Versions "2008", "2008 R2", "2012", "2014", "2016", "2017", "2019"

    .EXAMPLE
    PS C:\> Get-SPSqlPatch -SqlVersion "2017", "2016"
    
    Returns all SQL patches available for SQL Server 2017 and SQL Server 2016

    .NOTES
    Author: Patrick Cull
    Date: 2020-03-23
    #>
	[Cmdletbinding()] 
    param(
        [string[]] $SqlVersion = @("2008", "2008 R2", "2012", "2014", "2016", "2017", "2019")
    )

    #Setup proxy credentials in case they're needed.
    $browser = New-Object System.Net.WebClient
    $browser.Proxy.Credentials =[System.Net.CredentialCache]::DefaultNetworkCredentials
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $PatchListURL   = "https://docs.google.com/spreadsheets/d/16Ymdz80xlCzb6CwRFVokwo0onkofVYFoSkc7mYe6pgw/gviz/tq?tq=&tqx=out:csv"
    $DocOutput= Invoke-WebRequest $PatchListURL | ConvertFrom-Csv

    $RelevantPatches = $DocOutput | Select-Object SQLServer, SP, CU, Build, Description, Link, ReleaseDate | Where-Object {(($_.SP -or $_.CU) -or $_.Description -like '*GDR*') -and $_.Link -and $_.ReleaseDate }

    if($SqlVersion) {
        $RelevantPatches = $RelevantPatches | Where-Object SQLServer -in $SqlVersion
    }

    #Reverse the array so we can pick up the service packs as it gets scanned and we can assign it to each following CU.
    [array]::reverse($RelevantPatches)

    $RelevantPatches | Foreach-Object {

        $SqlRelease = $_.SQLServer
        $BuildNum = $_.Build

    
        if($_.SP -eq 'TRUE') {
            $PatchType = "Service Pack"
        }
        elseif($_.CU -eq 'TRUE'){
            $PatchType = "Cumulative Update"
        }
        else {
            $PatchType = "Hotfix"
        } 

        try {
            $ReleaseDate = [datetime]::parseexact($_.ReleaseDate, 'yyyy-MM-dd', $null)
        }
        catch {
            $ReleaseError = $_.ReleaseDate
            Write-Error "$ReleaseError of $BuildNum not valid date"
        }

        $PatchNumPattern = "\((.*?)\)"
        $PatchNumber = [regex]::match($_.Description, $PatchNumPattern).Groups[1].Value

        if($SqlRelease -gt 2016) {
            $ServicePack = $null
            $CumulativeUpdate = $PatchNumber 
        }
        elseif($PatchType -eq "Service Pack") {
            $ServicePack = $PatchNumber 
            $CumulativeUpdate = $null           
        }
        else {
            $CumulativeUpdate = $PatchNumber                      
        }

        $DownloadLink = $_.Link
        $KBNumber = $DownloadLink -split '/' | Where-Object {$_ -match "^[\d\.]+$"}

        #If the KB number is not in the URL, attempt to access the downloadlink and parse the KB number from the resulting webpage.
        if(!$KBNumber) {
            $ProgressPreference = 'SilentlyContinue'
            try {
                $KBDownloadResponse = Invoke-WebRequest -Uri $DownloadLink -UseBasicParsing
            }
            catch {
                #Write-Error "Error connecting to build $BuildNum link: $DownloadLink - KB Number was not attainable." #Error checking dead links
            }
            $ProgressPreference = 'Continue'

            $KBLinkContent = $KBDownloadResponse.Content
            $KBNumberPattern = "KB(.*?)-x64"
            $KBNumber = [regex]::match($KBLinkContent, $KBNumberPattern).Groups[1].Value

            if($KBNumber -eq ""){$KBNumber = $null}
        }

        [PSCustomObject][Ordered] @{
            SqlVersion = $SqlRelease
            PatchType = $PatchType
            ServicePack = $ServicePack
            CumulativeUpdate = $CumulativeUpdate
            ReleaseDate = $ReleaseDate 
            Build = $_.Build
            Link = $DownloadLink
            KBNumber = $KBNumber
            Description = $_.Description
        }
    }
}