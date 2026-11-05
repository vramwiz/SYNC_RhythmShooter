@echo off
setlocal
set "LOCAL_PRODUCT=%~1"
set "LOCAL_CONFIG=%~2"
if not defined LOCAL_CONFIG set "LOCAL_CONFIG=Debug"
if not "%LOCAL_CONFIG%"=="Debug" if not "%LOCAL_CONFIG%"=="Release" exit /b 2
if not "%LOCAL_PRODUCT%"=="SYNC_RhythmShooter" if not "%LOCAL_PRODUCT%"=="SYNC_RhythmBall" if not "%LOCAL_PRODUCT%"=="SYNC_RhythmFireworks" if not "%LOCAL_PRODUCT%"=="SYNC_RhythmRunner" if not "%LOCAL_PRODUCT%"=="SYNC_RhythmBreakout" if not "%LOCAL_PRODUCT%"=="SYNC_RhythmBombAction" if not "%LOCAL_PRODUCT%"=="SYNC_RhythmMining" if not "%LOCAL_PRODUCT%"=="SYNC_RhythmTrain" if not "%LOCAL_PRODUCT%"=="SYNC_RhythmNaval" if not "%LOCAL_PRODUCT%"=="SYNC_RhythmGame" exit /b 2
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if errorlevel 1 exit /b %errorlevel%
pushd "%~dp0.."
if errorlevel 1 exit /b %errorlevel%
set "LOCAL_OUTPUT=%CD%\Win64\Local\%LOCAL_PRODUCT%\%LOCAL_CONFIG%"
if not exist "%LOCAL_OUTPUT%\DCU" mkdir "%LOCAL_OUTPUT%\DCU"
msbuild "%LOCAL_PRODUCT%.dproj" /t:Build /p:Config=%LOCAL_CONFIG% /p:Platform=Win64 /p:DCC_BuildAllUnits=true /p:DCC_ExeOutput="%LOCAL_OUTPUT%" /p:DCC_DcuOutput="%LOCAL_OUTPUT%\DCU" /p:FinalOutputDir="%LOCAL_OUTPUT%" /p:IntermediateOutputPath="%LOCAL_OUTPUT%\Obj" /p:RhythmDeployDirectory= /p:PreBuildEvent= /p:PreLinkEvent= /p:PostBuildEvent= /p:SkipResGeneration=true /nologo /v:minimal /fl /flp:"logfile=%LOCAL_OUTPUT%\build.log;encoding=UTF-8;verbosity=normal"
set "LOCAL_RESULT=%errorlevel%"
if not "%LOCAL_RESULT%"=="0" goto finish
copy /b /y "%LOCAL_OUTPUT%\%LOCAL_PRODUCT%.dll" "%LOCAL_OUTPUT%\%LOCAL_PRODUCT%.auf2" >nul
set "LOCAL_RESULT=%errorlevel%"
:finish
popd
exit /b %LOCAL_RESULT%
