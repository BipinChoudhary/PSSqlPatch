
#This function is a used to display updates to the user throughout the script execution. It also allows for optionally logging the update to a file.
function Write-SPUpdate {
    [Cmdletbinding()]
    param(    
        [Parameter(ValueFromPipeline, Mandatory)]
        [string] $string,
 
        [ValidateSet("Info", "Normal", "Success", "Header", "Warning", "Error")]
        [string] $UpdateType = "Normal",

        [string] $Logfile,
        [switch] $NoTimeStamp
    )

    process {
        switch ($UpdateType) {     
            "Info" {
                $string = "`nINFO: " + $string
                Write-Host $string -ForegroundColor Yellow -BackgroundColor Black
            }
            
            "Normal" {
                Write-Host $string
            }
            
            "Success" {
                $string = "SUCCESS: " + $string
                Write-Host $string -ForegroundColor Green
            }

            "Header" {
                $string = $string.ToUpper()
                $string = "`r`n`r`n################################################`r`n" + $string + "`r`n################################################"
                Write-Host $string
            }
            "Warning" {
                $string = "[WARNING] " + $string            
                Write-Warning $string
            }
    
            "Error" {
                $string = "[ERROR] " + $string
                Write-Warning $string
            }
        }
        
        
        
        if ($Logfile) {
            if ($UpdateType -eq "Header") {
                $string | Out-File $LogFile -Append
            }
            else {
                if(!$NoTimeStamp) {
                    $datetimestamp = Get-Date -UFormat "[%Y-%m-%d %H:%M:%S]"
                    $LogString = "$datetimestamp : " + $string
                }
                else {
                    $LogString = $string
                }
                $Logstring | Out-File $Logfile -Append
            }
        }
    }
} #end Write-SPUpdate
