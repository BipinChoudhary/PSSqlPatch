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
    $CurrentPowerShellMaxMemoryPerShellMB = Get-Item WSMan:\$TargetServer\Plugin\microsoft.powershell\Quotas\MaxMemoryPerShellMB


    $OldMaxMemory = [PSCustomObject][Ordered] @{
        ValueType = "CurrentValue"
        Property = $CurrentMaxMemoryPerShellMB.Name
        ShellValue = $CurrentMaxMemoryPerShellMB.Value
        PowerShellValue = $CurrentPowerShellMaxMemoryPerShellMB.Value
    }
    $MaxMemorySettings += $OldMaxMemory

    if($CurrentMaxMemoryPerShellMB.Value -ne $MaxMemoryPerShellMB -or $CurrentPowerShellMaxMemoryPerShellMB.Value -ne $MaxMemoryPerShellMB) {
        Set-Item  WSMan:\$TargetServer\Shell\MaxMemoryPerShellMB $MaxMemoryPerShellMB -Force -WarningAction SilentlyContinue
        Set-Item  WSMan:\$TargetServer\Plugin\microsoft.powershell\Quotas\MaxMemoryPerShellMB $MaxMemoryPerShellMB -Force -WarningAction SilentlyContinue

        $NewMaxMemoryPerShellMB = Get-Item WSMan:\$TargetServer\Shell\MaxMemoryPerShellMB
        $NewPowerShellMaxMemoryPerShellMB = Get-Item WSMan:\$TargetServer\Plugin\microsoft.powershell\Quotas\MaxMemoryPerShellMB

        $NewMaxMemory = [PSCustomObject][Ordered] @{
            ValueType = "NewValue"
            Property = $NewMaxMemoryPerShellMB.Name
            ShellValue = $NewMaxMemoryPerShellMB.Value
            PowerShellValue = $NewPowerShellMaxMemoryPerShellMB.Value
        }
        $MaxMemorySettings += $NewMaxMemory

        Write-Verbose "Restarting WinRM for changes to take effect"
        Get-Service -ComputerName $TargetServer -Name WinRM | Restart-Service -Force
    }
    Disconnect-WSMan -ComputerName $TargetServer

    return $MaxMemorySettings
}
