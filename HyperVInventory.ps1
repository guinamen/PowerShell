function Check-Servers {
  Param(
    [parameter(Mandatory=$true)]
    [String[]]
    $Servers
  )
  $computers = [String[]]@()
  $I = 0
  foreach ($computer in $Servers) {
    try {
      Test-WSMan -ComputerName $computer -Authentication default  -ErrorAction Stop | Out-Null
      $computers += $computer
    } catch  {
      Write-Host "It is not possible access computer: $computer" -ForegroundColor Red
    }
    $I++
    $percentil = ($I / $Servers.Count) * 100
    Write-Progress -Activity "Testing servers connection..." -Status "$([int]$percentil)% Complete:" -PercentComplete $percentil -Id 1
  }
  Write-Progress -Activity 'Testing servers connection...' -Completed -Id 1
  return $computers
}

function Get-ServersInformation {
  Param(
    [parameter(Mandatory=$true)]
    [String[]]
    $Servers 
  )
  $wmiObjects = @{
    Win32_Operatingsystem = @{
      Query = "select InstallDate, Caption, Version, OSArchitecture from Win32_Operatingsystem";
      Param = @(@{Name="Computername";Expression={$_.PSComputername}},"InstallDate","Caption","Version","OSArchitecture");
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
#    Win32_Process = @{
#      Query = "select ProcessID, ParentProcessID from Win32_Process"
#      Param = @("PSComputername","ProcessID", "ParentProcessID");
#      Sort = "ProcessId";
#    }
#    Process = $null;
    NetworkOpenPort = $null;
    
  }
  $wmiValues = @{}
  $I = 0
  foreach ($wmiObjectKey in $wmiObjects.Keys) {
    $wmiObject = $wmiObjects[$wmiObjectKey]
    if (($wmiObjectKey -ne "NetworkOpenPort") -and ($wmiObjectKey -ne "Process")) {
      if ($wmiObject.Sort -eq $null) {
        $wmiValues[$wmiObjectKey] = Invoke-Command -ComputerName $computers {Get-WmiObject -Query $args[0] } -ArgumentList $wmiObject.Query | Select-Object $wmiObject.Param
        #$wmiValues[$wmiObjectKey] = gwmi -Namespace root/cimv2 $wmiObjectKey -ComputerName $computers -Filter $wmiObject.Filter | Select-Object $wmiObject.Param | Select-Object $wmiObject.Param
      } else {
        $wmiValues[$wmiObjectKey] = Invoke-Command -ComputerName $computers {Get-WmiObject -Query $args[0]} -ArgumentList $wmiObject.Query | Select-Object $wmiObject.Param | Sort $wmiObject.Sort
        #gwmi -Namespace root/cimv2 $wmiObjectKey -ComputerName $computers -Filter $wmiObject.Filter | Select-Object $wmiObject.Param | Select-Object $wmiObject.Param | Sort $wmiObject.Sort
      }
    } elseif  ($wmiObjectKey -eq "NetworkOpenPort"){
      $wmiValues[$wmiObjectKey] = Invoke-Command -ComputerName $computers {c:\windows\system32\netstat.exe -ano}
    } elseif ($wmiObjectKey -eq "Process") {
      $wmiValues[$wmiObjectKey] = Get-Process -ComputerName $computers | select Id,ProcessName,Description,Company,Product,ProductVersion,@{N='PSComputerName'; E={$_.MachineName}}
    }
    $I++
    $percentil = ($I / $wmiObjects.Keys.Count) * 100
    Write-Progress -Activity "Reading data from servers..." -Status "$([int]$percentil)% Complete:" -PercentComplete $percentil -Id 1
  }
  Write-Progress -Activity 'Reading data from servers...' -Completed -Id 1
  return $wmiValues
}

function Get-Invetary {
  Param($Out="C:\Work\MyInventory.xml", $Servers="C:\Users\pb003283\Documents\myservers.txt")
  $computers = Check-Servers -Servers (Get-Content $Servers)
  if(!$computers) {
    Exit
  }
  $wmiData = Get-ServersInformation -Servers $computers
  [xml]$XML = New-Object System.Xml.XmlDocument
 
  #create declaration
  $dec = $XML.CreateXmlDeclaration("1.0","UTF-8",$null)
  #append to XMLument
  $XML.AppendChild($dec) | Out-Null
 
  #create a comment and append it in one line
  $text = 
  @"
  Server Inventory Report
  Generated $(Get-Date)
  v1.0
"@
  $XML.AppendChild($XML.CreateComment($text)) | Out-Null
  #create root Node
  $root = $XML.CreateNode("element","Computers",$null)
 
  #create a node for each computer
  $I = 0
  #get a list of properties except PSComputername
  $props = $wmiData.Win32_Computersystem | Get-Member -MemberType NoteProperty | where {$_.Name -ne 'PSComputername'} | select -ExpandProperty Name
  $propsHD = $wmiData.Win32_DiskDrive | Get-Member -MemberType NoteProperty | where {$_.Name -ne 'PSComputername'} | select -ExpandProperty Name
  $propsNetInterface = $wmiData.Win32_NetworkAdapter | Get-Member -MemberType NoteProperty | where {$_.Name -ne 'PSComputername'} | select -ExpandProperty Name
  $propsService = $wmiData.Win32_Service | Get-Member -MemberType NoteProperty | where {$_.Name -ne 'PSComputername'} | select -ExpandProperty Name
  $propsNetConf = $wmiData.Win32_NetworkAdapterConfiguration | Get-Member -MemberType NoteProperty | where {$_.Name -ne 'PSComputername'} | select -ExpandProperty Name

  foreach ($computer in $computers) {
    $I++
    $percentil = ($I / $computers.Length) * 100
    Write-Progress -Activity "Creating XML for server $computer..." -Status "$([int]$percentil)% Complete:" -PercentComplete $percentil

    $c = $XML.CreateNode("element","Computer",$null)
    $pcID =  $wmiData.Win32_Computersystemproduct | where {$_.pscomputername -eq $Computer}
    #add an attribute for the name
    $c.SetAttribute("Id", $pcID.uuid)| Out-Null
    $c.SetAttribute("Type", $pcID.Name)| Out-Null
    $c.SetAttribute("Vendor", $pcID.Vendor)| Out-Null

    #create node for OS
    $osnode = $XML.CreateNode("element","OperatingSystem",$null)

    #get related data
    $data =  $wmiData.Win32_Operatingsystem | where {$_.computername -eq $Computer}

    #create an element
    $e = $XML.CreateNode("element","Name",$null)
    #assign a value
    $e.InnerText = $data.Caption
    $osnode.AppendChild($e) | Out-Null
 
    #create elements for the remaining properties
    "Version","InstallDate","OSArchitecture" | foreach {
      $e = $XML.CreateNode("element",$_,$null)
      $e.InnerText = $data.$_
      $osnode.AppendChild($e) | Out-Null
    }
 
    #add to parent node
    $c.AppendChild($osnode) | Out-Null
 
    #create node for Computer system
    $csnode =      $XML.CreateNode("element","ComputerSystem",$null)
    $cshd =        $XML.CreateNode("element","HDs",$null)
    $csInterface = $XML.CreateNode("element","NetworkInterfaces",$null)
    $csOpenPorts = $XML.CreateNode("element","OpenPorts",$null)
    $svcnode =     $XML.CreateNode("element","Services",$null)


    #this is using the original property name
    $data = $wmiData.Win32_Computersystem | where {$_.pscomputername -eq $Computer}
    $dataHDs = $wmiData.Win32_DiskDrive | where {$_.pscomputername -eq $Computer}
    $dataNetAdapters = $wmiData.Win32_NetworkAdapter | where {$_.pscomputername -eq $Computer}
    $dataNetConfigs = $wmiData.Win32_NetworkAdapterConfiguration | where {$_.pscomputername -eq $Computer}
    $dataService = $wmiData.Win32_Service | where {$_.pscomputername -eq $Computer}
    $dataOpenPorts = (($wmiData.NetworkOpenPort | where {$_.pscomputername -eq $Computer} | Select-String -Pattern '\s+(TCP.*LISTENING|UDP)') -replace '^\s+', '') -replace '\s+',' '

    #create elements for each property
    if ($data.DomainRole -ge 3) {
      $SId = $Computer | Get-ADComputer -Properties SID | select -ExpandProperty SID |select -ExpandProperty Value
      $c.SetAttribute("SId", $SId)| Out-Null
    }
    foreach ($prop in $props) {
      $e = $XML.CreateNode("element",$prop,$null)
      if ($prop -eq "DomainRole") {
        switch($data.$prop) {
          0 {$e.InnerText = "Standalone Workstation"}
          1 {$e.InnerText = "Member Workstation"}
          2 {$e.InnerText = "Standalone Server"}
          3 {$e.InnerText = "Member Server"}
          4 {$e.InnerText = "Backup Domain Controller"}
          5 {$e.InnerText = "Primary Domain Controller"}
        }
      } else {
        $e.InnerText = $data.$prop
      }
      $csnode.AppendChild($e) | Out-Null
    }
    #create hds elements
    foreach ($dataHD in $dataHDs) {
      $hdNode = $XML.CreateNode("element","HD",$null)
      foreach ($propHD in $propsHD) {
        if ($dataHD.$propHD) {
          $e = $XML.CreateNode("element",$propHD,$null)
          $e.InnerText = $dataHD.$propHD
          $hdNode.AppendChild($e) | Out-Null
        }
      }
      $cshd.AppendChild($hdNode) | Out-Null
    }
    #create net adapter elements
    foreach($dataNetAdapter in $dataNetAdapters) {
      $netAdapterNode = $XML.CreateNode("element","NetworkInterface",$null)
      foreach($propNetInterface in $propsNetInterface) {
        if ($dataNetAdapter.$propNetInterface) {
          $e = $XML.CreateNode("element",$propNetInterface,$null)
          $e.InnerText = $dataNetAdapter.$propNetInterface
          $netAdapterNode.AppendChild($e) | Out-Null
         }
      }
      $dataNetConfig = $dataNetConfigs | where {$_.MACAddress -eq $dataNetAdapter.MACAddress}
      if ($dataNetConfig) {
        $netAdapterConfNode = $XML.CreateNode("element","NetworkInterfaceConfig",$null)
        foreach($propNetConf in $propsNetConf) {
          if ($dataNetConfig.$propNetConf -and !($propNetConf -eq "MACAddress")) {
            $e = $XML.CreateNode("element",$propNetConf,$null)
            $e.InnerText = $dataNetConfig.$propNetConf
            $netAdapterConfNode.AppendChild($e) | Out-Null
          }
        }
        $netAdapterNode.AppendChild($netAdapterConfNode) | Out-Null
      }
      $csInterface.AppendChild($netAdapterNode) | Out-Null
    }
    #create hash open ports
    $hashOpenPorts = New-Object System.Collections.Specialized.OrderedDictionary
    foreach($line in $dataOpenPorts) {
      $dt = $line -split ' '
      $protocol = $dt[0]
      if ( $($dt[1]).StartsWith("[::]") ) {
        $ip = "[::]"
        $port = $dt[1] -replace "\[::]:", ""
      } else {
        $ip = ($dt[1] -split ":")[0]
        $port = ($dt[1] -split ":")[1]
      }
      $pidOpen = $dt[-1]
      if (! $hashOpenPorts[$protocol]) {
        $hashOpenPorts[$protocol] = @{}
      }
      if (! $($hashOpenPorts[$protocol])[$ip]) {
        $($hashOpenPorts[$protocol])[$ip] = @{}
      }
      if (! $($($hashOpenPorts[$protocol])[$ip])[$port]) {
        $($($hashOpenPorts[$protocol])[$ip])[$port] = [String[]]@()
      }
      $($($hashOpenPorts[$protocol])[$ip])[$port]+= $pidOpen
    }
    foreach($protocolKey in $hashOpenPorts.Keys) {
        $csOpenProtocol = $XML.CreateNode("element","Protocol",$null)
        $csOpenProtocol.SetAttribute("Name",$protocolKey) | Out-Null
        foreach($ipKey in $($hashOpenPorts[$protocolKey]).Keys ) {
          $csOpenIp = $XML.CreateNode("element","IP",$null)
          $csOpenIp.SetAttribute("Address",$ipKey) | Out-Null
          foreach($portKey in $($($hashOpenPorts[$protocolKey])[$ipKey]).Keys ) {
            $csOpenPort = $XML.CreateNode("element","Port",$null)
            $csOpenPort.SetAttribute("Number",$portKey) | Out-Null
            foreach($openPid in $($($($hashOpenPorts[$protocolKey])[$ipKey])[$portKey])) {
              $csOpenPid = $XML.CreateNode("element","ProcessID",$null)
              $csOpenPid.InnerText = $openPid
              $csOpenPort.AppendChild($csOpenPid) | Out-Null
            }
            $csOpenIp.AppendChild($csOpenPort) | Out-Null
          }
          $csOpenProtocol.AppendChild($csOpenIp) | Out-Null
        }
        $csOpenPorts.AppendChild($csOpenProtocol) | Out-Null
    }
    
    foreach ($service in $dataService) {
     $s = $XML.CreateNode("element","Service",$null)
     foreach ($propService in $propsService) {
       $e = $XML.CreateNode("element",$propService,$null)
       $e.InnerText = $service.$propService
       $s.AppendChild($e) | Out-Null
     }
     $svcnode.AppendChild($s) | Out-Null
    }

    $csnode.AppendChild($cshd) | Out-Null
    $csnode.AppendChild($csInterface) | Out-Null
    $csnode.AppendChild($csOpenPorts) | Out-Null
    $c.AppendChild($csnode) | Out-Null
    $c.AppendChild($svcnode) | Out-Null
    $root.AppendChild($c) | Out-Null
  }
  #add root to the XMLument
  $XML.AppendChild($root) | Out-Null
  #save file
  $XML.save($Out)
}

Get-Invetary
