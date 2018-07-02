#requires -version 4.0

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
    Write-Progress -Activity "Testing servers connection..." -Status "$([int]$percentil)% Complete:" -PercentComplete $percentil
  }
  return $computers
}

function Get-ServersInformation {
  Param(
    [parameter(Mandatory=$true)]
    [String[]]
    $Servers 
  )
  $wmiObjects = [ordered]@{
    Win32_Operatingsystem = @{
      Param = @(@{Name="Computername";Expression={$_.PSComputername}},"InstallDate","Caption","Version","OSArchitecture");
      Filter = $null;
      Sort = $null
    }
    Win32_Computersystem = @{
      Param = @("PSComputername","TotalPhysicalMemory","HyperVisorPresent","NumberOfProcessors","NumberofLogicalProcessors", "Domain");
      Filter = $null;
      Sort = $null
    }
    Win32_Computersystemproduct = @{
      Param = @("PSComputername", "Name", "Vendor", "uuid");
      Filter = $null;
      Sort = $null
    }
    Win32_DiskDrive = @{
      Param = @("PSComputername", "Caption", "Model", "Size", "SerialNumber", "DeviceID", "InterfaceType");
      Filter = $null;
      Sort = $null
    }
    Win32_NetworkAdapter = @{
      Param = @("PSComputername", "Name", "Speed", "MACAddress", "NetEnabled");
      Filter = "AdapterTypeID = 0 or AdapterTypeID = 9 or ConfigManagerErrorCode = 22";
      Sort = $null
    }
    Win32_NetworkAdapterConfiguration = @{
      Param = @("PSComputername", "MACAddress", "DHCPEnabled", "DefaultIPGateway", "IPAddress", "IPSubnet", "DNSServerSearchOrder");
      Filter = "MACAddress is not null";
      Sort = $null
    }
    Win32_Service = @{
      Param = @("PSComputername","Name","Displayname","StartMode","State","StartName","ProcessID");
      Filter = "State = 'Running'";
      Sort = "ProcessID"
    }
    Win32_NetworkOpenPort = $null
    
  }
  $wmiValues = [ordered]@{
    Win32_Operatingsystem = $null;
    Win32_Computersystem = $null;
    Win32_Computersystemproduct = $null;
    Win32_DiskDrive = $null;
    Win32_NetworkAdapter = $null;
    Win32_NetworkAdapterConfiguration = $null;
    Win32_NetworkOpenPort = $null;
    Win32_Service = $null;
  }
  $I = 0
  foreach ($wmiObjectKey in $wmiObjects.Keys) {
    $wmiObject = $wmiObjects[$wmiObjectKey]
    if ($wmiObjectKey -ne "Win32_NetworkOpenPort") {
      if ($wmiObject.Sort -eq $null) {
        $wmiValues[$wmiObjectKey] = gwmi $wmiObjectKey -ComputerName $computers -Filter $wmiObject.Filter | Select-Object $wmiObject.Param
      } else {
        $wmiValues[$wmiObjectKey] = gwmi $wmiObjectKey -ComputerName $computers -Filter $wmiObject.Filter | Select-Object $wmiObject.Param | Sort $wmiObject.Sort
      }
    } else {
      $wmiValues[$wmiObjectKey] = Invoke-Command -ComputerName $computers {c:\windows\system32\netstat.exe -ano}
    }
    $I++
    $percentil = ($I / $wmiObjects.Keys.Count) * 100
    Write-Progress -Activity "Reading data from servers..." -Status "$([int]$percentil)% Complete:" -PercentComplete $percentil
  }
  return $wmiValues
}

function Get-Invetary {
  Param($Out="C:\Work\MyInventory.xml", $Servers="C:\Users\pb003283\Documents\myservers.txt")
  $computers = Check-Servers -Servers (Get-Content $Servers)
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
  foreach ($computer in $computers) {
    $I++
    $percentil = ($I / $computers.Count) * 100
    Write-Progress -Activity "Creating XML for server $computer..." -Status "$([int]$percentil)% Complete:" -PercentComplete $percentil

    $c = $XML.CreateNode("element","Computer",$null)
    $pcID =  $wmiData.Win32_Computersystemproduct | where {$_.pscomputername -eq $Computer}
    #add an attribute for the name
    $c.SetAttribute("Name",$computer) | Out-Null
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
    $csnode = $XML.CreateNode("element","ComputerSystem",$null)
    $cshd = $XML.CreateNode("element","HDs",$null)
    $csInterface = $XML.CreateNode("element","NetworkInterfaces",$null)
    $csOpenPorts = $XML.CreateNode("element","OpenPorts",$null)

    #this is using the original property name
    $data =  $wmiData.Win32_Computersystem | where {$_.pscomputername -eq $Computer}
    $dataHDs =  $wmiData.Win32_DiskDrive | where {$_.pscomputername -eq $Computer}
    $dataNetAdapters =  $wmiData.Win32_NetworkAdapter | where {$_.pscomputername -eq $Computer} | sort Name
    $dataNetConfigs =  $wmiData.Win32_NetworkAdapterConfiguration | where {$_.pscomputername -eq $Computer}
    $dataOpenPorts = (($wmiData.Win32_NetworkOpenPort | where {$_.pscomputername -eq $Computer} | Select-String -Pattern '\s+(TCP.*LISTENING|UDP)') -replace '^\s+', '') -replace '\s+',' '
 
    #get a list of properties except PSComputername
    $props = ($wmiData.Win32_Computersystem[0] | Get-Member -MemberType Properties | where Name -ne 'PSComputername').Name
    $propsHD = ($wmiData.Win32_DiskDrive[0] | Get-Member -MemberType Properties | where Name -ne 'PSComputername').Name
    $propsNetInterface = ($wmiData.Win32_NetworkAdapter[0] | Get-Member -MemberType Properties | where Name -ne 'PSComputername').Name
    $propsNetConf = ($wmiData.Win32_NetworkAdapterConfiguration[0] | Get-Member -MemberType Properties | where Name -ne 'PSComputername').Name

    #create elements for each property
    $props | Foreach {
      $e = $XML.CreateNode("element",$_,$null)
      $e.InnerText = $data.$_
      $csnode.AppendChild($e) | Out-Null
    }
    #create hds elements
    foreach ($dataHD in $dataHDs) {
      $hdNode = $XML.CreateNode("element","HD",$null)
      $propsHD | Foreach {
        if ($dataHD.$_) {
          $e = $XML.CreateNode("element",$_,$null)
          $e.InnerText = $dataHD.$_
          $hdNode.AppendChild($e) | Out-Null
        }
      }
      $cshd.AppendChild($hdNode) | Out-Null
    }
    #create net adapter elements
    foreach($dataNetAdapter in $dataNetAdapters) {
      $netAdapterNode = $XML.CreateNode("element","NetworkInterface",$null)
      $propsNetInterface | Foreach {
      if ($dataNetAdapter.$_) {
        $e = $XML.CreateNode("element",$_,$null)
        $e.InnerText = $dataNetAdapter.$_
        $netAdapterNode.AppendChild($e) | Out-Null
       }
      }
      $dataNetConfig = $dataNetConfigs | where {$_.MACAddress -eq $dataNetAdapter.MACAddress}
      if ($dataNetConfig) {
        $netAdapterConfNode = $XML.CreateNode("element","NetworkInterfaceConfig",$null)
        $propsNetConf | Foreach {
          if ($dataNetConfig.$_ -and !($_ -eq "MACAddress")) {
            $e = $XML.CreateElement($_)
            $e.InnerText = $dataNetConfig.$_
            $netAdapterConfNode.AppendChild($e) | Out-Null
          }
        }
        $netAdapterNode.AppendChild($netAdapterConfNode) | Out-Null
      }
      $csInterface.AppendChild($netAdapterNode) | Out-Null
    }
    #create hash open ports
    $hashOpenPorts = [ordered]@{}
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
        $hashOpenPorts[$protocol] = [ordered]@{}
      }
      if (! $($hashOpenPorts[$protocol])[$ip]) {
        $($hashOpenPorts[$protocol])[$ip] = [ordered]@{}
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

    #add to parent
    $csnode.AppendChild($cshd) | Out-Null
    $csnode.AppendChild($csInterface) | Out-Null
    $csnode.AppendChild($csOpenPorts) | Out-Null
    $c.AppendChild($csnode) | Out-Null

    #create node for services
    $svcnode = $XML.CreateNode("element","Services",$null)
 
    #get a list of properties except PSComputername
    $props = ($wmiData.Win32_Service[0] | Get-Member -MemberType Properties | where Name -ne 'PSComputername').Name
    $data =  $wmiData.Win32_Service | where({$_.pscomputername -eq $Computer})
    foreach ($item in $data) {
     #create a service node
     $s = $XML.CreateNode("element","Service",$null)
     #create elements for each property
     $props | Foreach {
       $e = $XML.CreateElement($_)
       $e.InnerText = $item.$_
       $s.AppendChild($e) | Out-Null
     }
     #add to parent
     $svcnode.AppendChild($s) | Out-Null
    }
    #add to grandparent
    $c.AppendChild($svcnode) | Out-Null
    #append to root
    $root.AppendChild($c) | Out-Null
  } #foreach computer
  #add root to the XMLument
  $XML.AppendChild($root) | Out-Null
  #save file
  $XML.save($Out)
}

Get-Invetary
