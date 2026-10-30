@echo off
setlocal
set "RHYTHM_CONFIG=%~1"
if not defined RHYTHM_CONFIG set "RHYTHM_CONFIG=Debug"
if /i not "%RHYTHM_CONFIG%"=="Debug" if /i not "%RHYTHM_CONFIG%"=="Release" exit /b 2
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if errorlevel 1 exit /b %errorlevel%
pushd "%~dp0.."
if errorlevel 1 exit /b %errorlevel%
if not exist "Win64\RhythmBall\%RHYTHM_CONFIG%\ToolsDCU" mkdir "Win64\RhythmBall\%RHYTHM_CONFIG%\ToolsDCU"
dcc64 -B -Q -E"Win64\RhythmBall\%RHYTHM_CONFIG%" -NU"Win64\RhythmBall\%RHYTHM_CONFIG%\ToolsDCU" -U"%BDS%\lib\Win64\release;Source\Shared\Audio;Source\Shared\Render;Source\Shared\Settings;Source\Shared\Common;Source\Shared\Assets;Source\Shared\UI;Source\Shared\Host;Source\Shared\Integrations;Source\Composition;Source\Shooting;Source\Ball;Source\Fireworks;Source\Lib;Source\Lib\Process" Tools\RhythmBallPreview.dpr
exit /b %errorlevel%
