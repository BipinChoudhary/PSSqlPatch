#Function that returns the drive with sufficent given amount of space - will return the D drive if it has enough, otherwise drive with most is returned.
function Get-SPDriveWithSpace {
    Param
    (
        [Parameter(Mandatory)]
        [string] $TargetServer,
        [Parameter(Mandatory)]
        [string] $SpaceNeededGB
    )

    $drives = Get-WmiObject Win32_LogicalDisk -ComputerName $TargetServer

    #Initiate it so it can be used to find the drive with the most space.
    $MaxDriveSpace = 0

    foreach ($drive in $drives) {
                      
        $drivename = $drive.DeviceID
        $freespace = [float]($drive.FreeSpace / 1GB).ToString("#.##")

        #if the D drive has enough space, it should  be used
        if ($drivename -eq "D:" -and $freespace -gt $SpaceNeededGB) {
            $dspace = $freespace
        }

        #Otherwise find the drive with the most space.
        if ($freespace -gt $MaxDriveSpace ) { 
            $MaxDrive = $drivename
            $MaxDriveSpace = $freespace
        }
                    
    }#end loop


    #if D has been set it means it has enough space, and should be used for the patch
    if ($dspace) {
        $PatchDrive = "D:"
        $PatchDriveSpace = $dspace
    }

    elseif($MaxDriveSpace -lt $SpaceNeededGB) {
        return $false
    }

    #otherwise, use the drive with the most space available.
    else {
        $PatchDrive = $MaxDrive
        $PatchDriveSpace = $MaxDriveSpace
    }

    $PatchDrive = $PatchDrive -replace ":", ""

    return $PatchDrive, $PatchDriveSpace
    
}#end Get-DriveWithSpace
