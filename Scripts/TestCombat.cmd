@echo off
setlocal
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if errorlevel 1 exit /b %errorlevel%
pushd "%~dp0.."
if errorlevel 1 exit /b %errorlevel%
if not exist "Win64\CombatDCU" mkdir "Win64\CombatDCU"
if not exist "Win64\Debug\Assets" mkdir "Win64\Debug\Assets"
xcopy "Assets\*" "Win64\Debug\Assets\" /E /I /Y /Q >nul
if errorlevel 1 exit /b %errorlevel%
dcc64 -B -Q -E"Win64\Debug" -NU"Win64\CombatDCU" -U"%BDS%\lib\Win64\release;Source\Audio;Source\Engine;Source\Common;Source\UI;Source\Integrations;Source\Lib\Process" Tests\CombatSmoke.dpr
if errorlevel 1 exit /b %errorlevel%
set "LOCALAPPDATA=%CD%\Win64\CombatTestUserData"
if "%~1"=="" (
  "Win64\Debug\CombatSmoke.exe"
) else (
  if not exist "Win64\Debug\ThirdParty\FFmpeg" mkdir "Win64\Debug\ThirdParty\FFmpeg"
  xcopy "ThirdParty\FFmpeg\*" "Win64\Debug\ThirdParty\FFmpeg\" /E /I /Y /Q >nul
  if errorlevel 1 exit /b 1
  "Win64\Debug\CombatSmoke.exe" "%~1"
)
exit /b %errorlevel%
