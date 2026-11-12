[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
 [Parameter(Mandatory=$true)][string]$CandidateDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# Destructive fixture operations are forbidden on the owner's Windows host.
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID) -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'R299_ONLY_DISPOSABLE_GITHUB_WINDOWS'
}
function SHA([string]$path){
 if(!(Test-Path -LiteralPath $path -PathType Leaf)){return 'MISSING'}
 return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
function ExpectRefusal([string]$name,[Reflection.MethodInfo]$method,[object[]]$invokeArgs,[string]$pattern){
 $refused=$false
 try{[void]$method.Invoke($null,$invokeArgs)}
 catch{if($_.Exception.ToString() -match $pattern){$refused=$true}else{throw}}
 if(!$refused){throw ('R299_FAIL_OPEN_'+$name)}
 $script:checks.Add($name)
}
$testRoot=Join-Path $env:RUNNER_TEMP ('R299_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $testRoot 'R299_NONRECURSIVE_CLEANUP_RECEIPT.json'
$outside=Join-Path $testRoot 'external-canary'
$canary=Join-Path $outside 'do-not-delete.txt'
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$stage=Join-Path $app '.tbme-upgrade'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$prior=Join-Path $env:RUNNER_TEMP ('R298_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R298_EXPLICIT_POWERSHELL_HOST_RECEIPT.json')
$main=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$config=Join-Path $app 'config.json'
$state=Join-Path $app 'install_state.json'
$checks=[Collections.Generic.List[string]]::new()
if((Test-Path -LiteralPath $stage) -or (Test-Path -LiteralPath $testRoot)){
 throw 'R299_EXISTING_JOURNAL_OR_FIXTURE_WOULD_BE_TOUCHED'
}
$candidate=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
$last=Get-Content -LiteralPath $prior -Raw|ConvertFrom-Json
if($candidate.Commit -cne $env:GITHUB_SHA -or $candidate.SetupSHA256 -cne (SHA $setup) -or
   $candidate.MainSHA256 -cne (SHA $main) -or
   $last.SourceCommit -cne $env:GITHUB_SHA -or $last.Status -cne 'PASS_ABSOLUTE_SYSTEM_POWERSHELL_RUNAS_HOST' -or
   $last.Host -cne $HostLabel){
 throw 'R299_SOURCE_GUEST_OR_PRIOR_PROOF_MISMATCH'
}
$mainBefore=SHA $main
$configBefore=SHA $config
$stateBefore=SHA $state
[void][IO.Directory]::CreateDirectory($outside)
[IO.File]::WriteAllText($canary,'R299_EXTERNAL_PROTECTED_CANARY',[Text.UTF8Encoding]::new($false))
$outsideBefore=SHA $canary
$assembly=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
$type=$assembly.GetType('SetupProgram',$true)
$method=$type.GetMethod('CleanOwnedStage',[Reflection.BindingFlags]'Static,NonPublic')
$entryType=$type.GetNestedType('StageEntry',[Reflection.BindingFlags]'NonPublic')
if(!$method -or !$entryType){throw 'R299_EXPECTED_COMPILED_ENTRY_OR_CLEANUP_MISSING'}
$ctor=$entryType.GetConstructor([Reflection.BindingFlags]'Instance,NonPublic,Public',
 $null,[Type[]]@([string],[string],[string]),$null)
if(!$ctor){throw 'R299_COMPILED_STAGE_ENTRY_CONSTRUCTOR_MISSING'}
$listType=[Collections.Generic.List[string]].GetGenericTypeDefinition().MakeGenericType([Type[]]@($entryType))
$rows=[Activator]::CreateInstance($listType)
$entry=$ctor.Invoke([object[]]@('Docs/RELEASE_NOTES_v1.7.8.md','-','-'))
[void]$listType.GetMethod('Add').Invoke($rows,[object[]]@($entry))
$args1=[object[]]::new(1);$args1[0]=$rows
$old=Join-Path $stage 'old'
$new=Join-Path $stage 'new'
$oldDocs=Join-Path $old 'Docs'
$newDocs=Join-Path $new 'Docs'
$note=Join-Path $newDocs 'RELEASE_NOTES_v1.7.8.md'
[void][IO.Directory]::CreateDirectory($old)
[void][IO.Directory]::CreateDirectory($newDocs)
foreach($file in @('owner.txt','phase.txt','index.txt','previous_version.txt')){
 $value=if($file -ceq 'owner.txt'){'TBME_UPGRADE_R92_OWNED_STAGE_V1'}else{'R299_ONLY_'+$file}
 [IO.File]::WriteAllText((Join-Path $stage $file),$value)
}
[IO.File]::WriteAllText($note,'R299_NEW_MANAGED_NOTE')
$ownerBefore=SHA (Join-Path $stage 'owner.txt')
$noteBefore=SHA $note
$unknown=Join-Path $stage 'unrecognized.txt'
[IO.File]::WriteAllText($unknown,'R299_UNRECOGNIZED_KEEP')
ExpectRefusal 'UNKNOWN_FILE_REFUSED_BEFORE_DELETION' $method $args1 'Unknown file inside update stage'
if((SHA $note) -cne $noteBefore -or
   (SHA (Join-Path $stage 'owner.txt')) -cne $ownerBefore -or
   (SHA $unknown) -eq 'MISSING'){throw 'R299_UNKNOWN_FILE_DID_NOT_FAIL_CLOSED'}
[IO.File]::Delete($unknown)
$unknownDir=Join-Path $stage 'unrecognized-empty-directory'
[void][IO.Directory]::CreateDirectory($unknownDir)
ExpectRefusal 'UNKNOWN_EMPTY_DIRECTORY_REFUSED' $method $args1 'Unknown directory inside update stage'
if(!(Test-Path -LiteralPath $unknownDir) -or
   (SHA (Join-Path $stage 'owner.txt')) -cne $ownerBefore){
 throw 'R299_UNKNOWN_EMPTY_DIRECTORY_WAS_DELETED'
}
[IO.Directory]::Delete($unknownDir,$false)
# A junction named like an expected parent must never be traversed.
New-Item -ItemType Junction -Path $oldDocs -Target $outside -ErrorAction Stop|Out-Null
if(-not ((Get-Item -LiteralPath $oldDocs -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){
 throw 'R299_NATIVE_JUNCTION_NOT_PRESENT'
}
ExpectRefusal 'EXPECTED_PARENT_JUNCTION_REFUSED' $method $args1 'reparse|symlink/junction'
if((SHA $canary) -cne $outsideBefore){throw 'R299_JUNCTION_DESTINATION_CHANGED'}
[IO.Directory]::Delete($oldDocs)
if(Test-Path -LiteralPath $oldDocs){throw 'R299_TEST_JUNCTION_LEFT_BEHIND'}
$checks.Add('EXTERNAL_CANARY_IMMUTABLE')
# Positive cleanup must work with recognized nested old/new files, without
# recursively traversing any directory or deleting unrelated application data.
[void][IO.Directory]::CreateDirectory($oldDocs)
[IO.File]::WriteAllText((Join-Path $oldDocs 'RELEASE_NOTES_v1.7.8.md'),'R299_OLD_MANAGED_NOTE')
[void]$method.Invoke($null,$args1)
if(Test-Path -LiteralPath $stage){throw 'R299_KNOWN_ONLY_STAGE_NOT_REMOVED'}
$checks.Add('EXACT_KNOWN_FILES_AND_DIRECTORIES_REMOVED_NONRECURSIVELY')
if((SHA $canary) -cne $outsideBefore -or (SHA $main) -cne $mainBefore -or
   (SHA $config) -cne $configBefore -or (SHA $state) -cne $stateBefore){
 throw 'R299_EXTERNAL_OR_INSTALLED_USER_ASSET_CHANGED'
}
$checks.Add('ORIGINAL_GUEST_MAIN_CONFIG_AND_STATE_IMMUTABLE')
$result=[ordered]@{
 Schema=1;Revision='R299';Status='PASS_NONRECURSIVE_ALLOWLISTED_STAGE_CLEANUP'
 Host=$HostLabel;SourceCommit=$env:GITHUB_SHA;OwnerComputerTouched=$false
 UnknownFilePreserved=$true;UnknownEmptyDirPreserved=$true
 NativeJunctionRefused=$true;ExternalCanaryPreserved=$true
 PositiveNestedStageCleaned=$true;NoStageResidue=$true
 InstalledUserFilesUnchanged=$true;Checks=@($checks)
 RecordedUtc=[DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($receipt,($result|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
'R299_NATIVE_'+$HostLabel+'_NONRECURSIVE_STAGE_CLEANUP_PASS'
