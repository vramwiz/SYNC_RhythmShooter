@echo off
setlocal
set "RHYTHM_CONFIG="
if /i "%~1"=="Debug" set "RHYTHM_CONFIG=Debug"
if /i "%~1"=="Release" set "RHYTHM_CONFIG=Release"
if not defined RHYTHM_CONFIG exit /b 2
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if errorlevel 1 exit /b %errorlevel%
pushd "%~dp0.."
if errorlevel 1 exit /b %errorlevel%
if not exist "Win64\ToolsDCU" mkdir "Win64\ToolsDCU"
if not exist "Win64\%RHYTHM_CONFIG%" mkdir "Win64\%RHYTHM_CONFIG%"
dcc64 -B -Q -E"Win64\%RHYTHM_CONFIG%" -NU"Win64\ToolsDCU" -U"%BDS%\lib\Win64\release;Source\Shared\Audio;Source\Shared\Render;Source\Shared\Settings;Source\Shared\Common;Source\Shared\Assets;Source\Shared\UI;Source\Shared\Host;Source\Shared\Integrations;Source\Composition;Source\Shooting;Source\Ball;Source\Fireworks;Source\Lib;Source\Lib\Process" Tools\BuildAssets.dpr
if errorlevel 1 exit /b %errorlevel%
"Win64\%RHYTHM_CONFIG%\BuildAssets.exe" "%CD%\Assets"
if errorlevel 1 exit /b %errorlevel%
dcc64 -B -Q -E"Win64\%RHYTHM_CONFIG%" -NU"Win64\ToolsDCU" -U"%BDS%\lib\Win64\release;Source\Shared\Audio;Source\Shared\Render;Source\Shared\Settings;Source\Shared\Common;Source\Shared\Assets;Source\Shared\UI;Source\Shared\Host;Source\Shared\Integrations;Source\Composition;Source\Shooting;Source\Ball;Source\Fireworks;Source\Lib;Source\Lib\Process" Tools\RhythmPreview.dpr
exit /b %errorlevel%
