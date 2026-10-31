# ==============================================================================
# BootOS - USB Drive Restore Tool (Restores to 100% Clean FAT32 Windows Drive)
# ==============================================================================

# Ensure Administrator privileges
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Clear-Host
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "          BootOS - USB Flash Drive Restore Tool" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "This tool restores any USB drive back to a clean Windows FAT32 drive.`n" -ForegroundColor White

Write-Host "Scanning connected storage disks..." -ForegroundColor Gray
$disks = Get-Disk | Sort-Object Number

Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host (" {0,-4} {1,-10} {2,-7} {3,-32} {4,10}  {5}" -f "#", "BusType", "Drive", "Friendly Name", "Size (GB)", "Status") -ForegroundColor Yellow
Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray

$validTargets = @()
foreach ($d in $disks) {
    $partitions = Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue
    $driveLetters = ($partitions | Where-Object { $_.DriveLetter } | ForEach-Object { "$($_.DriveLetter):" }) -join ", "
    if (-not $driveLetters) { $driveLetters = "-" }
    
    $isProtected = $d.IsSystem -or $d.IsBoot -or ($partitions | Where-Object { $_.DriveLetter -in @('C', 'D') }) -or ($d.BusType -ne 'USB')
    $status = if ($isProtected) { "[PROTECTED / BLOCKED]" } elseif ($d.BusType -eq 'USB') { "[USB Flash Drive]" } else { "[Internal Disk]" }
    $sizeGB = [math]::Round($d.Size / 1GB, 1)

    $color = if ($isProtected) { "DarkRed" } elseif ($d.BusType -eq 'USB') { "Green" } else { "Gray" }
    Write-Host (" [{0,-2}] {1,-10} {2,-7} {3,-32} {4,10}  {5}" -f $d.Number, $d.BusType, $driveLetters, $d.FriendlyName, $sizeGB, $status) -ForegroundColor $color

    if (-not $isProtected -and $d.BusType -eq 'USB') {
        $validTargets += $d.Number
    }
}
Write-Host "--------------------------------------------------------------------------------`n" -ForegroundColor DarkGray

if ($validTargets.Count -eq 0) {
    Write-Host "[!] No USB flash drives currently detected." -ForegroundColor Yellow
    Write-Host "    If your USB drive is plugged in, try unplugging it and plugging it back in" -ForegroundColor White
    Write-Host "    (or try a different USB port on your PC).`n" -ForegroundColor White
    Read-Host "Press Enter to exit..."
    exit
}

if ($validTargets.Count -eq 1) {
    $defNum = $validTargets[0]
    $defDisk = Get-Disk -Number $defNum
    $ans = Read-Host "Detected USB: Disk $defNum ($($defDisk.FriendlyName)). Press ENTER to restore or 'C' to Cancel"
    if ($ans -eq 'C' -or $ans -eq 'c') { exit }
    $targetNum = if ([string]::IsNullOrWhiteSpace($ans)) { $defNum } else { [int]$ans }
} else {
    $targetNum = Read-Host "Enter the Disk Number of the USB Drive to restore (e.g. 1, 2) or 'C' to Cancel"
    if ($targetNum -eq 'C' -or $targetNum -eq 'c') { exit }
    $targetNum = [int]$targetNum
}
if ($targetNum -notin $validTargets) {
    Write-Host "`n[ERROR] Invalid or non-USB disk number selected." -ForegroundColor Red
    Read-Host "Press Enter to exit..."
    exit 1
}

$selectedDisk = Get-Disk -Number $targetNum
Write-Host "`nRestoring Disk $targetNum ($($selectedDisk.FriendlyName))..." -ForegroundColor Cyan

# Use diskpart to cleanly wipe and recreate FAT32
$dpScript = @"
select disk $targetNum
clean
convert mbr
create partition primary
active
format fs=fat32 quick label="USB DRIVE"
assign
exit
"@

$dpFile = [System.IO.Path]::GetTempFileName()
Set-Content -Path $dpFile -Value $dpScript

Write-Host "Running diskpart clean and format..." -ForegroundColor Gray
Start-Process diskpart.exe -ArgumentList "/s `"$dpFile`"" -Wait -NoNewWindow
Remove-Item $dpFile -Force -ErrorAction SilentlyContinue

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host " [SUCCESS] USB Drive restored successfully!" -ForegroundColor Green
Write-Host " It is now a clean FAT32 drive and visible in File Explorer." -ForegroundColor White
Write-Host "==========================================================" -ForegroundColor Green

Read-Host "`nPress Enter to exit..."
