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
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'R291_ONLY_DISPOSABLE_GITHUB_WINDOWS_VM'
}
$out=Join-Path $env:RUNNER_TEMP ('R291_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$report=Join-Path $out 'R291_BOUNDARY_RECEIPT.json'
$src=(Resolve-Path (Join-Path $PSScriptRoot '..\installer\TBME_Setup_Elevated_Helper.ps1')).Path
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$fixtureApp=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$tempRoot=Join-Path ([Environment]::GetFolderPath('UserProfile')) 'AppData\Local\Temp'
$prior=Join-Path $env:RUNNER_TEMP ('R290_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R290_REPARSE_RECEIPT.json')
$user=[Security.Principal.WindowsIdentity]::GetCurrent().Name
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$live=Join-Path $fixtureApp 'TaskbarMonitorEnhanced.exe'
$log=[Collections.Generic.List[string]]::new()
$link='';$dangling='';$external='';$missing=''
$accepted=$false
function Hash([string]$p){if(Test-Path -LiteralPath $p -PathType Leaf){return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash};return 'MISSING'}
function Reject([string]$name,[string]$mode,[string]$payload,[string]$app,[string]$user){
 $failed=$false
 try{[void](Assert-SensorPrivilegedBoundary $mode $payload $app $user)}
 catch{
  if($_.Exception.Message -notmatch 'SENSOR_BOUNDARY_'){throw ('R291_WRONG_REJECTION_'+$name+': '+$_.Exception.Message)}
  $failed=$true
 }
 if(!$failed){throw ('R291_FAIL_OPEN_'+$name)}
 $script:log.Add($name)
}
if(Test-Path $out){throw 'R291_OUTPUT_ALREADY_PRESENT'}
[void][IO.Directory]::CreateDirectory($out)
$mainBefore=Hash $live
try{
 $priorInfo=Get-Content $prior -Raw|ConvertFrom-Json
 $identity=Get-Content $manifest -Raw|ConvertFrom-Json
 if($priorInfo.Status -cne 'PASS_NATIVE_UPGRADE_CHILD_REPARSE_FAIL_CLOSED' -or
   $priorInfo.SourceCommit -cne $env:GITHUB_SHA -or
   $identity.Commit -cne $env:GITHUB_SHA -or
   (Hash $setup) -cne $identity.SetupSHA256 -or
   (Hash $live) -cne $identity.MainSHA256){throw 'R291_EXACT_GUEST_CANDIDATE_NOT_PINNED'}
 $tokens=$null;$errors=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile($src,[ref]$tokens,[ref]$errors)
 if(@($errors).Count){throw 'R291_PS51_SOURCE_PARSER_FAIL'}
 $defs=@($ast.FindAll({param($n)
  $n -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $n.Name -in @('Assert-SensorBoundaryNoReparse','Assert-SensorPrivilegedBoundary')
 },$true))
 if($defs.Count -ne 2){throw 'R291_GUARD_FUNCTION_COUNT_MISMATCH'}
 $raw=Get-Content $src -Raw
  $first=$raw.IndexOf('$validatedSensorSid=Assert-SensorPrivilegedBoundary',[StringComparison]::Ordinal)
  $pipeGuard=$raw.IndexOf('SENSOR_STATUS_CHANNEL_REQUIRED',[StringComparison]::Ordinal)
  $logsCreate=$raw.IndexOf('New-Item -ItemType Directory -Force -Path $LogsRoot',[StringComparison]::Ordinal)
  $privilegedLog=$raw.IndexOf('Add-Content -LiteralPath $LogPath',[StringComparison]::Ordinal)
  $privilegedResult=$raw.IndexOf('Set-Content -LiteralPath $ResultPath',[StringComparison]::Ordinal)
  # R080: reject regressions to privileged user-profile writes rather than
  # demand those unsafe writes as the old R291 test mistakenly did.
  if($first -lt 0 -or $pipeGuard -le $first -or
     $logsCreate -ge 0 -or $privilegedLog -ge 0 -or $privilegedResult -ge 0){
    throw 'R291_ELEVATED_SID_CHECK_AND_IPC_PREWRITE_GUARD_FAILED'
  }
  $log.Add('SID_PREFLIGHT_BEFORE_IPC_NO_PRIVILEGED_APPDATA_STATUS_WRITES')
 # Dot-source ONLY the two selected function ASTs, never the full privileged script.
 . ([scriptblock]::Create(($defs|ForEach-Object {$_.Extent.Text}) -join [Environment]::NewLine))
 $validInstall=Join-Path $tempRoot ('tbme_setup_'+('a'*32))
 $validUninstall=Join-Path $tempRoot ('tbme_uninstall_'+('b'*32))
 if((Assert-SensorPrivilegedBoundary Install $validInstall $fixtureApp $user) -cne $sid -or
    (Assert-SensorPrivilegedBoundary Uninstall $validUninstall $fixtureApp $user) -cne $sid){
  throw 'R291_VALID_USER_OR_PROFILE_REJECTED'
 }
 $log.Add('LEGITIMATE_INSTALL_AND_UNINSTALL_ACCEPTED')
 Reject 'WRONG_APP_ROOT_REFUSED' Install $validInstall (Join-Path $env:WINDIR 'TaskbarMonitorEnhanced') $user
 Reject 'OUTSIDE_USER_PROFILE_REFUSED' Install (Join-Path $env:WINDIR ('tbme_setup_'+('a'*32))) $fixtureApp $user
 Reject 'DOWNLOADS_ROOT_WITH_VALID_NAME_REFUSED' Install (Join-Path ([Environment]::GetFolderPath('UserProfile')) ('Downloads\tbme_setup_'+('a'*32))) $fixtureApp $user
 Reject 'NESTED_TEMP_WITH_VALID_NAME_REFUSED' Install (Join-Path (Join-Path $tempRoot 'nested') ('tbme_setup_'+('b'*32))) $fixtureApp $user
 Reject 'WRONG_MODE_PAYLOAD_REFUSED' Uninstall $validInstall $fixtureApp $user
 Reject 'MALFORMED_PAYLOAD_NAME_REFUSED' Install (Join-Path $tempRoot 'tbme_setup_bad') $fixtureApp $user
 Reject 'SERVICE_SID_REFUSED' Install $validInstall $fixtureApp 'S-1-5-18'
 Reject 'UNRESOLVABLE_WINDOWS_ACCOUNT_REFUSED' Install $validInstall $fixtureApp 'THIS_ACCOUNT_MUST_NOT_EXIST_R291'
 $asm=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
 $stream=$asm.GetManifestResourceStream('Payload.TBME_Setup_Elevated_Helper.ps1')
 if(!$stream){throw 'R291_BOUNDARY_RESOURCE_MISSING'}
 $reader=[IO.StreamReader]::new($stream)
 try{$embedded=$reader.ReadToEnd()}finally{$reader.Dispose()}
 $crlf=[string][char]13+[string][char]10
 $lf=[string][char]10
 if($embedded.Replace($crlf,$lf).TrimStart([char]0xFEFF).TrimEnd() -cne
    $raw.Replace($crlf,$lf).TrimStart([char]0xFEFF).TrimEnd()){
  throw 'R291_EMBEDDED_HELPER_NOT_EXACT_SOURCE'
 }
 $log.Add('EMBEDDED_SETUP_HELPER_MATCHES_GUARDED_SOURCE')
 $external=Join-Path $out 'outside'
 [void][IO.Directory]::CreateDirectory($external)
 $canary=Join-Path $external 'outside.txt'
 [IO.File]::WriteAllText($canary,'R291_CANARY_NOT_TO_BE_CHANGED',[Text.UTF8Encoding]::new($false))
 $canarySHA=Hash $canary
 $link=Join-Path $tempRoot ('tbme_setup_'+[guid]::NewGuid().ToString('N'))
 New-Item -ItemType Junction -Path $link -Target $external -ErrorAction Stop|Out-Null
 if(-not ((Get-Item -LiteralPath $link -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){
  throw 'R291_ACTUAL_WINDOWS_JUNCTION_REQUIRED'
 }
 Reject 'REAL_PAYLOAD_JUNCTION_REFUSED' Install $link $fixtureApp $user
 [IO.Directory]::Delete($link)
 $link=''
 $missing=Join-Path $out 'missingTarget'
 [void][IO.Directory]::CreateDirectory($missing)
 $dangling=Join-Path $tempRoot ('tbme_setup_'+[guid]::NewGuid().ToString('N'))
 New-Item -ItemType Junction -Path $dangling -Target $missing -ErrorAction Stop|Out-Null
 [IO.Directory]::Delete($missing)
 $missing=''
 Reject 'DANGLING_PAYLOAD_JUNCTION_REFUSED' Install $dangling $fixtureApp $user
 [IO.Directory]::Delete($dangling)
 $dangling=''
 if((Hash $live) -cne $mainBefore -or (Hash $canary) -cne $canarySHA){
  throw 'R291_INSTALLED_OR_EXTERNAL_CANARY_CHANGED'
 }
 $log.Add('MAIN_AND_CANARY_UNCHANGED')
 $rec=[ordered]@{Schema=1;Revision='R291';Status='PASS_PRIVILEGED_HELPER_BOUNDARY_NATIVE'
  Host=$HostLabel;SourceCommit=$env:GITHUB_SHA;OriginalOwnerComputerTouched=$false
  ProtectedServicesOrUACInvoked=$false;RealWindowsJunctionUsed=$true
  PositiveAndNegativePathChecksPassed=$true;DanglingJunctionRejected=$true
  EmbeddedHelperSourceMatched=$true;InstalledMainUnchanged=$true
  CheckCount=$log.Count;Checks=@($log);RecordedUtc=[DateTime]::UtcNow.ToString('o')}
 [IO.File]::WriteAllText($report,($rec|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
 $accepted=$true
 'R291_GUEST_'+$HostLabel+'_PRIVILEGE_BOUNDARY=PASS'
}finally{
 if($link){try{[IO.Directory]::Delete($link)}catch{}}
 if($dangling){try{[IO.Directory]::Delete($dangling)}catch{}}
 if($missing -and (Test-Path $missing)){try{[IO.Directory]::Delete($missing)}catch{}}
 if(!$accepted){
  $fail=[ordered]@{Schema=1;Revision='R291';Status='FAIL_NOT_ACCEPTED';Host=$HostLabel
   SourceCommit=$env:GITHUB_SHA;MainPreserved=((Hash $live) -ceq $mainBefore)
   OriginalOwnerComputerTouched=$false;RecordedUtc=[DateTime]::UtcNow.ToString('o')}
  [IO.File]::WriteAllText($report,($fail|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
 }
}
