$hostnames = ("<node1.x.com","node2.x.com","node3.x.com>")
$vswitch = “vSwitch0”
$vportgroup = "VM Network"
$vlanid = 202
 
#Set credentials
$login = Get-Credential$hostnames | ForEach {
 
#Connect to host
Connect-VIServer -Server $_ -Credential $login
 
#Set NTP server
Add-VmHostNtpServer -VMHost $_ -NtpServer "<ntp.x.com>"
 
#Start NTP client service and set to enabled
Get-VmHostService -VMHost $_ | Where-Object {$_.key -eq "ntpd"} | Start-VMHostService
Get-VmHostService -VMHost $_ | Where-Object {$_.key -eq "ntpd"} | Set-VMHostService -policy "on"
 
#Enable SSH service and set to automatic
Get-VmHostService -VMHost $_ | Where-Object {$_.key -eq "TSM-SSH"} | Start-VMHostService
Get-VmHostService -VMHost $_ | Where-Object {$_.key -eq "TSM-SSH"} | Set-VMHostService -policy "on"
 
#Remove SSH Enabled Warning
log "Disabling SSH Warning"
$VMhost | Get-AdvancedSetting UserVars.SuppressShellWarning | Set-AdvancedSetting -Value 1 -Confirm:$false
 
#Set PG VLAN
Get-VirtualSwitch -VMHost $_  -Name $vswitch | Get-VirtualPortGroup -Name $vportgroup  | Set-VirtualPortGroup -VLanId $vlanid
 
#Set PG VLAN
Get-VirtualSwitch -VirtualSwitch $vswitch -MTU 9000 -Confirm:$false
 
#Disconnect host
Disconnect-VIServer -Server * -Force -Confirm:$false
 
}