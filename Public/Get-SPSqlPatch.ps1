function Get-SPSqlPatch {
    <#
    .SYNOPSIS
    This function accesses the Microsoft website to check the latest SQL Server Patch info and return it as a PSObject

    .DESCRIPTION
    The function accesses the Microsoft page "https://technet.microsoft.com/en-us/library/ff803383.aspx" which displays the latest SQL Server patches available for each SQL Version. The function then parses the table and converts it into a PSObject, with parameters such as Cumlative Update and Service Pack download links.

    .PARAMETER SqlVersion
    The SQL Version you want to search for. If not specified the function returns patches for all SQL versions.

    .EXAMPLE
    PS C:\> Get-SPSqlPatch
    
    Returns all available patches listed on https://technet.microsoft.com/en-us/library/ff803383.aspx

    .EXAMPLE
    PS C:\> Get-SPSqlPatch -SqlVersion "2017"
    
    Returns all SQL patches available for SQL Server 2017

    .NOTES
    Author: Patrick Cull
    Date: 2020-03-23
    #>
	[Cmdletbinding()] 
    param(
        [string[]] $SqlVersion
    )

    $browser = New-Object System.Net.WebClient
    $browser.Proxy.Credentials =[System.Net.CredentialCache]::DefaultNetworkCredentials
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $MicrosoftUpdatePage = "https://technet.microsoft.com/en-us/library/ff803383.aspx"     
    $WebResponse = Invoke-WebRequest -Uri $MicrosoftUpdatePage -UseBasicParsing

    # Create HTML file Object
    $HTML = New-Object -Com "HTMLFile"
    # Write HTML content according to DOM Level2 
    $HTML.IHTMLDocument2_write($WebResponse.Content)

    ## Extract the tables out of the web request
    $tables = @($HTML.getElementsByTagName("table"))

    #Table with the patch info is the first one in the page.
    $table = $tables[0]
    $titles = @()
    $rows = @($table.Rows)

    $LatestPatches = @()
    
    ## Go through all of the rows in the table
    $LatestPatches = foreach($row in $rows) {
        $cells = @($row.Cells)  

        ## If we've found a table header, remember its titles
        if($cells[0].OuterHTML -like "*<TH>*")
        {
            
            $titles = @($cells | ForEach-Object { ("" + $_.InnerText).Trim() -replace ' ' })
            continue
        }
        ## If we haven't found any table headers, make up names "P1", "P2", etc.
        if(-not $titles)
        {
            $titles = @(1..($cells.Count + 2) | ForEach-Object { "P$_" })
        }
        ## Now go through the cells in the the row. For each, try to find the
        ## title that represents that column and create a hashtable mapping those
        ## titles to content
        $resultObject = [Ordered] @{}
        for($counter = 0; $counter -lt $cells.Count; $counter++)
        {
            $title = $titles[$counter]
            if(-not $title) { continue }
        
            $resultObject[$title] = ("" + $cells[$counter].InnerHTML).Trim()
        }
        ## And finally cast that hashtable to a PSCustomObject
        [PSCustomObject] $resultObject
    }

    #Format the result into a better, more usable format.Split the SP/CU number up with the download links
    $LatestPatches | ForEach-Object {
        #Add new objects not in the table. we extract the actual download link to use separately.
        Add-Member -memberType NoteProperty -InputObject $_ -Name LatestSPDownLoadLink -Value ($_.LatestServicePack -split '"')[1]
        Add-Member -memberType NoteProperty -InputObject $_ -Name LatestCUDownloadLink -Value ($_.LatestCumulativeUpdate -split '"')[1]


        $_.LatestServicePack = ($_.LatestServicePack -split " ")[0]
        $_.LatestCumulativeUpdate = (($_.LatestCumulativeUpdate -split " ")[0]) + (($_.LatestCumulativeUpdate -split " ")[1]) 
    } 

    if($SqlVersion) {
        foreach($version in $SqlVersion) {
            $LatestPatches | Where-Object ProductVersions -like "*$version"
        }
    }

    else {
        return $LatestPatches
    }
}