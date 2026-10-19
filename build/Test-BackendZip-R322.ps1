[CmdletBinding()]
param(
    [string]$SetupPath = '',
    [string]$ZipPath = ''
)
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($SetupPath)) { $SetupPath = Join-Path $PSScriptRoot '_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe' }
if ([string]::IsNullOrWhiteSpace($ZipPath)) { $ZipPath = Join-Path $PSScriptRoot '_deps\LibreHardwareMonitor.zip' }
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (!(Test-Path -LiteralPath $SetupPath) -or !(Test-Path -LiteralPath $ZipPath)) { throw 'R322_REQUIRED_BUILD_MISSING' }

$lock = Get-Content (Join-Path $PSScriptRoot 'dependencies.lock.json') -Raw | ConvertFrom-Json
$actualZipSha = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash
if ($actualZipSha -ne [string]$lock.dependencies.LibreHardwareMonitor.sha256) { throw 'R322_LOCKED_ZIP_SHA_MISMATCH' }

$setup = [Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath $SetupPath).Path)
$program = $setup.GetType('SetupProgram', $true)
$method = $program.GetMethod('ExtractBackendFromArchive', [Reflection.BindingFlags]'Static, NonPublic')
if ($null -eq $method) { throw 'R322_EXTRACT_METHOD_MISSING' }
$embedded = $setup.GetManifestResourceStream('Payload.LibreHardwareMonitor.zip')
if ($null -eq $embedded) { throw 'R322_PE_RESOURCE_MISSING' }
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $embeddedSha = ([BitConverter]::ToString($sha.ComputeHash($embedded))).Replace('-', '')
    if ($embeddedSha -ne $actualZipSha) { throw 'R322_PE_RESOURCE_HASH_MISMATCH' }
    $embedded.Position = 0
} finally { $sha.Dispose() }

$base = Join-Path ([IO.Path]::GetTempPath()) ('tbme_r322_zip_' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($base) | Out-Null
$passed = 0
$caseCount = 0

function New-BadZip([string[]]$names, [bool]$large = $false, [bool]$link = $false) {
    $memory = New-Object IO.MemoryStream
    $zip = [IO.Compression.ZipArchive]::new($memory, [IO.Compression.ZipArchiveMode]::Create, $true)
    try {
        for ($i = 0; $i -lt $names.Count; $i++) {
            $entry = $zip.CreateEntry($names[$i])
            if ($link -and $i -eq 0) { $entry.ExternalAttributes = [int](-1577127936) }
            $stream = $entry.Open()
            try {
                if ($large) {
                    $content = New-Object 'byte[]' (8*1024*1024+1)
                    $stream.Write($content,0,$content.Length)
                } else {
                    [byte[]]$content = [Text.Encoding]::ASCII.GetBytes('test')
                    $stream.Write($content,0,$content.Length)
                }
            } finally { $stream.Dispose() }
        }
    } finally { $zip.Dispose() }
    return ,$memory.ToArray()
}

function Check-Refusal([string]$name, [byte[]]$zipData, [string]$marker) {
    $script:caseCount++
    $target = Join-Path $base ('negative_' + $script:caseCount)
    [IO.Directory]::CreateDirectory($target) | Out-Null
    $sentinel = Join-Path $target 'sentinel.txt'
    [IO.File]::WriteAllText($sentinel,'original')
    $stream = [IO.MemoryStream]::new($zipData,$false)
    $observed = ''
    try {
        $reflectionArgs = New-Object 'object[]' 2
        $reflectionArgs[0] = $stream.PSObject.BaseObject
        $reflectionArgs[1] = [string]$target
        $method.Invoke($null, $reflectionArgs) | Out-Null
        throw ('R322_UNSAFE_ACCEPTED_' + $name)
    } catch {
        $failure = $_.Exception
        while ($null -ne $failure.InnerException) { $failure = $failure.InnerException }
        $observed = $failure.Message
    } finally { $stream.Dispose() }
    if (!$observed.Contains($marker) -or [IO.File]::ReadAllText($sentinel) -ne 'original' -or
        @([IO.Directory]::GetFileSystemEntries($target)).Count -ne 1) {
        throw ('R322_NEGATIVE_FAILED_' + $name + ' message=' + $observed)
    }
    $script:passed++
    Write-Output ('PASS ' + $name + ' => ' + $marker)
}

try {
    $positiveRoot = Join-Path $base 'positive'
    [IO.Directory]::CreateDirectory($positiveRoot) | Out-Null
    [IO.File]::WriteAllText((Join-Path $positiveRoot 'stale.tmp'),'previous backend')
    $reflectionArgs = New-Object 'object[]' 2
    $reflectionArgs[0] = $embedded.PSObject.BaseObject
    $reflectionArgs[1] = [string]$positiveRoot
    try { $method.Invoke($null,$reflectionArgs) | Out-Null }
    finally { $embedded.Dispose() }
    if ((Test-Path -LiteralPath (Join-Path $positiveRoot 'stale.tmp'))) { throw 'R322_OLD_BACKEND_NOT_REPLACED' }
    $zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ZipPath).Path)
    try {
        if ($zip.Entries.Count -ne 43) { throw 'R322_REFERENCE_ENTRY_COUNT_CHANGED' }
        foreach ($entry in $zip.Entries) {
            $file = Join-Path $positiveRoot ($entry.FullName.Replace('/', '\'))
            if (!(Test-Path -LiteralPath $file -PathType Leaf) -or
                (Get-Item -LiteralPath $file).Length -ne $entry.Length) {
                throw ('R322_EXTRACTED_ENTRY_MISMATCH_' + $entry.FullName)
            }
            $reader = $entry.Open()
            try {
                $digest=[Security.Cryptography.SHA256]::Create()
                try {
                    $expected=([BitConverter]::ToString($digest.ComputeHash($reader))).Replace('-','')
                    $actual=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
                    if($expected -ne $actual){throw ('R322_ENTRY_DIGEST_MISMATCH_' + $entry.FullName)}
                } finally {$digest.Dispose()}
            } finally {$reader.Dispose()}
        }
    } finally { $zip.Dispose() }
    $caseCount++; $passed++
    Write-Output 'PASS embedded_PE_zip_exact_43_files_and_replaced_backend'

    Check-Refusal 'traversal' (New-BadZip @('../outside.txt')) 'SENSOR_BACKEND_ARCHIVE_PATH_REFUSED'
    Check-Refusal 'windows_backslash' (New-BadZip @('..\outside.txt')) 'SENSOR_BACKEND_ARCHIVE_PATH_REFUSED'
    Check-Refusal 'absolute_path' (New-BadZip @('/outside.txt')) 'SENSOR_BACKEND_ARCHIVE_PATH_REFUSED'
    Check-Refusal 'ads_colon' (New-BadZip @('evil.txt:ads')) 'SENSOR_BACKEND_ARCHIVE_PATH_REFUSED'
    Check-Refusal 'case_alias_duplicate' (New-BadZip @('a.bin','A.BIN')) 'SENSOR_BACKEND_ARCHIVE_PATH_OR_DUPLICATE'
    Check-Refusal 'symlink' (New-BadZip @('symlink.bin') $false $true) 'SENSOR_BACKEND_ARCHIVE_LINK_REFUSED'
    Check-Refusal 'oversize' (New-BadZip @('big.bin') $true $false) 'SENSOR_BACKEND_ARCHIVE_SIZE_REFUSED'
    Check-Refusal 'wrong_manifest' (New-BadZip @('valid.bin')) 'SENSOR_BACKEND_ARCHIVE_PIN_MISMATCH'
    if (Test-Path -LiteralPath (Join-Path $base 'outside.txt')) { throw 'R322_EXTERNAL_CANARY_MODIFIED' }
    if ($caseCount -ne 9 -or $passed -ne 9) { throw 'R322_TEST_COUNT_MISMATCH' }
    Write-Output ('R322_BACKEND_ZIP_NATIVE_PASS=' + $passed + '/' + $caseCount)
} finally {
    if ($null -ne $embedded) { $embedded.Dispose() }
    if (Test-Path -LiteralPath $base) { [IO.Directory]::Delete($base,$true) }
}
