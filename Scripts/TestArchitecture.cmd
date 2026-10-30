@echo off
setlocal
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if errorlevel 1 exit /b %errorlevel%
pushd "%~dp0.."
if errorlevel 1 exit /b %errorlevel%
if not exist "Win64\ArchitectureTests\DCU" mkdir "Win64\ArchitectureTests\DCU"
dcc64 -B -Q -E"Win64\ArchitectureTests" -NU"Win64\ArchitectureTests\DCU" -U"%BDS%\lib\Win64\release;Source\Shared\Audio;Source\Shared\Render;Source\Shared\Settings;Source\Shared\Common;Source\Shared\Assets;Source\Shared\UI;Source\Shared\Host;Source\Shared\Integrations;Source\Composition;Source\Shooting;Source\Ball;Source\Fireworks;Source\Lib;Source\Lib\Process" Tests\AnimationArchitectureSmoke.dpr
if errorlevel 1 exit /b %errorlevel%
set "LOCALAPPDATA=%CD%\Win64\ArchitectureTests\TestUserData"
"Win64\ArchitectureTests\AnimationArchitectureSmoke.exe"
exit /b %errorlevel%
