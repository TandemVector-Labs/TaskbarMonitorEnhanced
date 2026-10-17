[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$AssemblyPath,[switch]$LocalFixture)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop'){throw 'R090_NATIVE_WINDOWS_POWERSHELL51_REQUIRED'}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sha=(git -C $repo rev-parse HEAD).Trim()
$dll=[IO.Path]::GetFullPath($AssemblyPath)
if(-not(Test-Path -LiteralPath $dll -PathType Leaf)){throw 'R090_CANDIDATE_ASSEMBLY_MISSING'}
if($LocalFixture){
    $expectedSha='888B7C27E9158E79D886ED181C72BFDA9E2769B0D34C9BE0D3E56D9B0E66434F'
    if(-not $dll.EndsWith('_r090_native_disposable_source.dll',[StringComparison]::OrdinalIgnoreCase) -or
       -not $dll.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or
       (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash -cne $expectedSha){
         throw 'R090_LOCAL_ASSEMBLY_NOT_EXACT_TEST_FIXTURE'
    }
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
}else{
    if($env:GITHUB_ACTIONS -cne 'true' -or
       $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       $env:GITHUB_SHA -cne $sha -or
       [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID) -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
        throw 'R090_ONLY_EXACT_HEAD_HOSTED_WINDOWS'
    }
    $built=[IO.Path]::GetFullPath((Join-Path $repo 'build/_out/Setup/TaskbarMonitorEnhanced_Setup_1.7.8.exe'))
    if(-not [string]::Equals($dll,$built,[StringComparison]::OrdinalIgnoreCase)){
        throw 'R090_CANDIDATE_SETUP_PE_NOT_FROM_THIS_BUILD'
    }
    $temp=[IO.Path]::GetFullPath($env:RUNNER_TEMP)
}
$owned=Join-Path $temp ('tbme_r090_schema_owned_'+[guid]::NewGuid().ToString('N'))
if(Test-Path -LiteralPath $owned -PathType Container){throw 'R090_TEST_OWNER_COLLISION'}
if(-not [string]::Equals([IO.Path]::GetDirectoryName($owned),
 $temp.TrimEnd([IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){
    throw 'R090_NOT_DIRECT_TEST_TEMP_CHILD'
}
[void][IO.Directory]::CreateDirectory($owned)
$asm=[Reflection.Assembly]::LoadFile($dll)
$type=$asm.GetType('SetupProgram+SensorStatusReceiver',$true)
$validator=$type.GetMethod('ValidateSensorStatusJson',[Reflection.BindingFlags]'NonPublic,Static')
$persist=$type.GetMethod('PersistToUserRoot',[Reflection.BindingFlags]'NonPublic,Instance')
$nonce=$type.GetProperty('Nonce',[Reflection.BindingFlags]'Public,Instance')
$messageField=$type.GetField('message',[Reflection.BindingFlags]'NonPublic,Instance')
if(-not $validator -or -not $persist -or -not $nonce -or -not $messageField){
    throw 'R090_CURRENT_COMPILED_SCHEMA_INTERFACE_MISSING'
}
$base=[ordered]@{
    Status='DEGRADED'
    Message='R090_HARMLESS_DIAGNOSTIC'
    PawnIOStatus='NOT_STARTED'
    PawnIOExitCode=$null
    RebootRequired=$false
    TaskInstalled=$false
    SensorHealthy=$false
    SupervisorHealthy=$false
    CpuTransportHealthy=$false
    GpuTransportHealthy=$false
    StorageTransportHealthy=$false
    CpuDataAvailable=$false
    Architecture='R090_TEST_ONLY'
    RollbackPerformed=$false
    RollbackSucceeded=$false
    PreviousSensorLayerPresent=$false
    Time=(Get-Date).ToString('o')
    LogPath='R090_NON_IO_REFERENCE'
}
if($base.Count -ne 18){throw 'R090_EXPECTED_HELPER_FIELD_COUNT_CHANGED'}
$positive=0;$negative=0;$index=0
function To-Json($fields){
    return [string]($fields|ConvertTo-Json -Compress -Depth 5)
}
function Assert-Case([string]$label,[string]$json,[bool]$shouldPass){
    $script:index++
    $dest=Join-Path $owned ('case_'+$script:index)
    if(Test-Path -LiteralPath $dest){throw 'R090_CASE_PATH_EXISTS'}
    $receiver=[Activator]::CreateInstance($type,$true)
    try{
        $id=[string]$nonce.GetValue($receiver,$null)
        $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
        $logs=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('R090_BENIGN'))
        $messageField.SetValue($receiver,('TBME80|'+$id+'|'+$encoded+'|'+$logs))
        $succeeded=$false
        try{
            [void]$persist.Invoke($receiver,([object[]]@([string]$dest)))
            $succeeded=$true
        }catch{
            $err=$_.Exception
            while($err.InnerException){$err=$err.InnerException}
            if($shouldPass -or $err -isnot [IO.InvalidDataException]){
                throw ('R090_UNEXPECTED_PARSE_REJECTION_'+$label+': '+$err.GetType().Name+' '+$err.Message)
            }
        }
        if($shouldPass -ne $succeeded){
            throw ('R090_SCHEMA_EXPECTATION_MISMATCH_'+$label+': accepted='+$succeeded)
        }
        if($succeeded){
            $file=Join-Path $dest 'Logs/sensor_install_result.json'
            $log=Join-Path $dest 'Logs/sensor_install.log'
            if(!(Test-Path -LiteralPath $file -PathType Leaf) -or
               !(Test-Path -LiteralPath $log -PathType Leaf) -or
               ([IO.File]::ReadAllText($file) -cnotlike '*Status*')){
                throw ('R090_POSITIVE_STATUS_FILE_NOT_PRODUCED_'+$label)
            }
            $script:positive++
        }else{
            if(Test-Path -LiteralPath $dest){
                throw ('R090_REJECTED_JSON_CREATED_FILES_'+$label)
            }
            $script:negative++
        }
        'R090_'+$label+'_'+$(if($succeeded){'ACCEPTED'}else{'REJECTED'})+'=PASS'
    }finally{
        $receiver.Dispose()
        if(Test-Path -LiteralPath $dest){[IO.Directory]::Delete($dest,$true)}
    }
}
$success=$false
try {
    $normal=To-Json $base
    Assert-Case 'LEGITIMATE_DEGRADED_FULL_SCHEMA' $normal $true
    $ready=[ordered]@{};foreach($k in $base.Keys){$ready[$k]=$base[$k]}
    $ready['Status']='READY';$ready['SensorHealthy']=$true
    $ready['SupervisorHealthy']=$true;$ready['TaskInstalled']=$true
    Assert-Case 'LEGITIMATE_READY_FULL_SCHEMA' (To-Json $ready) $true
    $reboot=[ordered]@{};foreach($k in $base.Keys){$reboot[$k]=$base[$k]}
    $reboot['Status']='REBOOT_REQUIRED';$reboot['RebootRequired']=$true
    Assert-Case 'LEGITIMATE_REBOOT_REQUIRED' (To-Json $reboot) $true
    $afterRollback=[ordered]@{};foreach($k in $base.Keys){$afterRollback[$k]=$base[$k]}
    $afterRollback['Status']='DEGRADED_ROLLED_BACK'
    $afterRollback['RollbackPerformed']=$true
    $afterRollback['RollbackSucceeded']=$true
    Assert-Case 'LEGITIMATE_ROLLBACK' (To-Json $afterRollback) $true
    foreach($key in $base.Keys){
        $missing=[ordered]@{}
        foreach($k in $base.Keys){if($k -cne $key){$missing[$k]=$base[$k]}}
        Assert-Case ('MISSING_'+$key) (To-Json $missing) $false
    }
    $badReady=[ordered]@{};foreach($k in $base.Keys){$badReady[$k]=$base[$k]}
    $badReady['Status']='READY'
    Assert-Case 'READY_WITH_FALSE_HEALTH' (To-Json $badReady) $false
    $rebootBad=[ordered]@{};foreach($k in $base.Keys){$rebootBad[$k]=$base[$k]}
    $rebootBad['Status']='REBOOT_REQUIRED'
    Assert-Case 'REBOOT_WITHOUT_REBOOT_FLAG' (To-Json $rebootBad) $false
    $malformed=$normal.Substring(0,$normal.Length-1)
    Assert-Case 'TRUNCATED_JSON' $malformed $false
    Assert-Case 'DUPLICATE_STATUS' ($normal.Replace('"Status":','"Status":"READY","Status":')) $false
    Assert-Case 'TRAILING_GARBAGE' ($normal+';evil') $false
    Assert-Case 'INVALID_ESCAPE' ($normal.Replace('R090_HARMLESS_DIAGNOSTIC','\zbad')) $false
    Assert-Case 'UNKNOWN_STATUS' ($normal.Replace('"DEGRADED"','"DOES_NOT_EXIST"')) $false
    Assert-Case 'EMPTY_REQUIRED_MESSAGE' ($normal.Replace('R090_HARMLESS_DIAGNOSTIC','')) $false
    Assert-Case 'STRING_INSTEAD_OF_BOOLEAN' ($normal.Replace('"SensorHealthy":false','"SensorHealthy":"false"')) $false
    Assert-Case 'FRACTIONAL_INT' ($normal.Replace('"PawnIOExitCode":null','"PawnIOExitCode":1.5')) $false
    Assert-Case 'NONNUMERIC_EXIT' ($normal.Replace('"PawnIOExitCode":null','"PawnIOExitCode":"bad"')) $false
    Assert-Case 'EXTRA_FIELD' ($normal.Replace('"Status":','"Unknown":"x","Status":')) $false
    Assert-Case 'NESTED_OBJECT' ($normal.Replace('"Message":"R090_HARMLESS_DIAGNOSTIC"','"Message":{}')) $false
    Assert-Case 'EMPTY_ROOT_OBJECT' '{}' $false
    Assert-Case 'INVALID_ROOT_ARRAY' '[]' $false
    $wrongRoll=[ordered]@{};foreach($k in $base.Keys){$wrongRoll[$k]=$base[$k]}
    $wrongRoll['Status']='DEGRADED_ROLLED_BACK'
    Assert-Case 'ROLLBACK_SUCCESS_WITHOUT_ROLLBACK' (To-Json $wrongRoll) $false
    if($positive -ne 4 -or $negative -ne (18+16)){
        throw ('R090_TEST_COVERAGE_CHANGED_POS_'+$positive+'_NEG_'+$negative)
    }
    'R090_VALID_FULL_SCHEMA_CASES='+$positive
    'R090_INVALID_SCHEMA_CASES='+$negative
    'R090_NO_WRITES_FOR_ALL_REJECTED_CASES=PASS'
    'R090_EXACT_SOURCE_NET48_AND_POWERSHELL51=PASS'
    'R090_PRIVILEGED_HELPER_OR_INSTALLED_HOST_TOUCHED=FALSE'
    $success=$true
}finally{
    if($success){
        [IO.Directory]::Delete($owned,$true)
        if(Test-Path -LiteralPath $owned){throw 'R090_OWNED_TEMP_CLEANUP_FAILED'}
    }else{
        Write-Warning ('R090 failing owned fixture retained at '+$owned)
    }
}