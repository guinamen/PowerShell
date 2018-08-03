workflow paralleltest {
 param(
    [Parameter (Mandatory = $true)]
    [string[]]$ServersNames
 )
 $computers = [String[]]@() 
 $wmiValues = [ordered]@{}
 $wmiObjects = @{
    Win32_Operatingsystem = @{
      Query = "select InstallDate, Caption, Version, OSArchitecture from Win32_Operatingsystem";
      Param = @("PSComputername",@{Name="Computername";Expression={$_.PSComputername}},"InstallDate","Caption","Version","OSArchitecture");
      Sort = $null;
    }
    Win32_Computersystem = @{
      Query = "select TotalPhysicalMemory, HyperVisorPresent, NumberOfProcessors, NumberofLogicalProcessors, Domain, Name, DomainRole from Win32_Computersystem";
      Param = @("PSComputername","TotalPhysicalMemory","HyperVisorPresent","NumberOfProcessors","NumberofLogicalProcessors", "Domain", "Name", "DomainRole");
      Sort = $null;
    }
    Win32_Computersystemproduct = @{
      Query = "select Name, Vendor, uuid from Win32_Computersystemproduct";
      Param = @("PSComputername", "Name", "Vendor", "uuid");
      Sort = $null;
    }
    Win32_DiskDrive = @{
      Query = "select Caption, Model, Size, SerialNumber, DeviceID, InterfaceType from Win32_DiskDrive";
      Param = @("PSComputername", "Caption", "Model", "Size", "SerialNumber", "DeviceID", "InterfaceType");
      Sort = $null;
    }
    Win32_NetworkAdapter = @{
      Query = "select Name, Speed, MACAddress, NetEnabled from Win32_NetworkAdapter where AdapterTypeID = 0 or AdapterTypeID = 9 or ConfigManagerErrorCode = 22";
      Param = @("PSComputername", "Name", "Speed", "MACAddress", "NetEnabled");
      Sort = "Name";
    }
    Win32_NetworkAdapterConfiguration = @{
      Query = "select MACAddress, DHCPEnabled, DefaultIPGateway, IPAddress, IPSubnet, DNSServerSearchOrder from Win32_NetworkAdapterConfiguration where MACAddress is not null";
      Param = @("PSComputername", "MACAddress", "DHCPEnabled", "DefaultIPGateway", "IPAddress", "IPSubnet", "DNSServerSearchOrder");
      Sort = $null;
    }
    Win32_Service = @{
      Query = "select Name, Displayname, StartMode, StartName, ProcessID from Win32_Service where State = 'Running'"
      Param = @("PSComputername","Name", "Displayname", "StartMode", "StartName", "ProcessID");
      Sort = "ProcessId";
    }
    Win32_Process = @{
      Query = "select ProcessID, ParentProcessID, Caption from Win32_Process"
      Param = @("PSComputername", "Caption","ProcessID", "ParentProcessID");
      Sort = "ProcessId";
    }
    NetworkOpenPort = $null;
    
 }
 [xml]$XML = New-Object System.Xml.XmlDocument
 $wmiObjectsXMLNodeName = @{
    Win32_Operatingsystem = "OperatingSystem"
    Win32_Computersystem = "ComputerSystem"
    Win32_Computersystemproduct = "Computer"
    Win32_DiskDrive = "HDs"
    Win32_NetworkAdapter = "NetworkInterfaces",$null;
    Win32_NetworkAdapterConfiguration = "NetworkInterfaceConfig"
    Win32_Service = "Services"
    Win32_Process = "Process"
    NetworkOpenPort = "OpenPorts"
 }
 
 foreach -parallel ($computer in $ServersNames){
   $WORKFLOW:computers += InlineScript {
      try {
        Test-WSMan -ComputerName $using:computer -Authentication default  -ErrorAction Stop | Out-Null
        $using:computer
      } catch  {
      }
    }
 }
 foreach -parallel ($wmiObjectKey in ($wmiObjects.clone()).keys) {
   $wmiObject = $wmiObjects[$wmiObjectKey]
   $temp = @{}
   if (($wmiObjectKey -ne "NetworkOpenPort")) {
     $temp = InlineScript {
       $value = Get-CimInstance -ComputerName ($using:computers) -Namespace root/cimv2 -Query $(($using:wmiObject).Query)  | Select-Object $(($using:wmiObject).Param) | Sort $(($using:wmiObject).Sort) | Group-Object -AsHashTable PSComputerName
       @{($using:wmiObjectKey) = $value}
     }
   } else {
     $temp = InlineScript {
       $value = Invoke-Command ($using:computers) {c:\windows\system32\netstat.exe -ano} | Group-Object -AsHashTable PSComputerName
       @{($using:wmiObjectKey) = $value}
     }
   } 
   $WORKFLOW:wmiValues += $temp
 }
 return $wmiValues
}
