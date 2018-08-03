function Get-ComputerUpTime {
  #Requires -version 2.0
  $startUpID = 6005
  $shutDownID = 6006
  $events = Get-WinEvent -FilterHashtable @{Logname='System';ID=@($startUpID,$shutDownID);ProviderName='EventLog'} | Sort-Object TimeCreated
  $totalTime = $null
  $now = Get-Date

  $eventAfter = $null
  $eventNow = $null
  $eventFirst = $null
  ForEach($event in $events) {
    if ($event.Id -eq 6006) {
      $eventNow = $event.TimeCreated
    } elseif ($eventNow -ne $null -and $event.Id -eq 6005) {
      $eventAfter = $event.TimeCreated
    }
    if ($eventAfter -ne $null -and $eventNow -ne $null) {
      if ($eventFirst -eq $null) {
        $eventFirst = $eventNow
      }
      $totalTime += $eventAfter - $eventNow
      $eventAfter = $null
      $eventNow = $null
    }
  }
  return (100- (($totalTime.TotalSeconds / ($now - $eventFirst).TotalSeconds) *100))
}
