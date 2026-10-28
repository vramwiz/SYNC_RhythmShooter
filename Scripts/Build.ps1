param([ValidateSet('Debug','Release')][string]$Config='Debug',[switch]$Tools)
$ErrorActionPreference='Stop'
if($Tools){
  & $env:ComSpec /d /c (Join-Path $PSScriptRoot 'BuildTools.cmd') $Config
  if($LASTEXITCODE -ne 0){throw "Tools build failed ($LASTEXITCODE)"}
}
& $env:ComSpec /d /c (Join-Path $PSScriptRoot 'Build.cmd') $Config
if($LASTEXITCODE -ne 0){throw "Plugin build failed ($LASTEXITCODE)"}
