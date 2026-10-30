param(
    [Parameter(Mandatory = $true)][ValidateSet('Prepare', 'Complete')][string]$Stage,
    [Parameter(Mandatory = $true)][ValidateSet('Debug', 'Release')][string]$Config,
    [Parameter(Mandatory = $true)][string]$LibraryPath,
    [string]$DeployDirectory,
    [ValidateSet('SYNC_RhythmShooter','SYNC_RhythmBall','SYNC_RhythmFireworks')][string]$ProjectName='SYNC_RhythmShooter'
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$LibraryPath = [IO.Path]::GetFullPath($LibraryPath)
if ([IO.Path]::GetFileName($LibraryPath) -ne ($ProjectName+'.dll')) {
    throw 'The build event must pass the matching project DLL output path.'
}
$outputDirectory = [IO.Path]::GetDirectoryName($LibraryPath)
[IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
if ($Stage -eq 'Prepare') {
    Write-Output ('PLUGIN_OUTPUT_PREPARED ' + $Config + ': ' + $outputDirectory)
    exit 0
}

# A successful build must include the decoder, not only FFmpeg's license files.
$provenance = Get-Content -LiteralPath (Join-Path $projectRoot 'ThirdParty\FFmpeg\provenance.json') -Raw | ConvertFrom-Json
foreach ($runtime in $provenance.files | Where-Object { $_.path -like 'ThirdParty\FFmpeg\bin\*' }) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $runtime.path) -PathType Leaf)) {
        throw 'FFmpeg runtime is missing. Run Scripts\PrepareFFmpeg.ps1 before building.'
    }
}
$pluginPath = Join-Path $outputDirectory ($ProjectName+'.auf2')
[IO.File]::Copy($LibraryPath, $pluginPath, $true)
if ($Config -eq 'Release') {
    $symbolsPath = Join-Path $outputDirectory ($ProjectName+'.rsm')
    if (Test-Path -LiteralPath $symbolsPath -PathType Leaf) {
        Remove-Item -LiteralPath $symbolsPath
    }
}

$runtimeFiles = foreach ($folder in @('Assets', 'ThirdParty')) {
    Get-ChildItem -LiteralPath (Join-Path $projectRoot $folder) -Recurse -File | ForEach-Object {
        $relativePath = $_.FullName.Substring($projectRoot.Length).TrimStart('\')
        $outputPath = Join-Path $outputDirectory $relativePath
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputPath)) | Out-Null
        if ($_.FullName -ne $outputPath) {
            [IO.File]::Copy($_.FullName, $outputPath, $true)
        }
        [pscustomobject]@{ Source = $outputPath; RelativePath = $relativePath }
    }
}
Write-Output ('PLUGIN_OUTPUT_COPIED ' + $Config + ': ' + $pluginPath)
if ([string]::IsNullOrWhiteSpace($DeployDirectory)) { exit 0 }

$deployRoot = [IO.Path]::GetFullPath($DeployDirectory).TrimEnd('\')
if ($deployRoot -ne (Join-Path 'C:\ProgramData\aviutl2\Plugin' $ProjectName)) {
    throw 'Unexpected plugin deployment directory.'
}
$deployment = @([pscustomobject]@{ Source = $pluginPath; RelativePath = ($ProjectName+'.auf2') }) + @($runtimeFiles)
$previewName = switch($ProjectName){'SYNC_RhythmBall'{'RhythmBallPreview.exe'}'SYNC_RhythmFireworks'{'RhythmFireworksPreview.exe'}default{'RhythmPreview.exe'}}
$previewPath = Join-Path $outputDirectory $previewName
if (Test-Path -LiteralPath $previewPath -PathType Leaf) {
    $deployment += [pscustomobject]@{ Source = $previewPath; RelativePath = $previewName }
}
# Check every existing destination before updating. Locked files remain untouched.
foreach ($entry in $deployment) {
    $destination = Join-Path $deployRoot $entry.RelativePath
    if ([IO.File]::Exists($destination)) {
        $exclusive = [IO.File]::Open($destination, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $exclusive.Dispose()
    }
}
foreach ($entry in $deployment) {
    $destination = Join-Path $deployRoot $entry.RelativePath
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
    [IO.File]::Copy($entry.Source, $destination, $true)
}
# DesignAssets and user settings are outside the deployment file list.
Write-Output ('PLUGIN_DEPLOYED ' + $Config + ': ' + (Join-Path $deployRoot ($ProjectName+'.auf2')))
