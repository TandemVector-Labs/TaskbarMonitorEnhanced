[CmdletBinding()]
param([string]$SetupPath='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($SetupPath)){
    $SetupPath=Join-Path $PSScriptRoot '_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   !(Test-Path -LiteralPath $SetupPath -PathType Leaf)){
    throw 'R327_COMPILED_NET_FRAMEWORK_SETUP_REQUIRED'
}
$setup=[Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath $SetupPath).Path)
$type=$setup.GetType('SetupProgram',$true)
$canonical=$type.GetMethod('CanonicalSensorTempFromKnownFolders',
    [Reflection.BindingFlags]'NonPublic,Static')
$create=$type.GetMethod('CreatePrivateSensorPayloadDirectory',
    [Reflection.BindingFlags]'NonPublic,Static')
if(!$canonical -or !$create){throw 'R327_EXACT_PE_MISSING_CANONICAL_PAYLOAD_METHODS'}
$checks=[Collections.Generic.List[string]]::new()
function Pass([string]$label){
    $script:checks.Add($label)
    Write-Output ('PASS '+$label)
}
function Invoke-Canonical([string]$local,[string]$profile){
    $args=New-Object 'object[]' 2
    $args[0]=[string]$local;$args[1]=[string]$profile
    return [string]$canonical.Invoke($null,$args)
}
function Expect-BoundaryRefusal([string]$label,[string]$local,[string]$profile){
    $actual=''
    try{
        $returned=Invoke-Canonical $local $profile
        throw ('R327_UNEXPECTEDLY_ACCEPTED_'+$label+' '+$returned)
    }catch{
        $failure=$_.Exception
        while($null -ne $failure.InnerException){$failure=$failure.InnerException}
        $actual=$failure.Message
    }
    if($actual -match '^R327_UNEXPECTEDLY_ACCEPTED_'){throw $actual}
    if($actual -notmatch '(?i)reparse|canonical|unavailable|outside|root|path'){
        throw ('R327_REJECTED_FOR_WRONG_REASON_'+$label+' '+$actual)
    }
    Pass $label
}
function Invoke-Create([string]$prefix){
    $args=New-Object 'object[]' 1
    $args[0]=[string]$prefix
    return [string]$create.Invoke($null,$args)
}
$source=[IO.File]::ReadAllText((Resolve-Path (Join-Path $PSScriptRoot '..\installer\TaskbarMonitorEnhanced_Setup.cs')).Path)
$resource=$setup.GetManifestResourceStream('Payload.TaskbarMonitorEnhanced_Setup.cs')
if(!$resource){throw 'R327_SOURCE_RESOURCE_MISSING'}
$reader=[IO.StreamReader]::new($resource)
try{$embeddedSource=$reader.ReadToEnd()}finally{$reader.Dispose()}
$normalize={param($x) $x.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
if((& $normalize $source) -cne (& $normalize $embeddedSource)){throw 'R327_PE_DOES_NOT_EMBED_THIS_SOURCE'}
Pass 'EXACT_COMPILED_PE_EMBEDS_SOURCE'

$profile=[Environment]::GetFolderPath('UserProfile')
$local=[Environment]::GetFolderPath('LocalApplicationData')
$expectedReal=[IO.Path]::GetFullPath((Join-Path $local 'Temp'))
$result=Invoke-Canonical $local $profile
if(![string]::Equals($result,$expectedReal,[StringComparison]::OrdinalIgnoreCase)){
    throw ('R327_ACTUAL_PROFILE_TEMP_MISMATCH_'+$result)
}
Pass 'REAL_OS_PROFILE_CANONICAL_TEMP'

$base=Join-Path ([IO.Path]::GetTempPath()) ('tbme_r327_sensor_temp_'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($base)
$created=@()
$originalTemp=$env:TEMP
$originalTmp=$env:TMP
try{
    $fakeProfile=Join-Path $base 'literal & special $profile'
    $fakeLocal=Join-Path $fakeProfile 'AppData\Local'
    [void][IO.Directory]::CreateDirectory($fakeLocal)
    $expected=Join-Path $fakeLocal 'Temp'
    $actual=Invoke-Canonical $fakeLocal $fakeProfile
    if(![string]::Equals($actual,$expected,[StringComparison]::OrdinalIgnoreCase)){
        throw 'R327_SYNTHETIC_PROFILE_NOT_CANONICAL'
    }
    Pass 'SYNTHETIC_PROFILE_WITH_METACHARACTERS'

    Expect-BoundaryRefusal 'MISMATCHED_LOCAL_PROFILE' (Join-Path $base 'wrong\AppData\Local') $fakeProfile
    Expect-BoundaryRefusal 'RELATIVE_KNOWN_LOCAL_REFUSED' 'AppData\Local' $fakeProfile
    Expect-BoundaryRefusal 'UNC_PROFILE_REFUSED' '\\attacker.invalid\share\AppData\Local' '\\attacker.invalid\share'
    $drive=[IO.Path]::GetPathRoot([IO.Path]::GetFullPath($base))
    Expect-BoundaryRefusal 'DRIVE_ROOT_ONLY_PROFILE_REFUSED' (Join-Path $drive 'AppData\Local') $drive

    $external=Join-Path $base 'external-canary-target'
    [void][IO.Directory]::CreateDirectory($external)
    $sentinel=Join-Path $external 'do_not_touch.txt'
    [IO.File]::WriteAllText($sentinel,'R327_UNTOUCHED')

    $link=Join-Path $fakeLocal 'Temp'
    New-Item -ItemType Junction -Path $link -Target $external -ErrorAction Stop|Out-Null
    try{
        Expect-BoundaryRefusal 'TEMP_JUNCTION_REFUSED' $fakeLocal $fakeProfile
        if([IO.File]::ReadAllText($sentinel) -cne 'R327_UNTOUCHED'){
            throw 'R327_FOREIGN_CONTENT_CHANGED_AFTER_TEMP_REFUSAL'
        }
    }finally{
        if([IO.Directory]::Exists($link)){[IO.Directory]::Delete($link)}
    }
    $otherProfile=Join-Path $base 'otherProfile'
    [void][IO.Directory]::CreateDirectory((Join-Path $otherProfile 'AppData'))
    $otherLocal=Join-Path $otherProfile 'AppData\Local'
    $link2=New-Item -ItemType Junction -Path $otherLocal -Target $external -ErrorAction Stop
    try{
        Expect-BoundaryRefusal 'LOCAL_JUNCTION_REFUSED' $otherLocal $otherProfile
        if([IO.File]::ReadAllText($sentinel) -cne 'R327_UNTOUCHED'){
            throw 'R327_FOREIGN_CONTENT_CHANGED_AFTER_LOCAL_REFUSAL'
        }
    }finally{
        if([IO.Directory]::Exists($otherLocal)){[IO.Directory]::Delete($otherLocal)}
    }

    $refused=$false
    try{$invalid=Invoke-Create 'arbitrary_'}catch{
        $failure=$_.Exception
        while($null -ne $failure.InnerException){$failure=$failure.InnerException}
        if($failure.Message -match 'Unexpected private sensor payload prefix'){
            $refused=$true
        }else{throw}
    }
    if(!$refused){throw 'R327_BAD_PAYLOAD_PREFIX_ACCEPTED'}
    Pass 'UNRECOGNIZED_PREFIX_REFUSED'

    $poison=Join-Path $base 'unrelated-env-TEMP'
    [void][IO.Directory]::CreateDirectory($poison)
    $env:TEMP=$poison
    $env:TMP=$poison
    foreach($prefix in @('tbme_setup_','tbme_uninstall_')){
        $payload=Invoke-Create $prefix
        if(![string]::Equals([IO.Path]::GetDirectoryName($payload),
                              $expectedReal,[StringComparison]::OrdinalIgnoreCase)){
            throw ('R327_TAINTED_TEMP_ENV_SELECTED_'+$payload)
        }
        if(![IO.Directory]::Exists($payload) -or
           [IO.Path]::GetFileName($payload) -cnotmatch ('^'+$prefix+'[0-9a-f]{32}$')){
            throw 'R327_NOT_A_RANDOM_PRIVATE_PAYLOAD'
        }
        if(@([IO.Directory]::GetFileSystemEntries($payload)).Count -ne 0){
            throw 'R327_GENERATED_PAYLOAD_NOT_EMPTY'
        }
        $created+=,$payload
        Pass ('RANDOM_'+$prefix+'PAYLOAD_UNDER_REAL_PROFILE')
    }
    if(@([IO.Directory]::GetFileSystemEntries($poison)).Count -ne 0){
        throw 'R327_ENV_POISON_DIRECTORY_TOUCHED'
    }
    Pass 'POISONED_TEMP_TMP_ENV_NOT_USED'

    if($source.Contains('Path.GetTempPath()') -or
       !$source.Contains('CreatePrivateSensorPayloadDirectory("tbme_setup_")') -or
       !$source.Contains('CreatePrivateSensorPayloadDirectory("tbme_uninstall_")')){
        throw 'R327_INSTALL_OR_UNINSTALL_BYPASSES_CANONICAL_PAYLOAD_DIRECTORY'
    }
    Pass 'INSTALL_AND_UNINSTALL_USE_ONE_CANONICAL_PATH'
    if($checks.Count -ne 14){throw ('R327_TEST_COUNT_MISMATCH_'+$checks.Count)}
    Write-Output ('R327_CANONICAL_SENSOR_TEMP_NET48_PASS='+$checks.Count+'/14')
}finally{
    $env:TEMP=$originalTemp
    $env:TMP=$originalTmp
    foreach($p in $created){
        if([IO.Directory]::Exists($p) -and
           [IO.Path]::GetFileName($p) -match '^tbme_(setup|uninstall)_[0-9a-f]{32}$' -and
           [IO.Path]::GetDirectoryName($p) -eq $expectedReal -and
           @([IO.Directory]::GetFileSystemEntries($p)).Count -eq 0){
            [IO.Directory]::Delete($p)
        }
    }
    if([IO.Directory]::Exists($base) -and
       [IO.Path]::GetFileName($base).StartsWith('tbme_r327_sensor_temp_',[StringComparison]::Ordinal)){
        [IO.Directory]::Delete($base,$true)
    }
}
