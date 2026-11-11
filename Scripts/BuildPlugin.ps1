param(
    [Parameter(Mandatory = $true)][ValidateSet('Prepare', 'Complete')][string]$Stage,
    [Parameter(Mandatory = $true)][ValidateSet('Debug', 'Release')][string]$Config,
    [Parameter(Mandatory = $true)][string]$LibraryPath,
    [string]$DeployDirectory,
    [ValidateSet('SYNC_RhythmShooter','SYNC_RhythmBall','SYNC_RhythmBreakout','SYNC_RhythmBombAction','SYNC_RhythmMining','SYNC_RhythmTrain','SYNC_RhythmGame')][string]$ProjectName='SYNC_RhythmShooter'
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

# MP3 is linked into the DLL; WAV uses Windows. Only the decoder notices are bundled.
foreach ($notice in @('LICENSE.md','provenance.json','CORE_CHANGES.md','integration.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot ('ThirdParty\MP3Decoder\'+$notice)) -PathType Leaf)) {
        throw "MP3 decoder notice is missing: $notice"
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

$runtimeFiles = foreach ($notice in @('LICENSE.md','provenance.json','CORE_CHANGES.md','integration.json')) {
    $relativePath = 'ThirdParty\MP3Decoder\' + $notice
    $sourcePath = Join-Path $projectRoot $relativePath
    $outputPath = Join-Path $outputDirectory $relativePath
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputPath)) | Out-Null
    if ($sourcePath -ne $outputPath) { [IO.File]::Copy($sourcePath, $outputPath, $true) }
    [pscustomobject]@{ Source = $outputPath; RelativePath = $relativePath }
}
Write-Output ('PLUGIN_OUTPUT_COPIED ' + $Config + ': ' + $pluginPath)
if ([string]::IsNullOrWhiteSpace($DeployDirectory)) { exit 0 }

$deployRoot = [IO.Path]::GetFullPath($DeployDirectory).TrimEnd('\')
if ($deployRoot -ne (Join-Path 'C:\ProgramData\aviutl2\Plugin' $ProjectName)) {
    throw 'Unexpected plugin deployment directory.'
}
$deployment = @([pscustomobject]@{ Source = $pluginPath; RelativePath = ($ProjectName+'.auf2') }) + @($runtimeFiles)
$previewName = switch($ProjectName){'SYNC_RhythmBall'{'RhythmBallPreview.exe'}'SYNC_RhythmBreakout'{'RhythmBreakoutPreview.exe'}'SYNC_RhythmBombAction'{'RhythmBombActionPreview.exe'}'SYNC_RhythmMining'{'RhythmMiningPreview.exe'}'SYNC_RhythmTrain'{'RhythmTrainPreview.exe'}'SYNC_RhythmGame'{'RhythmGamePreview.exe'}default{'RhythmPreview.exe'}}
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
# Deployment includes the plugin, optional preview and decoder notices.
Write-Output ('PLUGIN_DEPLOYED ' + $Config + ': ' + (Join-Path $deployRoot ($ProjectName+'.auf2')))
