[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$PublishedSetup)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# READ-ONLY: inspect exact original published Setup resource bytes and
# candidate private upgrade identity methods. Never invoke UpgradeExisting.
if($PSVersionTable.PSEdition -cne 'Desktop' -or [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
 throw 'R299_REQUIRES_WINDOWS_POWERSHELL_51'
}
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$candidate=Join-Path $root 'build/_out/Setup/TaskbarMonitorEnhanced_Setup_1.7.10.exe'
if(!(Test-Path -LiteralPath $candidate)){throw 'R299_CANDIDATE_NOT_BUILT'}
if(!(Test-Path -LiteralPath $PublishedSetup)){throw 'R299_PUBLIC_PREDECESSOR_ABSENT'}
$publ=[IO.Path]::GetFullPath($PublishedSetup)
if([IO.File]::GetAttributes($publ) -band [IO.FileAttributes]::ReparsePoint){throw 'R299_UNTRUSTED_PUBLIC_REPARSE'}
$official='3AE5E2AC7428C3443FF7768C543117AF864E7C73F68D32EFAD4AB40B30FB5B0E'
if((Get-Item -LiteralPath $publ).Length -ne 8577536 -or
   (Get-FileHash -LiteralPath $publ -Algorithm SHA256).Hash -cne $official){
 throw 'R299_IMMUTABLE_PUBLIC_V179_SETUP_IDENTITY_MISMATCH'
}
$old=[Reflection.Assembly]::LoadFrom($publ)
$new=[Reflection.Assembly]::LoadFrom((Resolve-Path $candidate).Path)
if($old.GetName().Version.ToString() -cne '1.7.9.0' -or
   $new.GetName().Version.ToString() -cne '1.7.10.0'){
 throw 'R299_RELEASE_OR_CANDIDATE_ASSEMBLY_VERSION_MISMATCH'
}
$type=$new.GetType('SetupProgram',$true)
$flags=[Reflection.BindingFlags]'Static,NonPublic'
$method=$type.GetMethod('LegacyExpected',$flags)
$stateFactory=$type.GetMethod('NewInstallState',$flags)
if(!$method -or !$stateFactory){throw 'R299_UPGRADE_IDENTITY_FACTORIES_MISSING'}
$params=[object[]]::new(2);$params[0]=[string]'1.7.9';$params[1]=[string]'OFFICIAL_STABLE_V179'
$expected=[Collections.IDictionary]$method.Invoke($null,$params)
if($expected.Count -ne 22 -or
   [string]$expected['Uninstall.exe'] -cne $official -or
   [string]$expected['TaskbarMonitorEnhanced.exe'] -cne '04776E870A492733BBA33A550F732F5DB688A6585FC6533224A56687F1A6D88E'){
 throw 'R299_CANDIDATE_PUBLIC_MANAGED_PIN_COUNT_OR_IDENTITY'
}
$resources=@(
 @('TaskbarMonitorEnhanced.exe','Payload.TaskbarMonitorEnhanced.exe'),
 @('TaskbarMonitorEnhanced.exe.config','Payload.TaskbarMonitorEnhanced.exe.config'),
 @('TaskbarMonitorEnhanced.ico','Payload.TaskbarMonitorEnhanced.ico'),
 @('Source/TaskbarMonitorEnhanced.cs','Payload.TaskbarMonitorEnhanced.cs'),
 @('Source/StudioThemes.cs','Payload.StudioThemes.cs'),
 @('Source/WallpaperStudio.cs','Payload.WallpaperStudio.cs'),
 @('Source/TaskbarGlass.cs','Payload.TaskbarGlass.cs'),
 @('Source/WorkspaceModels.cs','Payload.WorkspaceModels.cs'),
 @('Source/MonitorWorkspace.cs','Payload.MonitorWorkspace.cs'),
 @('Source/WorkspaceSelfTest.cs','Payload.WorkspaceSelfTest.cs'),
 @('Source/TaskbarMonitorSensorBroker.cs','Payload.TaskbarMonitorSensorBroker.cs'),
 @('Source/TaskbarMonitorSensorSupervisor.cs','Payload.TaskbarMonitorSensorSupervisor.cs'),
 @('Source/TaskbarMonitorEnhanced_Setup.cs','Payload.TaskbarMonitorEnhanced_Setup.cs'),
 @('Docs/LICENSE','Payload.LICENSE'),
 @('Docs/README.md','Payload.README.md'),
 @('Docs/AUTHORS.md','Payload.AUTHORS.md'),
 @('Docs/COPYRIGHT_AND_ATTRIBUTION.md','Payload.COPYRIGHT_AND_ATTRIBUTION.md'),
 @('Docs/AI_ASSISTED_DEVELOPMENT.md','Payload.AI_ASSISTED_DEVELOPMENT.md'),
 @('Docs/THIRD_PARTY_NOTICES.md','Payload.THIRD_PARTY_NOTICES.md'),
 @('Docs/RELEASE_NOTES_v1.7.9.md','Payload.RELEASE_NOTES_v1.7.9.md'),
 @('Docs/UPSTREAM_REFERENCE_GPL_NOTICE.md','Payload.UPSTREAM_REFERENCE_GPL_NOTICE.md')
)
if($resources.Count -ne 21){throw 'R299_EXPECTED_EMBEDDED_RESOURCE_COUNT_CHANGED'}
foreach($row in $resources){
 $rel=[string]$row[0];$res=[string]$row[1]
 if(!$expected.ContainsKey($rel)){throw ('R299_MISSING_PREDECESSOR_PIN_'+$rel)}
 $stream=$old.GetManifestResourceStream($res)
 if(!$stream){throw ('R299_PUBLISHED_RESOURCE_NOT_EMBEDDED_'+$res)}
 try{
  $sha=[Security.Cryptography.SHA256]::Create()
  try{$digest=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','')}
  finally{$sha.Dispose()}
 }finally{$stream.Dispose()}
 if($digest -cne [string]$expected[$rel]){throw ('R299_PIN_DIFFERENT_FROM_IMMUTABLE_PUBLISHED_RESOURCE_'+$rel)}
}
# In-memory only: previous state version is rewritten with all non-version
# fields untouched. A mismatched or foreign version is refused.
$oldState='{"Version":"1.7.9","PublicVersion":"1.7.9","ProductIdentity":"LOCKED","OwnerCanary":"stay-exact"}'
$p=[object[]]::new(1);$p[0]=[string]$oldState
$next=[string]$stateFactory.Invoke($null,$p)
if($next -cne '{"Version":"1.7.10","PublicVersion":"1.7.10","ProductIdentity":"LOCKED","OwnerCanary":"stay-exact"}'){
 throw 'R299_IN_MEMORY_PRESERVE_UNRELATED_INSTALL_STATE_FAIL'
}
$rejected=0
foreach($bad in @(
 @('1.7.9','OFFICIAL_STABLE_V178'),
 @('1.7.10','OFFICIAL_STABLE_V179'),
 @('1.9.0','OFFICIAL_STABLE_V179')
)){
 $x=[object[]]::new(2);$x[0]=[string]$bad[0];$x[1]=[string]$bad[1]
 try{$null=$method.Invoke($null,$x)}
 catch{$rejected++;continue}
 throw 'R299_UNKNOWN_PREDECESSOR_IDENTITY_ACCEPTED'
}
foreach($badState in @(
 '{"Version":"1.7.9","PublicVersion":"1.7.8"}',
 '{"Version":"1.8.0","PublicVersion":"1.8.0"}'
)){
 $x=[object[]]::new(1);$x[0]=[string]$badState
 try{$null=$stateFactory.Invoke($null,$x)}
 catch{$rejected++;continue}
 throw 'R299_INVALID_PRIOR_INSTALL_STATE_ACCEPTED'
}
if($rejected -ne 5){throw 'R299_NEGATIVE_GATES_NOT_EXERCISED'}
'R299_PUBLIC_OFFICIAL_179_SETUP_SHA=PASS'
'R299_CANDIDATE_1710_VERSION_AND_IDENTITY=PASS'
'R299_IMMUTABLE_PUBLIC_RESOURCE_MATCH=PASS_21_OF_21'
'R299_PREDECESSOR_MANAGED_FILE_PINS=PASS_22_OF_22'
'R299_IN_MEMORY_UPDATE_PRESERVES_UNRELATED_FIELDS=PASS'
'R299_FOREIGN_OR_MISMATCHED_PREDECESSOR_REJECTED=PASS_5_OF_5'
