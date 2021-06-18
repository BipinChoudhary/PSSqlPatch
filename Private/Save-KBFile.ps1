####################################################################################
# Save-KBFIle function below taken from the internet and modified by me, Patrick Cull, to work better with Sql KBs
####################################################################################
function Save-KBFile {
    <#
    .SYNOPSIS
        Downloads patches from Microsoft

    .DESCRIPTION
         Downloads patches from Microsoft

    .PARAMETER Name
        The KB name or number. For example, KB4057119 or 4057119.

    .PARAMETER Path
        The directory to save the file.

    .PARAMETER FilePath
        The exact file name to save to, otherwise, it uses the name given by the webserver

    .PARAMETER Architecture
        Defaults to x64. Can be x64, x86 or "All"

    .NOTES
        Props to https://keithga.wordpress.com/2017/05/21/new-tool-get-the-latest-windows-10-cumulative-updates/
        Adapted for dbatools by Chrissy LeMaire (@cl)
        Then adapted again for general use without dbatools
        See https://github.com/sqlcollaborative/dbatools/pull/5863 for screenshots

        Patrick Cull - Changes I've made;
            - I've added a retry loop to this function as I found it failed intermittently. 
            - Changed some of the download code so it works a bit better with SQL Server exe files, because that's all this module uses it for.

    .EXAMPLE
        PS C:\> Save-KBFile -Name KB4057119

        Downloads KB4057119 to the current directory. This works for SQL Server or any other KB.

    .EXAMPLE
        PS C:\> Save-KBFile -Name KB4057119, 4057114 -Path C:\temp

        Downloads KB4057119 and the x64 version of KB4057114 to C:\temp. This works for SQL Server or any other KB.

    .EXAMPLE
        PS C:\> Save-KBFile -Name KB4057114 -Architecture All -Path C:\temp

        Downloads the x64 version of KB4057114 and the x86 version of KB4057114 to C:\temp. This works for SQL Server or any other KB.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Name,
        [string]$Path = ".",
        [string]$FilePath,
        [ValidateSet("x64", "x86", "All")]
        [string]$Architecture = "x64"
    )
    begin {
        function Get-KBLink {
            param(
                [Parameter(Mandatory)]
                [string]$Name
            )
            $kb = $Name.Replace("KB", "")
            $results = Invoke-WebRequest -Uri "http://www.catalog.update.microsoft.com/Search.aspx?q=KB$kb" -UseBasicParsing
            $kbids = $results.InputFields |
                Where-Object { $_.type -eq 'Button' -and $_.Value -eq 'Download' } |
                Select-Object -ExpandProperty  ID

            Write-Verbose -Message "$kbids"

            if (-not $kbids) {
                Write-Warning -Message "No results found for $Name"
                return
            }

            $guids = $results.Links |
                Where-Object ID -match '_link' |
                Where-Object { $_.OuterHTML -match ( "(?=.*" + ( $Filter -join ")(?=.*" ) + ")" ) } |
                ForEach-Object { $_.id.replace('_link', '') } |
                Where-Object { $_ -in $kbids }

            if (-not $guids) {
                Write-Warning -Message "No file found for $Name id"
                return
            }

            foreach ($guid in $guids) {
                Write-Verbose -Message "Downloading information for $guid"
                $post = @{ size = 0; updateID = $guid; uidInfo = $guid } | ConvertTo-Json -Compress
                $body = @{ updateIDs = "[$post]" }

                # Added loop, as sometimes the DownloadDialog below doesn't work on the Microsoft website itself, so we retry up to 10 times.
                $RetryCount = 0
                while(!$links -and $RetryCount -ne 10) {
                $links = Invoke-WebRequest -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' -UseBasicParsing -Method Post -Body $body |
                    Select-Object -ExpandProperty Content |
                    Select-String -AllMatches -Pattern "(http[s]?\://download\.windowsupdate\.com\/[^\'\""]*)" |
                    Select-Object -Unique

                    Write-Verbose "DownloadDialog did not return the download file, retrying."
                    $RetryCount ++
                    Start-Sleep 1
                }

                if (-not $links) {
                    Write-Warning -Message "No file found for $Name id"
                    return
                }
                else {
                    Write-Verbose "Success. Download link returned, proceeding with the download."
                }

                foreach ($link in $links) {
                    $link.matches.value | Where-Object {$_ -like '*x64*exe'}
                }
            }
        }
    }
    process {
        if ($Name.Count -gt 0 -and $PSBoundParameters.FilePath) {
            throw "You can only specify one KB when using FilePath"
        }

        foreach ($kb in $Name) {
            $links = Get-KBLink -Name $kb

            if ($links.Count -gt 1 -and $Architecture -ne "All") {
                $templinks = $links | Where-Object { $PSItem -like "*$Architecture*" }
                if ($templinks) {
                    $links = $templinks
                } else {
                    Write-Warning -Message "Could not find architecture match, downloading all"
                }
            }

            foreach ($link in $links) {
                if (-not $PSBoundParameters.FilePath) {
                    $FilePath = Split-Path -Path $link -Leaf
                } else {
                    $Path = Split-Path -Path $FilePath
                }

                #Tidy up the filename
                $FilePath = ($FilePath -split "_")[0] + ".exe"
                $FilePath = (($FilePath -replace "sqlserver", "SQLServer") -replace "kb", "KB") -replace "sp", "SP"

                $file = "$Path$([IO.Path]::DirectorySeparatorChar)$FilePath"
                

                #Make sure the download is english version. (Only SP's have langauge versions)
                if($filePath -like '*-enu*' -or $filepath -notlike '*SP*') {    
                        if(Test-Path $file) {
                            return "AlreadyDownloaded", $FilePath
                        }
                        else {
                            #Test connection to website.
                            try {
                                Invoke-WebRequest "http://download.windowsupdate.com" -UseBasicParsing -ErrorAction Stop | Out-Null
                            }
                            catch {
                                return "CantConnectToDownloadWebsite", $FilePath
                            }
                            
                            #try to download using BitsTransfer first
                            try {
                                Start-BitsTransfer -Source $link -Destination $file -ErrorAction Stop -Asynchronous | Out-Null

                                $BitsJob = Get-BitsTransfer -Name "BITS Transfer"

                                if($BitsJob.JobState -eq "Error" -or !$BitsJob) {
                                    Throw "Error with BitsTransfer"
                                }
                               
                                while ($BitsJob.JobState -eq "Transferring" -or $BitsJob.JobState -eq "Connecting"  -and $BitsPctComplete -ne 100){                                    
                                    $BitsPctComplete = ($BitsJob.BytesTransferred / $BitsJob.BytesTotal)*100

                                    $PctCompleteForDisplay = [math]::Round($BitsPctComplete)
                                    
                                    Write-Progress -PercentComplete $BitsPctComplete -Id 1 -Activity "Downloading $FilePath to $path" -Status "${PctCompleteForDisplay}% complete"
                                    
                                    if($BitsJob.JobState -eq "Error") {
                                        Throw "Error with BitsTransfer"
                                    }

                                    Start-Sleep 1
                                } 
                            }
                            
                            #If BitsTransfer fails, try DownloadFile instead.
                            catch {
                                Get-BitsTransfer -Name "BITS Transfer" | Complete-BitsTransfer -ErrorAction SilentlyContinue  
                                
                                Write-Verbose "Start-BitsTransfer failed trying DownloadFile method instead."

                                Write-Progress -Activity "Downloading $FilePath to $path" -Id 1
                                (New-Object Net.WebClient).DownloadFile($link, $file)
                                Write-Progress -Activity "Downloading $FilePath" -Id 1 -Completed
                            }
                            #cleanup in case BitsTransfer stopped mid download.
                            finally {
                                Get-BitsTransfer -Name "BITS Transfer" | Complete-BitsTransfer -ErrorAction SilentlyContinue  
                            }
                            
                            if (Test-Path -Path $file) {
                                return "DownloadedSucessfully", $FilePath
                            }
                            else {
                                return "Error", $FilePath                                
                            }
                        }
                }
                
            }
        }
    }
} 

