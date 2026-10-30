@echo off
setlocal
set "BUILD_CONFIG=%~1"
if not defined BUILD_CONFIG set "BUILD_CONFIG=Debug"
if not "%BUILD_CONFIG%"=="Debug" if not "%BUILD_CONFIG%"=="Release" exit /b 2
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if errorlevel 1 exit /b %errorlevel%
pushd "%~dp0.."
if errorlevel 1 exit /b %errorlevel%
msbuild SYNC_RhythmRunner.dproj /t:Build /p:Config=%BUILD_CONFIG% /p:Platform=Win64 /nologo
set "BUILD_RESULT=%errorlevel%"
popd
exit /b %BUILD_RESULT%
