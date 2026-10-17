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
 throw 'R295_ONLY_DISPOSABLE_GITHUB_WINDOWS_VM'
}
function Hash([string]$Path){
 if(!(Test-Path -LiteralPath $Path -PathType Leaf)){return 'MISSING'}
 return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}
function ExpectRefusal([string]$Name,[string]$File,[string]$SHA,[string]$ExpectedMessage){
 $blocked=$false
 try{$null=Get-VerifiedSensorBackendEntries $File $SHA}
 catch{
  if($_.Exception.Message -match [regex]::Escape($ExpectedMessage)){$blocked=$true}else{
    throw ('R295_UNEXPECTED_REFUSAL_'+$Name+': '+$_.Exception.Message)
  }
 }
 if(!$blocked){throw ('R295_UNSAFE_ARCHIVE_ACCEPTED_'+$Name)}
 $script:checks.Add($Name)
}
function MakeSyntheticZip([string]$Destination,[string]$Variant){
 $buffer=[IO.MemoryStream]::new()
 $zip=[IO.Compression.ZipArchive]::new($buffer,[IO.Compression.ZipArchiveMode]::Create,$true)
 try{
  for($i=0;$i -lt 43;$i++){
   $name=('fixtures/entry'+$i.ToString('D2')+'.bin')
   if($Variant -eq 'TRAVERSAL' -and $i -eq 0){$name='../outside.dll'}
   if($Variant -eq 'DUPLICATE' -and $i -eq 0){$name='fixtures/COLLIDE.dll'}
   if($Variant -eq 'DUPLICATE' -and $i -eq 1){$name='FIXTURES/collide.DLL'}
   $entry=$zip.CreateEntry($name)
   if($Variant -eq 'LINK' -and $i -eq 0){$entry.ExternalAttributes=[int]-1610612736}
   $stream=$entry.Open()
   try{$data=[byte[]]@(0x41,[byte]$i,0x42);$stream.Write($data,0,$data.Length)}
   finally{$stream.Dispose()}
  }
 }finally{$zip.Dispose()}
 [IO.File]::WriteAllBytes($Destination,$buffer.ToArray())
 $buffer.Dispose()
}
$root=Join-Path $env:RUNNER_TEMP ('R295_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receiptFile=Join-Path $root 'R295_ZIP_PROVENANCE_RECEIPT.json'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$main=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$prior=Join-Path $env:RUNNER_TEMP ('R294_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R294_PROVENANCE_RECEIPT.json')
$checks=[Collections.Generic.List[string]]::new()
$success=$false
if(Test-Path $root){throw 'R295_PREEXISTING_FIXTURE_REFUSED'}
[void][IO.Directory]::CreateDirectory($root)
$beforeMain=Hash $main
try{
 $id=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
 $prev=Get-Content -LiteralPath $prior -Raw|ConvertFrom-Json
 if($id.Commit -cne $env:GITHUB_SHA -or (Hash $setup) -cne $id.SetupSHA256 -or
    (Hash $main) -cne $id.MainSHA256 -or
    $prev.SourceCommit -cne $env:GITHUB_SHA -or $prev.Host -cne $HostLabel -or
    $prev.Status -cne 'PASS_SHA_PINNED_EXCLUSIVE_SINGLE_READ_SENSOR_BINARIES'){
   throw 'R295_EXACT_SOURCE_AND_PRIOR_RECEIPT_NOT_VERIFIED'
 }
 $assembly=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
 $type=$assembly.GetType('SetupProgram',$true)
 $m=$type.GetMethod('BuildElevatedHelperCommandWithPipe',[Reflection.BindingFlags]'NonPublic,Static')
 if(!$m){throw 'R295_BUILD_INLINE_COMMAND_METHOD_MISSING'}
 $args4=[object[]]::new(6)
 $args4[0]=[string]'Install'
 $args4[1]=[string](Join-Path ([IO.Path]::GetTempPath()) ('tbme_setup_'+('a'*32)))
 $args4[2]=[string]$app
 $args4[3]=[string]([Security.Principal.WindowsIdentity]::GetCurrent().Name)
 $args4[4]=[string]('tbme_sensor_'+('a'*32))
 $args4[5]=[string]('b'*32)
 $command=[string]$m.Invoke($null,$args4)
 $prefix='-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand '
 $inline='-NoProfile -NonInteractive -WindowStyle Hidden -Command '
 $isEncoded=$command.StartsWith($prefix,[StringComparison]::Ordinal)
 $isInline=$command.StartsWith($inline,[StringComparison]::Ordinal)
 if((!$isEncoded -and !$isInline) -or
    ($isEncoded -and $command.Length -gt 32080) -or
    ($isInline -and $command.Length -gt 30000) -or
    $command.Contains(' -File ') -or
    $command.Contains('ExecutionPolicy Bypass') -or
    $command.Contains([string]$args4[1]) -or
    $command.Contains([string]$args4[2])){
     throw 'R295_UNSAFE_COMMAND_SOURCE_OR_SIZE'
 }
 $bootstrap=if($isEncoded){
  [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($command.Substring($prefix.Length)))
 }else{$command.Substring($inline.Length)}
 if(-not $bootstrap.Contains('[ScriptBlock]::Create($code)') -or
    -not $bootstrap.Contains('-StatusPipe $q -StatusNonce $n')){
     throw 'R295_UNSAFE_COMMAND_SOURCE_OR_SIZE2'
 }
 $match=[regex]::Match($bootstrap,"-ExpectedBackendZipSHA256 '([A-F0-9]{64})'")
 if(!$match.Success){throw 'R295_EMBEDDED_ZIP_SHA_NOT_TRANSPORTED'}
 $expectedHash=$match.Groups[1].Value
 $checks.Add('PE_EMBEDDED_ZIP_SHA_TRANSPORTED')
 $compactor=$type.GetMethod('CompactTrustedHelperSource',[Reflection.BindingFlags]'NonPublic,Static')
 if(!$compactor){throw 'R295_SOURCE_COMPACTOR_NOT_FOUND'}
 $helper=Join-Path $PSScriptRoot '..\installer\TBME_Setup_Elevated_Helper.ps1'
 $helper=[IO.Path]::GetFullPath($helper)
 $tokens=$null;$errors=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile($helper,[ref]$tokens,[ref]$errors)
 if(@($errors).Count){throw 'R295_PS51_HELPER_SYNTAX_INVALID'}
 $selected=@($ast.FindAll({param($node)
   $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
     $node.Name -in @('Assert-SensorBoundaryNoReparse','Get-VerifiedSensorPayloadBytes','Get-VerifiedSensorBackendEntries')
 },$true))
 if($selected.Count -ne 3){throw 'R295_THREE_SECURITY_FUNCTIONS_NOT_PRESENT'}
 . ([scriptblock]::Create(($selected|ForEach-Object {$_.Extent.Text}) -join [Environment]::NewLine))
 $raw=Get-Content -LiteralPath $helper -Raw
 $zipResource=$assembly.GetManifestResourceStream('Payload.LibreHardwareMonitor.zip')
 if(!$zipResource){throw 'R295_SETUP_MISSING_BUNDLED_ZIP_RESOURCE'}
 $zipPath=Join-Path $root 'LibreHardwareMonitor.zip'
 $writer=[IO.FileStream]::new($zipPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$zipResource.CopyTo($writer)}finally{$writer.Dispose();$zipResource.Dispose()}
 if((Hash $zipPath) -cne $expectedHash){throw 'R295_STAGED_ZIP_NOT_PE_EMBEDDED'}
 $checks.Add('STAGED_ZIP_MATCHES_PE_PINNED_SHA')
 $items=Get-VerifiedSensorBackendEntries $zipPath $expectedHash
 if(@($items).Count -ne 43){throw 'R295_EXPECTED_43_FILES_MISSING'}
 $count=0
 $bytesTotal=0
 $dir=Join-Path $root 'private-sandbox'
 [void][IO.Directory]::CreateDirectory($dir)
 foreach($item in $items){
  $destination=Join-Path $dir ($item.Rel.Replace('/','\'))
  $parent=[IO.Path]::GetDirectoryName($destination)
  if($parent){[void][IO.Directory]::CreateDirectory($parent)}
  [IO.File]::WriteAllBytes($destination,[byte[]]$item.Bytes)
  $sha=[Security.Cryptography.SHA256]::Create()
  try{$expectedFileSHA=[BitConverter]::ToString($sha.ComputeHash([byte[]]$item.Bytes)).Replace('-','')}
  finally{$sha.Dispose()}
  if((Hash $destination) -cne $expectedFileSHA){throw 'R295_VERIFIED_BUFFER_COPY_DIFFERS'}
  $count++;$bytesTotal+=$item.Bytes.Length
 }
 if($count -ne 43 -or $bytesTotal -ne 12203773 -or
   @(Get-ChildItem -LiteralPath $dir -Recurse -File).Count -ne 43){
   throw 'R295_PROTECTED_DEPENDENCIES_NOT_EXACT_43'
 }
 $checks.Add('ALL_43_ARCHIVE_ENTRIES_ARE_VERIFIED_BUFFERS')
 $checks.Add('COPIED_ONLY_VERIFIED_BUFFERS_TO_ISOLATED_SANDBOX')
 $tampered=[IO.File]::ReadAllBytes($zipPath)
 $tampered[10]=$tampered[10] -bxor 0x01
 [IO.File]::WriteAllBytes($zipPath,$tampered)
 $blocked=$false
 try{$null=Get-VerifiedSensorBackendEntries $zipPath $expectedHash}
 catch{if($_.Exception.Message -match 'SENSOR_PAYLOAD_EMBEDDED_SHA_MISMATCH'){$blocked=$true}else{throw}}
 if(!$blocked){throw 'R295_TAMPERED_ARCHIVE_NOT_REJECTED'}
 $checks.Add('TAMPERED_ARCHIVE_REJECTED_BEFORE_ANY_EXTRACTION')
 $exclusive=[IO.FileStream]::new($zipPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
 try{
  $blocked=$false
  try{$null=Get-VerifiedSensorBackendEntries $zipPath $expectedHash}
  catch [IO.IOException]{$blocked=$true}
  if(!$blocked){throw 'R295_EXCLUSIVE_ZIP_HANDLE_NOT_PROTECTED'}
 }finally{$exclusive.Dispose()}
 $checks.Add('EXCLUSIVE_ZIP_FILE_HANDLE_BLOCKS_SECOND_READER')
 foreach($mode in @('TRAVERSAL','DUPLICATE','LINK')){
  $filename=Join-Path $root ($mode+'.zip')
  MakeSyntheticZip $filename $mode
  $expected=switch($mode){
   'TRAVERSAL'{'SENSOR_BACKEND_ZIP_UNSAFE_ENTRY'}
   'DUPLICATE'{'SENSOR_BACKEND_ZIP_DUPLICATE_ENTRY'}
   'LINK'{'SENSOR_BACKEND_ZIP_LINK_REFUSED'}
  }
  ExpectRefusal ('ADVERSARIAL_ZIP_'+$mode+'_REJECTED') $filename (Hash $filename) $expected
 }
 $checks.Add('ZIP_PATHS_HAVE_NO_ESCAPE_SYMLINK_OR_COLLISION')
 $checks.Add('NO_HOST_UAC_OR_PROTECTED_SENSOR_SERVICE_ACTION')
 if((Hash $main) -cne $beforeMain){throw 'R295_RUNNING_MAIN_CHANGED'}
 $checks.Add('INSTALLED_MAIN_UNCHANGED')
 $proof=[ordered]@{
  Schema=1;Revision='R295';Status='PASS_PE_PINNED_ZIP_BYTE_ONLY_BACKEND_PROVENANCE'
  Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
  OriginalOwnerComputerTouched=$false;ElevatedUACOrProtectedServiceUsed=$false
  EmbeddedArchiveSHA256=$expectedHash;EntryCount=$count;UncompressedBytes=$bytesTotal
  TamperedArchiveRefused=$true;TraversalAndDuplicateAndLinkRefused=$true
  ExclusiveSourceLockVerified=$true;VerifiedBytesOnlyCopiedToSandbox=$true
  InstalledMainUnchanged=$true
  Checks=@($checks);RecordedUtc=[DateTime]::UtcNow.ToString('o')
 }
 [IO.File]::WriteAllText($receiptFile,($proof|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
 $success=$true
 'R295_NATIVE_'+$HostLabel+'_PINNED_BUNDLED_ZIP_PASS'
}finally{
 if(!$success){
  $fail=[ordered]@{Schema=1;Revision='R295';Status='FAILED_NOT_ACCEPTED';Host=$HostLabel;SourceCommit=$env:GITHUB_SHA;OwnerHostUntouched=$true}
  [IO.File]::WriteAllText($receiptFile,($fail|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
 }
}
