# R85: hermetic early PawnIO-degrade regression on disposable GitHub Windows.
# Dedicated R291 native A/B tests exercise the real privileged path boundary.
# This test mocks only its isolated fixture boundary and PawnIO discovery.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
# Never write even a test config to a real owner's user profile.
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){throw 'R85_ONLY_DISPOSABLE_GITHUB_WINDOWS'}
$Root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$Helper=Join-Path $Root 'installer\TBME_Setup_Elevated_Helper.ps1'
$Base=Join-Path $Root 'artifacts\_r85_external_degrade_test'
$Payload=Join-Path $Base 'payload'
$Profile=Join-Path $Base 'isolated-profile'
$App=Join-Path $Profile 'AppData\Local\TaskbarMonitorEnhanced'
$Mock=Join-Path $Base 'helper_mocked_pawnio_discovery.ps1'
$Result=Join-Path $App 'Logs\sensor_install_result.json'
$Log=Join-Path $App 'Logs\sensor_install.log'
if(Test-Path -LiteralPath $Base){throw 'R85 GUEST_FIXTURE_COLLISION_NO_USER_DATA_TOUCH'}
if(!(Test-Path -LiteralPath $Helper -PathType Leaf)){throw 'R85 HELPER MISSING'}
$source=Get-Content -LiteralPath $Helper -Raw
$guardAt=$source.IndexOf('PAWNIO_UPSTREAM_EXTERNAL_INSTALL_REQUIRED',[StringComparison]::Ordinal)
# R344 adds a separate *Uninstall-only* PREPARED snapshot before PawnIO
# discovery. The R85 regression is for Install: bind this static check to
# the Install-specific capture following the completed Uninstall branch.
$uninstallBegin=$source.IndexOf('if($Mode -eq ''Uninstall'')',[StringComparison]::Ordinal)
$uninstallEnd=$source.IndexOf('# R294: one exclusive read',$uninstallBegin,[StringComparison]::Ordinal)
$captureAt=$source.IndexOf('if(-not(Capture-PreviousSensorLayer))',$uninstallEnd,[StringComparison]::Ordinal)
if($uninstallBegin -lt 0 -or $uninstallEnd -le $uninstallBegin -or
   $guardAt -lt $uninstallEnd -or $captureAt -le $guardAt){
    throw 'R85 INSTALL_DEGRADED_GUARD_NOT_BEFORE_INSTALL_SENSOR_MUTATION'
}
if($source.Substring($uninstallBegin,$uninstallEnd-$uninstallBegin).IndexOf(
    'if(-not(Capture-PreviousSensorLayer))',[StringComparison]::Ordinal) -lt 0){
    throw 'R85 R344_UNINSTALL_JOURNAL_CAPTURE_MISSING'
}
$tok=$null;$errs=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tok,[ref]$errs)
if($errs.Count -ne 0){throw 'R85 HELPER HAS PARSER ERRORS'}
$funcs=@($ast.FindAll({param($x)
    $x -is [Management.Automation.Language.FunctionDefinitionAst] -and
      $x.Name -in @('Get-PawnIOVersion','Assert-SensorPrivilegedBoundary')
},$true))
if($funcs.Count -ne 2 -or @($funcs|Where-Object Name -eq 'Get-PawnIOVersion').Count -ne 1 -or
   @($funcs|Where-Object Name -eq 'Assert-SensorPrivilegedBoundary').Count -ne 1){
    throw 'R85_TWO_EXACT_MOCK_FUNCTIONS_REQUIRED'
}
$preflight=$source.IndexOf('$validatedSensorSid=Assert-SensorPrivilegedBoundary',[StringComparison]::Ordinal)
$logWrite=$source.IndexOf('New-Item -ItemType Directory -Force -Path $LogsRoot',[StringComparison]::Ordinal)
if($preflight -lt 0 -or $logWrite -le $preflight){throw 'R85_UNMODIFIED_PRODUCTION_GUARD_MISSING'}
$escapeApp=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($App)))
$escapeProfile=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Profile)))
$escapePayload=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Payload)))
$escapeUser=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([Security.Principal.WindowsIdentity]::GetCurrent().Name))
$escapeSid=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
$mockBoundary=@'
function Assert-SensorPrivilegedBoundary([string]$RequestedMode,[string]$RequestedPayload,[string]$RequestedAppRoot,[string]$RequestedUser){
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       $env:RUNNER_OS -cne 'Windows'){throw 'R85_MOCK_ONLY_HOSTED_DISPOSABLE'}
    $app=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__APP__'))
    $profile=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PROFILE__'))
    $payload=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD__'))
    $user=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__USER__'))
    $sid=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__SID__'))
    if($RequestedMode -cne 'Install' -or $RequestedUser -cne $user -or
       -not [string]::Equals([IO.Path]::GetFullPath($RequestedAppRoot),$app,[StringComparison]::OrdinalIgnoreCase) -or
       -not [string]::Equals($app,[IO.Path]::GetFullPath((Join-Path $profile 'AppData\Local\TaskbarMonitorEnhanced')),[StringComparison]::OrdinalIgnoreCase) -or
       -not [string]::Equals([IO.Path]::GetFullPath($RequestedPayload),$payload,[StringComparison]::OrdinalIgnoreCase)){
       throw 'R85_MOCK_REJECTS_OUTSIDE_OWNED_FIXTURE'
    }
    $script:ValidatedSensorProfileRoot=$profile
    return $sid
}
'@
$mockBoundary=$mockBoundary.Replace('__APP__',$escapeApp).Replace('__PROFILE__',$escapeProfile).Replace('__PAYLOAD__',$escapePayload).Replace('__USER__',$escapeUser).Replace('__SID__',$escapeSid)
$mocked=$source
foreach($fn in @($funcs|Sort-Object {$_.Extent.StartOffset} -Descending)){
    $replacement=if($fn.Name -ceq 'Get-PawnIOVersion'){"function Get-PawnIOVersion { return '' }"}else{$mockBoundary}
    $mocked=$mocked.Substring(0,$fn.Extent.StartOffset)+$replacement+$mocked.Substring($fn.Extent.EndOffset)
}
if(-not $mocked.Contains('R85_MOCK_REJECTS_OUTSIDE_OWNED_FIXTURE')){throw 'R85_BOUNDARY_MOCK_INJECTION_FAILED'}
$done=$false
try {
    New-Item -ItemType Directory -Path $Payload -Force -ErrorAction Stop|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $App 'SensorBackend\LibreHardwareMonitor-0.9.6') -Force -ErrorAction Stop|Out-Null
    [IO.File]::WriteAllBytes((Join-Path $Payload 'TaskbarMonitorSensorBroker.exe'),[byte[]](1,2,3))
    [IO.File]::WriteAllBytes((Join-Path $Payload 'TaskbarMonitorSensorSupervisor.exe'),[byte[]](1,2,3))
    [IO.File]::WriteAllBytes((Join-Path $App 'SensorBackend\LibreHardwareMonitor-0.9.6\LibreHardwareMonitorLib.dll'),[byte[]](1,2,3))
    [IO.File]::WriteAllText($Mock,$mocked,[Text.UTF8Encoding]::new($false))
    $exec=@(& pwsh -NoProfile -File $Mock -Mode Install -PayloadDir $Payload -AppRoot $App -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name))
    if($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $Result)){throw 'R85 MOCK HOST SENSOR HELPER FAILED'}
    $receipt=Get-Content -LiteralPath $Result -Raw|ConvertFrom-Json
    if($receipt.Status -cne 'DEGRADED' -or
       $receipt.PawnIOStatus -cne 'EXTERNAL_INSTALL_REQUIRED' -or
       $receipt.SensorHealthy -ne $false -or
       $receipt.TaskInstalled -ne $false -or
       $receipt.RebootRequired -ne $false -or
       $receipt.RollbackPerformed -ne $false -or
       $receipt.Architecture -cne 'PAWNIO_EXTERNAL_INSTALL_REQUIRED' -or
       $receipt.Message -notmatch 'https://github.com/namazso/PawnIO.Setup/releases/tag/2.2.0'){
       throw 'R85 MISSING PAWNIO DID NOT FAIL SAFE'
    }
    $lograw=Get-Content -LiteralPath $Log -Raw
    if($lograw -match 'PAWNIO_INSTALL_START|ROLLBACK_CAPTURE|SENSOR_PROCESS_DRAIN|REGISTER_TASK'){throw 'R85 PROTECTED MUTATION WAS ATTEMPTED'}
    $files=@(Get-ChildItem -LiteralPath $Base -Recurse -File)
    $allowed=@(
      'payload\TaskbarMonitorSensorBroker.exe','payload\TaskbarMonitorSensorSupervisor.exe',
      'isolated-profile\AppData\Local\TaskbarMonitorEnhanced\SensorBackend\LibreHardwareMonitor-0.9.6\LibreHardwareMonitorLib.dll',
      'isolated-profile\AppData\Local\TaskbarMonitorEnhanced\Logs\sensor_install_result.json','isolated-profile\AppData\Local\TaskbarMonitorEnhanced\Logs\sensor_install.log',
      'helper_mocked_pawnio_discovery.ps1')
    if($files.Count -ne $allowed.Count -or @($files|Where-Object {$_.FullName.Substring($Base.Length+1) -notin $allowed}).Count -ne 0){throw 'R85_UNKNOWN_FIXTURE_FILES'}
    Write-Output 'R85_MISSING_PAWNIO_DEGRADED_FAIL_CLOSED_NO_DRIVER_INSTALL_NO_ROLLBACK_NO_OS_CHANGE=PASS'
    $done=$true
} finally {
    if($done){
        # Delete only this initially absent, owned fixture; never touch user AppData.
        Remove-Item -LiteralPath $Base -Recurse -Force -ErrorAction Stop
        if(Test-Path -LiteralPath $Base){throw 'R85_FIXTURE_CLEANUP_FAILED'}
    }else{
        Write-Warning ('R85 GUEST FAILURE: owned fixture preserved at '+$Base)
    }
}
exit 0
