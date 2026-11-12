[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop'){throw 'R330_REQUIRES_NATIVE_WINDOWS_POWERSHELL_DOTNET_FRAMEWORK'}
$p=Join-Path $PSScriptRoot 'Test-R302-ActualSetupStageCleanupCrash-Native.ps1'
$s=[IO.File]::ReadAllText($p)
$hits=[regex]::Matches($s,'(?s)\$sourceCode=@''\r?\n(.*?)\r?\n''@')
if($hits.Count -ne 1){throw 'R330_R302_CSHARP_CLASS_BLOCK_MISSING'}
Add-Type -TypeDefinition $hits[0].Groups[1].Value -ErrorAction Stop
$method=[R302RealSetupDeleteWatcher].GetMethod('Bind')
if(!$method){throw 'R330_NATIVE_OBSERVER_NOT_IN_PRODUCTION_TEST_SCRIPT'}
$exact=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if(!(Test-Path $exact)){throw 'R330_EXACT_WINDOWS_POWERSHELL_NOT_FOUND'}
$base=Join-Path ([IO.Path]::GetTempPath()) ('tbme_r330_native_watcher_'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($base)|Out-Null
$counts=0
function Run-Scenario([string]$variant,[int]$index){
 $root=Join-Path $base ($variant+'_'+$index)
 $old=Join-Path $root 'old'
 $new=Join-Path $root 'new'
 [IO.Directory]::CreateDirectory($old)|Out-Null
 [IO.Directory]::CreateDirectory($new)|Out-Null
 $known=@()
 for($i=0;$i -lt 12;$i++){
  foreach($folder in @($old,$new)){
   $file=Join-Path $folder ('owned_{0:D2}.json' -f $i)
   [IO.File]::WriteAllText($file,'TEST_ONLY_KNOWN_STAGE_LEAF')
   $known+=,$file
  }
 }
 $psi=[Diagnostics.ProcessStartInfo]::new()
 $psi.FileName=$exact
 $psi.Arguments='-NoProfile -NonInteractive -Command "Start-Sleep -Seconds 60"'
 $psi.UseShellExecute=$false
 $psi.CreateNoWindow=$true
 $process=$null;$watcher=$null
 try {
  $process=[Diagnostics.Process]::Start($psi)
  if(!$process -or $process.Id -le 0){throw 'R330_SYNTHETIC_CHILD_NOT_STARTED'}
  $watcher=[R302RealSetupDeleteWatcher]::new()
  $watcher.Arm($old,$new)
  if($variant -ceq 'NATIVE_ONLY'){
   $flags=[Reflection.BindingFlags]'Instance,NonPublic'
   foreach($member in @('oldWatcher','newWatcher')){
    $f=[R302RealSetupDeleteWatcher].GetField($member,$flags)
    if(!$f){throw 'R330_NATIVE_ONLY_NO_MANAGED_WATCHER_REFLECTION'}
    $managed=[IO.FileSystemWatcher]$f.GetValue($watcher)
    $managed.EnableRaisingEvents=$false
   }
  }
  $watcher.Bind($process)
  $noise=Join-Path $old 'noise.tmp'
  [IO.File]::WriteAllText($noise,'UNRELATED_CREATED_FILE')
  Start-Sleep -Milliseconds 175
  $process.Refresh()
  if($process.HasExited -or $watcher.Killed -or $watcher.TerminatedEvent.IsSet){
   throw 'R330_NOISE_TRIPPED_A_KILL_OR_PROCESS_ALREADY_EXITED'
  }
  [IO.File]::Delete($known[0])
  if(!$watcher.TerminatedEvent.Wait(10000) -or !$watcher.Killed -or
     $watcher.TriggerFile -cne [IO.Path]::GetFileName($known[0])){
      throw ('R330_OWNED_STAGE_LEAF_DID_NOT_KILL_EXACT_PROCESS variant='+$variant+
             ' origin='+$watcher.TriggerOrigin+' reason='+$watcher.Failure)
  }
  $process.Refresh()
  if(!$process.HasExited -or $process.ExitCode -eq 0){throw 'R330_KILL_EXIT_NOT_NONZERO'}
  if($variant -ceq 'NATIVE_ONLY' -and
     ($watcher.TriggerOrigin -cne 'NATIVE_KNOWN_STAGE_LEAF_DELETION' -or
      $watcher.NativeKnownDeleteObservations -lt 1)){
   throw 'R330_NATIVE_FALLBACK_NOT_ACTUALLY_TRIGGERED'
  }
  $script:counts++
  Write-Output ('R330_SYNTHETIC_'+$variant+'_'+$index+'_PASS pid='+$process.Id+
                ' origin='+$watcher.TriggerOrigin+
                ' nativeEvents='+$watcher.NativeKnownDeleteObservations+
                ' managedEvents='+$watcher.Notifications)
 }finally{
  if($watcher){$watcher.Dispose()}
  if($process){
   try{$process.Refresh();if(!$process.HasExited){$process.Kill();[void]$process.WaitForExit(10000)}}
   finally{$process.Dispose()}
  }
 }
}
try {
 foreach($mode in @('NATIVE_ONLY','NATIVE_AND_MANAGED')){
  foreach($i in 1..3){Run-Scenario $mode $i}
 }
 if($counts -ne 6){throw ('R330_SYNTHETIC_SCENARIO_COUNT_'+$counts)}
 Write-Output 'R330_NATIVE_WATCHER_TEST_SIX_SYNTHETIC_PROCESS_KILLS=PASS'
}finally{
 if([IO.Directory]::Exists($base) -and
    [IO.Path]::GetFileName($base).StartsWith('tbme_r330_native_watcher_',[StringComparison]::Ordinal)){
  $links=@(Get-ChildItem $base -Recurse -Force|Where-Object {($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0})
  if($links.Count -ne 0){throw 'R330_UNEXPECTED_SANDBOX_REPARSE_NO_CLEANUP'}
  [IO.Directory]::Delete($base,$true)
 }
}
