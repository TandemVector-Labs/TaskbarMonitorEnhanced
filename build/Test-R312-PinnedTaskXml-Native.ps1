[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
 [Parameter(Mandatory=$true)][string]$CandidateDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID) -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'R312_DISPOSABLE_WINDOWS_GUEST_ONLY'
}
function Hash([string]$path){
 if(-not [IO.File]::Exists($path)){return 'MISSING'}
 return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
function AssertRefused([string]$name,[string]$document,[string]$expected){
 $failed=$false
 try{[void](Assert-SensorTrustedOldTaskXml $document $sid $brokerRoot $appRoot)}
 catch{if($_.Exception.ToString() -match $expected){$failed=$true}else{throw}}
 if(-not $failed){throw ('R312_UNSAFE_TASK_XML_ACCEPTED_'+$name)}
 $script:checks.Add($name)
}
function ParseDoc(){
 $document=[Xml.XmlDocument]::new();$document.XmlResolver=$null
 $document.LoadXml($validXML)
 return $document
}
function Ns([Xml.XmlDocument]$doc){
 $ns=[Xml.XmlNamespaceManager]::new($doc.NameTable)
 $ns.AddNamespace('t','http://schemas.microsoft.com/windows/2004/02/mit/task')
 return ,$ns
}
$root=Join-Path $env:RUNNER_TEMP ('R312_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $root 'R312_TRUSTED_TASK_XML_RECEIPT.json'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$prior=Join-Path $env:RUNNER_TEMP ('R311_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R311_HEALTHY_TERMINAL_HOOK_RECEIPT.json')
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$main=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$config=Join-Path $app 'config.json'
$state=Join-Path $app 'install_state.json'
$checks=[Collections.Generic.List[string]]::new()
if([IO.Directory]::Exists($root)){throw 'R312_DUPLICATE_TEST_ROOT'}
[void][IO.Directory]::CreateDirectory($root)
$before=@{Main=(Hash $main);Config=(Hash $config);State=(Hash $state)}
$c=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
$p=Get-Content -LiteralPath $prior -Raw|ConvertFrom-Json
if($c.Commit -cne $env:GITHUB_SHA -or $c.SetupSHA256 -cne (Hash $setup) -or
   $c.MainSHA256 -cne $before.Main -or
   $p.SourceCommit -cne $env:GITHUB_SHA -or $p.Host -cne $HostLabel -or
   $p.Status -cne 'PASS_SYNTHETIC_NORMAL_HEALTHY_TERMINAL_HOOKS'){
 throw 'R312_EXACT_PRIVATE_CANDIDATE_OR_PREDECESSOR_NOT_VERIFIED'
}
$assembly=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
$res=$assembly.GetManifestResourceStream('Payload.TBME_Setup_Elevated_Helper.ps1')
if(!$res){throw 'R312_NO_EMBEDDED_PE_HELPER'}
$reader=[IO.StreamReader]::new($res)
try{$embedded=[string]$reader.ReadToEnd()}finally{$reader.Dispose()}
$helper=(Resolve-Path (Join-Path $PSScriptRoot '..\installer\TBME_Setup_Elevated_Helper.ps1')).Path
$normalize={param([string]$s) $s.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
if((& $normalize $embedded) -cne (& $normalize ([IO.File]::ReadAllText($helper)))){
 throw 'R312_PE_HELPER_SOURCE_UNPINNED'
}
$checks.Add('EXACT_PE_SOURCE_WITH_NO_UNTRUSTED_SCRIPT_FILE')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($helper,[ref]$tokens,[ref]$errors)
if(@($errors).Count){throw 'R312_POWERSHELL51_SOURCE_PARSER_FAILED'}
$wanted=@('Resolve-SensorPriorTaskPrincipalSid','Assert-SensorTrustedOldTaskXml')
$defs=@($ast.FindAll({param($n)
 $n -is [Management.Automation.Language.FunctionDefinitionAst] -and
 $n.Name -in $wanted
},$true))
if($defs.Count -ne 2){throw 'R312_EXACT_PRODUCTION_XML_GUARDS_MISSING'}
. ([scriptblock]::Create(($defs|ForEach-Object {$_.Extent.Text}) -join [Environment]::NewLine))
$checks.Add('TWO_PURE_PRODUCTION_PE_XML_FUNCTIONS_LOADED')
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($sid -cnotmatch '^S-1-5-21-(?:\d+-){3}\d+$'){
 throw 'R312_DISPOSABLE_RUNNER_NOT_INTERACTIVE_SID'
}
$brokerRoot=Join-Path $root 'ProtectedBroker'
$appRoot=Join-Path $root 'AppRoot'
$supervisor=Join-Path $brokerRoot 'TaskbarMonitorSensorSupervisor.exe'
$broker=Join-Path $brokerRoot 'TaskbarMonitorSensorBroker.exe'
$out=Join-Path $appRoot 'cpu_temp_broker.json'
$args='--broker "'+$broker+'" --output "'+$out+'"'
$uri='\TaskbarMonitorEnhanced Sensor Broker'
$escSid=[Security.SecurityElement]::Escape([string]$sid)
$escExe=[Security.SecurityElement]::Escape($supervisor)
$escArgs=[Security.SecurityElement]::Escape($args)
$validXML=@"
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><URI>$uri</URI></RegistrationInfo>
  <Triggers><LogonTrigger><Enabled>true</Enabled><UserId>$escSid</UserId></LogonTrigger></Triggers>
  <Principals><Principal id="Author"><UserId>$escSid</UserId><LogonType>InteractiveToken</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings><Enabled>true</Enabled><AllowStartOnDemand>true</AllowStartOnDemand></Settings>
  <Actions Context="Author"><Exec><Command>$escExe</Command><Arguments>$escArgs</Arguments></Exec></Actions>
</Task>
"@
if(-not (Assert-SensorTrustedOldTaskXml $validXML $sid $brokerRoot $appRoot)){
 throw 'R312_VALID_OWNED_SYNTHETIC_XML_REFUSED'
}
$checks.Add('SYNTHETIC_PRIOR_TASK_EXACT_SID_ACTION_TRIGGER_ACCEPTED')
$d=ParseDoc;$n=Ns $d
$d.SelectSingleNode('/t:Task/t:Actions/t:Exec/t:Command',$n).InnerText='C:\Windows\System32\cmd.exe'
AssertRefused 'ALTERED_EXECUTABLE_REFUSED' $d.OuterXml 'SENSOR_JOURNAL_TASK_XML_EXEC_NOT_PINNED'
$d=ParseDoc;$n=Ns $d
$d.SelectSingleNode('/t:Task/t:Actions/t:Exec/t:Arguments',$n).InnerText+=' & altered'
AssertRefused 'ARGUMENT_INJECTION_REFUSED' $d.OuterXml 'SENSOR_JOURNAL_TASK_XML_EXEC_NOT_PINNED'
$d=ParseDoc;$n=Ns $d
$d.SelectSingleNode('/t:Task/t:Principals/t:Principal/t:UserId',$n).InnerText='S-1-5-21-111-222-333-444'
AssertRefused 'FOREIGN_PRINCIPAL_REFUSED' $d.OuterXml 'SENSOR_JOURNAL_TASK_XML_FOREIGN_PRINCIPAL_OR_PRIVILEGES'
$d=ParseDoc;$n=Ns $d
$d.SelectSingleNode('/t:Task/t:Triggers/t:LogonTrigger/t:UserId',$n).InnerText='S-1-5-21-111-222-333-444'
AssertRefused 'FOREIGN_LOGON_TRIGGER_REFUSED' $d.OuterXml 'SENSOR_JOURNAL_TASK_XML_WRONG_LOGON_USER'
$d=ParseDoc;$n=Ns $d
$d.SelectSingleNode('/t:Task/t:Principals/t:Principal/t:RunLevel',$n).InnerText='LeastPrivilege'
AssertRefused 'CHANGED_PRIVILEGE_LEVEL_REFUSED' $d.OuterXml 'SENSOR_JOURNAL_TASK_XML_FOREIGN_PRINCIPAL_OR_PRIVILEGES'
$d=ParseDoc;$n=Ns $d
$d.SelectSingleNode('/t:Task/t:Principals/t:Principal/t:LogonType',$n).InnerText='Password'
AssertRefused 'DIFFERENT_LOGON_TYPE_REFUSED' $d.OuterXml 'SENSOR_JOURNAL_TASK_XML_FOREIGN_PRINCIPAL_OR_PRIVILEGES'
$d=ParseDoc;$n=Ns $d
$exec=$d.SelectSingleNode('/t:Task/t:Actions/t:Exec',$n)
$working=$d.CreateElement('WorkingDirectory','http://schemas.microsoft.com/windows/2004/02/mit/task')
$working.InnerText='C:\Windows\Temp'
[void]$exec.AppendChild($working)
AssertRefused 'UNPINNED_WORKDIR_REFUSED' $d.OuterXml 'SENSOR_JOURNAL_TASK_XML_EXEC_SHAPE_UNEXPECTED'
$d=ParseDoc;$n=Ns $d
$trig=$d.SelectSingleNode('/t:Task/t:Triggers/t:LogonTrigger',$n)
$newTrig=$d.CreateElement('RegistrationTrigger','http://schemas.microsoft.com/windows/2004/02/mit/task')
[void]$trig.ParentNode.ReplaceChild($newTrig,$trig)
AssertRefused 'REGISTRATION_TRIGGER_REFUSED' $d.OuterXml 'SENSOR_JOURNAL_TASK_XML_UNEXPECTED_ACTION_OR_TRIGGER'
$d=ParseDoc;$n=Ns $d
$actions=$d.SelectSingleNode('/t:Task/t:Actions',$n)
$com=$d.CreateElement('ComHandler','http://schemas.microsoft.com/windows/2004/02/mit/task')
[void]$actions.AppendChild($com)
AssertRefused 'SECOND_ACTION_COM_HANDLER_REFUSED' $d.OuterXml 'SENSOR_JOURNAL_TASK_XML_UNEXPECTED_ACTION_OR_TRIGGER'
$d=ParseDoc;$n=Ns $d
$info=$d.SelectSingleNode('/t:Task/t:RegistrationInfo',$n)
$sd=$d.CreateElement('SecurityDescriptor','http://schemas.microsoft.com/windows/2004/02/mit/task')
$sd.InnerText='D:(A;;GA;;;WD)'
[void]$info.AppendChild($sd)
AssertRefused 'SECURITY_DESCRIPTOR_ESCALATION_REFUSED' $d.OuterXml 'SENSOR_JOURNAL_TASK_XML_EMBEDDED_SECURITY_DESCRIPTOR_REFUSED'
$d=ParseDoc;$n=Ns $d
$d.SelectSingleNode('/t:Task/t:RegistrationInfo/t:URI',$n).InnerText='\Another Task'
AssertRefused 'TASK_URI_IMPERSONATION_REFUSED' $d.OuterXml 'SENSOR_JOURNAL_TASK_XML_URI_UNPINNED'
$d=ParseDoc;$n=Ns $d
$principal=$d.SelectSingleNode('/t:Task/t:Principals/t:Principal',$n)
$group=$d.CreateElement('GroupId','http://schemas.microsoft.com/windows/2004/02/mit/task')
$group.InnerText='BUILTIN\Administrators'
[void]$principal.AppendChild($group)
AssertRefused 'GROUP_PRINCIPAL_INJECTION_REFUSED' $d.OuterXml 'SENSOR_JOURNAL_TASK_XML_GROUP_PRINCIPAL_FORBIDDEN'
AssertRefused 'XML_DTD_ENTITY_PROHIBITED' ('<!DOCTYPE Task [<!ENTITY attack "X">]>'+$validXML) 'DTD|DOCTYPE|XmlException'
AssertRefused 'MISSING_TASK_XML_REFUSED' '' 'SENSOR_JOURNAL_TASK_XML_MISSING_OR_OVERSIZE'
if((Hash $main) -cne $before.Main -or (Hash $config) -cne $before.Config -or
   (Hash $state) -cne $before.State){
 throw 'R312_NO_REAL_TASK_TEST_MUTATED_INSTALLED_OWNER'
}
$checks.Add('INSTALLED_MAIN_AND_SETTINGS_UNCHANGED')
$record=[ordered]@{
 Schema=1;Revision='R312'
 Status='PASS_EXACT_PRODUCTION_TASK_XML_POLICY_SYNTHETIC'
 Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
 OriginalOwnerComputerTouched=$false;ActualProgramFilesWritten=$false
 ActualUACInvoked=$false;ActualScheduledTaskModified=$false
 ExactPEPolicyFunctionsLoaded=$true;LegitimateTaskXmlAccepted=$true
 CommandPrincipalTriggerAndXmlInjectionRejected=$true
 InstalledOwnerDataUnchanged=$true
 ProductionColdTaskRegistrationIntegrated=$false
 Checks=@($checks);RecordedUtc=[DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($receipt,($record|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
'R312_NATIVE_'+$HostLabel+'_PINNED_TASK_XML_PURE_POLICY_PASS'
