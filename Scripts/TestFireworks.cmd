@echo off
setlocal
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if errorlevel 1 exit /b %errorlevel%
pushd "%~dp0.."
if errorlevel 1 exit /b %errorlevel%
if not exist "Win64\FireworksTests\DCU" mkdir "Win64\FireworksTests\DCU"
set "LOCALAPPDATA=%CD%\Win64\FireworksTests\TestUserData"
dcc64 -B -Q -E"Win64\FireworksTests" -NU"Win64\FireworksTests\DCU" -U"%BDS%\lib\Win64\release;Source\Shared\Audio;Source\Shared\Render;Source\Shared\Settings;Source\Shared\Common;Source\Shared\Assets;Source\Shared\UI;Source\Shared\Host;Source\Shared\Integrations;Source\Composition;Source\Shooting;Source\Ball;Source\Fireworks;Source\Lib;Source\Lib\Process" Tests\FireworksPlanSmoke.dpr
if errorlevel 1 exit /b %errorlevel%
"Win64\FireworksTests\FireworksPlanSmoke.exe"
exit /b %errorlevel%
