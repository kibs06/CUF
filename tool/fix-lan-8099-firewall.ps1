#Requires -RunAsAdministrator
# Allow this PC to reach BlueWrite on the station LAN (port 8099).
# Root cause of Edge ERR_NETWORK_ACCESS_DENIED to 192.168.1.215:8099:
# this PC has DefaultOutboundAction = Block on all profiles, and the only
# web rule allows remote ports 80,443, so port 8099 is denied instantly
# (curl says Bad access) while ping works (Allow Ping Out exists).
# Run this file as Administrator: right-click > Run as administrator,
# or double-click tool/fix-lan-8099-firewall.bat and approve the UAC prompt.
$ErrorActionPreference = 'Stop'

$ruleName = 'Allow LAN 8099 TCP-Out'
$existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if ($existing) {
  Write-Host 'Rule already exists - updating it.'
  Set-NetFirewallRule -DisplayName $ruleName -Direction Outbound -Action Allow -Enabled True -Profile Any
} else {
  New-NetFirewallRule -DisplayName $ruleName -Direction Outbound -Action Allow -Protocol TCP -RemotePort 8099 -RemoteAddress 192.168.1.0/24 -Profile Any -Enabled True | Out-Null
  Write-Host 'Rule created.'
}

Write-Host 'Verifying...'
curl.exe --max-time 5 -s -o NUL -w 'HTTP status: %{http_code}' http://192.168.1.215:8099/
Write-Host ''
Write-Host 'Done. Reload the Edge tab.'
