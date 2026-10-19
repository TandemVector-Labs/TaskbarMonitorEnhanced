[CmdletBinding()]
param([string]$SetupPath='', [switch]$HostedGuest,
      [ValidateSet('LOCAL','A','B')][string]$HostLabel='LOCAL')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop'){
    throw 'R335_REQUIRES_NATIVE_WINDOWS_NETFRAMEWORK'
}
if([string]::IsNullOrWhiteSpace($SetupPath)){
    $SetupPath=Join-Path $PSScriptRoot '_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
}
if(!(Test-Path -LiteralPath $SetupPath -PathType Leaf)){
    throw 'R335_EXACT_COMPILED_SETUP_NOT_PRESENT'
}
$setup=(Resolve-Path -LiteralPath $SetupPath).Path
$assembly=[Reflection.Assembly]::LoadFrom($setup)
$resource=$assembly.GetManifestResourceStream('Payload.TBME_Setup_Elevated_Helper.ps1')
if(!$resource){throw 'R335_PRODUCTION_HELPER_RESOURCE_MISSING'}
$reader=[IO.StreamReader]::new($resource,[Text.Encoding]::UTF8)
try{$embedded=$reader.ReadToEnd()}finally{$reader.Dispose()}
$helperPath=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\installer\TBME_Setup_Elevated_Helper.ps1')).Path
$source=[IO.File]::ReadAllText($helperPath,[Text.Encoding]::UTF8)
$normalize={param($x) $x.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
if((& $normalize $embedded) -cne (& $normalize $source)){
    throw 'R335_COMPILED_PE_HELPER_SOURCE_NOT_EXACT'
}
$script:checks=[Collections.Generic.List[string]]::new()
function Pass([string]$name){
    $script:checks.Add($name)
    Write-Output ('PASS '+$name)
}
Pass 'EXACT_COMPILED_SETUP_EMBEDS_PRODUCTION_HELPER'

$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$parseErrors)
if(@($parseErrors).Count -ne 0){
    throw ('R335_HELPER_PS51_PARSE_ERRORS_'+@($parseErrors).Count)
}
Pass 'PRODUCTION_HELPER_POWERSHELL51_AST_PARSES'

$native=[regex]::Matches($source,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
if($native.Count -ne 1 -or
   -not $native[0].Groups[1].Value.Contains('public sealed class TBMEProtectedBrokerLease : IDisposable') -or
   $native[0].Groups[1].Value.Contains('TBMEScopedUserLogLease')){
    throw 'R335_CURRENT_NATIVE_BROKER_LEASE_SOURCE_NOT_UNIQUE'
}
Pass 'CURRENT_NATIVE_BROKER_LEASE_CLASS_UNIQUE'
Add-Type -TypeDefinition $native[0].Groups[1].Value -ErrorAction Stop
if($null -eq ('TBMEProtectedBrokerLease' -as [type])){
    throw 'R335_CURRENT_BROKER_NATIVE_CLASS_NOT_COMPILED'
}
Pass 'CURRENT_BROKER_LEASE_COMPILES_NATIVE_NETFRAMEWORK'
if($null -ne ('TBMEScopedUserLogLease' -as [type]) -or
   $source.Contains('TBMEScopedUserLogLease')){
    throw 'R335_RETIRED_ELEVATED_USER_LOG_LEASE_REINTRODUCED'
}
Pass 'RETIRED_PRIVILEGED_USER_LOG_HANDLE_NOT_SHIPPED'

$functions=@($ast.FindAll({
    param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]
},$true))
$logFn=@($functions|Where-Object Name -EQ 'Write-Log')
$resultFn=@($functions|Where-Object Name -EQ 'Write-Result')
if($logFn.Count -ne 1 -or $resultFn.Count -ne 1){
    throw 'R335_IPC_STATUS_FUNCTIONS_NOT_UNIQUE'
}
$logBody=$logFn[0].Body.Extent.Text
$resultBody=$resultFn[0].Body.Extent.Text
if(!$logBody.Contains('SENSOR_STATUS_CHANNEL_CLOSED') -or
   !$resultBody.Contains('SENSOR_STATUS_CHANNEL_CLOSED') -or
   !$resultBody.Contains('$script:StatusPipeClient.Write(') -or
   !$resultBody.Contains('TBME80|')){
    throw 'R335_CURRENT_STATUS_FUNCTIONS_NOT_IPC_BOUND'
}
foreach($body in @($logBody,$resultBody)){
    if($body -match '(?i)(WriteAllText|WriteAllBytes|Set-Content|Add-Content|Out-File|FileStream|TBMEScopedUserLogLease|File\]::Write)'){
        throw 'R335_PRIVILEGED_DIRECT_USER_LOG_WRITE_REINTRODUCED'
    }
}
Pass 'PRIVILEGED_LOG_AND_RESULT_FUNCTIONS_IPC_ONLY'
if(!$source.Contains('if($StatusPipe -cnotmatch') -or
   !$source.Contains('SENSOR_STATUS_PEER_NOT_VERIFIED') -or
   !$source.Contains('SENSOR_STATUS_CHANNEL_REQUIRED') -or
   $source.Contains('New-Item -ItemType Directory -Force -Path $LogsRoot')){
    throw 'R335_PRIVILEGED_STATUS_AUTHENTICATION_OR_NO_WRITE_CONTRACT_MISSING'
}
Pass 'PRIVILEGED_CHANNEL_NONCE_PRECONDITION_BEFORE_USER_OUTPUT'

$setupType=$assembly.GetType('SetupProgram',$true)
$flags=[Reflection.BindingFlags]'NonPublic,Static'
$compact=$setupType.GetMethod('CompactTrustedHelperSource',$flags)
$factory=$setupType.GetMethod('BuildElevatedSensorProcessInfo',$flags)
$command=$setupType.GetMethod('BuildElevatedHelperCommandWithPipe',$flags)
$receiverType=$assembly.GetType('SetupProgram+SensorStatusReceiver',$true)
$persist=$receiverType.GetMethod('PersistToUserRoot',
           [Reflection.BindingFlags]'NonPublic,Instance')
if(!$compact -or !$factory -or !$command -or !$persist){
    throw 'R335_CURRENT_TRUSTED_BUILDER_AND_ASINVOKER_RECEIVER_MISSING'
}
Pass 'CURRENT_ASINVOKER_RECEIVER_PERSISTS_STATUS_NOT_HELPER'

$compacted=[string]$compact.Invoke($null,([object[]]@([string]$embedded)))
$literal=$native[0].Value.Replace(([string][char]13+[string][char]10),[string][char]10)
if(!$compacted.Contains($literal) -or
   !$compacted.Contains('TBMEProtectedBrokerLease') -or
   $compacted.Contains('TBMEScopedUserLogLease')){
    throw 'R335_TRUSTED_NATIVE_HERE_LITERAL_CHANGED_OR_LEGACY_CLASS_PRESENT'
}
Pass 'PE_COMPACTOR_RETAINS_EXACT_BROKER_NATIVE_HERE_LITERAL'

$payload='C:\R335_TEST_ONLY\payload & literal'
$app='C:\R335_TEST_ONLY\AppData\Local\TaskbarMonitorEnhanced'
$user='R335_TEST_ONLY\user'
try{
    $psi=[Diagnostics.ProcessStartInfo]$factory.Invoke($null,
         ([object[]]@('Install',$payload,$app,$user)))
}catch{
    $e=$_.Exception
    while($e.InnerException){$e=$e.InnerException}
    throw $e
}
$system=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
if(!$psi.FileName.Equals($system,[StringComparison]::OrdinalIgnoreCase) -or
   !$psi.UseShellExecute -or $psi.Verb -cne 'runas' -or
   $psi.Arguments.Contains(' -File ') -or
   $psi.Arguments.Contains('ExecutionPolicy Bypass')){
    throw 'R335_PRIVILEGED_COMMAND_FACTORY_WEAKENED'
}
Pass 'NONLAUNCHING_RUNAS_PINNED_SYSTEM32_NO_TEMP_SCRIPT'
if($psi.Arguments.Contains('R335_TEST_ONLY') -or
   $psi.Arguments.Length -gt 32080 -or
   (!$psi.Arguments.StartsWith('-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand ',[StringComparison]::Ordinal) -and
    !$psi.Arguments.StartsWith('-NoProfile -NonInteractive -WindowStyle Hidden -Command ',[StringComparison]::Ordinal))){
    throw 'R335_UNBOUNDED_OR_UNTRUSTED_HELPER_COMMAND'
}
Pass 'OPERATOR_INPUTS_BASE64_AND_COMMAND_LENGTH_BOUNDED'

function Reject-Channel([string]$label,[string]$pipe,[string]$nonce){
    $refused=$false
    try{
        $null=$command.Invoke($null,
         ([object[]]@('Install',$payload,$app,$user,$pipe,$nonce)))
    }catch{
        $e=$_.Exception
        while($e.InnerException){$e=$e.InnerException}
        if($e -is [IO.InvalidDataException] -and
           $e.Message.Contains('status channel parameters invalid')){
            $refused=$true
        }else{throw $e}
    }
    if(!$refused){throw ('R335_FAIL_OPEN_'+$label)}
    Pass $label
}
Reject-Channel 'INVALID_STATUS_PIPE_REJECTED_PREWRITE' 'other_process_pipe' ('a'*32)
Reject-Channel 'INVALID_STATUS_NONCE_REJECTED_PREWRITE' ('tbme_sensor_'+('a'*32)) 'bad_nonce'

# No native elevated Helper is launched by this test. Observe only an owned
# disposable fixture under the test runner's Temp, never the owner AppRoot.
$base=if($HostedGuest){[string]$env:RUNNER_TEMP}else{[IO.Path]::GetTempPath()}
if([string]::IsNullOrWhiteSpace($base) -or -not [IO.Path]::IsPathRooted($base)){
    throw 'R335_TEST_TEMP_ROOT_UNAVAILABLE'
}
$base=[IO.Path]::GetFullPath($base).TrimEnd([IO.Path]::DirectorySeparatorChar)
$fixture=Join-Path $base ('tbme_r335_ipc_only_'+[guid]::NewGuid().ToString('N'))
if([IO.Directory]::Exists($fixture) -or
   ![IO.Path]::GetDirectoryName($fixture).Equals($base,[StringComparison]::OrdinalIgnoreCase)){
    throw 'R335_TEST_FIXTURE_NOT_ABSENT_DIRECT_CHILD'
}
[IO.Directory]::CreateDirectory($fixture)|Out-Null
$canary=Join-Path $fixture 'NO_WRITES_OUTSIDE_IPC.txt'
$marker='R335_CURRENT_IPC_ONLY_USER_DATA_NOT_TOUCHED'
[IO.File]::WriteAllText($canary,$marker,[Text.UTF8Encoding]::new($false))
try{
    if([IO.File]::ReadAllText($canary) -cne $marker -or
       @(Get-ChildItem -LiteralPath $fixture -Force -File).Count -ne 1){
        throw 'R335_DISPOSABLE_USER_CANARY_MODIFIED'
    }
    Pass 'DISPOSABLE_CANARY_UNTOUCHED_NO_PRIVILEGED_WRITES'
}finally{
    if([IO.Directory]::Exists($fixture) -and
       [IO.Path]::GetFileName($fixture).StartsWith('tbme_r335_ipc_only_',[StringComparison]::Ordinal)){
        [IO.Directory]::Delete($fixture,$true)
    }
}

if($script:checks.Count -ne 14){
    throw ('R335_IPC_BOUNDARY_CHECK_COUNT_MISMATCH_'+$script:checks.Count)
}
Write-Output ('R335_CURRENT_PRIVILEGED_IPC_ONLY_NATIVE_PASS='+$script:checks.Count+'/14')

if($HostedGuest){
    if($HostLabel -cnotin @('A','B') -or $env:GITHUB_ACTIONS -cne 'true' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       $env:RUNNER_OS -cne 'Windows' -or
       $env:GITHUB_SHA -cnotmatch '^[0-9a-f]{40}$' -or
       $env:GITHUB_RUN_ID -cnotmatch '^\d+$'){
        throw 'R335_REQUIRES_DISPOSABLE_GITHUB_WINDOWS'
    }
    $folder=Join-Path $env:RUNNER_TEMP ('R335_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
    if([IO.Directory]::Exists($folder)){throw 'R335_RECEIPT_ALREADY_EXISTS'}
    [IO.Directory]::CreateDirectory($folder)|Out-Null
    $receipt=Join-Path $folder 'R335_PRIVILEGED_IPC_BOUNDARY.json'
    $data=[ordered]@{
        Schema=2;Revision='R335-IPC';Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
        Status='PASS_CURRENT_PRIVILEGED_IPC_ONLY_NATIVE'
        Checks=@($script:checks.ToArray())
        PrivilegedUserLogLeasePresent=$false
        AsInvokerStatusPersistencePresent=$true
        RealElevatedHelperLaunched=$false
        ActualProgramFilesModified=$false
        AtomicCrossUserUacProven=$false
        ForeignCanaryPreserved=$true
        SecurityFinalAccepted=$false
    }
    [IO.File]::WriteAllText($receipt,($data|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    Write-Output ('R335_HOSTED_CURRENT_IPC_RECEIPT_SHA256='+(Get-FileHash $receipt -Algorithm SHA256).Hash)
}
