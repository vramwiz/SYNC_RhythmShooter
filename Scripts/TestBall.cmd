@echo off
setlocal
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if errorlevel 1 exit /b %errorlevel%
pushd "%~dp0.."
if errorlevel 1 exit /b %errorlevel%
if not exist "Win64\BallTests\DCU" mkdir "Win64\BallTests\DCU"
set "LOCALAPPDATA=%CD%\Win64\BallTests\TestUserData"
dcc64 -B -Q -E"Win64\BallTests" -NU"Win64\BallTests\DCU" -U"%BDS%\lib\Win64\release;Source\Shared\Audio;Source\Shared\Render;Source\Shared\Settings;Source\Shared\Common;Source\Shared\Assets;Source\Shared\UI;Source\Shared\Host;Source\Shared\Integrations;Source\Composition;Source\Shooting;Source\Ball;Source\Fireworks;Source\Runner;Source\Lib;Source\Lib\Process" Tests\BallPlanSmoke.dpr
if errorlevel 1 exit /b %errorlevel%
"Win64\BallTests\BallPlanSmoke.exe"
exit /b %errorlevel%
