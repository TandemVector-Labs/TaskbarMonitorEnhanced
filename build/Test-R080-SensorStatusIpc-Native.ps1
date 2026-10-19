[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$AssemblyPath,
 [switch]$LocalFixture
)
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition -cne 'Desktop'){throw 'R080_ONLY_NATIVE_WINDOWS_PS51'}
if(-not $LocalFixture){
 if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
    $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
    [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -or
    $env:COMPUTERNAME -match '(?i)EMAD-PC'){
    throw 'R080_NEEDS_DISPOSABLE_GITHUB_WINDOWS_RUNNER'
 }
 if((git rev-parse HEAD).Trim() -cne $env:GITHUB_SHA){
    throw 'R080_BUILD_SHA_MISMATCH'
 }
 if(-not $AssemblyPath.EndsWith('TaskbarMonitorEnhanced_Setup_1.7.8.exe',
                          [StringComparison]::OrdinalIgnoreCase)){
    throw 'R080_EXPECTED_REAL_INSTALLER_BUILD_MISSING'
 }
}else{
 if(-not $AssemblyPath.EndsWith('_r080_safe_v3.dll',
                          [StringComparison]::OrdinalIgnoreCase) -or
    -not ([IO.Path]::GetFullPath($AssemblyPath)).StartsWith(
              [IO.Path]::GetFullPath([IO.Path]::GetTempPath()),
              [StringComparison]::OrdinalIgnoreCase)){
    throw 'R080_LOCAL_FIXTURE_OUTSIDE_BOUNDED_TEMP'
 }
}
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$dll=[IO.Path]::GetFullPath($AssemblyPath)
$helper=Join-Path $root 'installer/TBME_Setup_Elevated_Helper.ps1'
if(-not [IO.File]::Exists($dll)){throw 'TEST_DLL_MISSING'}
$asm=[Reflection.Assembly]::LoadFile($dll)
$receiverType=$asm.GetType('SetupProgram+SensorStatusReceiver',$true)
$flags=[Reflection.BindingFlags]'Public,Instance'
$receiverName=$receiverType.GetField('Name',$flags)
$receiverNonce=$receiverType.GetProperty('Nonce',$flags)
$receiverPoll=$receiverType.GetMethod('Poll',$flags)
$receiverHasResult=$receiverType.GetProperty('HasResult',$flags)
$messageField=$receiverType.GetField('message',[Reflection.BindingFlags]'NonPublic,Instance')
if(!$receiverName -or !$receiverNonce -or !$receiverPoll -or !$receiverHasResult -or !$messageField){throw 'ACTUAL_RECEIVER_METHODS_MISSING'}
# Verify that the actual PE resource and checkout source compact identically.
$t=$asm.GetType('SetupProgram',$true)
$compact=$t.GetMethod('CompactTrustedHelperSource',[Reflection.BindingFlags]'NonPublic,Static')
if(!$compact){throw 'R080_COMPACTOR_MISSING'}
$stream=$asm.GetManifestResourceStream('Payload.TBME_Setup_Elevated_Helper.ps1')
if(!$stream){throw 'R080_EMBEDDED_HELPER_MISSING'}
try{
 $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true)
 $embedded=$reader.ReadToEnd()
}finally{$stream.Dispose()}
$packaged=[string]$compact.Invoke($null,([object[]]@([string]$embedded)))
$fromSource=[string]$compact.Invoke($null,([object[]]@([IO.File]::ReadAllText($helper))))
if($packaged -cne $fromSource){throw 'R080_EMBEDDED_AND_SOURCE_HELPER_DO_NOT_MATCH'}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($packaged,[ref]$tokens,[ref]$errors)
if(@($errors).Count){throw 'REAL_EMBEDDED_COMPACTED_HELPER_PARSE_INVALID'}
$functions=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$true))
$need=@('Write-Log','Write-Result')
$bodyFunctions=''
foreach($n in $need){
 $f=@($functions|Where-Object{$_.Name -ceq $n})
 if($f.Count -ne 1){throw ('HELPER_REAL_FUNCTION_MISSING_'+$n)}
 $bodyFunctions+=[string]$f[0].Extent.Text+[char]10
}
$raw=$packaged
$start=$raw.IndexOf('if($StatusPipe -cnotmatch',[StringComparison]::Ordinal)
$end=$raw.IndexOf('$TaskName=',[StringComparison]::Ordinal)
if($start -lt 0 -or $end -le $start -or $raw.IndexOf('if($StatusPipe -cnotmatch',$start+1,[StringComparison]::Ordinal) -ge 0){throw 'HELPER_HANDSHAKE_NOT_UNIQUE'}
$handshake=$raw.Substring($start,$end-$start)
$winps=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
function Verify-One([string]$kind) {
 $receiver=[Activator]::CreateInstance($receiverType,$true)
 $client=$null
 try{
  $name=[string]$receiverName.GetValue($receiver)
  $nonce=[string]$receiverNonce.GetValue($receiver,$null)
  $sentNonce=if($kind -eq 'wrong_nonce'){'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'}else{$nonce}
  $code='$ErrorActionPreference="Stop"'+[char]10+
    '$StatusPipe="'+$name+'";$StatusNonce="'+$sentNonce+'";'+[char]10+
    $handshake+[char]10+
    '$SupervisorHealthy=$false;$CpuTransportHealthy=$false;$GpuTransportHealthy=$false;'+
    '$StorageTransportHealthy=$false;$CpuDataAvailable=$false;'+
    '$RollbackPerformed=$false;$RollbackSucceeded=$false;$PreviousSensorLayerPresent=$false;'+
    '$ActiveArchitecture="R080_TEST_ONLY";$LogPath="R080_TEST_NO_DISK_PATH";'+[char]10+
    $bodyFunctions+[char]10+
    'Write-Log "R080_TEST_ONLY";'+[char]10+
    'Write-Result "DEGRADED" "R080_HARMLESS_NONADMIN" "SKIPPED" $null $false $false $false;'+[char]10+
    '[Threading.Thread]::Sleep(1000)'+[char]10
  $cmd=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
  $psi=[Diagnostics.ProcessStartInfo]::new()
  $psi.FileName=$winps
  $psi.Arguments='-NoProfile -NonInteractive -EncodedCommand '+$cmd
  $psi.UseShellExecute=$false
  $psi.CreateNoWindow=$true
  $psi.RedirectStandardError=$true
  $client=[Diagnostics.Process]::Start($psi)
  if(!$client){throw 'CLIENT_NOT_STARTED'}
  $success=$false;$rejected=$false;$deadline=[DateTime]::UtcNow.AddSeconds(12)
  while([DateTime]::UtcNow -lt $deadline){
   $expected=if($kind -eq 'wrong_expected_pid'){[Diagnostics.Process]::GetCurrentProcess()}else{$client}
   try{[void]$receiverPoll.Invoke($receiver,([object[]]@($expected)))}
   catch{
    $e=$_.Exception
    while($e.InnerException){$e=$e.InnerException}
     if($kind -eq 'wrong_nonce' -and $e -is [IO.InvalidDataException] -and $e.Message.Contains('HELLO nonce')){$rejected=$true;break}
     if($kind -eq 'wrong_expected_pid' -and $e -is [IO.InvalidDataException] -and $e.Message.Contains('identity mismatch')){$rejected=$true;break}
    throw ('R080_RECEIVER_ERROR_'+$kind+': '+$e.GetType().Name+' '+$e.Message)
   }
   if([bool]$receiverHasResult.GetValue($receiver,$null)){$success=$true;break}
   Start-Sleep -Milliseconds 40
  }
   if($kind -eq 'wrong_nonce' -or $kind -eq 'wrong_expected_pid'){
    if(!$rejected){throw ('R080_EXPECTED_NEGATIVE_REJECTION_'+$kind)}
    'R080_ACTUAL_RECEIVER_'+$kind.ToUpperInvariant()+'=REJECTED'
   }else{
   if(!$success){throw ('R080_REAL_HELPER_FUNCTION_RESULT_NOT_RECEIVED;clientExited='+$client.HasExited)}
   $frame=[string]$messageField.GetValue($receiver)
   $parts=$frame.Split('|')
   if($parts.Length -ne 4 -or $parts[0] -ne 'TBME80' -or $parts[1] -cne $nonce){throw 'R080_FRAME_BOUNDARY_INVALID'}
   $json=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($parts[2]))|ConvertFrom-Json
   $logs=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($parts[3]))
   if($json.Status -cne 'DEGRADED' -or $json.Message -cne 'R080_HARMLESS_NONADMIN' -or !$logs.Contains('R080_TEST_ONLY')){throw 'R080_STATUS_CONTENT_NOT_PRESERVED'}
   'R080_REAL_HELPER_FUNCTION_STATUS_FRAME=PASS'
   'R080_POLL_WITH_OS_PID_NONCE_SESSION=PASS'
   'R080_NO_PRIVILEGED_PERUSER_WRITES=TRUE'
    # Never create/delete the installed AppRoot, even on the hosted runner:
    # Build and Verification may have populated it earlier in this same job.
    # Exercise the *actual* refactored persistence method in a fresh, explicitly
    # test-owned RUNNER_TEMP/OS-TEMP direct child, including schema verification.
    $testBase=if($LocalFixture){[IO.Path]::GetTempPath()}else{$env:RUNNER_TEMP}
    if([string]::IsNullOrWhiteSpace($testBase) -or
       -not [IO.Path]::IsPathRooted($testBase)){
      throw 'R080_DISPOSABLE_TEST_ROOT_UNAVAILABLE'
    }
    $baseCanonical=[IO.Path]::GetFullPath($testBase).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $fixture=Join-Path $baseCanonical ('tbme_r080_owned_'+[guid]::NewGuid().ToString('N'))
    if((Test-Path -LiteralPath $fixture) -or
       -not [string]::Equals([IO.Path]::GetDirectoryName($fixture),
                          $baseCanonical,[StringComparison]::OrdinalIgnoreCase)){
      throw 'R080_FIXTURE_NOT_NEW_DIRECT_TEMP_CHILD'
    }
    $normalApp=[string]$t.GetProperty('AppRoot',[Reflection.BindingFlags]'NonPublic,Static').GetValue($null,$null)
    if([string]::Equals($fixture,$normalApp,[StringComparison]::OrdinalIgnoreCase) -or
       $fixture.StartsWith($normalApp+[IO.Path]::DirectorySeparatorChar,
                            [StringComparison]::OrdinalIgnoreCase)){
      throw 'R080_TEST_WOULD_TOUCH_REAL_INSTALLED_APP_ROOT'
    }
    try{
      $persist=$receiverType.GetMethod('PersistToUserRoot',
                          [Reflection.BindingFlags]'NonPublic,Instance')
      if(!$persist){throw 'R080_ACTUAL_PERSISTENCE_METHOD_MISSING'}
      [void]$persist.Invoke($receiver,([object[]]@([string]$fixture)))
      $resultFile=Join-Path $fixture 'Logs/sensor_install_result.json'
      $logFile=Join-Path $fixture 'Logs/sensor_install.log'
      if(-not(Test-Path -LiteralPath $resultFile -PathType Leaf) -or
         -not(Test-Path -LiteralPath $logFile -PathType Leaf)){
        throw 'R080_ISOLATED_USER_STATUS_PERSIST_MISSING'
      }
      $saved=Get-Content -LiteralPath $resultFile -Raw|ConvertFrom-Json
      if($saved.Status -cne 'DEGRADED' -or
         $saved.Message -cne 'R080_HARMLESS_NONADMIN' -or
         -not([IO.File]::ReadAllText($logFile).Contains('R080_TEST_ONLY'))){
        throw 'R080_ISOLATED_USER_STATUS_CONTENT_WRONG'
      }
      'R080_ISOLATED_NORMAL_USER_LOG_AND_RESULT_PERSIST=PASS'
    }finally{
      if(Test-Path -LiteralPath $fixture){
        # Narrow owner-known fixture cleanup; never use the user AppRoot.
        [IO.Directory]::Delete($fixture,$true)
      }
    }
   }
  }finally{
  if($client){
   if(!$client.HasExited){try{$client.Kill();$client.WaitForExit(3000)|Out-Null}catch{}}
   $client.Dispose()
  }
  $receiver.Dispose()
 }
}
Verify-One 'valid'
Verify-One 'wrong_nonce'
Verify-One 'wrong_expected_pid'

# R080+R305: verify the ACTUAL protected-source receiver DACL at OS level.
# R305 refuses runas as a different administrator SID before sensor mutation.
$own=[Activator]::CreateInstance($receiverType,$true)
try{
    $pipeField=$receiverType.GetField('stream',
                         [Reflection.BindingFlags]'Instance,NonPublic')
    if(!$pipeField){throw 'R080_CURRENT_RECEIVER_PIPE_FIELD_MISSING'}
    $stream=[IO.Pipes.NamedPipeServerStream]$pipeField.GetValue($own)
    $aclRules=@($stream.GetAccessControl().GetAccessRules($true,$false,
                                  [Security.Principal.SecurityIdentifier]))
    $actualSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if($aclRules.Count -ne 1 -or
       $aclRules[0].IdentityReference.Value -cne $actualSid -or
       $aclRules[0].AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or
       ($aclRules[0].PipeAccessRights -band [IO.Pipes.PipeAccessRights]::FullControl) -ne
                            [IO.Pipes.PipeAccessRights]::FullControl){
        throw 'R080_BROAD_AUTHENTICATED_USER_DACL_REINTRODUCED'
    }
    'R080_EXACT_SID_ONLY_DACL_NO_ANY_AUTH_USERS=PASS'
}finally{$own.Dispose()}

# R304 long-profile security compatibility: use exactly the live six-arg
# pipe/nonce builder, NOT the backward-compatibility fixture overload.
$buildWithPipe=$t.GetMethod('BuildElevatedHelperCommandWithPipe',
                  [Reflection.BindingFlags]'NonPublic,Static')
$buildStartInfo=$t.GetMethod('BuildElevatedSensorProcessInfoWithPipe',
                  [Reflection.BindingFlags]'NonPublic,Static')
if(!$buildWithPipe -or !$buildStartInfo){
    throw 'R080_R304_COMPILED_LIVE_FACTORY_MISSING'
}
$probePipe='tbme_sensor_'+('a'*32)
$probeNonce='b'*32
$probeUser='EXAMPLE\fixture'
$probePayload='C:\Users\fixture\AppData\Local\Temp\tbme_setup_'+('a'*32)
$probeRoot='C:\Users\fixture\AppData\Local\TaskbarMonitorEnhanced'
function Build-Transport([string]$payload,[string]$app,[string]$user){
    $v=[object[]]@([string]'Install',[string]$payload,[string]$app,
                   [string]$user,[string]$probePipe,[string]$probeNonce)
    return [string]$buildWithPipe.Invoke($null,$v)
}
function Source-FromArguments([string]$cmdline) {
    $enc='-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand '
    $raw='-NoProfile -NonInteractive -WindowStyle Hidden -Command '
    if($cmdline.StartsWith($enc,[StringComparison]::Ordinal) -and
       $cmdline.Length -le 32080){
        return [Text.Encoding]::Unicode.GetString(
            [Convert]::FromBase64String($cmdline.Substring($enc.Length)))
    }
    if($cmdline.StartsWith($raw,[StringComparison]::Ordinal) -and
       $cmdline.Length -le 30000 -and
       $cmdline.EndsWith(' }"',[StringComparison]::Ordinal)){
        return $cmdline.Substring($raw.Length)
    }
    throw 'R080_R304_UNSAFE_HELPER_COMMAND_FORMAT_OR_SIZE'
}
$short=Build-Transport $probePayload $probeRoot $probeUser
$shortSource=Source-FromArguments $short
$longProfile='C:\Users\'+('Q'*128)
$longPayload=$longProfile+'\AppData\Local\Temp\tbme_setup_'+('b'*32)
$longApp=$longProfile+'\AppData\Local\TaskbarMonitorEnhanced'
$long=Build-Transport $longPayload $longApp $probeUser
$longSource=Source-FromArguments $long
if(-not $long.StartsWith('-NoProfile -NonInteractive -WindowStyle Hidden -Command ',
                         [StringComparison]::Ordinal) -or
   $short.Contains($probePayload) -or $short.Contains($probeRoot) -or
   $long.Contains($longPayload) -or $long.Contains($longApp) -or
   $short.Contains(' -File ') -or $long.Contains(' -File ')){
    throw 'R080_R304_LONG_PROFILE_OR_SHORT_RAW_USER_ARGS'
}
$blobPattern='(?m)^\$blob=\[Convert\]::FromBase64String\(''([A-Za-z0-9+/=]+)''\)'
$shortBlob=[regex]::Match($shortSource,$blobPattern)
$longBlob=[regex]::Match($longSource,$blobPattern)
if(-not $shortBlob.Success -or -not $longBlob.Success -or
   $shortBlob.Groups[1].Value -cne $longBlob.Groups[1].Value -or
   -not $longSource.Contains('[ScriptBlock]::Create($code)')){
    throw 'R080_R304_PEBLOB_PROVENANCE_CHANGED'
}
$sentinel='R080_QA_DO_NOT_EXECUTE_THIS_SENTINEL'
$hostile=$longPayload+"'; [IO.File]::WriteAllText('"+$sentinel+"','X'); #"
$attack=Build-Transport $hostile $longApp $probeUser
$attackCode=Source-FromArguments $attack
if($attack.Contains($sentinel) -or $attack.Contains($hostile) -or
   -not $attackCode.Contains('[ScriptBlock]::Create($code)')){
    throw 'R080_R304_INPUT_TOKENS_NOT_OPAQUE'
}
$oversizeRejected=$false
try{$null=Build-Transport ('X'*4100) $probeRoot $probeUser}
catch{
    $ex=$_.Exception
    while($ex.InnerException){$ex=$ex.InnerException}
    if($ex -is [IO.InvalidDataException]){$oversizeRejected=$true}else{throw}
}
if(!$oversizeRejected){throw 'R080_R304_PARAMETER_LENGTH_GUARD_MISSING'}
$plan=[Diagnostics.ProcessStartInfo]$buildStartInfo.Invoke($null,
  ([object[]]@([string]'Install',[string]$probePayload,[string]$probeRoot,
              [string]$probeUser,[string]$probePipe,[string]$probeNonce)))
if(-not $plan.UseShellExecute -or $plan.Verb -cne 'runas' -or
   -not [IO.Path]::IsPathRooted($plan.FileName) -or
   -not [IO.File]::Exists($plan.FileName)){
    throw 'R080_R304_PINNED_NATIVE_RUNAS_PROCESS_PLAN_CHANGED'
}
'R080_R304_SHORT_OR_LONG_TRUSTED_INMEMORY_PEBLOB=PASS'
'R080_R304_HOSTILE_PATH_OPAQUE_AND_LENGTH_LIMIT=PASS'
'R080_NATIVE_PRODUCTION_RUNAS_PLAN_INSPECTED_NOT_STARTED=PASS'
'R080_REAL_INSTALLED_APP_ROOT_NOT_MUTATED_BY_TEST=TRUE'
'R080_OS_UAC_OR_SETUP_INSTALL_RUN=FALSE'
'R080_REAL_HELPER_SOURCE_SHA256='+((Get-FileHash $helper -Algorithm SHA256).Hash)