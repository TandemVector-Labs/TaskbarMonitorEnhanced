[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$AssemblyPath,[switch]$LocalFixture)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop'){throw 'R089_NATIVE_WINDOWS_POWERSHELL51_REQUIRED'}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourceHead=(git -C $repo rev-parse HEAD).Trim()
if([string]::IsNullOrWhiteSpace($sourceHead)){throw 'R089_GIT_SOURCE_IDENTITY_UNAVAILABLE'}
$dll=[IO.Path]::GetFullPath($AssemblyPath)
if(!(Test-Path -LiteralPath $dll -PathType Leaf)){throw 'R089_REAL_SETUP_PE_NOT_BUILT'}
if($LocalFixture){
  $expectedTestDll='888B7C27E9158E79D886ED181C72BFDA9E2769B0D34C9BE0D3E56D9B0E66434F'
  if(-not $dll.EndsWith('_r090_native_disposable_source.dll',[StringComparison]::OrdinalIgnoreCase) -or
     -not $dll.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or
     (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash -cne $expectedTestDll){
    throw 'R089_LOCAL_FIXTURE_NOT_EXACT_COMPILED_SECURITY_SOURCE'
  }
  $tempBase=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
}else{
  if($env:GITHUB_ACTIONS -cne 'true' -or
     $env:RUNNER_OS -cne 'Windows' -or
     $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
     $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
     $sourceHead -cne $env:GITHUB_SHA -or
     [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID) -or
     [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    throw 'R089_HOSTED_WINDOWS_WITH_EXACT_HEAD_REQUIRED'
  }
  $expectedBuiltDll=[IO.Path]::GetFullPath((Join-Path $repo 'build/_out/Setup/TaskbarMonitorEnhanced_Setup_1.7.8.exe'))
  if(-not [string]::Equals($dll,$expectedBuiltDll,[StringComparison]::OrdinalIgnoreCase)){
    throw 'R089_NOT_BUILT_INSTALLER_FROM_THIS_CHECKOUT'
  }
  $tempBase=[IO.Path]::GetFullPath($env:RUNNER_TEMP)
}
$root=Join-Path $tempBase ('tbme_r089_owned_'+[guid]::NewGuid().ToString('N'))
if(Test-Path -LiteralPath $root){throw 'R089_RANDOM_TEST_OWNERSHIP_COLLISION'}
if(-not [string]::Equals([IO.Path]::GetDirectoryName($root),$tempBase.TrimEnd([IO.Path]::DirectorySeparatorChar),
                         [StringComparison]::OrdinalIgnoreCase)){throw 'R089_NOT_DIRECT_TEMP_CHILD'}
[void][IO.Directory]::CreateDirectory($root)
$asm=[Reflection.Assembly]::LoadFile($dll)
$rt=$asm.GetType('SetupProgram+SensorStatusReceiver',$true)
$pub=[Reflection.BindingFlags]'Public,Instance'
$fName=$rt.GetField('Name',$pub)
$pNonce=$rt.GetProperty('Nonce',$pub)
$poll=$rt.GetMethod('Poll',$pub)
$pHas=$rt.GetProperty('HasResult',$pub)
$persist=$rt.GetMethod('PersistToUserRoot',[Reflection.BindingFlags]'NonPublic,Instance')
if(!$fName -or !$pNonce -or !$poll -or !$pHas -or !$persist){throw 'R089_REAL_RECEIVER_INTERFACE_MISSING'}
$winps=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
$template=@'
$ErrorActionPreference='Stop'
$pipe='__NAME__'
$nonce='__NONCE__'
$kind='__KIND__'
$c=[IO.Pipes.NamedPipeClientStream]::new('.',$pipe,[IO.Pipes.PipeDirection]::InOut)
try {
    $c.Connect(5000)
    $hello=[Text.Encoding]::UTF8.GetBytes(('HELLO|'+$nonce+[char]10))
    $c.Write($hello,0,$hello.Length)
    $c.Flush()
    $reader=[IO.StreamReader]::new($c,[Text.Encoding]::UTF8,$false,1024,$true)
    $ack=$reader.ReadLine()
    $reader.Dispose()
    if($ack -cne ('ACK|'+$nonce)){throw 'R089_HANDSHAKE_NOT_ACKNOWLEDGED'}
    # Full, source-owned 18-field schema required by R090, not the former
    # structurally incomplete R089 fixture; malformed-frame tests stay negative.
    $json='{"Status":"DEGRADED","Message":"R089_TEST_ONLY","PawnIOStatus":"NOT_STARTED","PawnIOExitCode":null,"RebootRequired":false,"TaskInstalled":false,"SensorHealthy":false,"SupervisorHealthy":false,"CpuTransportHealthy":false,"GpuTransportHealthy":false,"StorageTransportHealthy":false,"CpuDataAvailable":false,"Architecture":"R089_TEST_ONLY","RollbackPerformed":false,"RollbackSucceeded":false,"PreviousSensorLayerPresent":false,"Time":"2026-10-17T00:00:00Z","LogPath":"R089_NONIO_REFERENCE"}'
    $logs='R089_BENIGN'
    $j=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    $l=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($logs))
    $frame='TBME80|'+$nonce+'|'+$j+'|'+$l+[char]10
    if($kind -ceq 'wrong_result_nonce'){$frame='TBME80|WRONG_NONCE|'+$j+'|'+$l+[char]10}
    if($kind -ceq 'bad_base64'){$frame='TBME80|'+$nonce+'|!BADB64!|'+$l+[char]10}
    if($kind -ceq 'truncated_frame'){$frame='TBME80|'+$nonce+'|'+$j+'|'+$l}
    if($kind -ceq 'oversized_frame'){$frame='TBME80|'+$nonce+'|'+('A'*66000)+'|'+$l+[char]10}
    $data=[Text.Encoding]::UTF8.GetBytes($frame)
    $c.Write($data,0,$data.Length)
    $c.Flush()
}finally{$c.Dispose()}
'@
function Verify-Case([string]$kind){
    $receiver=[Activator]::CreateInstance($rt,$true)
    $client=$null
    $dest=Join-Path $root ('out_'+$kind)
    if(Test-Path -LiteralPath $dest){throw ('R089_TEST_DESTINATION_PREEXISTS_'+$kind)}
    try{
        $name=[string]$fName.GetValue($receiver)
        $nonce=[string]$pNonce.GetValue($receiver,$null)
        $src=$template.Replace('__NAME__',$name).Replace('__NONCE__',$nonce).Replace('__KIND__',$kind)
        $start=[Diagnostics.ProcessStartInfo]::new()
        $start.FileName=$winps
        $start.Arguments='-NoProfile -NonInteractive -EncodedCommand '+
             [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($src))
        $start.UseShellExecute=$false
        $start.CreateNoWindow=$true
        $client=[Diagnostics.Process]::Start($start)
        if(!$client){throw 'R089_REAL_WINDOWS_CLIENT_NOT_STARTED'}
        $received=$false;$rejected=$false;$cause=''
        $deadline=[DateTime]::UtcNow.AddSeconds(9)
        while([DateTime]::UtcNow -lt $deadline){
            try{[void]$poll.Invoke($receiver,([object[]]@($client)))}
            catch {
                $e=$_.Exception
                while($e.InnerException){$e=$e.InnerException}
                $cause=$e.GetType().Name
                if($kind -cne 'valid_fast_exit' -and
                   ($e -is [IO.IOException] -or $e -is [IO.InvalidDataException] -or
                    $e -is [FormatException])){$rejected=$true;break}
                throw ('R089_UNEXPECTED_RECEIVER_FAILURE_'+$kind+': '+$e.Message)
            }
            if([bool]$pHas.GetValue($receiver,$null)){$received=$true;break}
            Start-Sleep -Milliseconds 35
        }
        if($received){
            try{[void]$persist.Invoke($receiver,([object[]]@([string]$dest)))}
            catch{
                $e=$_.Exception
                while($e.InnerException){$e=$e.InnerException}
                $cause=$e.GetType().Name
                if($kind -cne 'valid_fast_exit' -and
                   ($e -is [IO.InvalidDataException] -or $e -is [FormatException])){
                    $rejected=$true
                }else{throw ('R089_UNEXPECTED_STORE_ERROR_'+$kind+': '+$e.Message)}
            }
        }
        if($kind -ceq 'valid_fast_exit'){
            if(!$received -or -not(Test-Path -LiteralPath (Join-Path $dest 'Logs/sensor_install_result.json') -PathType Leaf)){
                throw 'R089_SHORT_LIVED_LEGITIMATE_MESSAGE_WAS_LOST'
            }
            'R089_VALID_FAST_EXIT_DELIVERED_TO_ASINVOKER=PASS'
        }else{
            if(!$rejected){throw ('R089_UNSAFE_FRAME_WAS_NOT_REJECTED_'+$kind)}
            if(Test-Path -LiteralPath $dest){throw ('R089_REJECTED_FRAME_CREATED_STATUS_FILES_'+$kind)}
            'R089_'+$kind.ToUpperInvariant()+'_REJECTED_NO_FILE_MUTATION=PASS ('+$cause+')'
        }
    }finally{
        if($client){
            if(-not $client.HasExited){try{$client.Kill();$client.WaitForExit(2000)|Out-Null}catch{}}
            $client.Dispose()
        }
        $receiver.Dispose()
        if(Test-Path -LiteralPath $dest){[IO.Directory]::Delete($dest,$true)}
    }
}
$allPassed=$false
try{
    foreach($kind in @('valid_fast_exit','wrong_result_nonce','bad_base64',
                       'truncated_frame','oversized_frame')){
        Verify-Case $kind
    }
    $allPassed=$true
    'R089_ALL_FIVE_REAL_SOURCE_NOUAC_FRAME_GATES_PASS=TRUE'
    'R089_REAL_UAC_OR_PROTECTED_INSTALL=FALSE'
}finally{
    if($allPassed){
        [IO.Directory]::Delete($root,$true)
        if(Test-Path -LiteralPath $root){throw 'R089_OWNED_TEMP_CLEANUP_FAILED'}
    }else{
        Write-Warning ('R089 test-owned Temp fixture retained after failure: '+$root)
    }
}
