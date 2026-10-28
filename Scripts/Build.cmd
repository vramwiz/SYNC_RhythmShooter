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
if not exist "Win64" mkdir "Win64"
msbuild "SYNC_RhythmShooter.dproj" /t:Build /p:Config=%RHYTHM_CONFIG% /p:Platform=Win64 /nologo /v:minimal /fl /flp:"logfile=Win64\%RHYTHM_CONFIG%.build.log;encoding=UTF-8;verbosity=normal"
exit /b %errorlevel%
