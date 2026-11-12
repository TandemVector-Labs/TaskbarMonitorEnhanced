[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
 [Parameter(Mandatory=$true)][string]$CandidateDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID) -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'R303_ONLY_DISPOSABLE_WINDOWS'
}
function SHA([string]$p){
 if(!(Test-Path -LiteralPath $p -PathType Leaf)){return 'MISSING'}
 return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
}
$root=Join-Path $env:RUNNER_TEMP ('R303_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $root 'R303_PROTECTED_SENSOR_OWNER_RECEIPT.json'
$childFile=Join-Path $root 'guard-child.ps1'
$broker=Join-Path $root 'simulated-protected-broker'
$markerFile=Join-Path $broker '.tbme-owner.sid'
$external=Join-Path $root 'external-canary'
$canary=Join-Path $external 'untouched.txt'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$prior=Join-Path $env:RUNNER_TEMP ('R302_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R302_REAL_SETUP_CLEANUP_KILL_RECEIPT.json')
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$main=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$config=Join-Path $app 'config.json'
$state=Join-Path $app 'install_state.json'
$checks=[Collections.Generic.List[string]]::new()
if(Test-Path -LiteralPath $root){throw 'R303_TEST_ROOT_PREEXISTS'}
$candidate=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
$previous=Get-Content -LiteralPath $prior -Raw|ConvertFrom-Json
if($candidate.Commit -cne $env:GITHUB_SHA -or
   $candidate.SetupSHA256 -cne (SHA $setup) -or
   $candidate.MainSHA256 -cne (SHA $main) -or
   $previous.SourceCommit -cne $env:GITHUB_SHA -or
   $previous.Host -cne $HostLabel -or
   $previous.Status -cne 'PASS_NATIVE_SETUP_KILLED_DURING_STAGE_CLEANUP_RECOVERED'){
 throw 'R303_UNTRUSTED_CANDIDATE_OR_PREDECESSOR_NATIVE_RECEIPT'
}
$before=@{Main=(SHA $main);Config=(SHA $config);State=(SHA $state)}
$sid=[string][Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($sid -cnotmatch '^S-1-5-21-(?:\d+-){3}\d+$'){throw 'R303_NOT_INTERACTIVE_SID'}
if(Get-ScheduledTask -TaskPath '\' -TaskName 'TaskbarMonitorEnhanced Sensor Broker' -ErrorAction SilentlyContinue){
 throw 'R303_GUEST_ALREADY_HAS_SENSOR_TASK'
}
if(@(Get-Process TaskbarMonitorSensorBroker,TaskbarMonitorSensorSupervisor -ErrorAction SilentlyContinue).Count -gt 0){
 throw 'R303_GUEST_ALREADY_HAS_SENSOR_PROCESS'
}
[void][IO.Directory]::CreateDirectory($root)
[void][IO.Directory]::CreateDirectory($external)
[IO.File]::WriteAllText($canary,'R303_EXTERNAL_CANARY_PRESERVE',[Text.UTF8Encoding]::new($false))
$canarySHA=SHA $canary
$helper=(Resolve-Path (Join-Path $PSScriptRoot '..\installer\TBME_Setup_Elevated_Helper.ps1')).Path
$raw=[IO.File]::ReadAllText($helper)
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($helper,[ref]$tokens,[ref]$errors)
if(@($errors).Count){throw 'R303_PRODUCTION_HELPER_PS51_PARSE_FAILED'}
$defs=@($ast.FindAll({param($node)
 $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
 $node.Name -in @('Assert-SensorBoundaryNoReparse','Assert-OrRecordSensorOwner')
},$true))
if($defs.Count -ne 2){throw 'R303_EXPECTED_TWO_REAL_GUARD_FUNCTIONS'}
$begin='# R264-SENSOR-GUARD-BOUNDARY-BEGIN'
$end='# R264-SENSOR-GUARD-BOUNDARY-END'
$i=$raw.IndexOf($begin,[StringComparison]::Ordinal)
$j=$raw.IndexOf($end,[StringComparison]::Ordinal)
if($i -lt 0 -or $j -le $i -or
   $raw.IndexOf($begin,$i+1,[StringComparison]::Ordinal) -ge 0 -or
   $raw.IndexOf($end,$j+1,[StringComparison]::Ordinal) -ge 0){
 throw 'R303_PRODUCTION_SID_GUARD_SPAN_NOT_UNIQUE'
}
$guard=$raw.Substring($i,$j+$end.Length-$i)
$install=$raw.IndexOf('$taskInstalled=$false',[StringComparison]::Ordinal)
$markerCall=$raw.IndexOf('    Assert-OrRecordSensorOwner',[StringComparison]::Ordinal)
$stop=$raw.IndexOf('    Get-Process TaskbarMonitorSensorSupervisor,TaskbarMonitorSensorBroker -ErrorAction SilentlyContinue |',$install,[StringComparison]::Ordinal)
if($markerCall -lt 0 -or $install -le $markerCall -or $stop -le $install){
 throw 'R303_OWNER_MARKER_MUST_BE_PERSISTED_PRE_MUTATION'
}
$checks.Add('EXACT_SOURCE_MARKER_BEFORE_PROTECTED_TASK_OR_PROCESS_MUTATION')
$assembly=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
$stream=$assembly.GetManifestResourceStream('Payload.TBME_Setup_Elevated_Helper.ps1')
if(!$stream){throw 'R303_EMBEDDED_HELPER_RESOURCE_MISSING'}
$reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true)
try{$embedded=$reader.ReadToEnd()}finally{$reader.Dispose()}
$normalize={param([string]$s) return $s.Replace([string][char]13+[string][char]10,[string][char]10).Replace([string][char]13,[string][char]10)}
if((& $normalize $raw) -cne (& $normalize $embedded)){
 throw 'R303_REVIEW_HELPER_AND_PE_EMBEDDED_TEXT_DIFFER'
}
$checks.Add('PE_EMBEDDED_HELPER_EXACT_SOURCE_MATCH')
$header=@'
[CmdletBinding()]
param([string]$Scenario,[string]$Broker,[string]$Result)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$BrokerRoot=$Broker
$SensorOwnerMarker=Join-Path $BrokerRoot '.tbme-owner.sid'
$validatedSensorSid=[string][Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$UserId=[string][Security.Principal.WindowsIdentity]::GetCurrent().Name
$TaskName='TaskbarMonitorEnhanced Sensor Broker'
$Mode='Install'
$ActiveArchitecture='UNKNOWN'
function Write-Log([string]$value){}
function Write-Result([string]$Status){
 [IO.File]::WriteAllText($Result,$Status,[Text.Encoding]::ASCII)
}
'@
$beforeGuard=@'
if($Scenario -ceq 'Record'){
 Assert-OrRecordSensorOwner
 [IO.File]::WriteAllText($Result,'MARKER_DURABLE',[Text.Encoding]::ASCII)
 Start-Sleep -Seconds 30
}elseif($Scenario -ceq 'Guard'){
'@
$afterGuard=@'
 [IO.File]::WriteAllText($Result,'GUARD_ACCEPTED_SAME_OWNER',[Text.Encoding]::ASCII)
}else{throw 'R303_TEST_SCENARIO_UNSUPPORTED'}
'@
$child=$header+[Environment]::NewLine+
 (($defs|ForEach-Object {$_.Extent.Text}) -join [Environment]::NewLine)+[Environment]::NewLine+
 $beforeGuard+[Environment]::NewLine+
 $guard+[Environment]::NewLine+
 $afterGuard
[IO.File]::WriteAllText($childFile,$child,[Text.UTF8Encoding]::new($false))
$tk=$null;$err=$null
[void][Management.Automation.Language.Parser]::ParseFile($childFile,[ref]$tk,[ref]$err)
if(@($err).Count){throw 'R303_SCOPED_CHILD_SCRIPT_PARSE_FAILED'}
function Start-Child([string]$scenario,[string]$folder,[string]$result){
 $ps=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
 $info=[Diagnostics.ProcessStartInfo]::new()
 $info.FileName=$ps
 $info.Arguments='-NoProfile -NonInteractive -File "'+$childFile+'" -Scenario '+$scenario+' -Broker "'+$folder+'" -Result "'+$result+'"'
 $info.UseShellExecute=$false
 $info.CreateNoWindow=$true
 $info.RedirectStandardError=$true
 $info.RedirectStandardOutput=$true
 return [Diagnostics.Process]::Start($info)
}
function Expect-Guard([string]$name,[string]$folder,[string]$expected){
 $result=Join-Path $root ($name+'.txt')
 if(Test-Path -LiteralPath $result){throw 'R303_DUPLICATE_SCENARIO'}
 $proc=Start-Child 'Guard' $folder $result
 try{
  if(!$proc.WaitForExit(18000)){throw ('R303_GUARD_TIMED_OUT_'+$name)}
  if($proc.ExitCode -ne 0){throw ('R303_GUARD_FAILED_'+$name+' '+$proc.StandardError.ReadToEnd())}
  if(!(Test-Path -LiteralPath $result)){throw ('R303_MISSING_GUARD_RECEIPT_'+$name)}
  $value=[IO.File]::ReadAllText($result,[Text.Encoding]::ASCII)
  if($value -cne $expected){
   throw ('R303_WRONG_GUARD_'+$name+' EXPECTED='+$expected+' ACTUAL='+$value)
  }
  $script:checks.Add($name)
 }finally{
  if(!$proc.HasExited){$proc.Kill();[void]$proc.WaitForExit(10000)}
  $proc.Dispose()
 }
}
$ready=Join-Path $root 'record-ready.txt'
$producer=Start-Child 'Record' $broker $ready
$watch=[Diagnostics.Stopwatch]::StartNew()
try{
 while(!(Test-Path -LiteralPath $ready) -and !$producer.HasExited -and $watch.ElapsedMilliseconds -lt 16000){
  Start-Sleep -Milliseconds 80
 }
 $producer.Refresh()
 if(!(Test-Path -LiteralPath $ready) -or $producer.HasExited -or
    [IO.File]::ReadAllText($ready) -cne 'MARKER_DURABLE' -or
    [IO.File]::ReadAllText($markerFile,[Text.Encoding]::ASCII) -cne $sid){
  throw ('R303_REAL_WRITER_DID_NOT_FLUSH_MARKER '+$(if($producer.HasExited){$producer.StandardError.ReadToEnd()}else{'TIMEOUT'}))
 }
 $producer.Kill()
 if(!$producer.WaitForExit(10000) -or !$producer.HasExited -or $producer.ExitCode -eq 0){
  throw 'R303_TEST_WRITER_KILL_NOT_PROVEN'
 }
}finally{
 if(!$producer.HasExited){$producer.Kill();[void]$producer.WaitForExit(10000)}
 $producer.Dispose()
}
$checks.Add('EXCLUSIVE_OWNER_MARKER_FLUSH_BEFORE_REAL_TEST_PROCESS_KILL')
$oldSHA=SHA $markerFile
Expect-Guard 'REPAIR_CURRENT_OWNER_AFTER_PROCESS_DEATH' $broker 'GUARD_ACCEPTED_SAME_OWNER'
if((SHA $markerFile) -cne $oldSHA){throw 'R303_REPAIR_CHANGED_VALID_OWNER_MARKER'}
$checks.Add('SAME_OWNER_PROTECTED_MARKER_IMMUTABLE_ON_RETRY')
[IO.File]::Delete($markerFile)
Expect-Guard 'ROOT_WITH_MISSING_OWNER_REFUSED' $broker 'DEGRADED_OTHER_USER_SENSOR_LAYER_PRESERVED'
if(Test-Path -LiteralPath $markerFile){throw 'R303_MISSING_OWNER_WAS_CREATED_DURING_REFUSAL'}
$checks.Add('MISSING_OWNER_REFUSAL_NO_MUTATION')
[IO.File]::WriteAllText($markerFile,'S-1-5-21-0-0-0-1',[Text.Encoding]::ASCII)
Expect-Guard 'FOREIGN_OWNER_SID_REFUSED' $broker 'DEGRADED_OTHER_USER_SENSOR_LAYER_PRESERVED'
$checks.Add('OTHER_SID_REFUSAL_NO_MUTATION')
[IO.File]::WriteAllText($markerFile,$sid,[Text.Encoding]::ASCII)
Expect-Guard 'CORRECT_SID_ACCEPTED_AGAIN' $broker 'GUARD_ACCEPTED_SAME_OWNER'
$checks.Add('EXACT_SID_VALIDATION_REUSABLE')
$priorBroker=Join-Path $root 'prior-owned-root'
[IO.Directory]::Move($broker,$priorBroker)
New-Item -ItemType Junction -Path $broker -Target $external -ErrorAction Stop|Out-Null
if(-not ((Get-Item -LiteralPath $broker -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){
 throw 'R303_NATIVE_JUNCTION_NOT_CREATED'
}
Expect-Guard 'PARENT_JUNCTION_REFUSED' $broker 'DEGRADED_OTHER_USER_SENSOR_LAYER_PRESERVED'
if((SHA $canary) -cne $canarySHA){throw 'R303_EXTERNAL_CANARY_MODIFIED'}
[IO.Directory]::Delete($broker)
if(Test-Path -LiteralPath $broker){throw 'R303_JUNCTION_LINK_RESIDUE'}
[IO.Directory]::Move($priorBroker,$broker)
$checks.Add('REAL_WINDOWS_JUNCTION_REJECTED_EXTERNAL_BYTES_UNTOUCHED')
if((SHA $main) -cne $before.Main -or (SHA $config) -cne $before.Config -or
   (SHA $state) -cne $before.State -or
   (SHA $canary) -cne $canarySHA -or
   [IO.File]::ReadAllText($markerFile,[Text.Encoding]::ASCII) -cne $sid){
 throw 'R303_GUEST_PROTECTED_USER_BYTES_CHANGED'
}
$checks.Add('GUEST_MAIN_CONFIG_STATE_AND_EXTERNAL_CANARY_PRESERVED')
$result=[ordered]@{
 Schema=1;Revision='R303';Status='PASS_PROTECTED_SENSOR_OWNER_MARKER_REPAIR_GUARD'
 Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
 OriginalOwnerComputerTouched=$false
 PEEmbeddedSourceExact=$true
 RealDisposableWriterKilledAfterMarkerFlush=$true
 ActualElevatedHelperProcessKilled=$false
 ActualProtectedServicesChanged=$false
 MissingOrForeignOwnerRefused=$true
 SameOwnerWithoutTaskAccepted=$true
 ActualJunctionRefused=$true
 MainAndUserDataPreserved=$true
 Checks=@($checks)
 RecordedUtc=[DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($receipt,($result|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
'R303_NATIVE_'+$HostLabel+'_PROTECTED_OWNER_RETRY_PASS'
