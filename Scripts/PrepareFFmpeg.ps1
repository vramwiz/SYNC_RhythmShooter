param([string]$ArchivePath)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$provenance = Get-Content -LiteralPath (Join-Path $projectRoot 'ThirdParty\FFmpeg\provenance.json') -Raw | ConvertFrom-Json
$runtimeFiles = @($provenance.files | Where-Object { $_.path -like 'ThirdParty\FFmpeg\bin\*' })
$missingFiles = @($runtimeFiles | Where-Object {
    $runtimePath = Join-Path $projectRoot $_.path
    -not (Test-Path -LiteralPath $runtimePath -PathType Leaf) -or
        (Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash -ne $_.sourceSha256
})
if ($missingFiles.Count -eq 0) {
    Write-Output 'FFMPEG_RUNTIME_VERIFIED'
    exit 0
}
if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
    $cacheDirectory = Join-Path $projectRoot 'Win64\Dependencies'
    [IO.Directory]::CreateDirectory($cacheDirectory) | Out-Null
    $ArchivePath = Join-Path $cacheDirectory ([IO.Path]::GetFileName($provenance.archive.url))
    if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
        Write-Output ('Downloading pinned FFmpeg runtime: ' + $provenance.archive.url)
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $webClient = New-Object Net.WebClient
        try { $webClient.DownloadFile($provenance.archive.url, $ArchivePath) }
        finally { $webClient.Dispose() }
    }
}
if ((Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash -ne $provenance.archive.sha256) {
    throw 'FFmpeg archive SHA256 does not match ThirdParty\FFmpeg\provenance.json.'
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($ArchivePath))
try {
    foreach ($runtime in $missingFiles) {
        $fileName = [IO.Path]::GetFileName($runtime.path)
        $entries = @($archive.Entries | Where-Object { $_.FullName.EndsWith('/bin/' + $fileName) })
        if ($entries.Count -ne 1) { throw "Missing or ambiguous FFmpeg archive entry: $fileName" }
        $destination = Join-Path $projectRoot $runtime.path
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entries[0], $destination, $true)
        if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $runtime.sourceSha256) {
            throw "FFmpeg runtime SHA256 mismatch: $fileName"
        }
    }
}
finally { $archive.Dispose() }
Write-Output 'FFMPEG_RUNTIME_VERIFIED'
