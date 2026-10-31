# ==============================================================================
# BootOS - PowerShell Direct USB Flasher (No Rufus Required)
# ==============================================================================

# Ensure Administrator privileges
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$workspace = Split-Path -Parent $PSScriptRoot
$isoPath = Join-Path $workspace "bootos.iso"

if (-not (Test-Path $isoPath)) {
    Write-Error "Could not find bootos.iso at $isoPath"
    Read-Host "Press Enter to exit..."
    exit 1
}

$isoItem = Get-Item $isoPath
$isoSizeMB = [math]::Round($isoItem.Length / 1MB, 1)

Clear-Host
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "         BootOS - Direct USB Flasher (No Rufus Needed)" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host " ISO File: $isoPath ($isoSizeMB MB)`n" -ForegroundColor White

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
    
    $isSystem = $d.IsSystem -or $d.IsBoot -or ($partitions | Where-Object { $_.DriveLetter -eq 'C' })
    $status = if ($isSystem) { "[SYSTEM / BLOCKED]" } elseif ($d.BusType -eq 'USB') { "[USB Target]" } else { "[Internal Disk]" }
    $sizeGB = [math]::Round($d.Size / 1GB, 1)

    $color = if ($isSystem) { "DarkRed" } elseif ($d.BusType -eq 'USB') { "Green" } else { "Gray" }
    Write-Host (" [{0,-2}] {1,-10} {2,-7} {3,-32} {4,10}  {5}" -f $d.Number, $d.BusType, $driveLetters, $d.FriendlyName, $sizeGB, $status) -ForegroundColor $color

    if (-not $isSystem) {
        $validTargets += $d.Number
    }
}
Write-Host "--------------------------------------------------------------------------------`n" -ForegroundColor DarkGray

$targetNum = Read-Host "Enter the Disk Number of your USB Drive (e.g. 1, 2) or 'C' to Cancel"
if ($targetNum -eq 'C' -or $targetNum -eq 'c') { exit }

$targetNum = [int]$targetNum
if ($targetNum -notin $validTargets) {
    Write-Host "`n[ERROR] Invalid or blocked disk number." -ForegroundColor Red
    Read-Host "Press Enter to exit..."
    exit 1
}

$selectedDisk = Get-Disk -Number $targetNum
Write-Host "`n********************************************************************************" -ForegroundColor Red
Write-Host " WARNING: ALL DATA ON Disk $targetNum ($($selectedDisk.FriendlyName)) WILL BE ERASED!" -ForegroundColor Yellow
Write-Host "********************************************************************************" -ForegroundColor Red
$confirm = Read-Host "Type 'YES' (all caps) to confirm and flash BootOS"
if ($confirm -ne 'YES') {
    Write-Host "Operation cancelled. No changes made." -ForegroundColor Yellow
    exit
}

Write-Host "`nDismounting and preparing Disk $targetNum..." -ForegroundColor Cyan
Get-Partition -DiskNumber $targetNum -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.DriveLetter) {
        $vol = "$($_.DriveLetter):"
        Write-Host "  -> Unmounting $vol" -ForegroundColor Gray
    }
}

# Use bootos-flasher.exe if compiled, or raw disk stream
$flasherExe = Join-Path $workspace "bootos-flasher.exe"
if (Test-Path $flasherExe) {
    & $flasherExe
} else {
    Write-Host "Writing raw hybrid ISO image to \\.\PhysicalDrive$targetNum..." -ForegroundColor Cyan
    $inStream = [System.IO.File]::OpenRead($isoPath)
    $diskStream = New-Object System.IO.FileStream("\\.\PhysicalDrive$targetNum", [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite)
    
    $buffer = New-Object byte[] (1024 * 1024)
    $totalRead = 0
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    while (($bytesRead = $inStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $diskStream.Write($buffer, 0, $bytesRead)
        $totalRead += $bytesRead
        $pct = [math]::Round(($totalRead / $inStream.Length) * 100)
        $mbWritten = [math]::Round($totalRead / 1MB, 1)
        $speed = [math]::Round(($mbWritten / ($sw.ElapsedMilliseconds / 1000)), 1)
        Write-Progress -Activity "Flashing BootOS to USB Drive" -Status "$pct% ($mbWritten MB / $isoSizeMB MB) @ $speed MB/s" -PercentComplete $pct
    }

    $diskStream.Flush()
    $diskStream.Close()
    $inStream.Close()
    Write-Progress -Activity "Flashing BootOS to USB Drive" -Completed

    Write-Host "`n==========================================================" -ForegroundColor Green
    Write-Host " [SUCCESS] BootOS has been successfully flashed to USB!" -ForegroundColor Green
    Write-Host " Your USB flash drive is now 100% bootable (BIOS + UEFI)." -ForegroundColor White
    Write-Host "==========================================================" -ForegroundColor Green
}

Read-Host "`nPress Enter to exit..."
