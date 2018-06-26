#requires -version 4.0
 
#Demo-ServerInventoryXML.ps1
 
Param($Out="C:\Work\MyInventory.xml", $Servers="C:\Users\pb003283\Documents\myservers.txt")
 
Write-Host "Creating computer list" -ForegroundColor Green
#process list of computers filtering out those offline
$computers = Get-Content $Servers | Where { Test-WSMan $_ -ErrorAction SilentlyContinue}
 
Write-Host "Getting Operating System information" -ForegroundColor Green
$os = Get-CimInstance Win32_Operatingsystem -ComputerName $computers | Select @{Name="Computername";Expression={$_.PSComputername}},InstallDate,Caption,Version,OSArchitecture
 
Write-Host "Getting Computer system information" -ForegroundColor Green
$cs = Get-Ciminstance Win32_Computersystem -ComputerName $computers | Select PSComputername,TotalPhysicalMemory,HyperVisorPresent,NumberOfProcessors,NumberofLogicalProcessors, Domain
$csp = Get-Ciminstance  Win32_Computersystemproduct -ComputerName $computers | Select PSComputername, Name, Vendor, uuid

Write-Host "Getting Computer system hard driver" -ForegroundColor Green
$hd = Get-Ciminstance Win32_DiskDrive -ComputerName $computers | Select Caption, Model, Size, SerialNumber, DeviceID, InterfaceType, PSComputername

Write-Host "Getting Computer system network adpater" -ForegroundColor Green
$netAdapter = Get-Ciminstance Win32_NetworkAdapter -ComputerName $computers -Filter "AdapterTypeID = 0 or AdapterTypeID = 9 or ConfigManagerErrorCode = 22" | Select PSComputername, Name, Speed, MACAddress, NetEnabled
$netAdapterConf = Get-Ciminstance Win32_NetworkAdapterConfiguration -ComputerName $computers -Filter "MACAddress is not null" |select PSComputername, MACAddress, DHCPEnabled, DefaultIPGateway, IPAddress, IPSubnet, DNSServerSearchOrder

Write-Host "Getting Services" -ForegroundColor Green
$services = Get-Ciminstance Win32_Service -ComputerName $computers -Filter "State = 'Running'" | Select PSComputername,Name,Displayname,StartMode,State,StartName

 
Write-Host "Initializing new XML document" -ForegroundColor Green
[xml]$Doc = New-Object System.Xml.XmlDocument
 
#create declaration
$dec = $Doc.CreateXmlDeclaration("1.0","UTF-8",$null)
#append to document
$doc.AppendChild($dec) | Out-Null
 
#create a comment and append it in one line
$text = @"
 
Server Inventory Report
Generated $(Get-Date)
v1.0
 
"@
 
$doc.AppendChild($doc.CreateComment($text)) | Out-Null
 
#create root Node
$root = $doc.CreateNode("element","Computers",$null)
 
#create a node for each computer
foreach ($computer in $Computers) {
 
 Write-Host "Adding inventory information for $computer" -ForegroundColor Green
 $c = $doc.CreateNode("element","Computer",$null)
 $pcID = $csp | where {$_.pscomputername -eq $Computer}
 #add an attribute for the name
 $c.SetAttribute("Name",$computer) | Out-Null
 $c.SetAttribute("Id", $pcID.uuid)| Out-Null
 $c.SetAttribute("Type", $pcID.Name)| Out-Null
 $c.SetAttribute("Vendor", $pcID.Vendor)| Out-Null
 
 #create node for OS
 Write-Host "...OS" -ForegroundColor Green
 $osnode = $doc.CreateNode("element","OperatingSystem",$null)
 
 #get related data
 $data = $os|where {$_.computername -eq $Computer}
 
 #create an element
 $e = $doc.CreateElement("Name")
 #assign a value
 $e.InnerText = $data.Caption
 $osnode.AppendChild($e) | Out-Null
 
 #create elements for the remaining properties
 "Version","InstallDate","OSArchitecture" | foreach {
  $e = $doc.CreateElement($_)
  $e.InnerText = $data.$_
  $osnode.AppendChild($e) | Out-Null
 }
 
 #add to parent node
 $c.AppendChild($osnode) | Out-Null
 
 #create node for Computer system
 Write-Host "...ComputerSystem" -ForegroundColor Green
 $csnode = $doc.CreateNode("element","ComputerSystem",$null)
 $cshd = $doc.CreateNode("element","HDs",$null)
 $csInterface = $doc.CreateNode("element","NetworkInterfaces",$null)

 #this is using the original property name
 
 $data = $cs | where {$_.pscomputername -eq $Computer}
 $dataHDs = $hd | where {$_.pscomputername -eq $Computer}
 $dataNetAdapters = $netAdapter | where {$_.pscomputername -eq $Computer} | sort Name
 $dataNetConfigs = $netAdapterConf | where {$_.pscomputername -eq $Computer}
 
 #get a list of properties except PSComputername
 $props = ($cs[0] | Get-Member -MemberType Properties | where Name -ne 'PSComputername').Name
 $propsHD = ($hd[0] | Get-Member -MemberType Properties | where Name -ne 'PSComputername').Name
 $propsNetInterface = ($netAdapter[0] | Get-Member -MemberType Properties | where Name -ne 'PSComputername').Name
 $propsNetConf = ($netAdapterConf[0] | Get-Member -MemberType Properties | where Name -ne 'PSComputername').Name

 #create elements for each property
 $props | Foreach {
  $e = $doc.CreateElement($_)
  $e.InnerText = $data.$_
  $csnode.AppendChild($e) | Out-Null
 }
 #create hds elements
 foreach ($dataHD in $dataHDs) {
  $hdNode = $doc.CreateNode("element","HD",$null)
  $propsHD | Foreach {
    if ($dataHD.$_) {
      $e = $doc.CreateElement($_)
      $e.InnerText = $dataHD.$_
      $hdNode.AppendChild($e) | Out-Null
    }
  }
  $cshd.AppendChild($hdNode) | Out-Null
 }
 #create net adapter elements
 foreach($dataNetAdapter in $dataNetAdapters) {
  $netAdapterNode = $doc.CreateNode("element","NetworkInterface",$null)
  $propsNetInterface | Foreach {
    if ($dataNetAdapter.$_) {
      $e = $doc.CreateElement($_)
      $e.InnerText = $dataNetAdapter.$_
      $netAdapterNode.AppendChild($e) | Out-Null
    }
  }
  $dataNetConfig = $dataNetConfigs | where {$_.MACAddress -eq $dataNetAdapter.MACAddress}
  if ($dataNetConfig) {
    $netAdapterConfNode = $doc.CreateNode("element","NetworkInterfaceConfig",$null)
    $propsNetConf | Foreach {
      if ($dataNetConfig.$_ -and !($_ -eq "MACAddress")) {
        $e = $doc.CreateElement($_)
        $e.InnerText = $dataNetConfig.$_
        $netAdapterConfNode.AppendChild($e) | Out-Null
      }
    }
    $netAdapterNode.AppendChild($netAdapterConfNode) | Out-Null
  }
  $csInterface.AppendChild($netAdapterNode) | Out-Null
 }

 #add to parent
 $csnode.AppendChild($cshd) | Out-Null
 $csnode.AppendChild($csInterface) | Out-Null
 $c.AppendChild($csnode) | Out-Null


 
 
 #create node for services
 Write-Host "...Services" -ForegroundColor green
 $svcnode = $doc.CreateNode("element","Services",$null)
 
 #get a list of properties except PSComputername
 $props = ($services[0] | Get-Member -MemberType Properties | where Name -ne 'PSComputername').Name
 
 $data = $services.where({$_.pscomputername -eq $Computer})
 foreach ($item in $data) {
   #create a service node
   $s = $doc.CreateNode("element","Service",$null)
 
   #create elements for each property
   $props | Foreach {
    $e = $doc.CreateElement($_)
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
 
#add root to the document
$doc.AppendChild($root) | Out-Null
 
#save file
Write-Host "Saving the XML document to $Path" -ForegroundColor Green
$doc.save($Path)
 
Write-Host "Finished!" -ForegroundColor green
