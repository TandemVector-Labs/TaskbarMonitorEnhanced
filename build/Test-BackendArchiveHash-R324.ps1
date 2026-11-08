[CmdletBinding()]
param(
    [string]$SetupPath = '',
    [string]$ZipPath = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ([string]::IsNullOrWhiteSpace($SetupPath)) { $SetupPath = Join-Path $PSScriptRoot '_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe' }
if ([string]::IsNullOrWhiteSpace($ZipPath)) { $ZipPath = Join-Path $PSScriptRoot '_deps\LibreHardwareMonitor.zip' }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if ($PSVersionTable.PSEdition -cne 'Desktop') { throw 'R324_NEEDS_NATIVE_NETFRAMEWORK_POWERSHELL' }
if (!(Test-Path -LiteralPath $SetupPath -PathType Leaf) -or !(Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
    throw 'R324_COMPILED_SETUP_OR_PINNED_ARCHIVE_MISSING'
}
$lock=Get-Content (Join-Path $PSScriptRoot 'dependencies.lock.json') -Raw|ConvertFrom-Json
$want=[string]$lock.dependencies.LibreHardwareMonitor.sha256
if ($want -cne '086D9F1B5A99E643EDC2CFAAAC16051685B551E4C5AC0B32A57C58C0E529C001' -or
    (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash -cne $want) {
    throw 'R324_DEPENDENCY_LOCK_DIFFERENT_FROM_COMPILED_SOURCE'
}
$setup=[Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath $SetupPath).Path)
$method=$setup.GetType('SetupProgram',$true).GetMethod('ExtractBackendFromArchive',[Reflection.BindingFlags]'Static, NonPublic')
if ($null -eq $method) { throw 'R324_REAL_SETUP_METHOD_MISSING' }
$embedded=$setup.GetManifestResourceStream('Payload.LibreHardwareMonitor.zip')
if ($null -eq $embedded) { throw 'R324_EMBEDDED_ZIP_MISSING' }
try {
    $hash=[Security.Cryptography.SHA256]::Create()
    try {$embeddedHash=([BitConverter]::ToString($hash.ComputeHash($embedded))).Replace('-','')}
    finally {$hash.Dispose()}
} finally {$embedded.Dispose()}
if ($embeddedHash -cne $want) { throw 'R324_SETUP_EMBEDDED_ARCHIVE_DIFFERENT_FROM_LOCK' }

$original=[IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $ZipPath).Path)
$sourceZip=[IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ZipPath).Path)
try {
    if ($sourceZip.Entries.Count -ne 43 -or $sourceZip.Entries[0].CompressedLength -lt 33000) {
        throw 'R324_PINNED_ARCHIVE_LAYOUT_CHANGED'
    }
} finally {$sourceZip.Dispose()}

$base=Join-Path ([IO.Path]::GetTempPath()) ('tbme_r324_archive_' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($base)|Out-Null
$canary=Join-Path $base 'external-untouched.txt'
[IO.File]::WriteAllText($canary,'KEEP_R324_OUTSIDE')
$checks=0

function Check-NoMutation([string]$name,[byte[]]$mutated) {
    $target=Join-Path $base $name
    [IO.Directory]::CreateDirectory($target)|Out-Null
    $old=Join-Path $target 'previous-backend.txt'
    [IO.File]::WriteAllText($old,'PRESERVE_PREVIOUS_BACKEND')
    $ms=[IO.MemoryStream]::new($mutated,$false)
    $args=New-Object 'object[]' 2
    $args[0]=$ms.PSObject.BaseObject
    $args[1]=[string]$target
    $exception=''
    try {
        $method.Invoke($null,$args)|Out-Null
        throw ('R324_BAD_ARCHIVE_INSTALLED_'+$name)
    } catch {
        $errorObject=$_.Exception
        while ($null -ne $errorObject.InnerException) {
            $errorObject=$errorObject.InnerException
        }
        $exception=$errorObject.Message
    } finally {$ms.Dispose()}
    if ($exception -cne 'SENSOR_BACKEND_ARCHIVE_SHA_REFUSED' -or
        ![IO.File]::Exists($old) -or
        [IO.File]::ReadAllText($old) -cne 'PRESERVE_PREVIOUS_BACKEND' -or
        @([IO.Directory]::GetFileSystemEntries($target)).Count -ne 1 -or
        [IO.File]::ReadAllText($canary) -cne 'KEEP_R324_OUTSIDE') {
        throw ('R324_FAIL_CLOSED_REGRESSION_'+$name+':'+$exception)
    }
    $script:checks++
    Write-Output ('PASS_'+$name+'_SHA_REFUSED_BEFORE_BACKEND_CHANGE')
}

try {
    $crc=[byte[]]$original.Clone()
    $firstCentral=-1
    for ($i=0;$i -lt $crc.Length-46;$i++) {
        if ($crc[$i] -eq 0x50 -and $crc[$i+1] -eq 0x4b -and
            $crc[$i+2] -eq 0x01 -and $crc[$i+3] -eq 0x02) {
            $firstCentral=$i
            break
        }
    }
    if ($firstCentral -lt 0) { throw 'R324_CENTRAL_HEADER_MISSING' }
    $crc[$firstCentral+16]=[byte]($crc[$firstCentral+16] -bxor 1)
    Check-NoMutation 'invalid_central_crc' $crc

    $deflate=[byte[]]$original.Clone()
    if ([BitConverter]::ToUInt32($deflate,0) -ne 0x04034b50) {
        throw 'R324_FIRST_LOCAL_HEADER_MISSING'
    }
    $payloadStart=30+[BitConverter]::ToUInt16($deflate,26)+[BitConverter]::ToUInt16($deflate,28)
    $offset=$payloadStart+32000
    if ($offset -ge $deflate.Length) { throw 'R324_DEFLATE_OFFSET_OUTSIDE_ARCHIVE' }
    $deflate[$offset]=[byte]($deflate[$offset] -bxor 2)
    Check-NoMutation 'altered_compressed_payload' $deflate

    $valid=Join-Path $base 'valid'
    [IO.Directory]::CreateDirectory($valid)|Out-Null
    [IO.File]::WriteAllText((Join-Path $valid 'old-backend.txt'),'OLD')
    $resource=$setup.GetManifestResourceStream('Payload.LibreHardwareMonitor.zip')
    try {
        $args=New-Object 'object[]' 2
        $args[0]=$resource.PSObject.BaseObject
        $args[1]=[string]$valid
        $method.Invoke($null,$args)|Out-Null
    } finally {$resource.Dispose()}
    $files=@([IO.Directory]::GetFiles($valid,'*',[IO.SearchOption]::AllDirectories))
    if ($files.Count -ne 43 -or [IO.File]::Exists((Join-Path $valid 'old-backend.txt'))) {
        throw 'R324_VALID_RESOURCE_EXTRACTION_FAILED'
    }
    $sourceZip=[IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ZipPath).Path)
    try {
        foreach($entry in $sourceZip.Entries) {
            $file=Join-Path $valid ($entry.FullName.Replace('/','\'))
            if (![IO.File]::Exists($file) -or (Get-Item -LiteralPath $file).Length -ne $entry.Length) {
                throw ('R324_VALID_FILE_LAYOUT_MISMATCH_'+$entry.FullName)
            }
            $reader=$entry.Open()
            try {
                $sha=[Security.Cryptography.SHA256]::Create()
                try {$expected=([BitConverter]::ToString($sha.ComputeHash($reader))).Replace('-','')}
                finally {$sha.Dispose()}
            } finally {$reader.Dispose()}
            if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -cne $expected) {
                throw ('R324_VALID_FILE_SHA_MISMATCH_'+$entry.FullName)
            }
        }
    } finally {$sourceZip.Dispose()}
    if ([IO.File]::ReadAllText($canary) -cne 'KEEP_R324_OUTSIDE') {
        throw 'R324_POSITIVE_EXTERNAL_CANARY_CHANGED'
    }
    $checks++
    Write-Output 'PASS_VALID_LOCKED_PE_ARCHIVE_43_FILES_ALL_SHA'
    if ($checks -ne 3) { throw ('R324_CHECK_COUNT_MISMATCH_'+$checks) }
    Write-Output ('R324_BACKEND_SHA_PREFLIGHT_NATIVE_PASS='+$checks+'/3')
} finally {
    if ([IO.Directory]::Exists($base) -and
        [IO.Path]::GetFileName($base).StartsWith('tbme_r324_archive_',[StringComparison]::Ordinal)) {
        [IO.Directory]::Delete($base,$true)
    }
}
