[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
    [Parameter(Mandatory=$true)][string]$CandidateDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# R293: only disposable GitHub-hosted Windows, never the owner's installation.
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    throw 'R293_ONLY_DISPOSABLE_GITHUB_WINDOWS'
}
function Hash([string]$p){
    if(!(Test-Path -LiteralPath $p -PathType Leaf)){return 'MISSING'}
    return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
}
$dir=Join-Path $env:RUNNER_TEMP ('R293_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$report=Join-Path $dir 'R293_INMEMORY_RECEIPT.json'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$live=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$prior=Join-Path $env:RUNNER_TEMP ('R291_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R291_BOUNDARY_RECEIPT.json')
$payload=Join-Path ([IO.Path]::GetTempPath()) ('tbme_setup_'+[guid]::NewGuid().ToString('N'))
$rogue=Join-Path $payload 'TBME_Setup_Elevated_Helper.ps1'
$sentinel=Join-Path $dir 'ROGUE_EXECUTED'
$user=[string]([Security.Principal.WindowsIdentity]::GetCurrent().Name)
$accepted=$false
$checks=[Collections.Generic.List[string]]::new()
if((Test-Path $dir) -or (Test-Path $payload) -or (Test-Path $sentinel)){
    throw 'R293_PREEXISTING_GUEST_FIXTURE_REFUSED'
}
[void][IO.Directory]::CreateDirectory($dir)
$mainBefore=Hash $live
try{
    $identity=Get-Content $manifest -Raw |ConvertFrom-Json
    $r291=Get-Content $prior -Raw |ConvertFrom-Json
    if($identity.Commit -cne $env:GITHUB_SHA -or
       (Hash $setup) -cne $identity.SetupSHA256 -or
       (Hash $live) -cne $identity.MainSHA256 -or
       $r291.Status -cne 'PASS_PRIVILEGED_HELPER_BOUNDARY_NATIVE' -or
       $r291.SourceCommit -cne $env:GITHUB_SHA -or $r291.Host -cne $HostLabel){
        throw 'R293_EXACT_CANDIDATE_OR_PRIOR_NATIVE_HOST_UNPINNED'
    }
    $assembly=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
    $type=$assembly.GetType('SetupProgram',$true)
    $m=$type.GetMethod('BuildElevatedHelperCommandWithPipe',[Reflection.BindingFlags]'NonPublic,Static')
    if(!$m){throw 'R293_SETUP_HAS_NO_INMEMORY_ELEVATION_BUILDER'}
    $args4=[object[]]::new(6)
    $args4[0]=[string]'Install'
    $args4[1]=[string]$payload
    # Known bad AppRoot: real trusted Helper must refuse before any filesystem mutation.
    $args4[2]=[string](Join-Path $env:WINDIR 'R293_Refuse_Outside_User_AppRoot')
    $args4[3]=[string]$user
    $args4[4]=[string]('tbme_sensor_'+('a'*32))
    $args4[5]=[string]('b'*32)
    $cmd=[string]$m.Invoke($null,$args4)
    $prefix='-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand '
    $inlinePrefix='-NoProfile -NonInteractive -WindowStyle Hidden -Command '
    $usesEncoded=$cmd.StartsWith($prefix,[StringComparison]::Ordinal)
    $usesInline=$cmd.StartsWith($inlinePrefix,[StringComparison]::Ordinal)
    if((!$usesEncoded -and !$usesInline) -or
       $cmd.Contains(' -File ') -or $cmd.Contains('ExecutionPolicy Bypass') -or
       ($usesEncoded -and $cmd.Length -gt 32080) -or
       ($usesInline -and $cmd.Length -gt 30000) -or
       $cmd.Contains($args4[1]) -or $cmd.Contains($args4[2])){
        throw 'R293_ELEVATION_COMMAND_USES_UNTRUSTED_FILE_PATH'
    }
    $encoded=if($usesEncoded){$cmd.Substring($prefix.Length)}else{''}
    if($usesEncoded -and ($encoded.Length -lt 1000 -or $encoded.Length -gt 32000)){
        throw 'R293_ENCODED_COMMAND_LENGTH_OUT_OF_BOUNDS'
    }
    $script=if($usesEncoded){
        [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))
    }else{$cmd.Substring($inlinePrefix.Length)}
    if(-not $script.Contains('[ScriptBlock]::Create($code)') -or
       $script.Contains(' -File ') -or
       -not $script.Contains('-StatusPipe $q -StatusNonce $n')){
        throw 'R293_DECODED_COMMAND_DOES_NOT_RUN_TRUSTED_IPC_SOURCE'
    }
    $checks.Add('NO_USER_WRITABLE_POWERSHELL_FILE_ENTRYPOINT')
    $re=[regex]::Match($script,'(?m)^\$blob=\[Convert\]::FromBase64String\(''([a-zA-Z0-9+/=]+)''\)')
    if(!$re.Success){throw 'R293_MISSING_TRUSTED_COMPRESSED_SOURCE'}
    $memory=[IO.MemoryStream]::new([Convert]::FromBase64String($re.Groups[1].Value))
    $zip=[IO.Compression.GZipStream]::new($memory,[IO.Compression.CompressionMode]::Decompress)
    $reader=[IO.StreamReader]::new($zip,[Text.Encoding]::UTF8)
    try{$code=$reader.ReadToEnd()}finally{$reader.Dispose();$zip.Dispose();$memory.Dispose()}
    $resource=$assembly.GetManifestResourceStream('Payload.TBME_Setup_Elevated_Helper.ps1')
    if(!$resource){throw 'R293_MISSING_SETUP_RESOURCE'}
    $textReader=[IO.StreamReader]::new($resource,[Text.Encoding]::UTF8)
    try{$source=$textReader.ReadToEnd()}finally{$textReader.Dispose()}
    # R295 transports a comment/indentation-compacted representation of the
    # exact source PE resource, not an independently writable source file.
    $compactor=$type.GetMethod('CompactTrustedHelperSource',[Reflection.BindingFlags]'NonPublic,Static')
    if(!$compactor){throw 'R295_TRUSTED_SOURCE_COMPACTOR_MISSING'}
    $expected=[string]$compactor.Invoke($null,([object[]]@([string]$source)))
    if($code -cne $expected){
        throw 'R295_PACKED_SOURCE_DIFFERS_FROM_COMPACTED_SETUP_RESOURCE'
    }
    $checks.Add('DECOMPRESSED_RESOURCE_EXACT_TO_COMPACTED_SETUP')
    if(@($script|Select-String -Pattern ([regex]::Escape($args4[2]))).Count){
        throw 'R293_UNTRUSTED_PATH_EMBEDDED_AS_RAW_SCRIPT_LITERAL'
    }
    $checks.Add('ALL_USER_PARAMETERS_ENCODED_AS_DATA')
    [void][IO.Directory]::CreateDirectory($payload)
    # This file was the previous vulnerable UAC execution entrypoint.
    # It is deliberately attacker-like, but owned only by this temporary fixture.
    $poison=[string]'Write-Output "R293_ROGUE_SCRIPT_EXECUTED"'
    [IO.File]::WriteAllText($rogue,$poison,[Text.UTF8Encoding]::new($false))
    $rogueBefore=Hash $rogue
    # No UAC: execute only invalid-Root probe on the disposable runner.
    $psi=[Diagnostics.ProcessStartInfo]::new()
    $psi.FileName='powershell.exe'
    $psi.Arguments=$cmd
    $psi.UseShellExecute=$false
    $psi.CreateNoWindow=$true
    $psi.RedirectStandardOutput=$true
    $psi.RedirectStandardError=$true
    $proc=[Diagnostics.Process]::Start($psi)
    if(!$proc){throw 'R293_BOUNDED_NON_ELEVATED_PROCESS_NOT_CREATED'}
    try{
        # Drain both redirected pipes concurrently so even verbose error output
        # cannot block the child before WaitForExit sees the bounded refusal.
        $outTask=$proc.StandardOutput.ReadToEndAsync()
        $errTask=$proc.StandardError.ReadToEndAsync()
        if(-not $proc.WaitForExit(20000)){
            try{$proc.Kill()}catch{}
            throw 'R293_INMEMORY_HELPER_TEST_TIMEOUT'
        }
        $out=$outTask.GetAwaiter().GetResult()
        $err=$errTask.GetAwaiter().GetResult()
        $exitCode=$proc.ExitCode
    }finally{$proc.Dispose()}
    if($exitCode -eq 0 -or
       ($out+$err) -notmatch 'SENSOR_BOUNDARY_APP_ROOT_OUTSIDE_USER_PROFILE'){
       throw ('R293_EXPECTED_PREWRITE_REFUSAL_NOT_OBSERVED_EXIT_'+$exitCode)
    }
    if($out -match 'R293_ROGUE_SCRIPT_EXECUTED' -or
       $err -match 'R293_ROGUE_SCRIPT_EXECUTED' -or
       (Hash $rogue) -cne $rogueBefore -or
       (Test-Path $sentinel)){
       throw 'R293_USER_WRITABLE_ROGUE_SCRIPT_EXECUTED_OR_CHANGED'
    }
    $checks.Add('REAL_POWERSHELL_51_INLINE_PREWRITE_REFUSAL')
    $checks.Add('ROGUE_WRITABLE_HELPER_IGNORED')
    # R293B: an adversarial account argument contains literal PowerShell tokens.
    # It must be data in the inline command, never executed as PowerShell code.
    $evilUser=$user+"'; [IO.File]::WriteAllText('"+$sentinel+"','R293_INJECTION'); #"
    $args4[3]=[string]$evilUser
    $evilCmd=[string]$m.Invoke($null,$args4)
    if($evilCmd.StartsWith($prefix,[StringComparison]::Ordinal)){
        $evilBootstrap=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($evilCmd.Substring($prefix.Length)))
    }else{
        # R305-F01: the added prewrite SID guard grows the trusted helper.
        # An adversarial longer user input now legitimately selects R304's
        # bounded inline -Command instead of UTF16 -EncodedCommand.
        # The exact trusted PE blob, no writable -File and Base64-only user
        # arguments are mandatory in EITHER supported transport.
        $inlinePrefix='-NoProfile -NonInteractive -WindowStyle Hidden -Command '
        if(-not $evilCmd.StartsWith($inlinePrefix,[StringComparison]::Ordinal) -or
           $evilCmd.Length -gt 30000 -or
           $evilCmd.Contains(' -File ') -or
           $evilCmd.Contains('ExecutionPolicy Bypass')){
            throw 'R293_INJECTED_COMMAND_UNSAFE_OR_UNBOUNDED'
        }
        $evilBootstrap=$evilCmd.Substring($inlinePrefix.Length)
        if(-not $evilBootstrap.Contains($re.Groups[1].Value) -or
           -not $evilBootstrap.Contains('[ScriptBlock]::Create($code)')){
            throw 'R293_LONG_FALLBACK_SOURCE_NOT_PINNED_TO_SAME_PE_RESOURCE'
        }
    }
    if($evilBootstrap.Contains($evilUser) -or $evilBootstrap.Contains($sentinel)){
       throw 'R293_CALLER_ARGUMENT_WAS_INTERPOLATED_AS_SCRIPT_SOURCE'
    }
    $checks.Add('QUOTED_HOSTILE_USER_INPUT_ENCODED_AS_DATA')
    $evilProcess=[Diagnostics.ProcessStartInfo]::new()
    $evilProcess.FileName='powershell.exe'
    $evilProcess.Arguments=$evilCmd
    $evilProcess.UseShellExecute=$false
    $evilProcess.CreateNoWindow=$true
    $evilProcess.RedirectStandardOutput=$true
    $evilProcess.RedirectStandardError=$true
    $evil=[Diagnostics.Process]::Start($evilProcess)
    if(!$evil){throw 'R293_HOSTILE_INJECTION_PROBE_PROCESS_MISSING'}
    try{
        $evilStdout=$evil.StandardOutput.ReadToEndAsync()
        $evilStderr=$evil.StandardError.ReadToEndAsync()
        if(-not $evil.WaitForExit(20000)){
            try{$evil.Kill()}catch{}
            throw 'R293_INJECTED_COMMAND_PROCESS_TIMEOUT'
        }
        $evilOut=$evilStdout.GetAwaiter().GetResult()
        $evilErr=$evilStderr.GetAwaiter().GetResult()
        $evilExit=$evil.ExitCode
    }finally{$evil.Dispose()}
    if($evilExit -eq 0 -or
       ($evilOut+$evilErr) -notmatch 'SENSOR_BOUNDARY_USER_ID_UNRESOLVABLE' -or
       (Test-Path -LiteralPath $sentinel) -or
       (Hash $rogue) -cne $rogueBefore){
        throw 'R293_COMMAND_INJECTION_NEGATIVE_PROBE_NOT_FAIL_CLOSED'
    }
    $checks.Add('COMMAND_LINE_INJECTION_SENTINEL_NOT_EXECUTED')
    $checks.Add('NO_UAC_PROTECTED_SERVICE_MUTATION')
    if((Hash $live) -cne $mainBefore){
        throw 'R293_GUEST_INSTALLED_MAIN_CHANGED'
    }
    $checks.Add('INSTALLED_MAIN_AND_ROGUE_FILE_PRESERVED')
    $receipt=[ordered]@{
        Schema=1;Revision='R293'
        Status='PASS_NO_TEMP_SCRIPT_ELEVATION_INLINE_TRUSTED_SOURCE'
        Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
        OriginalOwnerComputerTouched=$false
        UACOrProtectedServiceCalled=$false
        ExactTrustedHelperSource=$true
        MaliciousTempScriptIgnored=$true
        RealNonElevatedEncodedPowerShellCalled=$usesEncoded
        RealNonElevatedInlinePowerShellCalled=$usesInline
        InvalidAppRootRejectedBeforeWrite=$true
        InstalledMainUnchanged=$true
        BoundedEncodedCommandLength=$encoded.Length
        BoundedInMemoryCommandLength=$cmd.Length
        Checks=@($checks)
        RecordedUtc=[DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText($report,($receipt|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    $accepted=$true
    'R293_NATIVE_'+$HostLabel+'_TRUSTED_ELEVATION_CODE=PASS'
}finally{
    if(Test-Path -LiteralPath $payload){
        try{[IO.Directory]::Delete($payload,$true)}catch{}
    }
    if(!$accepted){
        $fail=[ordered]@{
            Schema=1;Revision='R293';Status='FAIL_NOT_ACCEPTED'
            Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
            OwnerComputerUntouched=$true
            RecordedUtc=[DateTime]::UtcNow.ToString('o')
        }
        [IO.File]::WriteAllText($report,($fail|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
    }
}
