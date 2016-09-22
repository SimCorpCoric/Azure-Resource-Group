Write-Verbose "Initializing and formatting raw disks"

$disks = Get-Disk | Where partitionstyle -eq 'raw' | sort number

## start at F:\
$letters = 70..89 | ForEach-Object { ([char]$_) }
$count = 0

foreach($d in $disks) {
    $driveLetter = $letters[$count].ToString()
    $d | 
    Initialize-Disk -PartitionStyle MBR -PassThru |
    New-Partition -UseMaximumSize -DriveLetter $driveLetter |
    Format-Volume -FileSystem NTFS -NewFileSystemLabel 'Data' -Confirm:$false -Force 
    $count++
}

Restart-Service Server