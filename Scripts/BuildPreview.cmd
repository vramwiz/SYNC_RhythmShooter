@echo off
setlocal
set "PREVIEW_PRODUCT=%~1"
set "PREVIEW_CONFIG=%~2"
if not defined PREVIEW_CONFIG set "PREVIEW_CONFIG=Debug"
if not "%PREVIEW_CONFIG%"=="Debug" if not "%PREVIEW_CONFIG%"=="Release" exit /b 2
set "PREVIEW_NAME="
for %%M in (Ball Breakout BombAction Mining Train Game) do if "%PREVIEW_PRODUCT%"=="SYNC_Rhythm%%M" set "PREVIEW_NAME=Rhythm%%MPreview"
if "%PREVIEW_PRODUCT%"=="SYNC_RhythmShooter" set "PREVIEW_NAME=RhythmPreview"
if not defined PREVIEW_NAME exit /b 2
for %%I in ("%~dp0..") do set "PREVIEW_ROOT=%%~fI"
set "PREVIEW_OUTPUT=%PREVIEW_ROOT%\Win64\%PREVIEW_PRODUCT:SYNC_=%\%PREVIEW_CONFIG%"
if "%PREVIEW_PRODUCT%"=="SYNC_RhythmShooter" set "PREVIEW_OUTPUT=%PREVIEW_ROOT%\Win64\%PREVIEW_CONFIG%"
if /i "%~3"=="Local" set "PREVIEW_OUTPUT=%PREVIEW_ROOT%\Win64\Local\%PREVIEW_PRODUCT%\%PREVIEW_CONFIG%"
if not exist "%PREVIEW_OUTPUT%\ToolsDCU" mkdir "%PREVIEW_OUTPUT%\ToolsDCU"
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if errorlevel 1 exit /b %errorlevel%
pushd "%PREVIEW_ROOT%\Tools"
if errorlevel 1 exit /b %errorlevel%
dcc64 -B -Q -NSSystem -E"%PREVIEW_OUTPUT%" -NU"%PREVIEW_OUTPUT%\ToolsDCU" -U"%BDS%\lib\Win64\release;%PREVIEW_ROOT%\Source\Shared\Audio;%PREVIEW_ROOT%\Source\Shared\Render;%PREVIEW_ROOT%\Source\Shared\Settings;%PREVIEW_ROOT%\Source\Shared\Common;%PREVIEW_ROOT%\Source\Shared\UI;%PREVIEW_ROOT%\Source\Shared\Host;%PREVIEW_ROOT%\Source\Composition;%PREVIEW_ROOT%\Source\Composition\Presentation;%PREVIEW_ROOT%\Source\Shooting;%PREVIEW_ROOT%\Source\Shooting\Assets;%PREVIEW_ROOT%\Source\Ball;%PREVIEW_ROOT%\Source\Fireworks;%PREVIEW_ROOT%\Source\Breakout;%PREVIEW_ROOT%\Source\Breakout\Score;%PREVIEW_ROOT%\Source\BombAction;%PREVIEW_ROOT%\Source\Mining;%PREVIEW_ROOT%\Source\Train;%PREVIEW_ROOT%\Source\MineCart;%PREVIEW_ROOT%\Source\CrashCannon;%PREVIEW_ROOT%\Source\TrapAction;%PREVIEW_ROOT%\Source\Parkour;%PREVIEW_ROOT%\Source\RobotWar;%PREVIEW_ROOT%\Source\MarbleRelay;%PREVIEW_ROOT%\Source\MarbleRelay\Planning;%PREVIEW_ROOT%\Source\SideRace;%PREVIEW_ROOT%\Source\FightingRush;%PREVIEW_ROOT%\Source\JumpAdventure;%PREVIEW_ROOT%\Source\RhythmGame;%PREVIEW_ROOT%\Source\RhythmGame\Orbit;%PREVIEW_ROOT%\Source\RhythmGame\Orbit\Render;%PREVIEW_ROOT%\Source\RhythmGame\Legacy;%PREVIEW_ROOT%\Source\RhythmGame\Step;%PREVIEW_ROOT%\Source\Lib;%PREVIEW_ROOT%\Source\Shared\Audio\MP3Decoder;%PREVIEW_ROOT%\Source\Shared\Audio\MP3Decoder\Core" "%PREVIEW_NAME%.dpr"
set "PREVIEW_RESULT=%errorlevel%"
popd
exit /b %PREVIEW_RESULT%
