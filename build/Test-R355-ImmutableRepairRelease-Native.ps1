[CmdletBinding()]
param([string]$MainPath='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:GITHUB_REPOSITORY -cne 'Usefull-Skills/TaskbarMonitorEnhanced' -or
   (git rev-parse HEAD).Trim() -cne $env:GITHUB_SHA){
    throw 'R355_REQUIRES_EXACT_SOURCE_DISPOSABLE_WINDOWS'
}
if(!$MainPath){$MainPath=Join-Path $PSScriptRoot '_out\App\TaskbarMonitorEnhanced.exe'}
if(!(Test-Path -LiteralPath $MainPath -PathType Leaf)){throw 'R355_MAIN_EXACT_COMPILED_PE_MISSING'}
$asm=[Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath $MainPath).Path)
$type=$asm.GetType('TaskbarMonitorEnhanced.UpdateManager',$true)
$flags=[Reflection.BindingFlags]'NonPublic,Static,Public'
$parse=$type.GetMethod('ParseCurrentRepairReleaseMetadata',$flags)
$download=$type.GetMethod('DownloadAndVerifyForRepair',$flags)
$repair=$type.GetMethod('BuildPinnedRepairProcessInfo',$flags)
if(!$parse -or !$download -or !$repair){throw 'R355_CURRENT_REPAIR_BOUNDARY_NOT_COMPILED'}
$checks=[Collections.Generic.List[string]]::new()
function Pass([string]$name){$checks.Add($name);Write-Output ('PASS '+$name)}
function Parse-Strict([string]$json){
    $argsTyped=[object[]]@([string]$json)
    return $parse.Invoke($null,$argsTyped)
}
function Refuse-Json([string]$name,[scriptblock]$mutation){
    $object=$script:validJson|ConvertFrom-Json
    & $mutation $object
    $data=$object|ConvertTo-Json -Compress -Depth 9
    $rejected=$false
    try{
        $null=Parse-Strict $data
    }catch{
        $cause=$_.Exception
        while($cause.InnerException){$cause=$cause.InnerException}
        if($cause -is [IO.InvalidDataException]){$rejected=$true}
        else{throw ('R355_WRONG_REFUSAL_CLASS_'+$name+'_'+$cause.GetType().FullName)}
    }
    if(!$rejected){throw ('R355_ACCEPTED_INVALID_RELEASE_'+$name)}
    Pass $name
}
$version='1.7.8'
$name='TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$site='https://github.com/GOD13emad/TaskbarMonitorEnhanced'
$goodDigest='sha256:'+('a'*64)
$valid=[ordered]@{
  tag_name='v'+$version
  name='TaskbarMonitorEnhanced v1.7.8'
  html_url=$site+'/releases/tag/v'+$version
  immutable=$true
  draft=$false
  prerelease=$false
  assets=@([ordered]@{
    name=$name
    browser_download_url=$site+'/releases/download/v'+$version+'/'+$name
    digest=$goodDigest
    size=8565760
  })
}
$script:validJson=$valid|ConvertTo-Json -Compress -Depth 9
$info=Parse-Strict $validJson
if($info.Version -cne $version -or $info.Tag -cne 'v1.7.8' -or
   $info.HasUpdate -ne $false -or !$info.Immutable -or
   !$info.TagValid -or !$info.ReleaseUrlValid -or !$info.SetupUrlValid -or
   !$info.DigestAvailable -or !$info.SetupAssetAvailable -or
   $info.SetupDigest -cne $goodDigest){
    throw 'R355_TYPED_GOOD_CURRENT_IMMUTABLE_RELEASE_NOT_ACCEPTED'
}
Pass 'CANONICAL_IMMUTABLE_CURRENT_VERSION_SHA_ASSET_ACCEPTED'
Refuse-Json 'MUTABLE_RELEASE_REFUSED' {$x=$args[0];$x.immutable=$false}
Refuse-Json 'DRAFT_RELEASE_REFUSED' {$x=$args[0];$x.draft=$true}
Refuse-Json 'PRERELEASE_REFUSED' {$x=$args[0];$x.prerelease=$true}
Refuse-Json 'WRONG_TAG_REFUSED' {$x=$args[0];$x.tag_name='v1.7.9'}
Refuse-Json 'FOREIGN_RELEASE_URL_REFUSED' {$x=$args[0];$x.html_url='https://github.com/evil/fake/releases/tag/v1.7.8'}
Refuse-Json 'RELEASE_URL_QUERY_REFUSED' {$x=$args[0];$x.html_url=$x.html_url+'?redirect=bad'}
Refuse-Json 'FOREIGN_ASSET_URL_REFUSED' {$x=$args[0];$x.assets[0].browser_download_url='https://example.com/setup.exe'}
Refuse-Json 'ASSET_URL_QUERY_REFUSED' {$x=$args[0];$x.assets[0].browser_download_url=$x.assets[0].browser_download_url+'?download=1'}
Refuse-Json 'MALFORMED_ASSET_DIGEST_REFUSED' {$x=$args[0];$x.assets[0].digest='sha256:NOT_VALID'}
Refuse-Json 'MISSING_EXACT_ASSET_REFUSED' {$x=$args[0];$x.assets[0].name='other.exe'}
Refuse-Json 'DUPLICATE_ASSET_REFUSED' {$x=$args[0];$x.assets=@($x.assets[0],$x.assets[0])}
Refuse-Json 'TOO_SMALL_ASSET_REFUSED' {$x=$args[0];$x.assets[0].size=23}
Refuse-Json 'STRING_ASSET_SIZE_REFUSED' {$x=$args[0];$x.assets[0].size='8565760'}
Refuse-Json 'STRING_IMMUTABLE_FLAG_REFUSED' {$x=$args[0];$x.immutable='true'}
Refuse-Json 'MALFORMED_ASSET_OBJECT_REFUSED' {$x=$args[0];$x.assets=@('not-an-object')}
Refuse-Json 'ABSENT_ASSET_SIZE_REFUSED' {$x=$args[0];$x.assets[0].PSObject.Properties.Remove('size')}

$releaseType=$asm.GetType('TaskbarMonitorEnhanced.ReleaseUpdateInfo',$true)
$validInfo=Parse-Strict $validJson
$rejected=$false
$releaseType.GetField('Version').SetValue($validInfo,'1.7.9')
try{$null=$download.Invoke($null,([object[]]@($validInfo)))}
catch{
    $e=$_.Exception
    while($e.InnerException){$e=$e.InnerException}
    if($e -is [IO.InvalidDataException]){$rejected=$true}else{throw $e}
}
if(!$rejected){throw 'R355_WRONG_VERSION_REPAIR_WOULD_DOWNLOAD'}
Pass 'REPAIR_WRONG_VERSION_REJECTED_WITHOUT_NETWORK'
$releaseType.GetField('Version').SetValue($validInfo,'1.7.8')
$releaseType.GetField('HasUpdate').SetValue($validInfo,$true)
$rejected=$false
try{$null=$download.Invoke($null,([object[]]@($validInfo)))}
catch{
    $e=$_.Exception
    while($e.InnerException){$e=$e.InnerException}
    if($e -is [IO.InvalidDataException]){$rejected=$true}else{throw $e}
}
if(!$rejected){throw 'R355_UPDATE_INFO_PASSED_AS_REPAIR_WITHOUT_REFUSAL'}
Pass 'REPAIR_UPGRADE_INFO_REJECTED_WITHOUT_NETWORK'

if($checks.Count -ne 19){throw ('R355_TYPED_CASE_COUNT_MISMATCH_'+$checks.Count)}
'R355_IMMUTABLE_OFFICIAL_REPAIR_METADATA_NATIVE_PASS=19/19'
