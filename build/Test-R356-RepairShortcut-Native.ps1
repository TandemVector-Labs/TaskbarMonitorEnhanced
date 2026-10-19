[CmdletBinding()]
param([string]$MainPath='', [string]$SetupPath='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:GITHUB_REPOSITORY -cne 'Usefull-Skills/TaskbarMonitorEnhanced' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC|ALIEMAD|SAEID|LAPTOP' -or
   (git rev-parse HEAD).Trim() -cne $env:GITHUB_SHA){
    throw 'R356_ONLY_EXACT_GITHUB_HOSTED_WINDOWS_SOURCE'
}
if(!$MainPath){$MainPath=Join-Path $PSScriptRoot '_out\App\TaskbarMonitorEnhanced.exe'}
if(!$SetupPath){$SetupPath=Join-Path $PSScriptRoot '_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'}
foreach($file in @($MainPath,$SetupPath)){
 if(!(Test-Path -LiteralPath $file -PathType Leaf)){throw 'R356_CURRENT_COMPILED_PE_MISSING'}
}
$main=[IO.Path]::GetFullPath((Resolve-Path $MainPath).Path)
$setup=[IO.Path]::GetFullPath((Resolve-Path $SetupPath).Path)
$m=[Reflection.Assembly]::LoadFrom($main)
$program=$m.GetType('TaskbarMonitorEnhanced.RepairShortcutEntryPoint',$true)
$mainEntry=$m.GetType('TaskbarMonitorEnhanced.Program',$true)
$f=[Reflection.BindingFlags]'NonPublic,Public,Static'
$recognize=$program.GetMethod('IsExactInvocation',$f)
if(!$recognize -or !$mainEntry.GetMethod('Main',$f)){throw 'R356_REPAIR_MAIN_ARG_DISPATCH_MISSING'}
$setupAsm=[Reflection.Assembly]::LoadFrom($setup)
$sp=$setupAsm.GetType('SetupProgram',$true)
$create=@($sp.GetMethods($f)|Where-Object { $_.Name -ceq 'Shortcut' -and $_.GetParameters().Count -eq 4 })
$owned=$sp.GetMethod('IsOwnedShortcut',$f)
$delete=$sp.GetMethod('DeleteOwnedShortcut',$f)
if($create.Count -ne 1 -or !$owned -or !$delete){throw 'R356_PRODUCTION_SHORTCUT_METHODS_NOT_COMPILED'}
$checks=[Collections.Generic.List[string]]::new()
function Pass([string]$x){$script:checks.Add($x);Write-Output ('PASS '+$x)}
function Matches([string[]]$argv){
 $parameters=New-Object 'object[]' 1
 $parameters[0]=$argv
 return [bool]$recognize.Invoke($null,$parameters)
}
function IsOwned([string]$link,[string]$target,[string]$argsText){
 return [bool]$owned.Invoke($null,([object[]]@($link,$target,$argsText)))
}
function Delete-Owner([string]$link,[string]$target,[string]$argsText){
 return [bool]$delete.Invoke($null,([object[]]@($link,$target,$argsText)))
}
if(!(Matches ([string[]]@('--repair-sensors')))){throw 'R356_CURRENT_MAIN_ARG_NOT_ACCEPTED'}
Pass 'CURRENT_MAIN_REPAIR_ARGUMENT_ACCEPTED'
$malformed=@(
 @{Argv=[string[]]@('/repair-sensors')},
 @{Argv=[string[]]@('--REPAIR-SENSORS')},
 @{Argv=[string[]]@('--repair-sensors','--quiet')},
 @{Argv=[string[]]@('--repair-sensors','extra')}
)
foreach($case in $malformed){
 if(Matches ([string[]]$case.Argv)){throw 'R356_UNTRUSTED_SHORTCUT_ARGUMENT_WAS_ACCEPTED'}
}
Pass 'LEGACY_CASE_VARIANT_AND_EXTRA_ARGS_REJECTED'
if(Matches ([string[]]@())){throw 'R356_EMPTY_REPAIR_REQUEST_ACCEPTED'}
Pass 'EMPTY_REPAIR_REQUEST_REJECTED'

# This particular additional-argument invocation must be refused before
# network, GUI, mutex, UAC, or any executable launch other than the Main
# itself. Only this bounded malicious-argument negative path is executed.
$psi=[Diagnostics.ProcessStartInfo]::new()
$psi.FileName=$main
$psi.Arguments='--repair-sensors --unexpected'
$psi.UseShellExecute=$false
$psi.CreateNoWindow=$true
$proc=$null
try {
 $proc=[Diagnostics.Process]::Start($psi)
 if(!$proc){throw 'R356_NONINTERACTIVE_MAIN_NEGATIVE_NOT_STARTED'}
 if(!$proc.WaitForExit(7000)){
  try{$proc.Kill()}catch{}
  throw 'R356_MALFORMED_MAIN_REPAIR_SHOULD_NOT_WAIT_FOR_GUI'
 }
 if($proc.ExitCode -ne 41){throw ('R356_MALFORMED_REPAIR_NOT_FAIL_CLOSED_'+$proc.ExitCode)}
}finally{if($proc){$proc.Dispose()}}
Pass 'ACTUAL_MAIN_REJECTED_MALFORMED_ARG_WITHOUT_UI_OR_UAC'

$fixture=Join-Path $env:RUNNER_TEMP ('R356_'+[Guid]::NewGuid().ToString('N'))
if(Test-Path -LiteralPath $fixture){throw 'R356_FIXTURE_NAME_ALREADY_EXISTS'}
[IO.Directory]::CreateDirectory($fixture)|Out-Null
$legacy=Join-Path $fixture 'legacy-repair.lnk'
$current=Join-Path $fixture 'new-repair.lnk'
$foreign=Join-Path $fixture 'foreign-repair.lnk'
$canary=Join-Path $fixture 'OUTSIDE_CANARY.txt'
[IO.File]::WriteAllText($canary,'R356_PRESERVE_FOREIGN',[Text.UTF8Encoding]::new($false))
$owner=$null;$link=$null
try{
 $argsTyped=[object[]]@([string]$current,[string]$main,[string]'--repair-sensors',
                      [string]'R356 TEST FILE - DOES NOT LAUNCH REPAIR')
 $null=$create[0].Invoke($null,$argsTyped)
 if(!(Test-Path -LiteralPath $current -PathType Leaf)){throw 'R356_REAL_PRODUCTION_COM_CREATION_FAILED'}
 Pass 'PRODUCTION_UNICODE_SHELLLINK_CREATED_NEW_MAIN_REPAIR'
 $owner=New-Object -ComObject WScript.Shell
 $link=$owner.CreateShortcut($current)
 if(-not [string]::Equals([string]$link.TargetPath,$main,[StringComparison]::OrdinalIgnoreCase) -or
    [string]$link.Arguments -cne '--repair-sensors'){
  throw 'R356_CURRENT_REPAIR_COM_TARGET_ARGUMENT_WRONG'
 }
 [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link);$link=$null
 Pass 'CURRENT_SHELLLINK_COM_READBACK_MAIN_AND_FIXED_ARG'

 if(!(IsOwned $current $main '--repair-sensors')){throw 'R356_CURRENT_LINK_NOT_OWNED'}
 if(IsOwned $current $setup '/repair-sensors'){throw 'R356_CURRENT_LINK_WRONGLY_LEGACY_OWNED'}
 Pass 'MODERN_REPAIR_LINK_ONLY_EXACT_OWNER_TUPLE'
 $oldHash=(Get-FileHash -LiteralPath $current -Algorithm SHA256).Hash
 if((Delete-Owner $current $setup '/repair-sensors') -or
   (Get-FileHash -LiteralPath $current -Algorithm SHA256).Hash -cne $oldHash){
  throw 'R356_WRONG_LEGACY_TUPLE_REMOVED_MODERN_SHORTCUT'
 }
 Pass 'WRONG_OLD_SETUP_TUPLE_REFUSED_TO_DELETE_MODERN_LINK'
 if(!(Delete-Owner $current $main '--repair-sensors') -or (Test-Path -LiteralPath $current)){
  throw 'R356_MODERN_OWNED_LINK_UNINSTALL_NOT_REMOVED'
 }
 Pass 'MODERN_REPAIR_LINK_REMOVED_ONLY_WITH_OWNER_MATCH'

 $link=$owner.CreateShortcut($legacy)
 $link.TargetPath=$setup;$link.Arguments='/repair-sensors';$link.Save()
 [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link);$link=$null
 if(!(IsOwned $legacy $setup '/repair-sensors')){throw 'R356_LEGACY_LINK_NOT_RECOGNIZED'}
 Pass 'LEGACY_REPAIR_OWNER_RECOGNIZED_FOR_SAFE_MIGRATION'
 $oldHash=(Get-FileHash -LiteralPath $legacy -Algorithm SHA256).Hash
 if((Delete-Owner $legacy $main '--repair-sensors') -or
    (Get-FileHash -LiteralPath $legacy -Algorithm SHA256).Hash -cne $oldHash){
  throw 'R356_NEW_TUPLE_DELETED_OLD_OWNED_LINK'
 }
 Pass 'MODERN_TUPLE_REFUSES_TO_DELETE_HISTORICAL_LINK'
 if(!(Delete-Owner $legacy $setup '/repair-sensors') -or (Test-Path -LiteralPath $legacy)){
  throw 'R356_LEGACY_OWNED_UNINSTALL_NOT_REMOVED'
 }
 Pass 'LEGACY_OWNED_SHORTCUT_UNINSTALL_STILL_WORKS'

 $link=$owner.CreateShortcut($foreign)
 $link.TargetPath=$main;$link.Arguments='--repair-sensors --evil';$link.Save()
 [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link);$link=$null
 $foreignHash=(Get-FileHash -LiteralPath $foreign -Algorithm SHA256).Hash
 if((Delete-Owner $foreign $main '--repair-sensors') -or
    (Get-FileHash -LiteralPath $foreign -Algorithm SHA256).Hash -cne $foreignHash){
  throw 'R356_FOREIGN_ARGUMENT_SHORTCUT_OVERWRITTEN_OR_REMOVED'
 }
 Pass 'FOREIGN_SIMILAR_NAMED_SHORTCUT_PRESERVED_EXACT_BYTES'
 if([IO.File]::ReadAllText($canary) -cne 'R356_PRESERVE_FOREIGN'){
  throw 'R356_UNRELATED_CANARY_WAS_CHANGED'
 }
 Pass 'OUTSIDE_CANARY_UNCHANGED'
}finally{
 if($link -and [Runtime.InteropServices.Marshal]::IsComObject($link)){
  [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)
 }
 if($owner -and [Runtime.InteropServices.Marshal]::IsComObject($owner)){
  [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($owner)
 }
 # Only remove exact fixture paths created here; unknown members fail closed.
 if([IO.Directory]::Exists($fixture)){
  $all=@([IO.Directory]::GetFileSystemEntries($fixture))
  if(@($all | Where-Object {$_ -notin @($current,$legacy,$foreign,$canary)}).Count){
   throw 'R356_UNKNOWN_FIXTURE_ENTRY_REFUSE_DELETE'
  }
  foreach($p in $all){
   if(([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    throw 'R356_UNEXPECTED_REPARSE'
   }
   [IO.File]::Delete($p)
  }
  [IO.Directory]::Delete($fixture,$false)
 }
}
Pass 'OWNED_DISPOSABLE_SHORTCUT_FIXTURE_REMOVED'
if($checks.Count -ne 15){throw ('R356_CHECK_COUNT_'+$checks.Count)}
'R356_REPAIR_SHORTCUT_NATIVE_CONTRACT=15/15'
