#Function to set the MaxMemoryPerShellMB on a target. This setting is set very low on older servers which prevents patching.
function Set-SPMaxMemoryPerShellMB {
    Param
    (
        [Parameter(Mandatory)]
        [string] $TargetServer,

        [string] $MaxMemoryPerShellMB="0"
    )

    $MaxMemorySettings = @()

    Connect-WSMan -ComputerName $TargetServer
    $CurrentMaxMemoryPerShellMB = Get-Item WSMan:\$TargetServer\Shell\MaxMemoryPerShellMB

    $OldMaxMemory = [PSCustomObject][Ordered] @{
        ValueType = "CurrentValue"
        Property = $CurrentMaxMemoryPerShellMB.Name
        Value = $CurrentMaxMemoryPerShellMB.Value
    }
    $MaxMemorySettings += $OldMaxMemory

    if($CurrentMaxMemoryPerShellMB.Value -ne $MaxMemoryPerShellMB) {
        Set-Item  WSMan:\$TargetServer\Shell\MaxMemoryPerShellMB $MaxMemoryPerShellMB -Force -WarningAction SilentlyContinue

        $NewMaxMemoryPerShellMB = Get-Item WSMan:\$TargetServer\Shell\MaxMemoryPerShellMB
        $NewMaxMemory = [PSCustomObject][Ordered] @{
            ValueType = "NewValue"
            Property = $NewMaxMemoryPerShellMB.Name
            Value = $NewMaxMemoryPerShellMB.Value
        }
        $MaxMemorySettings += $NewMaxMemory
    }
    Disconnect-WSMan -ComputerName $TargetServer

    return $MaxMemorySettings
}
