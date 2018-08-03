<#
.SYNOPSIS
    Retrieves information about pending restart on local computer.
.DESCRIPTION
    This function search in Windows Register informations about the need to restart the local machine.
.EXAMPLE
    C:\PS> Get-PendingReboot
.OUTPUTS
    True if there are need to restart the machine, or false if not.
.LINK
    https://github.com/guinamen/PowerShell/
#>
function Get-PendingReboot
{
 if (Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -EA Ignore) { return $true }
 if (Get-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -EA Ignore) { return $true }
 if (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -EA Ignore) { return $true }
 try { 
   $util = [wmiclass]"\\.\root\ccm\clientsdk:CCM_ClientUtilities"
   $status = $util.DetermineIfRebootPending()
   if(($status -ne $null) -and $status.RebootPending){
     return $true
   }
 }catch{}
 return $false
}
