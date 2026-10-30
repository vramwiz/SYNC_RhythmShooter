param([ValidateSet('Debug','Release')][string]$Config='Debug',[switch]$Tools,[ValidateSet('SYNC_RhythmShooter','SYNC_RhythmBall','SYNC_RhythmFireworks')][string]$ProjectName='SYNC_RhythmShooter')
$ErrorActionPreference='Stop'
$toolScript=switch($ProjectName){'SYNC_RhythmBall'{'BuildBallTools.cmd'}'SYNC_RhythmFireworks'{'BuildFireworksTools.cmd'}default{'BuildTools.cmd'}}
$buildScript=switch($ProjectName){'SYNC_RhythmBall'{'BuildBall.cmd'}'SYNC_RhythmFireworks'{'BuildFireworks.cmd'}default{'Build.cmd'}}
if($Tools){ & $env:ComSpec /d /c (Join-Path $PSScriptRoot $toolScript) $Config;if($LASTEXITCODE -ne 0){throw "Tools build failed ($LASTEXITCODE)"} }
& $env:ComSpec /d /c (Join-Path $PSScriptRoot $buildScript) $Config
if($LASTEXITCODE -ne 0){throw "Plugin build failed ($LASTEXITCODE)"}
