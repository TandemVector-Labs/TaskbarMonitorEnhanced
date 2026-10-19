[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SetupPath,[Parameter(Mandatory=$true)][string]$OutDir)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -eq 'Core'){throw 'R256_FRAMEWORK_REFLECTION_REQUIRED'}
if(Test-Path $OutDir){throw 'R256_CONTRACT_OUTPUT_EXISTS'}
$full=[IO.Path]::GetFullPath($SetupPath)
if([IO.Path]::GetFileName($full) -cne 'TaskbarMonitorEnhanced_Setup_1.7.4.exe'){throw 'R256_WRONG_SETUP_NAME'}
$a=[Reflection.Assembly]::LoadFile($full)
$t=$a.GetType('SetupProgram',$true)
$f=[Reflection.BindingFlags]'Static,Public,NonPublic'
$newState=$t.GetMethod('NewInstallState',$f)
$legacy=$t.GetMethod('LegacyExpected',$f)
$optional=$t.GetMethod('IsOptionalStableLegacyRoot',$f)
if($t.GetField('Version',$f).GetRawConstantValue() -cne '1.7.4'){throw 'R256_COMPILED_VERSION_NOT_172'}
$cases=0;$negative=0
foreach($v in @('1.6.0','1.7.0','1.7.1','1.7.2','1.7.3')){
 $before='{ "ProductIdentity":"LOCKED", "Version":"'+$v+'", "PublicVersion":"'+$v+'", "Unrelated":"preserve literal 1.7.1", "Custom":{"x":17}, "ProtocolVersion":"1.1.2+r21" }'
 $want=$before.Replace(('"Version":"'+$v+'"'),'"Version":"1.7.4"').Replace(('"PublicVersion":"'+$v+'"'),'"PublicVersion":"1.7.4"')
 $got=[string]$newState.Invoke($null,[object[]]@($before))
 if($got -cne $want){throw ('R256_STATE_NOT_EXACTLY_TWO_VERSION_FIELDS '+$v)}
 $cases++
}
$bad=@(
 '{"Version":"1.7.1","PublicVersion":"1.7.0"}',
 '{"Version":"1.7.1","Version":"1.7.1","PublicVersion":"1.7.1"}',
 '{"Version":"1.7.1","PublicVersion":"1.7.1","PublicVersion":"1.7.1"}',
 '{"Version":"0.9.0","PublicVersion":"0.9.0"}',
 '{"Version":"1.7.5","PublicVersion":"1.7.5"}',
 '{"Version":"1.7.1"}',
 '{"PublicVersion":"1.7.1"}'
)
foreach($s in $bad){
 $refused=$false
 try{[void]$newState.Invoke($null,[object[]]@($s))}catch{$refused=$true}
 if(!$refused){throw ('R256_INVALID_STATE_ACCEPTED '+$s)};$negative++
}
$inventory=Get-Content (Join-Path $PSScriptRoot 'official-v173-managed.json') -Raw|ConvertFrom-Json
$dict=$legacy.Invoke($null,[object[]]@('1.7.3','OFFICIAL_STABLE_V173'))
if($dict.Count -ne 23 -or $inventory.ManagedCount -ne 23){throw 'R256_171_EXACT_MANAGED_COUNT'}
foreach($row in $inventory.Rows){if(!$dict.ContainsKey($row.Path) -or $dict[$row.Path] -cne $row.SHA256){throw ('R256_COMPILED_MANAGED_SHA_DRIFT '+$row.Path)};$cases++}
foreach($pair in @(@('1.7.1','OFFICIAL_STABLE_V170'),@('1.7.1','PREVIEW1'),@('1.7.4','OFFICIAL_STABLE_V171'),@('1.7.1','UNKNOWN'))){
 $refused=$false;try{[void]$legacy.Invoke($null,[object[]]@($pair[0],$pair[1]))}catch{$refused=$true}
 if(!$refused){throw 'R256_WRONG_ANCESTOR_CHANNEL_ACCEPTED'};$negative++
}
foreach($channel in @('OFFICIAL_STABLE_V170','OFFICIAL_STABLE_V171','OFFICIAL_STABLE_V172','OFFICIAL_STABLE_V173')){
 if(!$optional.Invoke($null,[object[]]@('TaskbarMonitorEnhanced.cs',$channel))){throw 'R256_INHERITED_ROOT_DUPLICATE_REQUIRED'};$cases++
 foreach($path in @('Source/TaskbarMonitorEnhanced.cs','TaskbarMonitorEnhanced.exe','config.json')){
  if($optional.Invoke($null,[object[]]@($path,$channel))){throw ('R256_CRITICAL_SOURCE_MADE_OPTIONAL '+$path)};$negative++
 }
}
$targets=$t.GetField('UpgradeTargets',$f).GetValue($null)
$removed=0;$names=@();$if=[Reflection.BindingFlags]'Instance,NonPublic,Public'
foreach($target in $targets){
 $path=[string]$target.GetType().GetField('Rel',$if).GetValue($target)
 $resource=$target.GetType().GetField('ResourceName',$if).GetValue($target)
 if($names -ccontains $path -or $path -match '^(config\.json|SensorBackend/|Backups/|Data/)'){throw ('R256_UPGRADE_TOUCHES_PROTECTED_OR_DUPLICATE '+$path)}
 if($null -eq $resource){$removed++};$names+=@($path);$cases++
}
if($removed -ne 6 -or $names -cnotcontains 'Docs/RELEASE_NOTES_v1.7.4.md' -or $names -cnotcontains 'Docs/RELEASE_NOTES_v1.7.1.md'){throw 'R256_VERSIONED_NOTES_TRANSACTION_MAP'}
New-Item -ItemType Directory -Path $OutDir|Out-Null
$r=[ordered]@{Revision='R256';Status='PASS_COMPILED_174_UPGRADE_CONTRACT';SetupSHA256=(Get-FileHash $full -Algorithm SHA256).Hash;PositiveCases=$cases;RejectedCases=$negative;Official173ManagedFiles=23;PreviousVersions=@('1.6.0','1.7.0','1.7.1','1.7.2','1.7.3');CurrentVersion='1.7.4';NoAppEntryPointInvoked=$true;NoPersonalFilesOrRegistryMutated=$true;ActualInstallAcceptance='SEPARATE_HOSTED_VM_GATE'}
[IO.File]::WriteAllText((Join-Path $OutDir 'R256_CONTRACT.json'),($r|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
Write-Output ($r|ConvertTo-Json -Depth 6 -Compress)
