param()
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourceRoot=Join-Path $projectRoot 'Win64\Release'
$destinationRoot='C:\ProgramData\aviutl2\Plugin\SYNC_RhythmShooter'
if([IO.Path]::GetFullPath($destinationRoot) -ne 'C:\ProgramData\aviutl2\Plugin\SYNC_RhythmShooter'){throw 'Unexpected deployment path'}
if(Test-Path -LiteralPath $destinationRoot){
  if(@(Get-ChildItem -LiteralPath $destinationRoot -Force).Count -gt 0){throw 'Deployment folder is nonempty; inspect conflicts before updating.'}
}
$files=@(Join-Path $sourceRoot 'SYNC_RhythmShooter.auf2')
$preview=Join-Path $sourceRoot 'RhythmPreview.exe'
if(Test-Path -LiteralPath $preview){$files+=$preview}
foreach($relative in @('Assets','ThirdParty')){
  $folder=Join-Path $sourceRoot $relative
  if(-not (Test-Path -LiteralPath $folder -PathType Container)){throw "Missing runtime folder: $relative"}
  $files+=@(Get-ChildItem -LiteralPath $folder -Recurse -File | Select-Object -ExpandProperty FullName)
}
foreach($file in $files){if(-not (Test-Path -LiteralPath $file -PathType Leaf)){throw "Missing runtime file: $file"}}
[IO.Directory]::CreateDirectory($destinationRoot)|Out-Null
$manifest=foreach($file in $files){
  $relative=[IO.Path]::GetRelativePath($sourceRoot,$file)
  $destination=[IO.Path]::GetFullPath((Join-Path $destinationRoot $relative))
  if(-not $destination.StartsWith($destinationRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Destination escaped deployment folder'}
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))|Out-Null
  [IO.File]::Copy($file,$destination,$false)
  $expected=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
  if((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $expected){throw "Hash mismatch: $relative"}
  [pscustomobject]@{Path=$relative;SHA256=$expected;Bytes=(Get-Item -LiteralPath $file).Length}
}
$manifest|ConvertTo-Json -Depth 3|Set-Content -LiteralPath (Join-Path $destinationRoot 'deployment-manifest.json') -Encoding UTF8
Write-Output "Deployed $($manifest.Count) files to $destinationRoot. AviUtl2 was not started."
