[CmdletBinding()]
param(
 [ValidateSet('Driver','Worker','Recover')][string]$Mode='Driver',
 [string]$Fixture=''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# R306: isolated fault-injection prototype, never elevates or touches Program Files.
if($env:OS -cne 'Windows_NT'){throw 'R306_WINDOWS_REQUIRED'}
$Source=Join-Path $PSScriptRoot '..\installer\TBME_Setup_Elevated_Helper.ps1'
$sourceTokens=$null;$sourceErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($Source,[ref]$sourceTokens,[ref]$sourceErrors)
if(@($sourceErrors).Count){throw 'R306_PRODUCTION_PARSER_INVALID'}
$functions=@($ast.FindAll({param($node)
 $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
 $node.Name -in @('Get-SensorRollbackFiles','Assert-SensorBoundaryNoReparse')
},$true))
if($functions.Count -ne 2){throw 'R306_PRODUCTION_CAPTURE_FUNCTIONS_NOT_FOUND'}
. ([scriptblock]::Create(($functions|ForEach-Object{$_.Extent.Text}) -join [Environment]::NewLine))
function HashBytes([byte[]]$value){
 $sha=[Security.Cryptography.SHA256]::Create()
 try{return [BitConverter]::ToString($sha.ComputeHash($value)).Replace('-','')}
 finally{$sha.Dispose()}
}
function SHA([string]$name){
 if(!(Test-Path -LiteralPath $name -PathType Leaf)){return 'MISSING'}
 return (Get-FileHash -LiteralPath $name -Algorithm SHA256).Hash
}
function WriteNewAndFlush([string]$name,[byte[]]$data){
 if([IO.File]::Exists($name)){throw ('R306_EXISTING_OUTPUT_REFUSED_'+$name)}
 $parent=[IO.Path]::GetDirectoryName($name)
 [void][IO.Directory]::CreateDirectory($parent)
 Assert-SensorBoundaryNoReparse $parent
 $stream=[IO.FileStream]::new($name,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$stream.Write($data,0,$data.Length);$stream.Flush($true)}
 finally{$stream.Dispose()}
}
function SafeRelative([string]$rel){
 if([string]::IsNullOrEmpty($rel) -or [IO.Path]::IsPathRooted($rel) -or
   $rel.Contains('/') -or $rel.Contains(':') -or
   $rel.Contains('..') -or $rel.StartsWith('\') -or $rel.EndsWith('\')){
  throw 'R306_BAD_RELATIVE_SNAPSHOT_NAME'
 }
 foreach($p in $rel.Split('\')){
  if($p -notmatch '^[A-Za-z0-9_.-]+$' -or $p -in @('.','..')){throw ('R306_BAD_RELATIVE_SNAPSHOT_NAME REL='+$rel+' PART='+$p)}
 }
}
function SaveDurable([string]$broker,[string]$journal,[string]$owner,[string]$taskXml){
 if(Test-Path -LiteralPath $journal){throw 'R306_JOURNAL_ALREADY_EXISTS'}
 Assert-SensorBoundaryNoReparse $broker
 Assert-SensorBoundaryNoReparse ([IO.Path]::GetDirectoryName($journal))
 $files=Get-SensorRollbackFiles $broker
 if($files.Count -lt 1 -or $files.Count -gt 128){throw 'R306_CAPTURE_COUNT'}
 [void][IO.Directory]::CreateDirectory($journal)
 [void][IO.Directory]::CreateDirectory((Join-Path $journal 'files'))
 $index=[Collections.Generic.List[object]]::new()
 foreach($item in $files){
  $rel=[string]$item.Rel
  SafeRelative $rel
  $bytes=[byte[]]$item.Data
  $path=Join-Path (Join-Path $journal 'files') $rel
  WriteNewAndFlush $path $bytes
  $sum=HashBytes $bytes
  if((SHA $path) -cne $sum){throw 'R306_DURABLE_CAPTURE_READBACK_MISMATCH'}
  $index.Add([pscustomobject]@{Rel=$rel;Length=$bytes.Length;Sha256=$sum})
 }
 $taskBytes=[Text.Encoding]::UTF8.GetBytes($taskXml)
 if($taskBytes.Length -gt 262144){throw 'R306_TASK_XML_OVERLIMIT'}
 WriteNewAndFlush (Join-Path $journal 'task.xml') $taskBytes
 $manifest=[ordered]@{
  Schema=1;Status='PREPARED';Sid=$owner;
  OriginalFiles=@($index);TaskSha256=(HashBytes $taskBytes)
 }
 $data=[Text.Encoding]::UTF8.GetBytes(($manifest|ConvertTo-Json -Depth 7 -Compress))
 WriteNewAndFlush (Join-Path $journal 'manifest.json') $data
 # Durable READY is the last file created and flushed. The caller must not
 # change the live BrokerRoot before this point.
 WriteNewAndFlush (Join-Path $journal 'READY') ([Text.Encoding]::ASCII.GetBytes('R306_READY_V1'))
 if((SHA (Join-Path $journal 'READY')) -eq 'MISSING'){throw 'R306_READY_NOT_DURABLE'}
}
function RestoreDurable([string]$broker,[string]$journal,[string]$expectedSid){
 if(-not (Test-Path -LiteralPath (Join-Path $journal 'READY') -PathType Leaf)){
  throw 'R306_NOT_READY_NO_RESTORE'
 }
 Assert-SensorBoundaryNoReparse $journal
 $marker=[IO.File]::ReadAllText((Join-Path $journal 'READY'),[Text.Encoding]::ASCII)
 if($marker -cne 'R306_READY_V1'){throw 'R306_READY_NOT_MATCHED'}
 $manifest=[IO.File]::ReadAllText((Join-Path $journal 'manifest.json'),[Text.Encoding]::UTF8)|ConvertFrom-Json
 if($manifest.Schema -ne 1 -or $manifest.Status -cne 'PREPARED' -or
   $manifest.Sid -cne $expectedSid){throw 'R306_SNAPSHOT_ACCOUNT_MISMATCH'}
 $files=@($manifest.OriginalFiles)
 if($files.Count -lt 1 -or $files.Count -gt 128){throw 'R306_INVALID_MANIFEST_COUNT'}
 $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 # Validate ALL saved contents and paths before writing even the first restored byte.
 $validated=[Collections.Generic.List[object]]::new()
 foreach($entry in $files){
  $relative=[string]$entry.Rel
  SafeRelative $relative
  if(-not $seen.Add($relative)){throw 'R306_DUPLICATE_MANIFEST_FILE'}
  $path=Join-Path (Join-Path $journal 'files') $relative
  Assert-SensorBoundaryNoReparse $path
  $payload=[IO.File]::ReadAllBytes($path)
  if($payload.Length -ne [int]$entry.Length -or
     (HashBytes $payload) -cne [string]$entry.Sha256){
   throw 'R306_BACKUP_HASH_INVALID'
  }
  $validated.Add([pscustomobject]@{Rel=$relative;Bytes=$payload})
 }
 Assert-SensorBoundaryNoReparse (Join-Path $journal 'task.xml')
 $xml=[IO.File]::ReadAllBytes((Join-Path $journal 'task.xml'))
 if((HashBytes $xml) -cne [string]$manifest.TaskSha256){
  throw 'R306_TASK_XML_HASH_INVALID'
 }
 # Restore writes here are synthetic; in production they would be after
 # stopping only the owned task/process, and would need handle-bound writes.
 foreach($entry in $validated){
  $target=Join-Path $broker $entry.Rel
  Assert-SensorBoundaryNoReparse $target
  [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
  Assert-SensorBoundaryNoReparse $target
  [IO.File]::WriteAllBytes($target,[byte[]]$entry.Bytes)
 }
 foreach($entry in $validated){
  if((SHA (Join-Path $broker $entry.Rel)) -cne (HashBytes $entry.Bytes)){
   throw 'R306_RESTORED_HASH_NOT_EQUAL_TO_MANIFEST'
  }
 }
 return [Text.Encoding]::UTF8.GetString($xml)
}
function StartWorker([string]$mode,[string]$fixture){
 $hostPath=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
 if(-not [IO.File]::Exists($hostPath)){throw 'R306_PINNED_NATIVE_POWERSHELL_MISSING'}
 $command='-NoLogo -NoProfile -NonInteractive -File "'+$PSCommandPath+'" -Mode '+$mode+' -Fixture "'+$fixture+'"'
 $psi=[Diagnostics.ProcessStartInfo]::new()
 $psi.FileName=$hostPath;$psi.Arguments=$command
 $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
 $psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
 return [Diagnostics.Process]::Start($psi)
}
if($Mode -ne 'Driver'){
 if([string]::IsNullOrEmpty($Fixture) -or -not [IO.Directory]::Exists($Fixture)){throw 'R306_FIXTURE_UNKNOWN'}
 $broker=Join-Path $Fixture 'broker'
 $journal=Join-Path $Fixture 'journal'
 $sid=[string]([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
 if($Mode -eq 'Worker'){
  SaveDurable $broker $journal $sid '<Task>OWNED_PREVIOUS_SENSOR_SERVICE</Task>'
  [IO.File]::Delete((Join-Path $broker 'broker.exe'))
  [IO.File]::WriteAllText((Join-Path $Fixture 'MUTATED'),'READY_AND_LIVE_FILE_REMOVED')
  Start-Sleep -Seconds 35
  exit 0
 }
 if($Mode -eq 'Recover'){
  $xml=RestoreDurable $broker $journal $sid
  if($xml -cne '<Task>OWNED_PREVIOUS_SENSOR_SERVICE</Task>'){
   throw 'R306_TASK_XML_NOT_PRESERVED'
  }
  [Console]::Write('R306_SYNTHETIC_RESTORED')
  exit 0
 }
 throw 'R306_MODE_INVALID'
}
$fixture=Join-Path $env:TEMP ('R306_DISPOSABLE_'+[guid]::NewGuid().ToString('N'))
$broker=Join-Path $fixture 'broker'
$outside=Join-Path $fixture 'outside'
[void][IO.Directory]::CreateDirectory($broker)
[void][IO.Directory]::CreateDirectory($outside)
$first=Join-Path $broker 'broker.exe'
$second=Join-Path $broker 'sensor.config'
$canary=Join-Path $outside 'unrelated-user.txt'
[IO.File]::WriteAllBytes($first,([Text.Encoding]::ASCII.GetBytes('ORIGINAL_SIGNED_BROKER_BINARY_R306')))
[IO.File]::WriteAllBytes($second,([Text.Encoding]::ASCII.GetBytes('ORIGINAL_CONFIGURATION_R306')))
[IO.File]::WriteAllText($canary,'UNRELATED_USER_DATA_NOT_CHANGED')
$baselineA=SHA $first;$baselineB=SHA $second;$baselineCanary=SHA $canary
$worker=StartWorker Worker $fixture
try{
 $clock=[Diagnostics.Stopwatch]::StartNew()
 while(-not(Test-Path -LiteralPath (Join-Path $fixture 'MUTATED')) -and
       -not $worker.HasExited -and $clock.ElapsedMilliseconds -lt 20000){
  Start-Sleep -Milliseconds 80
 }
 if(-not (Test-Path -LiteralPath (Join-Path $fixture 'MUTATED')) -or $worker.HasExited){
  throw ('R306_WORKER_NO_DURABLE_READY_CHECKPOINT '+$worker.StandardError.ReadToEnd())
 }
 if((SHA $first) -cne 'MISSING' -or (SHA (Join-Path $fixture 'journal\READY')) -eq 'MISSING'){
  throw 'R306_PROTECTED_CRASH_WINDOW_NOT_REPRODUCED'
 }
 $worker.Kill()
 if(-not $worker.WaitForExit(9000) -or $worker.ExitCode -eq 0){
  throw 'R306_WORKER_NOT_ACTUALLY_TERMINATED'
 }
}finally{
 if(-not $worker.HasExited){$worker.Kill();[void]$worker.WaitForExit(9000)}
 $worker.Dispose()
}
$recover=StartWorker Recover $fixture
try{
 if(-not $recover.WaitForExit(16000) -or $recover.ExitCode -ne 0){
  throw ('R306_SEPARATE_PROCESS_RECOVERY_FAILED '+$recover.StandardError.ReadToEnd())
 }
}finally{
 if(-not $recover.HasExited){$recover.Kill();[void]$recover.WaitForExit(9000)}
 $recover.Dispose()
}
if((SHA $first) -cne $baselineA -or (SHA $second) -cne $baselineB -or (SHA $canary) -cne $baselineCanary){
 throw 'R306_CROSS_PROCESS_RECOVERY_WRONG'
}
# R306 negative tests: an unrelated SID and an incomplete journal are
# refused before any live write, even when the underlying snapshot is valid.
$foreign='S-1-5-21-12345-23456-34567-45678'
$denied=$false
try{$null=RestoreDurable $broker (Join-Path $fixture 'journal') $foreign}
catch{if($_.Exception.Message -match 'R306_SNAPSHOT_ACCOUNT_MISMATCH'){$denied=$true}else{throw}}
if(-not $denied -or (SHA $first) -cne $baselineA){throw 'R306_FOREIGN_SID_NOT_FAIL_CLOSED'}
$ready=Join-Path $fixture 'journal\READY'
[IO.File]::Delete($ready)
$notReady=$false
try{$null=RestoreDurable $broker (Join-Path $fixture 'journal') ([string]([Security.Principal.WindowsIdentity]::GetCurrent().User.Value))}
catch{if($_.Exception.Message -match 'R306_NOT_READY_NO_RESTORE'){$notReady=$true}else{throw}}
if(-not $notReady -or (SHA $first) -cne $baselineA){throw 'R306_INCOMPLETE_BACKUP_NOT_FAIL_CLOSED'}
WriteNewAndFlush $ready ([Text.Encoding]::ASCII.GetBytes('R306_READY_V1'))
if((SHA $canary) -cne $baselineCanary){throw 'R306_OUTSIDE_CANARY_CHANGED'}

# Tamper one protected snapshot AFTER restoring once. The next attempt must
# refuse before replacing live file: check existing modified test file hash.
[IO.File]::WriteAllBytes($first,[Text.Encoding]::ASCII.GetBytes('CURRENT_CANARY_KEEP'))
$liveBefore=SHA $first
[IO.File]::WriteAllBytes((Join-Path $fixture 'journal\files\broker.exe'),
 [Text.Encoding]::ASCII.GetBytes('TAMPERED_SNAPSHOT'))
$failed=$false
try{$null=RestoreDurable $broker (Join-Path $fixture 'journal') ([string]([Security.Principal.WindowsIdentity]::GetCurrent().User.Value))}
catch{if($_.Exception.Message -match 'R306_BACKUP_HASH_INVALID'){$failed=$true}else{throw}}
if(-not $failed -or (SHA $first) -cne $liveBefore -or (SHA $canary) -cne $baselineCanary){
 throw 'R306_INVALID_SNAPSHOT_MUST_NOT_MUTATE_LIVE'
}
$receipt=[ordered]@{
 Schema=1;Revision='R306-PROTOTYPE'
 Status='PASS_SYNTHETIC_DURABLE_SNAPSHOT_KILL_RESTORE_AND_TAMPER_REFUSAL'
 Commit=(git -C $PSScriptRoot rev-parse HEAD)
 OriginalProtectedServicesTouched=$false
 UACInvoked=$false
 ProgramFilesWritten=$false
 ActualProofWorkerKilled=$true
 SameUserFreshProcessRestore=$true
 PreWriteSnapshotHashValidation=$true
 CrossSidRefusedBeforeWrite=$true
 MissingReadyMarkerRefused=$true
 ActualSensorHelperKilled=$false
 PreviousTaskXmlTransportedButNotRegistered=$true
 ExternalCanaryPreserved=$true
 FixtureRoot=$fixture
 FixtureFilesSHA256=@{BrokerOriginal=$baselineA;ConfigOriginal=$baselineB;Canary=$baselineCanary}
 RecordedUtc=[DateTime]::UtcNow.ToString('o')
}
$resultPath=Join-Path $fixture 'R306_RECEIPT.json'
[IO.File]::WriteAllText($resultPath,($receipt|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
"R306_PROTOTYPE_PASS Receipt=$resultPath"
