param(
    [Parameter(Mandatory=$true)][string]$Fixtures,
    [string]$Music,
    [ValidateSet('Debug','Release')][string]$Config='Debug',
    [switch]$Audio
)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$testOutput=Join-Path $projectRoot 'Win64\NativeTests\NativeMP3Smoke'
if ($Config -eq 'Debug') { $testOutput=Join-Path $testOutput 'Checked' }
& (Join-Path $PSScriptRoot 'RunNativeTest.cmd') NativeMP3Smoke $Config CompileOnly
if ($LASTEXITCODE -ne 0) { throw 'Native MP3 test compile failed.' }
$previousLocalAppData=$env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA=Join-Path $testOutput ('TestUserData-'+[Guid]::NewGuid().ToString('N'))
    $arguments=@([IO.Path]::GetFullPath($Fixtures))
    if ($Music) { $arguments += [IO.Path]::GetFullPath($Music) }
    if ($Audio) { $arguments += '--audio' }
    & (Join-Path $testOutput 'NativeMP3Smoke.exe') @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Native MP3 integration test failed.' }
}
finally { $env:LOCALAPPDATA=$previousLocalAppData }
