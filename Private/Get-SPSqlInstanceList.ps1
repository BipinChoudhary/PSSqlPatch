#Gets SQL instances on a target server.
function Get-SPSqlInstanceList {

    Param
    (
        [Parameter(Mandatory)]
        [string] $TargetServer,
        [switch] $InstanceNamesOnly,
        [switch] $RunningOnly
    )

    if (Test-Connection -computername $TargetServer -Quiet -Count 1) {

        try {
            if($RunningOnly) {
                $instances = Get-Service -ComputerName $TargetServer | Where-Object { $_.DisplayName -like "SQL Server (*" -and $_.Status -eq "Running" } | Select-Object -ExpandProperty Name -ErrorAction Stop
            }
            else {
                $instances = Get-Service -ComputerName $TargetServer | Where-Object { $_.DisplayName -like "SQL Server (*" } | Select-Object -ExpandProperty Name -ErrorAction Stop
            }

            #Remove additional unneded string that gets added to non-default instances.
            $instanceList = $instances.Replace('MSSQL$', '')

            if(!$InstanceNamesOnly) {
                #Add the server name itself to the instance name and add a slash. e.g. instancename becomes server\instancename
                $instanceList = $instanceList | ForEach-Object { "${TargetServer}\$_" }

                #Remove any default instances, as servername\MSSQLSERVER does not work, it has to be servername on it's own to connect.
                $instanceList = $instanceList.Replace('\MSSQLSERVER', '')
            }

            return $instanceList

        }
        catch {
            return $null
        }
    }
    else {
        return $null
    }
} #end Get-SPSqlInstanceList