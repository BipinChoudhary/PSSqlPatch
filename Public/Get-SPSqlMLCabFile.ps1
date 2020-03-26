function Get-SPSqlMLCabFile {
    <#
    .SYNOPSIS
    This function accesses the Microsoft website to check the available cab files for R server and Python on SQL

    .DESCRIPTION
    The function accesses the Microsoft page "https://docs.microsoft.com/en-us/sql/advanced-analytics/install/sql-ml-cab-downloads" which displays the latest R Cab files for patches available for each SQL Version. The function then parses the table and converts it into a PSObject, with parameters such as Cumlative Update and Service Pack download links.

    .EXAMPLE
    PS C:\> Get-SPSqlMachineLearningCabFile
    
    Returns all available patches from https://docs.microsoft.com/en-us/sql/advanced-analytics/install/sql-ml-cab-downloads in a PSObject

    .NOTES
    Author: Patrick Cull
    Date: 2020-03-25
    #>
    $browser = New-Object System.Net.WebClient
    $browser.Proxy.Credentials =[System.Net.CredentialCache]::DefaultNetworkCredentials
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $MicrosoftUpdatePage = "https://docs.microsoft.com/en-us/sql/advanced-analytics/install/sql-ml-cab-downloads"     
    $WebResponse = Invoke-WebRequest -Uri $MicrosoftUpdatePage -UseBasicParsing

    # Create HTML file Object
    $HTML = New-Object -Com "HTMLFile"
    # Write HTML content according to DOM Level2 
    $HTML.IHTMLDocument2_write($WebResponse.Content)

    ## Extract the tables out of the web request
    $tables = @($HTML.getElementsByTagName("table"))

    #Table with the patch info is the first one in the page.
    #$table = $tables[0]

    foreach($table in $tables) {
        $rows = @($table.Rows)

        $RowContent = $Rows.InnerHtml

        foreach($row in $RowContent) {
            if($row -like '*SQL Server 20*CU*') {
                $SqlPattern = "SQL Server (.*?)</"
                $ShortRelease = [regex]::match($row, $SqlPattern).Groups[1].Value
                $Release = "SQL Server " + $ShortRelease

                $SplitRelease = $Release -split ' '
                $SqlVersion = $SplitRelease[0] + " " + $SplitRelease[1] + " " + $SplitRelease[2]


                if($row -like "*SP*") {
                    $ServicePack = $SplitRelease[3]
                    $CumulativeUpdate = $SplitRelease[4]
                }
                else {
                    $ServicePack = $null
                    $CumulativeUpdate = $SplitRelease[3]
                }

            }

            if($row -Like '*.cab*') {
               $SplitRow = ($row -split "<TD>" -replace '</TD>').Trim()
                $SplitRow = $SplitRow | Where-Object {$_} #Remove duplicates
                $SecondaryTitle = $SplitRow[0]

                $DownloadInfo = $SplitRow[1]

                $Namepattern = "data-linktype=`"external`">(.*?)</A>"
                $DownloadName = [regex]::match($DownloadInfo, $Namepattern).Groups[1].Value

                $LinkPattern = "href=`"(.*?)`""
                $DownloadLink = [regex]::match($DownloadInfo, $LinkPattern).Groups[1].Value -replace '&amp;', '&'

                [PSCustomObject][Ordered] @{ 
                    SqlVersion = $SqlVersion
                    ServicePack = $ServicePack
                    CumulativeUpdate = $CumulativeUpdate
                    CabFileType = $SecondaryTitle
                    CabName = $DownloadName
                    DownloadLink = $DownloadLink
                }
            }
        }
    
    }#end foreach table
}