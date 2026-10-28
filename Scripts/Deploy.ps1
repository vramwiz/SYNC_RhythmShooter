param()
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
& (Join-Path $PSScriptRoot 'BuildPlugin.ps1') -Stage Complete -Config Release `
    -LibraryPath (Join-Path $projectRoot 'Win64\Release\SYNC_RhythmShooter.dll') `
    -DeployDirectory 'C:\ProgramData\aviutl2\Plugin\SYNC_RhythmShooter'
