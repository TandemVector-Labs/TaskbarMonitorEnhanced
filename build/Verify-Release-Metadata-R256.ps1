# R256 independent, read-only authority check for the versioned 1.7.4
# release Build Manifest -> deterministic binary files -> SBOM 2.3.
[CmdletBinding()]
param(
 [string]$Root=(Join-Path $PSScriptRoot '..'),
 [switch]$SelfTest
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($Root)
$manifestPath=Join-Path $root 'artifacts\BUILD_MANIFEST.json'
$sbomPath=Join-Path $root 'artifacts\SBOM.spdx.json'
$setupVerifyPath=Join-Path $root 'build\_out\setup_verify.json'
$source=(Join-Path $root 'src\TaskbarMonitorEnhanced.cs')
foreach($f in @($manifestPath,$sbomPath,$setupVerifyPath,$source)){
 if(!(Test-Path -LiteralPath $f -PathType Leaf)){throw ('R256_REQUIRED_EVIDENCE_MISSING '+$f)}
}
$m=Get-Content $manifestPath -Raw|ConvertFrom-Json
$b=Get-Content $sbomPath -Raw|ConvertFrom-Json
$v=Get-Content $setupVerifyPath -Raw|ConvertFrom-Json
$commit=(& git -C $root rev-parse HEAD).Trim()
if($LASTEXITCODE -ne 0 -or $commit -cnotmatch '^[a-f0-9]{40}$'){throw 'R256_CURRENT_HEAD_NOT_EXACT'}
function Issues($manifest,$sbom,$setup,$sha){
 $fail=[Collections.Generic.List[string]]::new()
 if($manifest.Version -cne '1.7.4' -or $manifest.Build -cne 'V1_7_4_R256_FRESH_MAINTENANCE'){
  $fail.Add('WRONG_PUBLIC_BUILD_VERSION')
 }
 if($sbom.spdxVersion -cne 'SPDX-2.3' -or $sbom.name -cne 'Taskbar-Monitor-Enhanced-1.7.4' -or
    $sbom.documentNamespace -cne ('https://github.com/GOD13emad/TaskbarMonitorEnhanced/spdx/1.7.4/'+$sha)){
  $fail.Add('SPDX_SOURCE_AND_VERSION_DRIFT')
 }
 if(@($sbom.packages).Count -ne 3 -or @($sbom.files).Count -ne 5 -or
    $sbom.packages[0].versionInfo -cne '1.7.4'){
  $fail.Add('SPDX_PRODUCT_PACKAGE_VERSION_DRIFT')
 }
 $required=@('TaskbarMonitorEnhanced.exe','TaskbarMonitorEnhanced.exe.config',
   'TaskbarMonitorSensorBroker.exe','TaskbarMonitorSensorSupervisor.exe',
   'TaskbarMonitorEnhanced_Setup_1.7.4.exe')
 $found=@($manifest.Outputs|ForEach-Object {$_.Name})
 if(@($manifest.Outputs).Count -ne 5 -or
    @(Compare-Object ($required|Sort-Object) ($found|Sort-Object)).Count -ne 0){
  $fail.Add('MANIFEST_EXACT_FIVE_OUTPUTS_MISMATCH')
 }else{
  foreach($row in $manifest.Outputs){
   $name=[string]$row.Name
   $rel=switch($name){
    'TaskbarMonitorEnhanced_Setup_1.7.4.exe' {'build\_out\Setup\'+$name;break}
    'TaskbarMonitorSensorBroker.exe' {'build\_out\Broker\'+$name;break}
    'TaskbarMonitorSensorSupervisor.exe' {'build\_out\Supervisor\'+$name;break}
    default {'build\_out\App\'+$name}
   }
   $path=Join-Path $root $rel
   if(!(Test-Path $path -PathType Leaf) -or
      (Get-Item $path).Length -ne [int64]$row.Bytes -or
      (Get-FileHash $path -Algorithm SHA256).Hash -cne [string]$row.SHA256){
    $fail.Add('ACTUAL_OUTPUT_SHA_OR_SIZE_MISMATCH_'+$name)
   }
   $frow=@($sbom.files|Where-Object fileName -ceq $name)
   if($frow.Count -ne 1 -or @($frow[0].checksums).Count -ne 1 -or
      $frow[0].checksums[0].algorithm -cne 'SHA256' -or
      $frow[0].checksums[0].checksumValue -cne ([string]$row.SHA256).ToLowerInvariant()){
    $fail.Add('SBOM_OUTPUT_SHA_MISMATCH_'+$name)
   }
  }
 }
 if($setup.Status -cne 'PASS' -or [int]$setup.Resources -ne 25 -or
    $setup.PawnIOBundled -ne $false){
  $fail.Add('SETUP_RESOURCE_OR_PROPRIETARY_DEPENDENCY_REJECTED')
 }
 $main=(Join-Path $root 'build\_out\App\TaskbarMonitorEnhanced.exe')
 $setupExe=(Join-Path $root 'build\_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.4.exe')
 if((Get-Item $main).VersionInfo.ProductVersion -cne (Get-Item $setupExe).VersionInfo.ProductVersion -or
    !(Get-Item $main).VersionInfo.ProductVersion.StartsWith('1.7.4')){
  $fail.Add('ASSEMBLY_PRODUCT_VERSION_DIFFERENT')
 }
 return @($fail.ToArray())
}
$errors=@(Issues $m $b $v $commit)
if($errors.Count){throw ('R256_RELEASE_METADATA_FAIL_CLOSED '+($errors -join ';'))}
if($SelfTest){
 $mutants=@(
  @{Type='Manifest';Field='Version';Bad='1.7.0'},
  @{Type='Manifest';Field='Build';Bad='V1_7_0_R39_WALLPAPER_STUDIO'},
  @{Type='Sbom';Field='name';Bad='Taskbar-Monitor-Enhanced-1.7.0'},
  @{Type='Sbom';Field='documentNamespace';Bad=('https://github.com/GOD13emad/TaskbarMonitorEnhanced/spdx/1.7.4/'+('0'*40))},
  @{Type='Setup';Field='PawnIOBundled';Bad=$true}
 )
 foreach($mutation in $mutants){
  $am=$m|ConvertTo-Json -Depth 14|ConvertFrom-Json
  $ab=$b|ConvertTo-Json -Depth 14|ConvertFrom-Json
  $av=$v|ConvertTo-Json -Depth 14|ConvertFrom-Json
  switch($mutation.Type){
   'Manifest' {$am.($mutation.Field)=$mutation.Bad}
   'Sbom' {$ab.($mutation.Field)=$mutation.Bad}
   'Setup' {$av.($mutation.Field)=$mutation.Bad}
  }
  if(@(Issues $am $ab $av $commit).Count -eq 0){
   throw ('R256_HOSTILE_RELEASE_METADATA_ACCEPTED '+$mutation.Type+' '+$mutation.Field)
  }
 }
 Write-Output 'R256_FIVE_HOSTILE_RELEASE_METADATA_MUTANTS_REJECTED'
}
Write-Output ('R256_MANIFEST_SBOM_BINARY_VERSION=PASS VERSION='+$m.Version+
 ' OUTPUTS='+@($m.Outputs).Count+' SHA256='+(Get-FileHash $manifestPath -Algorithm SHA256).Hash)
exit 0
