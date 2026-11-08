# R127: retain R80 independent read-only verification and accept versioned 1.7.5 patch filename.
# R80: independent read-only verification that a Setup's exact embedded Main PE bytes
# equal the SHA256 of an independently pinned, already-signed Main distribution file.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SetupExe,
    [Parameter(Mandatory=$true)][string]$ExpectedMainSHA256
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($ExpectedMainSHA256 -notmatch '^[0-9a-fA-F]{64}$'){throw 'R80 EXPECTED MAIN SHA NOT 64 HEX'}
$path=[IO.Path]::GetFullPath($SetupExe)
if(!(Test-Path -LiteralPath $path -PathType Leaf) -or
   ([IO.Path]::GetFileName($path) -cnotin @('TaskbarMonitorEnhanced_Setup_1.7.0.exe','TaskbarMonitorEnhanced_Setup_1.7.5.exe','TaskbarMonitorEnhanced_Setup_1.7.6.exe','TaskbarMonitorEnhanced_Setup_1.7.7.exe','TaskbarMonitorEnhanced_Setup_1.7.8.exe'))){
    throw 'R80 SETUP EXE MISSING OR WRONG FILE NAME'
}
$setupHash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
$resource=$null
$hasher=$null
try {
    # Reflection reads managed PE manifest resources without calling the installer entrypoint.
    # It must never install, elevate, touch HKCU personalization, spawn sensors or write files.
    $assembly=[Reflection.Assembly]::LoadFile($path)
    # SignPath Foundation OSS eligibility: the official proprietary PawnIO installer must
    # not be embedded in the trusted distribution Setup. Reject it even if signatures match.
    if(@($assembly.GetManifestResourceNames() | Where-Object {$_ -ceq 'Payload.PawnIO_setup.exe'}).Count -ne 0){
        throw 'R85 REJECT_SIGNED_SETUP_EMBEDS_OFFICIAL_PROPRIETARY_PAWNIO'
    }
    $resource=$assembly.GetManifestResourceStream('Payload.TaskbarMonitorEnhanced.exe')
    if($null -eq $resource -or $resource.Length -lt 1024){throw 'R80 MISSING EMBEDDED MAIN'}
    $length=$resource.Length
    $hasher=[Security.Cryptography.SHA256]::Create()
    $embedded=[Convert]::ToHexString($hasher.ComputeHash($resource))
    if($embedded -cne $ExpectedMainSHA256.ToUpperInvariant()){
        throw ('R80 EMBEDDED MAIN SHA DOES NOT MATCH EXPECTED SIGNED MAIN. Actual='+$embedded)
    }
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $setupHash){
        throw 'R80 SETUP WAS MODIFIED DURING VERIFICATION'
    }
    [ordered]@{
        Status='PASS_EMBEDDED_MAIN_EXACT_SHA256'
        EmbeddedMainSHA256=$embedded
        EmbeddedMainBytes=$length
        SetupSHA256=$setupHash
        ReadOnlyNoInstallerExecution=$true
        PawnIOBundled=$false
        UpstreamDriver='EXTERNAL_OPTIONAL_MANUAL'
        PublicTrustNotInferred=$true
    } | ConvertTo-Json -Compress
    exit 0
} finally {
    if($resource){$resource.Dispose()}
    if($hasher){$hasher.Dispose()}
}
