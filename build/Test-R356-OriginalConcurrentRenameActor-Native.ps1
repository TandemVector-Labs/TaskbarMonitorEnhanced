[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
 [Parameter(Mandatory=$true)][string]$AppRoot,
 [Parameter(Mandatory=$true)][string]$MovedRoot,
 [Parameter(Mandatory=$true)][string]$ReadyPath,
 [Parameter(Mandatory=$true)][string]$SignalPath,
 [Parameter(Mandatory=$true)][string]$ReceiptPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# A separate real Windows process in an isolated GitHub-hosted runner.
# ONLY renames exact synthetic per-user application root; no junction,
# driver, real installation or user deletion.
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:GITHUB_REPOSITORY -cne 'GOD13emad/TaskbarMonitorEnhanced' -or
   $env:GITHUB_REF -cne 'refs/heads/audit/r356-handle-bound-directory-disposition' -or
   $env:GITHUB_SHA -cnotmatch '^[a-f0-9]{40}$' -or
   $env:GITHUB_RUN_ID -cnotmatch '^[0-9]{5,20}$' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC|ALIEMAD|SAEID|LAPTOP'){
 throw 'R355_REAL_CLEANUP_ACTOR_DISPOSABLE_ONLY'
}
$expected=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$canonical=[IO.Path]::GetFullPath($expected)
$expectedMoved=$canonical+'_R355_RACE_'+$HostLabel+'_'+$env:GITHUB_RUN_ID
$temp=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\')+'\'
if(-not [string]::Equals($canonical,[IO.Path]::GetFullPath($AppRoot),[StringComparison]::OrdinalIgnoreCase) -or
   -not [string]::Equals($expectedMoved,[IO.Path]::GetFullPath($MovedRoot),[StringComparison]::OrdinalIgnoreCase) -or
   @($ReadyPath,$SignalPath,$ReceiptPath|Where-Object{
      -not [IO.Path]::GetFullPath($_).StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)
   }).Count -gt 0){
 throw 'R355_ACTOR_UNTRUSTED_PATH_IDENTITY'
}
$actorPid=$PID;$cleanupPid=0;$preflightMoved=$false
$firstMissing=-1;$renameDenied=$false;$renameAllowed=$false
$hresult=0;$attempts=0;$failure='';$phase='PREFLIGHT';$helperAliveAtDenied=$false
$stage=Join-Path $canonical 'delete_stage'
$movedPath=$expectedMoved
try{
 foreach($p in @($ReadyPath,$SignalPath,$ReceiptPath,$movedPath)){
  if([IO.File]::Exists($p) -or [IO.Directory]::Exists($p)){throw 'R355_ACTOR_CONTROL_OR_MOVED_PREEXISTS'}
 }
 if(-not [IO.Directory]::Exists($canonical) -or
   ([IO.File]::GetAttributes($canonical) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
   throw 'R355_ACTOR_FRESH_SYNTHETIC_ROOT_NOT_NORMAL_DIRECTORY'
 }
 for($i=0;$i -lt 12;$i++){
  if(-not [IO.File]::Exists((Join-Path $stage ('{0:d5}.bin' -f $i)))){
    throw 'R355_ACTOR_SYNTHETIC_WITNESS_FILE_MISSING'
  }
 }
 # Native same-parent rename must be allowed without Helper's directory lease.
 [IO.Directory]::Move($canonical,$movedPath)
 if(-not [IO.Directory]::Exists($movedPath)){throw 'R355_PREHELPER_MOVE_NOT_REAL'}
 [IO.Directory]::Move($movedPath,$canonical)
 if(-not [IO.Directory]::Exists($canonical)){throw 'R355_PREHELPER_MOVE_NOT_RESTORED'}
 $preflightMoved=$true
 [IO.File]::WriteAllText($ReadyPath,'R355_REAL_NATIVE_ACTOR_READY_'+$env:GITHUB_SHA,[Text.UTF8Encoding]::new($false))
 $phase='WAIT_FOR_NATIVE_ORIGINAL_CLEANUP_PID'
 $clock=[Diagnostics.Stopwatch]::StartNew()
 while(-not [IO.File]::Exists($SignalPath) -and $clock.ElapsedMilliseconds -lt 24000){
  Start-Sleep -Milliseconds 2
 }
 if(-not [IO.File]::Exists($SignalPath)){throw 'R355_ACTOR_CLEANUP_SIGNAL_TIMEOUT'}
 $signal=Get-Content -LiteralPath $SignalPath -Raw|ConvertFrom-Json
 if($signal.SourceCommit -cne $env:GITHUB_SHA -or
    $signal.Host -cne $HostLabel -or
    $signal.CleanupPid -le 0 -or $signal.CleanupPid -eq $PID){
  throw 'R355_ACTOR_CLEANUP_PID_IDENTITY_UNTRUSTED'
 }
 $cleanupPid=[int]$signal.CleanupPid
 $phase='WAIT_FOR_WITNESSED_FIRST_REAL_SYNTHETIC_FILE_DELETION'
 $clock.Restart()
 while($clock.ElapsedMilliseconds -lt 27000){
  $live=Get-Process -Id $cleanupPid -ErrorAction SilentlyContinue
  if(!$live){break}
  for($i=0;$i -lt 12;$i++){
   if(-not [IO.File]::Exists((Join-Path $stage ('{0:d5}.bin' -f $i)))){
    $firstMissing=$i;break
   }
  }
  if($firstMissing -ge 0){break}
  Start-Sleep -Milliseconds 1
 }
 if($firstMissing -lt 0){throw 'R355_ACTOR_NO_REAL_DELETION_WITNESS_DURING_LIVE_CHILD'}
 $phase='ATTEMPT_REAL_SAME_PARENT_DIRECTORY_RENAME_DURING_NATIVE_DELETION'
 $clock.Restart()
 while($clock.ElapsedMilliseconds -lt 12000){
  $child=Get-Process -Id $cleanupPid -ErrorAction SilentlyContinue
  if(!$child){break}
  $attempts++
  try{
   [IO.Directory]::Move($canonical,$movedPath)
   $renameAllowed=$true
   # Strict test cleanup: only reverse our own exact moved root.
   if([IO.Directory]::Exists($movedPath) -and -not [IO.Directory]::Exists($canonical)){
     [IO.Directory]::Move($movedPath,$canonical)
   }
   break
  }catch [IO.IOException]{
   $hresult=$_.Exception.HResult -band 65535
   if($hresult -eq 32 -and $null -ne (Get-Process -Id $cleanupPid -ErrorAction SilentlyContinue)){
    $helperAliveAtDenied=$true;$renameDenied=$true;break
   }
  }catch [UnauthorizedAccessException]{
   $hresult=$_.Exception.HResult -band 65535
  }
  Start-Sleep -Milliseconds 1
 }
 if($renameAllowed){throw 'R355_REAL_ORIGINAL_CLEANUP_DIRECTORY_RENAME_ALLOWED_WHILE_CHILD_ACTIVE'}
 if(-not $renameDenied -or -not $helperAliveAtDenied){
  throw ('R355_REAL_ORIGINAL_CLEANUP_LEASE_DENIAL_NOT_WITNESSED attempts='+$attempts+' win32='+$hresult)
 }
}catch{
 $failure=$_.Exception.GetType().Name+': '+$_.Exception.Message+' PHASE='+$phase
}finally{
 # Never delete synthetic app bytes. If actor's rename got through, restore name
 # only if the exact sibling is still present, and fail instead of following links.
 try{
  if([IO.Directory]::Exists($movedPath) -and
     -not [IO.Directory]::Exists($canonical) -and
     ([IO.File]::GetAttributes($movedPath) -band [IO.FileAttributes]::ReparsePoint) -eq 0){
    [IO.Directory]::Move($movedPath,$canonical)
  }
 }catch{$failure+=' ACTOR_RESTORE_FAILED='+$_.Exception.Message}
 $status=if(-not $failure -and $renameDenied -and $preflightMoved -and
   $helperAliveAtDenied -and $firstMissing -ge 0 -and
   $attempts -gt 0 -and $hresult -eq 32){
   'PASS_REAL_NATIVE_ORIGINAL_CLEANUP_DIRECTORY_RENAME_DENIED_ON_LIVE_DELETION'
 }else{'FAIL_R355_LIVE_CLEANUP_RENAME_NOT_PROVEN'}
 $receipt=[ordered]@{
  Schema=1;Revision='R355';Status=$status;SourceCommit=$env:GITHUB_SHA
  Host=$HostLabel;ActorPid=$actorPid;OriginalCleanupPid=$cleanupPid
  SeparateNativeProcess=$true;PreHelperRenameSucceededAndRestored=$preflightMoved
  FirstSyntheticFileAlreadyDeletedBeforeProbe=$firstMissing
  RenameAttempts=$attempts;RealRenameAllowedDuringCleanup=$renameAllowed
  NativeSharingViolationWin32=$hresult;RealRenameDeniedWhileCleanupAlive=$renameDenied
  OriginalCleanupAliveAtDenial=$helperAliveAtDenied
  OutsideCanaryTouched=$false;OwnerMachineTouched=$false
  InteractiveUACObserved=$false;Failure=$failure
 }
 try{
  [IO.File]::WriteAllText($ReceiptPath,($receipt|ConvertTo-Json -Depth 7),
      [Text.UTF8Encoding]::new($false))
 }catch{Write-Output ('R355_ACTOR_RECEIPT_WRITE_FAILURE='+$_.Exception.Message)}
 Write-Output ('R355_ACTOR_LIVE_RENAME_STATUS='+$status+' tries='+$attempts+' code='+$hresult)
}
if($failure){throw ('R355_ACTOR_FAILED '+$failure)}
