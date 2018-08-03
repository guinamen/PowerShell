function Get-PendingUpdate {
  $temp = $null
  try {
    #Create Session COM object 
    $updatesession = [activator]::CreateInstance([type]::GetTypeFromProgID("Microsoft.Update.Session",'localhost'))
    # Configure Session COM Object 
    $updatesearcher = $updatesession.CreateUpdateSearcher()
    # Configure Searcher object to look for Updates awaiting installation 
    $searchresult = $updatesearcher.Search("IsInstalled=0")
    if ($searchresult.Updates.Count -gt 0) {
      $temp = "" | Select Title,KB,Priority,RebootBehavior,IsDownloaded
      for ($i=0; $i -lt $searchresult.Updates.Count; $i++) {
        # Create object holding update 
        $update = $searchresult.Updates.Item($i)
        # Define object
        $temp.Title = $update.Title
        $temp.KB = ('KB' + $update.KBArticleIDs)
 
        # Get priority
        $temp.Priority = switch ($update.DownloadPriority) {
          1 {'Low'}
          2 {'Normal'}
          3 {'High'}
        }
 
        # Get reboot behaivor
        $temp.RebootBehavior = switch ($update.InstallationBehavior.RebootBehavior) {
          0 {'NeverReboots'}
          1 {'AlwaysRequiresReboot'}
          2 {'CanRequestReboot'}
        }
 
        # Verify that update has been downloaded
        if ($update.IsDownLoaded -eq "True") {
          $temp.IsDownloaded = $true
        } else {
          $temp.IsDownloaded = $false
        }
      }
    }
  } 
  catch { 
    # Catch error and return it
    return $_.Exception
  }
  return $temp
}

function Download-Update {
  Param(
  [Parameter(Mandatory=$True,Position=1,ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
  $Updates
  )
  $Session = New-Object -ComObject Microsoft.Update.Session
  $Downloader = $Session.CreateUpdateDownloader()
  $Downloader.Updates = $Updates
  $Downloader.Download()
}

function Install-Update {
  Param(
   [Parameter(Mandatory=$True,Position=1,ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
   $Updates
  )
  $Installer = New-Object -ComObject Microsoft.Update.Installer
  $Installer.Updates = $SearchResult
  $Result = $Installer.Install()
}
