@echo off
setlocal
set "RHYTHM_CONFIG=%~1"
if not defined RHYTHM_CONFIG set "RHYTHM_CONFIG=Debug"
if /i not "%RHYTHM_CONFIG%"=="Debug" if /i not "%RHYTHM_CONFIG%"=="Release" exit /b 2
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if errorlevel 1 exit /b %errorlevel%
pushd "%~dp0.."
if errorlevel 1 exit /b %errorlevel%
if not exist "Win64\RhythmBall" mkdir "Win64\RhythmBall"
msbuild "SYNC_RhythmBall.dproj" /t:Build /p:Config=%RHYTHM_CONFIG% /p:Platform=Win64 /nologo /v:minimal /fl /flp:"logfile=Win64\RhythmBall\%RHYTHM_CONFIG%.build.log;encoding=UTF-8;verbosity=normal"
exit /b %errorlevel%
