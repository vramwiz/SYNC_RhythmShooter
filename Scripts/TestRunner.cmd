@echo off
setlocal
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if errorlevel 1 exit /b %errorlevel%
pushd "%~dp0.."
if errorlevel 1 exit /b %errorlevel%
if not exist "Win64\RunnerTests\DCU" mkdir "Win64\RunnerTests\DCU"
set "LOCALAPPDATA=%CD%\Win64\RunnerTests\TestUserData"
dcc64 -B -Q -E"Win64\RunnerTests" -NU"Win64\RunnerTests\DCU" -U"%BDS%\lib\Win64\release;Source\Shared\Audio;Source\Shared\Render;Source\Shared\Settings;Source\Shared\Common;Source\Shared\Assets;Source\Shared\UI;Source\Shared\Host;Source\Shared\Integrations;Source\Composition;Source\Shooting;Source\Ball;Source\Fireworks;Source\Runner;Source\Lib;Source\Lib\Process" Tests\RunnerPlanSmoke.dpr
if errorlevel 1 exit /b %errorlevel%
"Win64\RunnerTests\RunnerPlanSmoke.exe"
exit /b %errorlevel%
