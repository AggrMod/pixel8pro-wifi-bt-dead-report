<#
.SYNOPSIS
  Read-only check of a Pixel's Wi-Fi / Bluetooth state over adb. Changes nothing on the phone.

.DESCRIPTION
  Prints the signatures described in the report: wlan interfaces, whether the Broadcom
  Wi-Fi driver is loaded, Bluetooth state and crash count, Wi-Fi HAL error counts,
  chip-firmware restarts, and which PCIe devices are present.
  The device serial number is never printed.

.PARAMETER Adb
  Path to adb (default: adb from PATH).

.EXAMPLE
  .\pixel-radio-check.ps1 -Adb C:\platform-tools\adb.exe
#>
param([string]$Adb = 'adb')

function Sh([string]$cmd) { (& $Adb shell $cmd 2>&1) }
function Count-Lines($text) { @($text | Where-Object { $_ -and $_.ToString().Trim() }).Count }

$state = ((& $Adb get-state 2>&1) -join '')
if ($state -ne 'device') {
  Write-Host "adb state: '$state'. Connect the phone, enable USB debugging and tap Allow." -ForegroundColor Yellow
  exit 1
}

Write-Host '== Device ==' -ForegroundColor Cyan
"model        : " + (Sh 'getprop ro.product.model')
"build        : " + (Sh 'getprop ro.build.fingerprint')
"security     : " + (Sh 'getprop ro.build.version.security_patch')
"uptime       : " + ((Sh 'uptime') -join ' ').Trim()

Write-Host "`n== Wi-Fi ==" -ForegroundColor Cyan
$wlan = @(Sh 'ls /sys/class/net' | Where-Object { $_ -match 'wlan' })
$dhd  = @(Sh 'lsmod' | Where-Object { $_ -match 'dhd' })
"wlan interfaces      : " + $(if ($wlan.Count) { $wlan -join ', ' } else { 'NONE' })
"bcmdhd driver loaded : " + $(if ($dhd.Count) { 'yes' } else { 'NO' })
"wifi status          : " + ((Sh 'cmd wifi status' | Select-Object -First 1) -join '')

$log = Sh 'logcat -d -b main,system,crash'
"HAL 'Timed out waiting on Driver ready' : " + (Count-Lines ($log | Select-String -SimpleMatch 'Timed out waiting on Driver ready'))
"HAL 'Could not create handle'           : " + (Count-Lines ($log | Select-String -SimpleMatch 'Could not create handle'))
"chip firmware restarts (onSubsystemRestart): " + (Count-Lines ($log | Select-String -SimpleMatch 'onSubsystemRestart'))
"Android Wi-Fi recovery throttle hit     : " + (Count-Lines ($log | Select-String -SimpleMatch 'Disabling wifi'))

Write-Host "`n== Bluetooth ==" -ForegroundColor Cyan
$bt = Sh 'dumpsys bluetooth_manager'
"state   : " + (($bt | Select-String -Pattern '^\s+State:' | Select-Object -First 1) -join '').Trim()
"address : " + $(if ($bt -match 'Address:\s+\[address is null\]') { 'null (controller not up)' } else { 'present' })
"crashes : " + (($bt | Select-String -Pattern 'Bluetooth crashed' | Select-Object -First 1) -join '').Trim()
"HAL died events in log: " + (Count-Lines ($log | Select-String -SimpleMatch 'The Bluetooth HAL died'))

Write-Host "`n== PCIe (which chips does the SoC actually see?) ==" -ForegroundColor Cyan
foreach ($d in @(Sh 'ls /sys/bus/pci/devices')) {
  if ($d) {
    $drv = ((Sh "readlink /sys/bus/pci/devices/$d/driver") -join '') -replace '.*/', ''
    "{0}  driver: {1}" -f $d, $(if ($drv -and $drv -notmatch 'No such') { $drv } else { '(none)' })
  }
}

Write-Host "`n== Reading the result ==" -ForegroundColor Cyan
if (-not $wlan.Count -and -not $dhd.Count) {
  'No wlan interface and no Wi-Fi driver: the reported failure signature (driver never binds to the chip).'
} elseif ($wlan.Count -and -not ((Sh 'cmd wifi status' | Select-Object -First 1) -match 'enabled')) {
  'Interfaces exist but Wi-Fi will not start: chip is partly alive. See the report for what to try.'
} else {
  'Wi-Fi radio looks alive right now.'
}
