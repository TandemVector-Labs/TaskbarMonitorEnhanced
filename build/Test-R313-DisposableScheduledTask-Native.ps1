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
 throw 'R313_DISPOSABLE_GITHUB_WINDOWS_ONLY'
}
Import-Module ScheduledTasks -ErrorAction Stop
function Hash([string]$name){
 if(-not [IO.File]::Exists($name)){return 'MISSING'}
 return (Get-FileHash -LiteralPath $name -Algorithm SHA256).Hash
}
function Absent([string]$task){
 $items=@(Get-ScheduledTask -TaskPath '\' -TaskName $task -ErrorAction SilentlyContinue | Where-Object {$null -ne $_})
 if($items.Count -ne 0){throw ('R313_EPHEMERAL_TASK_UNEXPECTEDLY_PRESENT_'+$task)}
}
function ParseDocument([string]$source){
 $settings=[Xml.XmlReaderSettings]::new()
 $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit
 $settings.XmlResolver=$null
 $settings.MaxCharactersInDocument=262144
 $sr=[IO.StringReader]::new($source)
 $reader=$null
 try{
  $reader=[Xml.XmlReader]::Create($sr,$settings)
  $doc=[Xml.XmlDocument]::new()
  $doc.XmlResolver=$null
  $doc.Load($reader)
  return $doc
 }finally{
  if($reader){$reader.Dispose()}
  $sr.Dispose()
 }
}
function Namespace([Xml.XmlDocument]$doc){
 $n=[Xml.XmlNamespaceManager]::new($doc.NameTable)
 $n.AddNamespace('t','http://schemas.microsoft.com/windows/2004/02/mit/task')
 return ,$n
}
$fixture=Join-Path $env:RUNNER_TEMP ('R313_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $fixture 'R313_TASK_REGISTRATION_RECEIPT.json'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$previous=Join-Path $env:RUNNER_TEMP ('R312_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R312_TRUSTED_TASK_XML_RECEIPT.json')
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$main=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$config=Join-Path $app 'config.json'
$state=Join-Path $app 'install_state.json'
$checks=[Collections.Generic.List[string]]::new()
if([IO.Directory]::Exists($fixture)){throw 'R313_FIXTURE_COLLISION'}
[void][IO.Directory]::CreateDirectory($fixture)
$initial=@{Main=(Hash $main);Config=(Hash $config);State=(Hash $state)}
$source=Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
$prior=Get-Content -LiteralPath $previous -Raw | ConvertFrom-Json
if($source.Commit -cne $env:GITHUB_SHA -or
   $source.SetupSHA256 -cne (Hash $setup) -or
   $source.MainSHA256 -cne $initial.Main -or
   $prior.SourceCommit -cne $env:GITHUB_SHA -or
   $prior.Host -cne $HostLabel -or
   $prior.Status -cne 'PASS_EXACT_PRODUCTION_TASK_XML_POLICY_SYNTHETIC'){
 throw 'R313_EXACT_CANDIDATE_OR_PRIOR_NATIVE_PROOF_INVALID'
}
$checks.Add('EXACT_SOURCE_AND_R312_PREDECESSOR_BOUND')
$asm=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
$resource=$asm.GetManifestResourceStream('Payload.TBME_Setup_Elevated_Helper.ps1')
if(!$resource){throw 'R313_EMBEDDED_HELPER_RESOURCE_MISSING'}
$reader=[IO.StreamReader]::new($resource)
try{$embedded=$reader.ReadToEnd()}finally{$reader.Dispose()}
$helper=(Resolve-Path (Join-Path $PSScriptRoot '..\installer\TBME_Setup_Elevated_Helper.ps1')).Path
$norm={param([string]$s) $s.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
if((& $norm $embedded) -cne (& $norm ([IO.File]::ReadAllText($helper)))){
 throw 'R313_HELPER_SOURCE_NOT_EXACT_PE'
}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($helper,[ref]$tokens,[ref]$errors)
if(@($errors).Count){throw 'R313_PE_HELPER_PS51_PARSER_BAD'}
$desired=@('Resolve-SensorPriorTaskPrincipalSid','Assert-SensorTrustedOldTaskXml')
$defs=@($ast.FindAll({param($x)
 $x -is [Management.Automation.Language.FunctionDefinitionAst] -and
 $x.Name -in $desired
},$true))
if($defs.Count -ne 2){throw 'R313_PE_TASK_XML_GUARD_NOT_FOUND'}
. ([scriptblock]::Create(($defs|ForEach-Object {$_.Extent.Text}) -join [Environment]::NewLine))
$checks.Add('ONLY_EXACT_PE_TASK_XML_GUARD_EXTRACTED')
$sid=[string]([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
if($sid -cnotmatch '^S-1-5-21-(?:\d+-){3}\d+$'){throw 'R313_HOSTED_USER_SID_NOT_INTERACTIVE'}
$taskName='TBME-R313-Disposable-'+$env:GITHUB_RUN_ID+'-'+$HostLabel
if($taskName -cnotmatch '^TBME-R313-Disposable-[0-9]{5,20}-[AB]$'){
 throw 'R313_BAD_EPHEMERAL_TASK_NAME'
}
Absent $taskName
$realOriginal=@(Get-ScheduledTask -TaskPath '\' -TaskName 'TaskbarMonitorEnhanced Sensor Broker' -ErrorAction SilentlyContinue | Where-Object {$null -ne $_})
if($realOriginal.Count -ne 0){throw 'R313_PROTECTED_SENSOR_TASK_PRESENT_ON_GUEST_REFUSE_TEST'}
$checks.Add('UNIQUE_UNUSED_EPHEMERAL_TASK_AND_NO_REAL_PROTECTED_TASK')
$brokerRoot=Join-Path $fixture 'synthetic-protected-broker'
$appRoot=Join-Path $fixture 'synthetic-user-app'
$supervisor=Join-Path $brokerRoot 'TaskbarMonitorSensorSupervisor.exe'
$broker=Join-Path $brokerRoot 'TaskbarMonitorSensorBroker.exe'
$out=Join-Path $appRoot 'cpu_temp_broker.json'
if([IO.File]::Exists($supervisor) -or [IO.File]::Exists($broker)){
 throw 'R313_SYNTHETIC_ACTION_EXECUTABLE_ACTUALLY_PRESENT'
}
$args='--broker "'+$broker+'" --output "'+$out+'"'
$sidSafe=[Security.SecurityElement]::Escape($sid)
$commandSafe=[Security.SecurityElement]::Escape($supervisor)
$argsSafe=[Security.SecurityElement]::Escape($args)
$xml=@"
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
<Triggers><LogonTrigger><Enabled>false</Enabled><UserId>$sidSafe</UserId></LogonTrigger></Triggers>
<Principals><Principal id="Author"><UserId>$sidSafe</UserId><LogonType>InteractiveToken</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
<Settings><Enabled>false</Enabled><AllowStartOnDemand>false</AllowStartOnDemand><DisallowStartIfOnBatteries>true</DisallowStartIfOnBatteries></Settings>
<Actions Context="Author"><Exec><Command>$commandSafe</Command><Arguments>$argsSafe</Arguments></Exec></Actions>
</Task>
"@
# The URI is intentionally omitted in the disposable XML. Task Scheduler
# assigns this task's unique name; the real fixed-owner XML uses a pinned URI.
if(-not (Assert-SensorTrustedOldTaskXml $xml $sid $brokerRoot $appRoot)){
 throw 'R313_SAFE_DISABLED_XML_REFUSED_BEFORE_REGISTRATION'
}
$checks.Add('PE_GUARD_ACCEPTS_DISABLED_NONEXECUTING_EPHEMERAL_XML')
$created=$false
$registeredTwice=$false
$exportHash=''
try{
 # Never -Force. Name was checked absent immediately before registration.
 Register-ScheduledTask -TaskName $taskName -TaskPath '\' -Xml $xml -ErrorAction Stop | Out-Null
 $created=$true
 $checks.Add('EPHEMERAL_TASK_REGISTERED_WITHOUT_FORCE_OR_UAC')
 $reg=Get-ScheduledTask -TaskPath '\' -TaskName $taskName -ErrorAction Stop
 if([string]$reg.TaskName -cne $taskName -or
    [bool]$reg.Settings.Enabled -ne $false -or
    [string]$reg.State -cne 'Disabled' -or
    @($reg.Actions).Count -ne 1 -or
    @($reg.Triggers).Count -ne 1 -or
    [bool]$reg.Triggers[0].Enabled -ne $false -or
    -not [string]::Equals([string]$reg.Actions[0].Execute,$supervisor,[StringComparison]::OrdinalIgnoreCase) -or
    -not [string]::Equals([string]$reg.Actions[0].Arguments,$args,[StringComparison]::OrdinalIgnoreCase)){
  throw 'R313_REGISTERED_TASK_NOT_NONEXECUTING_AND_PINNED'
 }
 $checks.Add('READBACK_DISABLING_AND_EXACT_ACTION_PINNED')
 $exported=[string](Export-ScheduledTask -TaskPath '\' -TaskName $taskName -ErrorAction Stop)
 $doc=ParseDocument $exported;$n=Namespace $doc
 $uriNode=$doc.SelectSingleNode('/t:Task/t:RegistrationInfo/t:URI',$n)
 $sidNode=$doc.SelectSingleNode('/t:Task/t:Principals/t:Principal/t:UserId',$n)
 $commandNode=$doc.SelectSingleNode('/t:Task/t:Actions/t:Exec/t:Command',$n)
 $argNode=$doc.SelectSingleNode('/t:Task/t:Actions/t:Exec/t:Arguments',$n)
 if(!$sidNode -or !$commandNode -or !$argNode -or
    (Resolve-SensorPriorTaskPrincipalSid ([string]$sidNode.InnerText)) -cne $sid -or
    -not [string]::Equals([string]$commandNode.InnerText,$supervisor,[StringComparison]::OrdinalIgnoreCase) -or
    -not [string]::Equals([string]$argNode.InnerText,$args,[StringComparison]::OrdinalIgnoreCase)){
  throw 'R313_EXPORT_XML_PRINCIPAL_ACTION_CHANGED'
 }
 if($uriNode -and [string]$uriNode.InnerText -cne ('\'+$taskName)){
  throw 'R313_DISPOSABLE_TASK_URI_NOT_SCOPED'
 }
 $exportHash=[BitConverter]::ToString(([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($exported)))).Replace('-','')
 $checks.Add('EXPORT_XML_EXACT_TASK_NAME_SID_ACTION_VERIFIED')
 Unregister-ScheduledTask -TaskName $taskName -TaskPath '\' -Confirm:$false -ErrorAction Stop
 $created=$false
 Absent $taskName
 $checks.Add('FIRST_EPHEMERAL_TASK_REMOVED_AND_ABSENCE_RECHECKED')
 # A cold task-restore roundtrip of the same validated XML, still disabled.
 Register-ScheduledTask -TaskName $taskName -TaskPath '\' -Xml $xml -ErrorAction Stop|Out-Null
 $created=$true
 $registeredTwice=$true
 $t=Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
 if($t.State -ne 'Disabled' -or [bool]$t.Settings.Enabled -ne $false){
  throw 'R313_SECOND_REGISTER_NOT_DISABLED'
 }
 $checks.Add('SECOND_SAME_USER_REGISTRATION_DISABLED')
}finally{
 if($created){
  Unregister-ScheduledTask -TaskName $taskName -TaskPath '\' -Confirm:$false -ErrorAction Stop
 }
}
Absent $taskName
$checks.Add('SECOND_DISPOSABLE_TASK_FULL_CLEANUP_VERIFIED')
if(@(Get-ScheduledTask -TaskPath '\' -TaskName 'TaskbarMonitorEnhanced Sensor Broker' -ErrorAction SilentlyContinue | Where-Object {$null -ne $_}).Count -ne 0){
 throw 'R313_UNEXPECTED_ACTUAL_PROTECTED_TASK_CREATED'
}
$checks.Add('ACTUAL_PROTECTED_SENSOR_TASK_NEVER_PRESENT')
if([IO.File]::Exists($supervisor) -or
   (Hash $main) -cne $initial.Main -or
   (Hash $config) -cne $initial.Config -or
   (Hash $state) -cne $initial.State){
 throw 'R313_GUEST_USER_PROGRAM_FILES_OR_FAKE_EXEC_CHANGED'
}
$checks.Add('INSTALLED_USER_DATA_AND_ACTION_TARGET_UNCHANGED')
$result=[ordered]@{
 Schema=1;Revision='R313'
 Status='PASS_EPHEMERAL_DISABLED_SCHEDULED_TASK_REGISTER_EXPORT_UNREGISTER'
 Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
 OriginalOwnerComputerTouched=$false;ActualProtectedSensorTaskTouched=$false
 RealProgramFilesWritten=$false;ActualUACPerformed=$false
 RegisteredOnlyUniqueDisposableTask=$true
 NeverEnabledOrExecuted=$true;NoForceRegistration=$true
 ColdRegistrationPerformedOnDisposableTask=$registeredTwice
 ExactPrincipalAndCommandReadback=$true
 DisposableTaskAbsentAfterTest=$true;UserFilesUnchanged=$true
 ProductionPriorTaskColdRestoreIntegrated=$false
 ExportXmlSHA256=$exportHash
 Checks=@($checks)
 RecordedUtc=[DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($receipt,($result|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
'R313_'+$HostLabel+'_SCHEDULER_EPHEMERAL_DISABLED_XML_ROUNDTRIP_PASS'
