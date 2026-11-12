[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$CandidateSetup,
 [Parameter(Mandatory=$true)][string]$App,
 [Parameter(Mandatory=$true)][string]$Signal,
 [Parameter(Mandatory=$true)][string]$ExpectedSetupSha,
 [Parameter(Mandatory=$true)][string]$ExpectedPriorSetupSha,
 [Parameter(Mandatory=$true)][string]$ExpectedPriorMainSha,
 [Parameter(Mandatory=$true)][string]$ExpectedNewMainSha
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Child is launched and terminated by its parent ONLY on a new GitHub-hosted
# Windows runner. This script NEVER tries to clean up or install drivers.
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:GITHUB_REPOSITORY -cne 'GOD13emad/TaskbarMonitorEnhanced' -or
   $env:GITHUB_RUN_ID -cnotmatch '^[0-9]{5,20}$' -or
   $env:GITHUB_SHA -cnotmatch '^[a-f0-9]{40}$' -or
   $env:COMPUTERNAME -match '(?i)EMAD|ALIEMAD|LAPTOP|SAEID'){
 throw 'R299_CRASH_CHILD_REFUSES_ANY_NONDISPOSABLE_WINDOWS'
}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if((git -C $repo rev-parse HEAD).Trim() -cne $env:GITHUB_SHA){throw 'R299_CRASH_CHILD_SOURCE_COMMIT_CHANGED'}
$canonical=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
if(-not [string]::Equals([IO.Path]::GetFullPath($App),
 [IO.Path]::GetFullPath($canonical),[StringComparison]::OrdinalIgnoreCase)){
 throw 'R299_CRASH_CHILD_REQUIRES_EXACT_TEST_ROOT'
}
$main=Join-Path $App 'TaskbarMonitorEnhanced.exe'
$priorSetup=Join-Path $App 'Uninstall.exe'
$stage=Join-Path $App '.tbme-upgrade'
if(Test-Path $stage){throw 'R299_CRASH_CHILD_STAGE_PREEXISTS'}
foreach($probe in @(
 @{p=$CandidateSetup;sha=$ExpectedSetupSha},
 @{p=$priorSetup;sha=$ExpectedPriorSetupSha},
 @{p=$main;sha=$ExpectedPriorMainSha}
)){
 if((Get-FileHash -LiteralPath $probe.p -Algorithm SHA256).Hash -cne $probe.sha){
  throw ('R299_CRASH_CHILD_BINARY_SHA_UNEXPECTED_'+$probe.p)
 }
}
if(@(Get-Process TaskbarMonitorEnhanced -ErrorAction SilentlyContinue).Count){throw 'R299_CRASH_CHILD_MAIN_RUNNING'}
$oldState=Get-Content (Join-Path $App 'install_state.json') -Raw
if($oldState -cnotmatch '"Version"\s*:\s*"1.7.9"'){throw 'R299_CRASH_CHILD_PRIOR_VERSION_CHANGED'}
# Use original candidate Setup PE's unmodified private stage and journal
# factories; reflect the exact same code used by real /update.
try{
 $assembly=[Reflection.Assembly]::LoadFrom([IO.Path]::GetFullPath($CandidateSetup))
 $t=$assembly.GetType('SetupProgram',$true)
 $f=[Reflection.BindingFlags]'Static,NonPublic'
 $lex=$t.GetMethod('LegacyExpected',$f)
 $pre=$t.GetMethod('PrepareNewBytes',$f)
 $stageMethod=$t.GetMethod('StageNewManaged',$f)
 $write=$t.GetMethod('WritePhase',$f)
 if(!$lex -or !$pre -or !$stageMethod -or !$write){throw 'R299_CRASH_CHILD_PRIVATE_FACTORY_MISSING'}
 $v=[object[]]::new(2);$v[0]=[string]'1.7.9';$v[1]=[string]'OFFICIAL_STABLE_V179'
 $legacy=$lex.Invoke($null,$v)
 $s=[object[]]::new(1);$s[0]=[string]$oldState
 $newData=$pre.Invoke($null,$s)
 # Reflection runs under PowerShell; explicitly replace its unrelated @SELF
 # with exact current compiled candidate Setup bytes before staging.
 $newData['Uninstall.exe']=[IO.File]::ReadAllBytes($CandidateSetup)
 $a=[object[]]::new(5)
 $a[0]=$newData;$a[1]=$legacy;$a[2]=[string]$oldState
 $a[3]=[string]'1.7.9';$a[4]=[string]'OFFICIAL_STABLE_V179'
 [void]$stageMethod.Invoke($null,$a)
 $phase=[object[]]::new(1);$phase[0]=[string]'COMMITTING'
 [void]$write.Invoke($null,$phase)
 # Two genuine replacements, still no registry/version commit.
 Add-Type -TypeDefinition 'using System.IO; public static class R299FileBridge { public static void ReplaceNoBackup(string src,string dst){File.Replace(src,dst,null);} }'
 foreach($rel in @('TaskbarMonitorEnhanced.exe','Source/TaskbarMonitorEnhanced.cs')){
  $source=Join-Path (Join-Path $stage 'new') $rel
  $live=Join-Path $App $rel
  if(!(Test-Path $source) -or !(Test-Path $live)){throw ('R299_CRASH_CHILD_STAGED_PATH_MISSING_'+$rel)}
  [R299FileBridge]::ReplaceNoBackup($source,$live)
 }
 if((Get-FileHash $main -Algorithm SHA256).Hash -cne $ExpectedNewMainSha){
  throw 'R299_CRASH_CHILD_TWO_FILE_PARTIAL_MAIN_SHA_BAD'
 }
 if((Get-FileHash $priorSetup -Algorithm SHA256).Hash -cne $ExpectedPriorSetupSha){
  throw 'R299_CRASH_CHILD_CHANGED_UNINSTALL_BEFORE_KILL'
 }
 if((Get-Content (Join-Path $stage 'phase.txt') -Raw) -cnotmatch '\|COMMITTING$'){
  throw 'R299_CRASH_CHILD_NOT_IN_COMMITTING_PHASE'
 }
 $ack=[ordered]@{Pid=$PID;Phase='COMMITTING';ChangedFiles=2;GitSha=$env:GITHUB_SHA;Utc=[DateTime]::UtcNow.ToString('o')}
 if(Test-Path $Signal){throw 'R299_CRASH_CHILD_SIGNAL_ALREADY_EXISTS'}
 [IO.File]::WriteAllText($Signal,($ack|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
 # Parent will forcibly terminate exactly this one child process. Never exit
 # voluntarily or clean the stage: the real PE must replay its recovery.
 while($true){Start-Sleep -Seconds 2}
}catch{
 try{[IO.File]::WriteAllText($Signal+'.error.txt',$_.Exception.ToString(),[Text.UTF8Encoding]::new($false))}catch{}
 throw
}
