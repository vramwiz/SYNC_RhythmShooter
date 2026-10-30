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
set "RHYTHM_OUTPUT=%CD%\Win64\Revision4\%RHYTHM_CONFIG%"
if not exist "%RHYTHM_OUTPUT%\DCU" mkdir "%RHYTHM_OUTPUT%\DCU"
msbuild SYNC_RhythmShooter.dproj /t:Build /p:Config=%RHYTHM_CONFIG% /p:Platform=Win64 /p:DCC_ExeOutput="%RHYTHM_OUTPUT%" /p:DCC_DcuOutput="%RHYTHM_OUTPUT%\DCU" /p:RhythmDeployDirectory= /nologo /v:minimal /fl /flp:"logfile=Win64\Revision4\%RHYTHM_CONFIG%.build.log;encoding=UTF-8;verbosity=normal"
if errorlevel 1 exit /b %errorlevel%
dcc64 -B -Q -E"%RHYTHM_OUTPUT%" -NU"%RHYTHM_OUTPUT%\DCU" -U"%BDS%\lib\Win64\release;Source\Shared\Audio;Source\Shared\Render;Source\Shared\Settings;Source\Shared\Common;Source\Shared\Assets;Source\Shared\UI;Source\Shared\Host;Source\Shared\Integrations;Source\Composition;Source\Shooting;Source\Ball;Source\Fireworks;Source\Lib;Source\Lib\Process" Tools\RhythmPreview.dpr
exit /b %errorlevel%
