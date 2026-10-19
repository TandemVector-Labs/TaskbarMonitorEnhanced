[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
    [Parameter(Mandatory=$true)][string]$CandidateDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# Native, disposable Windows guest only; never invoke the real UAC boundary.
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    throw 'R298_ONLY_DISPOSABLE_GITHUB_WINDOWS'
}
function SHA([string]$p){
    if(-not (Test-Path -LiteralPath $p -PathType Leaf)){return 'MISSING'}
    return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
}
$root=Join-Path $env:RUNNER_TEMP ('R298_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $root 'R298_EXPLICIT_POWERSHELL_HOST_RECEIPT.json'
$fake=Join-Path $root 'attacker-current-directory'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$main=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$prior=Join-Path $env:RUNNER_TEMP ('R297_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R297_PAWN_REFUSAL_RECEIPT.json')
$checks=[Collections.Generic.List[string]]::new()
$accepted=$false
$previousPath=[Environment]::GetEnvironmentVariable('PATH','Process')
$previousCwd=[Environment]::CurrentDirectory
$mainBefore=SHA $main
if(Test-Path -LiteralPath $root){throw 'R298_TEST_FIXTURE_COLLISION'}
[void][IO.Directory]::CreateDirectory($root)
try{
    $identity=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
    $old=Get-Content -LiteralPath $prior -Raw|ConvertFrom-Json
    if($identity.Commit -cne $env:GITHUB_SHA -or
       $identity.SetupSHA256 -cne (SHA $setup) -or
       $identity.MainSHA256 -cne $mainBefore -or
       $old.SourceCommit -cne $env:GITHUB_SHA -or
       $old.Host -cne $HostLabel -or
       $old.Status -cne 'PASS_NO_UNTRUSTED_PAWNIO_AUTORUN'){
       throw 'R298_EXACT_SOURCE_OR_PRIOR_NATIVE_PROOF_NOT_PINNED'
    }
    $assembly=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
    $type=$assembly.GetType('SetupProgram',$true)
    $method=$type.GetMethod('BuildElevatedSensorProcessInfoWithPipe',[Reflection.BindingFlags]'NonPublic,Static')
    $resolver=$type.GetMethod('TrustedSystemPowerShellPath',[Reflection.BindingFlags]'NonPublic,Static')
    if(!$method -or !$resolver){throw 'R298_TESTABLE_ELEVATION_INFO_FACTORY_MISSING'}
    $system=[IO.Path]::GetFullPath([Environment]::SystemDirectory)
    $expected=[IO.Path]::Combine($system,'WindowsPowerShell','v1.0','powershell.exe')
    if(-not [IO.File]::Exists($expected)){throw 'R298_SYSTEM_POWERSHELL_MISSING'}
    $real=[string]$resolver.Invoke($null,$null)
    if(-not [IO.Path]::IsPathRooted($real) -or
       -not [string]::Equals($real,$expected,[StringComparison]::OrdinalIgnoreCase)){
       throw 'R298_SYSTEM_HOST_NOT_EXACT_ABSOLUTE_NATIVE_PATH'
    }
    $checks.Add('NATIVE_SYSTEM_POWERSHELL_HOST_ABSOLUTELY_PINNED')
    foreach($segment in @($system,
        [IO.Path]::Combine($system,'WindowsPowerShell'),
        [IO.Path]::Combine($system,'WindowsPowerShell','v1.0'),
        $expected)){
        if((([IO.File]::GetAttributes($segment)) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw 'R298_NATIVE_HOST_PATH_IS_REPARSE'
        }
    }
    $checks.Add('NATIVE_HOST_PATH_SEGMENTS_NOT_REPARSE')
    $args4=[object[]]::new(6)
    $args4[0]=[string]'Install'
    $args4[1]=[string]([IO.Path]::Combine($env:RUNNER_TEMP,('tbme_setup_'+('a'*32))))
    $args4[2]=[string]$app
    $args4[3]=[string]([Security.Principal.WindowsIdentity]::GetCurrent().Name)
    $args4[4]=[string]('tbme_sensor_'+('a'*32))
    $args4[5]=[string]('b'*32)
    $info=[Diagnostics.ProcessStartInfo]$method.Invoke($null,$args4)
    if(-not [string]::Equals($info.FileName,$expected,[StringComparison]::OrdinalIgnoreCase) -or
       -not [string]::Equals($info.WorkingDirectory,([IO.Path]::GetDirectoryName($expected)),[StringComparison]::OrdinalIgnoreCase)){
       throw 'R298_RUNAS_PROCESS_INFO_POINTS_OUTSIDE_SYSTEM_HOST'
    }
    $checks.Add('REAL_RUNAS_PROCESS_INFO_PINNED_TO_TRUSTED_SYSTEM_EXE_AND_WORKDIR')
    if($info.UseShellExecute -ne $true -or $info.Verb -cne 'runas'){
        throw 'R298_ELEVATION_VERB_BEHAVIOR_CHANGED'
    }
    $checks.Add('ORIGINAL_UAC_RUNAS_SHELL_CONTRACT_PRESERVED')
    $prefix='-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand '
    $inlinePrefix='-NoProfile -NonInteractive -WindowStyle Hidden -Command '
    function Checked-Bootstrap([string]$arguments){
      if($arguments.Contains(' -File ') -or $arguments.Contains('ExecutionPolicy Bypass')){
          throw 'R298_USER_WRITABLE_POWERSHELL_SCRIPT_NOT_ALLOWED'
      }
      if($arguments.StartsWith($prefix,[StringComparison]::Ordinal) -and
         $arguments.Length -le 32080){
          return [Text.Encoding]::Unicode.GetString(
              [Convert]::FromBase64String($arguments.Substring($prefix.Length)))
      }
      if($arguments.StartsWith($inlinePrefix,[StringComparison]::Ordinal) -and
         $arguments.Length -le 30000 -and
         $arguments.EndsWith(' }"',[StringComparison]::Ordinal)){
          return $arguments.Substring($inlinePrefix.Length)
      }
      throw 'R298_POWER_SHELL_SCRIPT_ENTRY_WAS_WEAKENED'
    }
    $bootstrap=Checked-Bootstrap $info.Arguments
    if($bootstrap.Contains([string]$args4[1]) -or
       $bootstrap.Contains([string]$args4[2]) -or
       -not $bootstrap.Contains('[ScriptBlock]::Create($code)') -or
       -not $bootstrap.Contains('-StatusPipe $q -StatusNonce $n')){
       throw 'R298_SOURCE_OR_IPC_NOT_PE_PINNED'
    }
    $checks.Add('TRUSTED_INMEMORY_COMMAND_NO_TEMP_SCRIPT')
    $originalEncoded=$info.Arguments
    [void][IO.Directory]::CreateDirectory($fake)
    $rogue=Join-Path $fake 'powershell.exe'
    [IO.File]::WriteAllBytes($rogue,[byte[]]@(77,90,1,2,3,4,5,6,7,8))
    $beforeFake=SHA $rogue
    $checks.Add('ATTACKER_NAMED_EXECUTABLE_FIXTURE_PRESENT')
    # Only modify this test process, never user/system PATH. Do not start runas.
    [Environment]::CurrentDirectory=$fake
    [Environment]::SetEnvironmentVariable('PATH',($fake+';'+$previousPath),'Process')
    $fakeResolved=[string]$resolver.Invoke($null,$null)
    $tamper=[Diagnostics.ProcessStartInfo]$method.Invoke($null,$args4)
    if(-not [string]::Equals($fakeResolved,$expected,[StringComparison]::OrdinalIgnoreCase) -or
       -not [string]::Equals($tamper.FileName,$expected,[StringComparison]::OrdinalIgnoreCase) -or
       -not [string]::Equals($tamper.WorkingDirectory,$info.WorkingDirectory,[StringComparison]::OrdinalIgnoreCase)){
       throw 'R298_ATTACKER_CWD_OR_PATH_REDIRECTED_RUNAS_TARGET'
    }
    $checks.Add('FAKE_CWD_AND_PATH_POWERSHELL_IGNORED')
    if($tamper.Arguments -cne $originalEncoded -or $tamper.Verb -cne 'runas' -or
       $tamper.UseShellExecute -ne $true){
       throw 'R298_ARGUMENTS_OR_UAC_VERB_CHANGED_BY_ATTACKER_SEARCH_PATH'
    }
    $checks.Add('INMEMORY_ARGUMENTS_UNCHANGED_DURING_PATH_POISONING')
    if((SHA $rogue) -cne $beforeFake){throw 'R298_FAKE_POWERSHELL_EXECUTED_OR_MODIFIED'}
    $checks.Add('ATTACKER_FAKE_EXECUTABLE_UNCHANGED_NOT_EXECUTED')
    $args4[0]=[string]'Uninstall'
    $uninstall=[Diagnostics.ProcessStartInfo]$method.Invoke($null,$args4)
    $uninstallSource=Checked-Bootstrap $uninstall.Arguments
    if(-not [string]::Equals($uninstall.FileName,$expected,[StringComparison]::OrdinalIgnoreCase) -or
       -not $uninstall.UseShellExecute -or $uninstall.Verb -cne 'runas' -or
       $uninstallSource -cnotmatch "\-Mode 'Uninstall'" -or
       -not $uninstallSource.Contains('[ScriptBlock]::Create($code)') -or
       -not $uninstallSource.Contains('-StatusPipe $q -StatusNonce $n')){
        throw 'R298_UNINSTALL_MODE_OR_HOST_NOT_PINNED'
    }
    $checks.Add('UNINSTALL_MODE_USES_SAME_ABSOLUTE_TRUSTED_HOST')
    if((SHA $main) -cne $mainBefore){throw 'R298_GUEST_MAIN_WAS_CHANGED'}
    $checks.Add('EXISTING_GUEST_MAIN_UNCHANGED')
    $checks.Add('NO_UAC_OR_PROTECTED_SERVICE_MUTATION')
    $data=[ordered]@{
       Schema=1;Revision='R298';Status='PASS_ABSOLUTE_SYSTEM_POWERSHELL_RUNAS_HOST'
       Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
       OriginalOwnerComputerTouched=$false;UACOrProtectedServiceInvoked=$false
       AbsoluteHostMatchesSystemDirectory=$true
       FakeCwdAndPathExecutableIgnored=$true
       BothModesPinned=$true;NoUntrustedScriptFile=$true
       InstalledMainUnchanged=$true;Checks=@($checks)
       RecordedUtc=[DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText($receipt,($data|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    $accepted=$true
    'R298_NATIVE_'+$HostLabel+'_PINNED_SYSTEM_RUNAS_HOST_PASS'
}finally{
    [Environment]::SetEnvironmentVariable('PATH',$previousPath,'Process')
    [Environment]::CurrentDirectory=$previousCwd
    if(-not $accepted){
        $failure=[ordered]@{
         Schema=1;Revision='R298';Status='FAIL_NOT_ACCEPTED'
         Host=$HostLabel;SourceCommit=$env:GITHUB_SHA;OwnerUntouched=$true
        }
        [IO.File]::WriteAllText($receipt,($failure|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
    }
}
