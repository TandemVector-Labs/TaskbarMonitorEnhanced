[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# TEST IS INTENTIONALLY HOSTED-ONLY. NEVER RUN ON OWNER COMPUTER.
if($env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:GITHUB_REPOSITORY -cne 'GOD13emad/TaskbarMonitorEnhanced' -or
   $env:COMPUTERNAME -match '(?i)EMAD|ALIEMAD|LAPTOP|SAEID' -or
   $env:GITHUB_RUN_ID -cnotmatch '^[0-9]{5,20}$' -or
   $env:GITHUB_SHA -cnotmatch '^[a-fA-F0-9]{40}$'){
 throw 'R298_REFUSE_ANY_NON_GITHUB_HOSTED_WINDOWS'
}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if((git -C $repo rev-parse HEAD).Trim() -cne $env:GITHUB_SHA){throw 'R298_REFUSE_UNPINNED_SOURCE'}
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$profile=[Environment]::GetFolderPath('UserProfile')
$expectedLocal=Join-Path $profile 'AppData/Local'
if(![string]::Equals([IO.Path]::GetFullPath((Split-Path $app)),[IO.Path]::GetFullPath($expectedLocal),[StringComparison]::OrdinalIgnoreCase)){throw 'R298_NONCANONICAL_OWNER_PROFILE'}
if(Test-Path $app){throw 'R298_REFUSE_EXISTING_APP_ROOT'}
if(Test-Path (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'TaskbarMonitorEnhanced')){throw 'R298_REFUSE_EXISTING_PROTECTED_APP'}
if(@(Get-Process TaskbarMonitorEnhanced,TaskbarMonitorSensorBroker,TaskbarMonitorSensorSupervisor -ErrorAction SilentlyContinue).Count){throw 'R298_REFUSE_EXISTING_PRODUCT_PROCESS'}
if(Get-ScheduledTask -TaskName 'TaskbarMonitorEnhanced Sensor Broker' -ErrorAction SilentlyContinue){throw 'R298_REFUSE_EXISTING_SENSOR_TASK'}
$setup=Join-Path $repo 'build/_out/Setup/TaskbarMonitorEnhanced_Setup_1.7.10.exe'
if(!(Test-Path $setup)){throw 'R298_COMPILED_SETUP_MISSING'}
$asm=[Reflection.Assembly]::LoadFrom((Resolve-Path $setup).Path)
$factory=$asm.GetType('SetupProgram',$true).GetMethod(
 'BuildDeferredUninstallCleanupProcessInfo',[Reflection.BindingFlags]'Static,NonPublic')
if(!$factory){throw 'R298_COMPILED_FACTORY_MISSING'}
$writable=Join-Path $env:RUNNER_TEMP ('tbme_r298_hosted_only_'+$env:GITHUB_RUN_ID)
if(Test-Path $writable){throw 'R298_EVIDENCE_ROOT_PREEXISTS'}
New-Item -ItemType Directory -Path $writable | Out-Null
$canaryDir=Join-Path $writable 'external-canary'
New-Item -ItemType Directory -Path $canaryDir|Out-Null
$canary=Join-Path $canaryDir 'NEVER_DELETE_OUTSIDE.txt'
[IO.File]::WriteAllText($canary,'R298 original runner canary')
$canarySha=(Get-FileHash $canary).Hash
$parent=$null
$children=@()
$createdProductFixture=$false
function AssertCanary {
 if((Get-FileHash -LiteralPath $canary -Algorithm SHA256).Hash -cne $canarySha){throw 'R298_EXTERNAL_CANARY_CHANGED'}
}
try {
 # Nominal: original compiled Setup's own private factory, a real live
 # test-owned parent process, and an actual native PowerShell child.
 # The synthetic owner profile starts absent and contains no installed App.
 [IO.Directory]::CreateDirectory($app)|Out-Null
 $createdProductFixture=$true
 [IO.Directory]::CreateDirectory((Join-Path $app 'nested'))|Out-Null
 $fixtureFile=Join-Path $app 'nested/test-owned.txt'
 [IO.File]::WriteAllText($fixtureFile,'R298 temporary owner-only fixture')
 $systemHost=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell/v1.0/powershell.exe'
 $parentPsi=[Diagnostics.ProcessStartInfo]::new()
 $parentPsi.FileName=$systemHost
 $parentPsi.Arguments='-NoProfile -NonInteractive -Command "Start-Sleep -Seconds 90"'
 $parentPsi.WorkingDirectory=$env:RUNNER_TEMP
 $parentPsi.UseShellExecute=$false
 $parentPsi.CreateNoWindow=$true
 $parent=[Diagnostics.Process]::Start($parentPsi)
 if(!$parent -or $parent.HasExited){throw 'R298_TEST_PARENT_NOT_STARTED'}
 $args=[object[]]::new(3)
 $args[0]=[string]$app
 $args[1]=[int]$parent.Id
 $args[2]=[long]$parent.StartTime.ToUniversalTime().Ticks
 $psi=[Diagnostics.ProcessStartInfo]$factory.Invoke($null,$args)
 if($psi.UseShellExecute -or $psi.FileName -cne $systemHost){throw 'R298_UNTRUSTED_CLEANUP_PROCESS'}
 $psi.RedirectStandardError=$true
 $psi.RedirectStandardOutput=$true
 $child=[Diagnostics.Process]::Start($psi)
 if(!$child){throw 'R298_CLEANUP_PROCESS_MISSING'}
 $children+=,$child
 Start-Sleep -Seconds 2
 if($child.HasExited -or !(Test-Path $fixtureFile)){throw 'R298_CLEANUP_RAN_BEFORE_PARENT_EXIT'}
 if(!$parent.HasExited){$parent.Kill();$parent.WaitForExit(8000)|Out-Null}
 if(!$child.WaitForExit(60000)){throw 'R298_NOMINAL_DEFERRED_TIMEOUT'}
 $err=$child.StandardError.ReadToEnd()
 if($child.ExitCode -ne 0){throw ('R298_NOMINAL_DEFERRED_EXIT_'+$child.ExitCode+' '+$err.Substring(0,[Math]::Min(500,$err.Length)))}
 if(Test-Path $app){throw 'R298_NOMINAL_ROOT_NOT_REMOVED'}
 AssertCanary
 'R298_HOSTED_ORIGINAL_PE_PARENT_WAIT_AND_CLEANUP=PASS'
 # Adversarial: the exact same native factory must refuse an owned
 # directory containing an external junction without touching the target.
 [IO.Directory]::CreateDirectory($app)|Out-Null
 $member=Join-Path $app 'owned-marker.txt'
 [IO.File]::WriteAllText($member,'R298 marker must survive reparse rejection')
 $junction=Join-Path $app 'malicious-child-junction'
 New-Item -ItemType Junction -Path $junction -Target $canaryDir -ErrorAction Stop|Out-Null
 if(!(Test-Path $junction)){throw 'R298_JUNCTION_NOT_CREATED'}
 $args=[object[]]::new(3)
 $args[0]=[string]$app
 $args[1]=[int]2147483000
 $args[2]=[long]1
 $psi=[Diagnostics.ProcessStartInfo]$factory.Invoke($null,$args)
 $psi.RedirectStandardError=$true
 $psi.RedirectStandardOutput=$true
 $child=[Diagnostics.Process]::Start($psi)
 if(!$child){throw 'R298_NEGATIVE_CHILD_NOT_STARTED'}
 $children+=,$child
 if(!$child.WaitForExit(60000)){throw 'R298_JUNCTION_REJECTION_TIMEOUT'}
 if($child.ExitCode -eq 0){throw 'R298_EXTERNAL_JUNCTION_NOT_REJECTED'}
 if(!(Test-Path $member)){throw 'R298_JUNCTION_REJECTION_MUTATED_OWNED_MARKER'}
 AssertCanary
 'R298_HOSTED_ORIGINAL_PE_EXTERNAL_JUNCTION_REFUSED=PASS'
} finally {
 # Fail closed: only remove our exact synthetic fixture after verifying
 # the junction target remains outside and no unknown files were introduced.
 foreach($ch in $children){try{if(!$ch.HasExited){$ch.Kill();$ch.WaitForExit(3000)|Out-Null}}catch{};try{$ch.Dispose()}catch{}}
 if($null -ne $parent){try{if(!$parent.HasExited){$parent.Kill();$parent.WaitForExit(3000)|Out-Null}}catch{};try{$parent.Dispose()}catch{}}
 if($createdProductFixture -and (Test-Path $app)){
  $allowed=@('owned-marker.txt','malicious-child-junction')
  $all=@(Get-ChildItem -LiteralPath $app -Force -ErrorAction Stop)
  if(@($all|Where-Object {$_.Name -notin $allowed}).Count -ne 0){throw 'R298_UNEXPECTED_OWNER_FIXTURE_MEMBER_LEFT_INTACT'}
  $j=Join-Path $app 'malicious-child-junction'
  if(Test-Path $j){[IO.Directory]::Delete($j)}
  $m=Join-Path $app 'owned-marker.txt'
  if(Test-Path $m){[IO.File]::Delete($m)}
  [IO.Directory]::Delete($app)
 }
 if((Test-Path $canary) -and ((Get-FileHash $canary).Hash -ceq $canarySha)){
  [IO.Directory]::Delete($canaryDir,$true)
  [IO.Directory]::Delete($writable)
 }else{throw 'R298_CANARY_MISSING_OR_CHANGED_PRESERVE_EVIDENCE'}
}
'R298_HOSTED_FRESH_DISPOSABLE_ORIGINAL_DEFERRED_CLEANUP=PASS'
