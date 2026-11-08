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
    throw 'R294_ONLY_GITHUB_DISPOSABLE_WINDOWS'
}
function Hash([string]$Path){
    if(!(Test-Path -LiteralPath $Path -PathType Leaf)){return 'MISSING'}
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}
$root=Join-Path $env:RUNNER_TEMP ('R294_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$report=Join-Path $root 'R294_PROVENANCE_RECEIPT.json'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$main=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$prior=Join-Path $env:RUNNER_TEMP ('R293_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R293_INMEMORY_RECEIPT.json')
$accepted=$false
$check=[Collections.Generic.List[string]]::new()
if(Test-Path $root){throw 'R294_GUEST_FIXTURE_ALREADY_PRESENT'}
[void][IO.Directory]::CreateDirectory($root)
$mainBefore=Hash $main
try{
    $info=Get-Content $manifest -Raw|ConvertFrom-Json
    $receipt=Get-Content $prior -Raw|ConvertFrom-Json
    if($info.Commit -cne $env:GITHUB_SHA -or $info.SetupSHA256 -cne (Hash $setup) -or
       $info.MainSHA256 -cne $mainBefore -or
       $receipt.SourceCommit -cne $env:GITHUB_SHA -or $receipt.Host -cne $HostLabel -or
       $receipt.Status -cne 'PASS_NO_TEMP_SCRIPT_ELEVATION_INLINE_TRUSTED_SOURCE'){
        throw 'R294_EXACT_GUEST_BASELINE_OR_SOURCE_NOT_PINNED'
    }
    $assembly=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
    $type=$assembly.GetType('SetupProgram',$true)
    $m=$type.GetMethod('BuildElevatedHelperCommand',[Reflection.BindingFlags]'NonPublic,Static')
    if(!$m){throw 'R294_EXPECTED_COMMAND_BUILDER_MISSING'}
    $args4=[object[]]::new(4)
    $args4[0]=[string]'Install'
    $args4[1]=[string](Join-Path ([IO.Path]::GetTempPath()) ('tbme_setup_'+('a'*32)))
    $args4[2]=[string]$app
    $args4[3]=[string]([Security.Principal.WindowsIdentity]::GetCurrent().Name)
    $command=[string]$m.Invoke($null,$args4)
    $encodedPrefix='-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand '
    $inlinePrefix='-NoProfile -NonInteractive -WindowStyle Hidden -Command '
    $encoded=$command.StartsWith($encodedPrefix,[StringComparison]::Ordinal)
    $inline=$command.StartsWith($inlinePrefix,[StringComparison]::Ordinal)
    if((-not $encoded -and -not $inline) -or $command.Contains(' -File ') -or
       $command.Contains('ExecutionPolicy Bypass') -or
       ($encoded -and $command.Length -gt 32080) -or
       ($inline -and $command.Length -gt 30000)){
     throw 'SENSOR_TRUSTED_BOOTSTRAP_TRANSPORT_UNSAFE'
    }
    $bootstrap=if($encoded){
     [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($command.Substring($encodedPrefix.Length)))
    }else{$command.Substring($inlinePrefix.Length)}
    $match=[regex]::Match($bootstrap,"-ExpectedBrokerSHA256 '([A-F0-9]{64})' -ExpectedSupervisorSHA256 '([A-F0-9]{64})'")
    if(!$match.Success){throw 'R294_TRUSTED_EMBEDDED_HASHES_NOT_TRANSPORTED'}
    $check.Add('RESOURCE_IDENTITY_PINNED_INSIDE_TRUSTED_IN_MEMORY_BOOTSTRAP')
    $helperPath=(Resolve-Path (Join-Path $PSScriptRoot '..\installer\TBME_Setup_Elevated_Helper.ps1')).Path
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($helperPath,[ref]$tokens,[ref]$errors)
    if(@($errors).Count){throw 'R294_HELPER_WINDOWS_POWERSHELL51_PARSE_FAILED'}
    $functions=@($ast.FindAll({param($node)
      $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -in @('Assert-SensorBoundaryNoReparse','Get-VerifiedSensorPayloadBytes')
    },$true))
    if($functions.Count -ne 2){throw 'R294_EXPECTED_TWO_PURE_FUNCTIONS'}
    . ([scriptblock]::Create(($functions|ForEach-Object{$_.Extent.Text}) -join [Environment]::NewLine))
    foreach($kind in @(
      @{Name='Broker';Resource='Payload.TaskbarMonitorSensorBroker.exe';Expected=$match.Groups[1].Value},
      @{Name='Supervisor';Resource='Payload.TaskbarMonitorSensorSupervisor.exe';Expected=$match.Groups[2].Value}
    )){
        $path=Join-Path $root ('TBME_R294_'+$kind.Name+'.exe')
        $stream=$assembly.GetManifestResourceStream($kind.Resource)
        if(!$stream){throw 'R294_EMBEDDED_EXECUTABLE_RESOURCE_MISSING'}
        $out=[IO.FileStream]::new($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$stream.CopyTo($out)}finally{$out.Dispose();$stream.Dispose()}
        if((Hash $path) -cne $kind.Expected){throw 'R294_EMBEDDED_RESOURCE_HASH_NOT_BOUND'}
        $verified=[byte[]](Get-VerifiedSensorPayloadBytes $path $kind.Expected 16777216)
        $verifiedSHA=[BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($verified)).Replace('-','')
        if($verifiedSHA -cne $kind.Expected){throw 'R294_VERIFIED_PAYLOAD_BYTES_ARE_DIFFERENT'}
        $check.Add($kind.Name.ToUpperInvariant()+'_SAME_VERIFIED_BYTES_AS_EMBEDDED')
        $installed=Join-Path $root ('TRUSTED_COPY_'+$kind.Name+'.exe')
        [IO.File]::WriteAllBytes($installed,$verified)
        if((Hash $installed) -cne $kind.Expected){throw 'R294_PROVENANCE_BUFFER_COULD_NOT_BE_INSTALLED'}
        $check.Add($kind.Name.ToUpperInvariant()+'_IN_MEMORY_COPY_IDENTITY')
        $rogue=[IO.File]::ReadAllBytes($path)
        $rogue[0]=$rogue[0] -bxor 0x01
        [IO.File]::WriteAllBytes($path,$rogue)
        $refused=$false
        try{$null=Get-VerifiedSensorPayloadBytes $path $kind.Expected 16777216}
        catch{if($_.Exception.Message -match 'SENSOR_PAYLOAD_EMBEDDED_SHA_MISMATCH'){$refused=$true}else{throw}}
        if(!$refused){throw 'R294_TAMPERED_SOURCE_WAS_ACCEPTED'}
        $check.Add($kind.Name.ToUpperInvariant()+'_TAMPERED_TEMP_BYTES_REJECTED')
        $locked=[IO.FileStream]::new($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
        try{
          $blocked=$false
          try{$null=Get-VerifiedSensorPayloadBytes $path $kind.Expected 16777216}
          catch [IO.IOException]{$blocked=$true}
          if(!$blocked){throw 'R294_EXCLUSIVE_SOURCE_LOCK_FAILED'}
        }finally{$locked.Dispose()}
        $check.Add($kind.Name.ToUpperInvariant()+'_CONCURRENT_ACCESS_BLOCKED')
    }
    if((Hash $main) -cne $mainBefore){throw 'R294_PROTECTED_MAIN_MUTATED'}
    $check.Add('EXTERNAL_GUEST_INSTALLED_MAIN_UNCHANGED')
    $record=[ordered]@{
      Schema=1;Revision='R294';Status='PASS_SHA_PINNED_EXCLUSIVE_SINGLE_READ_SENSOR_BINARIES'
      Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
      OriginalOwnerComputerTouched=$false;UACOrServiceMutation=$false
      ExpectedBrokerSHA256=$match.Groups[1].Value
      ExpectedSupervisorSHA256=$match.Groups[2].Value
      BothTamperedInputsRejected=$true;ExclusiveLockProved=$true
      VerifiedBuffersInstalledToSandboxOnly=$true;InstalledMainUnchanged=$true
      Checks=@($check);RecordedUtc=[DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText($report,($record|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    $accepted=$true
    'R294_GUEST_'+$HostLabel+'_EXCLUSIVE_EMBEDDED_BINARY_PROVENANCE_PASS'
}finally{
    if(!$accepted){
       $fail=[ordered]@{Schema=1;Revision='R294';Status='FAILED_NOT_ACCEPTED'
          Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
          OwnerComputerUntouched=$true;RecordedUtc=[DateTime]::UtcNow.ToString('o')}
       [IO.File]::WriteAllText($report,($fail|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
    }
}
