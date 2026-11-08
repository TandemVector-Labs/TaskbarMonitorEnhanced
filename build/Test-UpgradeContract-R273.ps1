[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SetupPath,[Parameter(Mandatory=$true)][string]$OutDir)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -eq 'Core'){throw 'R273_FRAMEWORK_REFLECTION_REQUIRED'}
if(Test-Path $OutDir){throw 'R273_CONTRACT_OUTPUT_EXISTS'}
$full=[IO.Path]::GetFullPath($SetupPath)
if([IO.Path]::GetFileName($full) -cne 'TaskbarMonitorEnhanced_Setup_1.7.6.exe'){throw 'R273_WRONG_SETUP_NAME'}
$a=[Reflection.Assembly]::LoadFile($full)
$t=$a.GetType('SetupProgram',$true)
$f=[Reflection.BindingFlags]'Static,Public,NonPublic'
$newState=$t.GetMethod('NewInstallState',$f)
$legacy=$t.GetMethod('LegacyExpected',$f)
$optional=$t.GetMethod('IsOptionalStableLegacyRoot',$f)
# Regression for the R274 real two-VM failure: the pre-mutation 1.7.5
# allowlist is not sufficient unless COMMITTING rollback also accepts 1.7.5.
if($null -eq $t.GetMethod('RestoreInterruptedUpgrade',$f)){throw 'R274_ROLLBACK_METHOD_ABSENT'}
$setupSource=Get-Content (Join-Path $PSScriptRoot '..\installer\TaskbarMonitorEnhanced_Setup.cs') -Raw
$restoreBlock=[regex]::Match($setupSource,'(?s)static void RestoreInterruptedUpgrade\(List<StageEntry> rows\)(.*?)// This works after')
if(!$restoreBlock.Success -or $restoreBlock.Groups[1].Value -notmatch 'priorVersion!=InstalledV175'){
 throw 'R274_COMMITTING_ROLLBACK_REJECTS_REAL_OFFICIAL_175'
}
if($t.GetField('Version',$f).GetRawConstantValue() -cne '1.7.6'){throw 'R273_COMPILED_VERSION_NOT_172'}
$cases=0;$negative=0
foreach($v in @('1.6.0','1.7.0','1.7.1','1.7.2','1.7.3','1.7.4','1.7.5')){
 $before='{ "ProductIdentity":"LOCKED", "Version":"'+$v+'", "PublicVersion":"'+$v+'", "Unrelated":"preserve literal 1.7.1", "Custom":{"x":17}, "ProtocolVersion":"1.1.2+r21" }'
 $want=$before.Replace(('"Version":"'+$v+'"'),'"Version":"1.7.6"').Replace(('"PublicVersion":"'+$v+'"'),'"PublicVersion":"1.7.6"')
 $got=[string]$newState.Invoke($null,[object[]]@($before))
 if($got -cne $want){throw ('R273_STATE_NOT_EXACTLY_TWO_VERSION_FIELDS '+$v)}
 $cases++
}
$bad=@(
 '{"Version":"1.7.1","PublicVersion":"1.7.0"}',
 '{"Version":"1.7.1","Version":"1.7.1","PublicVersion":"1.7.1"}',
 '{"Version":"1.7.1","PublicVersion":"1.7.1","PublicVersion":"1.7.1"}',
 '{"Version":"0.9.0","PublicVersion":"0.9.0"}',
 '{"Version":"1.7.7","PublicVersion":"1.7.7"}',
 '{"Version":"1.7.1"}',
 '{"PublicVersion":"1.7.1"}'
)
foreach($s in $bad){
 $refused=$false
 try{[void]$newState.Invoke($null,[object[]]@($s))}catch{$refused=$true}
 if(!$refused){throw ('R273_INVALID_STATE_ACCEPTED '+$s)};$negative++
}
$inventory=Get-Content (Join-Path $PSScriptRoot 'official-v174-managed.json') -Raw|ConvertFrom-Json
$dict=$legacy.Invoke($null,[object[]]@('1.7.4','OFFICIAL_STABLE_V174'))
if($dict.Count -ne 22 -or $inventory.ManagedCount -ne 22){throw 'R273_OFFICIAL_174_EXACT_22_MANAGED_COUNT'}
foreach($row in $inventory.Rows){if(!$dict.ContainsKey($row.Path) -or $dict[$row.Path] -cne $row.SHA256){throw ('R273_OFFICIAL_V174_COMPILED_MANAGED_SHA_DRIFT '+$row.Path)};$cases++}
$official175=Get-Content (Join-Path $PSScriptRoot 'official-v175-managed.json') -Raw|ConvertFrom-Json
$dict175=$legacy.Invoke($null,[object[]]@('1.7.5','OFFICIAL_STABLE_V175'))
if($dict175.Count -ne 22 -or $official175.ManagedCount -ne 22){throw 'R273_OFFICIAL_175_22_MANAGED_COUNT'}
foreach($row in $official175.Rows){
 if(!$dict175.ContainsKey($row.Path) -or $dict175[$row.Path] -cne $row.SHA256){throw ('R273_OFFICIAL175_COMPILED_SHA_DRIFT '+$row.Path)}
 $cases++
}
if([string]$official175.PublishedMainSHA256 -cne '25E0565301963467BF290908BE965F73EDDE6BF41EC693A4FE45ED19653FBDB6' -or
   [string]$official175.PublishedSetupSHA256 -cne '8E37397F02273952B5866003FC156E152B13FC90D95D80B5DB4208046DD588EC'){throw 'R273_OFFICIAL_175_PUBLIC_MAIN_SETUP_IDENTITY'}
# Retain exact previously accepted immutable v1.7.3 path as a separate ancestor.
$oldInventory=Get-Content (Join-Path $PSScriptRoot 'official-v173-managed.json') -Raw|ConvertFrom-Json
$oldDictionary=$legacy.Invoke($null,[object[]]@('1.7.3','OFFICIAL_STABLE_V173'))
if($oldInventory.ManagedCount -ne 23 -or $oldDictionary.Count -ne 23){throw 'R273_HISTORICAL_V173_23_ROWS_DRIFT'}
foreach($row in $oldInventory.Rows){if(!$oldDictionary.ContainsKey($row.Path) -or $oldDictionary[$row.Path] -cne $row.SHA256){throw ('R273_V173_HISTORIC_DRIFT '+$row.Path)};$cases++}
foreach($pair in @(@('1.7.1','OFFICIAL_STABLE_V170'),@('1.7.1','PREVIEW1'),@('1.7.6','OFFICIAL_STABLE_V171'),@('1.7.1','UNKNOWN'))){
 $refused=$false;try{[void]$legacy.Invoke($null,[object[]]@($pair[0],$pair[1]))}catch{$refused=$true}
 if(!$refused){throw 'R273_WRONG_ANCESTOR_CHANNEL_ACCEPTED'};$negative++
}
foreach($channel in @('OFFICIAL_STABLE_V170','OFFICIAL_STABLE_V171','OFFICIAL_STABLE_V172','OFFICIAL_STABLE_V173')){
 if(!$optional.Invoke($null,[object[]]@('TaskbarMonitorEnhanced.cs',$channel))){throw 'R273_INHERITED_ROOT_DUPLICATE_REQUIRED'};$cases++
 foreach($path in @('Source/TaskbarMonitorEnhanced.cs','TaskbarMonitorEnhanced.exe','config.json')){
  if($optional.Invoke($null,[object[]]@($path,$channel))){throw ('R273_CRITICAL_SOURCE_MADE_OPTIONAL '+$path)};$negative++
 }
}
if($optional.Invoke($null,[object[]]@('TaskbarMonitorEnhanced.cs','OFFICIAL_STABLE_V174'))){
 throw 'R273_OFFICIAL_V174_MUST_NOT_HAVE_OPTIONAL_ROOT_SOURCE'
}
$cases++
$targets=$t.GetField('UpgradeTargets',$f).GetValue($null)
$removed=0;$names=@();$if=[Reflection.BindingFlags]'Instance,NonPublic,Public'
foreach($target in $targets){
 $path=[string]$target.GetType().GetField('Rel',$if).GetValue($target)
 $resource=$target.GetType().GetField('ResourceName',$if).GetValue($target)
 if($names -ccontains $path -or $path -match '^(config\.json|SensorBackend/|Backups/|Data/)'){throw ('R273_UPGRADE_TOUCHES_PROTECTED_OR_DUPLICATE '+$path)}
 if($null -eq $resource){$removed++};$names+=@($path);$cases++
}
if($removed -ne 8 -or $names -cnotcontains 'Docs/RELEASE_NOTES_v1.7.6.md' -or $names -cnotcontains 'Docs/RELEASE_NOTES_v1.7.1.md'){throw 'R273_VERSIONED_NOTES_TRANSACTION_MAP'}
New-Item -ItemType Directory -Path $OutDir|Out-Null
$r=[ordered]@{Revision='R273';Status='PASS_COMPILED_175_UPGRADE_CONTRACT';SetupSHA256=(Get-FileHash $full -Algorithm SHA256).Hash;PositiveCases=$cases;RejectedCases=$negative;Official173ManagedFiles=23;Official174ManagedFiles=22;Official175ManagedFiles=22;PreviousVersions=@('1.6.0','1.7.0','1.7.1','1.7.2','1.7.3','1.7.4','1.7.5');CurrentVersion='1.7.6';NoAppEntryPointInvoked=$true;NoPersonalFilesOrRegistryMutated=$true;ActualInstallAcceptance='SEPARATE_HOSTED_VM_GATE'}
[IO.File]::WriteAllText((Join-Path $OutDir 'R273_CONTRACT.json'),($r|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
Write-Output ($r|ConvertTo-Json -Depth 6 -Compress)
