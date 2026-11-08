param([string]$ReleaseDirectory)

$ErrorActionPreference = 'Stop'

$packageName = 'SYNC_RhythmShooter'
$projectDir = Split-Path -Parent $PSScriptRoot
if (-not $ReleaseDirectory) { $ReleaseDirectory = Join-Path $projectDir 'Win64\Release' }
$pluginName = "$packageName.auf2"
$pluginPath = Join-Path $ReleaseDirectory $pluginName
if (-not (Test-Path -LiteralPath $pluginPath -PathType Leaf)) {
    throw "Release plugin not found: $pluginPath. Build the Win64 Release configuration first."
}

$xxhsumPath = Join-Path $projectDir 'Win64\Dependencies\xxHash-0.8.4\xxhsum.exe'
if (-not (Test-Path -LiteralPath $xxhsumPath -PathType Leaf)) {
    $xxhsum = Get-Command xxhsum.exe -CommandType Application -ErrorAction SilentlyContinue
    if (-not $xxhsum) { throw 'xxhsum.exe is required. See Setup\README.md.' }
    $xxhsumPath = $xxhsum.Source
}

$catalogPath = Join-Path $PSScriptRoot "$packageName.catalog.json"
$catalogSource = [IO.File]::ReadAllText($catalogPath)
$catalog = $catalogSource | ConvertFrom-Json
$version = $catalog[0].version[-1]
$pluginEntry = $version.file | Where-Object path -eq "{pluginsDir}/$packageName/$pluginName"
if (-not $pluginEntry) { throw 'The last catalog version must list the installed AUF2.' }

$provenancePath = 'ThirdParty\FFmpeg\provenance.json'
$provenance = Get-Content -LiteralPath (Join-Path $projectDir $provenancePath) -Raw | ConvertFrom-Json
$runtimeFiles = @($provenance.files | Where-Object { $_.path -like 'ThirdParty\FFmpeg\*' })
$sha256 = [Security.Cryptography.SHA256]::Create()
try {
    foreach ($file in $runtimeFiles) {
        $source = Join-Path $projectDir $file.path
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "FFmpeg file not found: $source. Run Scripts\PrepareFFmpeg.ps1 to restore the runtime."
        }
        $stream = [IO.File]::OpenRead($source)
        try { $hash = [BitConverter]::ToString($sha256.ComputeHash($stream)).Replace('-', '') }
        finally { $stream.Dispose() }
        if ($hash -ne $file.sourceSha256) { throw "FFmpeg file does not match provenance.json: $source" }
    }
}
finally { $sha256.Dispose() }

$assets = @(Get-ChildItem -LiteralPath (Join-Path $projectDir 'Assets') -Filter '*.bmp' -File)
if (-not $assets) { throw 'No standard BMP assets found.' }
$packageFiles = [ordered]@{
    'README.md' = Join-Path $PSScriptRoot 'README.md'
    'LICENSE' = Join-Path $projectDir 'LICENSE'
    'THIRD_PARTY_NOTICES.md' = Join-Path $projectDir 'THIRD_PARTY_NOTICES.md'
    $provenancePath = Join-Path $projectDir $provenancePath
}
foreach ($asset in $assets) { $packageFiles["Assets\$($asset.Name)"] = $asset.FullName }
foreach ($file in $runtimeFiles) { $packageFiles[$file.path] = Join-Path $projectDir $file.path }
foreach ($notice in @('LICENSE.md','provenance.json','CORE_CHANGES.md','integration.json')) {
    $relativePath = 'ThirdParty\MP3Decoder\' + $notice
    $sourcePath = Join-Path $projectDir $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "MP3 decoder notice not found: $sourcePath"
    }
    $packageFiles[$relativePath] = $sourcePath
}

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$zipPath = Join-Path $PSScriptRoot "$packageName.zip"
$tempBase = Join-Path $PSScriptRoot ('.release-' + [guid]::NewGuid().ToString('N'))
$tempPlugin = "$tempBase-plugin.tmp"
$tempZip = "$tempBase-zip.tmp"
$tempCatalog = "$tempBase-catalog.tmp"
$catalogBackup = "$tempBase-previous-catalog.tmp"

try {
    # Hash and compress the same snapshot even if a new build starts during packaging.
    Copy-Item -LiteralPath $pluginPath -Destination $tempPlugin
    $hashOutput = & $xxhsumPath -H128 --tag $tempPlugin
    if ($LASTEXITCODE -ne 0 -or $hashOutput -notmatch ' = ([a-f0-9]{32})$') {
        throw 'Could not calculate the AUF2 XXH3-128 hash.'
    }
    $hash = $Matches[1].ToLowerInvariant()
    $packageFiles[$pluginName] = $tempPlugin

    $zip = [IO.Compression.ZipFile]::Open($tempZip, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($relativePath in $packageFiles.Keys) {
            $entryName = "$packageName/" + $relativePath.Replace('\', '/')
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, $packageFiles[$relativePath], $entryName, [IO.Compression.CompressionLevel]::Optimal
            ) | Out-Null
        }
    }
    finally { $zip.Dispose() }

    if ($pluginEntry.XXH3_128 -cne $hash) {
        $pluginEntry.XXH3_128 = $hash
        $json = ConvertTo-Json -InputObject @($catalog) -Depth 12
        [IO.File]::WriteAllText($tempCatalog, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    }
    # Serialize publication of the ZIP and its catalog hash, and retain the old pair on failure.
    $lock = [Threading.Mutex]::new($false, 'Local\VRAMWIZ.SYNC_RhythmShooter.ReleaseZip')
    $ownsLock = $false
    try {
        $ownsLock = $lock.WaitOne(0)
        if (-not $ownsLock) { throw 'Another release ZIP is being finalized. Run the batch again.' }
        if ([IO.File]::ReadAllText($catalogPath) -cne $catalogSource) {
            throw 'Catalog changed during packaging. Run the batch again.'
        }
        if ([IO.File]::Exists($tempCatalog)) {
            [IO.File]::Replace($tempCatalog, $catalogPath, $catalogBackup)
        }
        try {
            if ([IO.File]::Exists($zipPath)) { [IO.File]::Replace($tempZip, $zipPath, [NullString]::Value) }
            else { [IO.File]::Move($tempZip, $zipPath) }
        }
        catch {
            if ([IO.File]::Exists($catalogBackup)) {
                [IO.File]::Replace($catalogBackup, $catalogPath, [NullString]::Value)
            }
            throw
        }
        if ([IO.File]::Exists($catalogBackup)) { [IO.File]::Delete($catalogBackup) }
    }
    finally {
        if ($ownsLock) { $lock.ReleaseMutex() }
        $lock.Dispose()
    }
}
finally {
    foreach ($tempPath in @($tempPlugin, $tempZip, $tempCatalog)) {
        if (Test-Path -LiteralPath $tempPath -PathType Leaf) { Remove-Item -LiteralPath $tempPath -Force }
    }
}

Write-Output "Created $zipPath"
Write-Output "Catalog $catalogPath ($($version.version), XXH3_128=$hash)"
