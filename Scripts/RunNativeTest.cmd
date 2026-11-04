@echo off
setlocal
set "TEST_NAME=%~1"
if "%TEST_NAME%"=="SettingsCheckboxPreview" if /i not "%~3"=="CompileOnly" exit /b 2
if not "%TEST_NAME%"=="HostTimingSmoke" if not "%TEST_NAME%"=="StyleCatalogSmoke" if not "%TEST_NAME%"=="MVOverlaySmoke" if not "%TEST_NAME%"=="SettingsCheckboxPreview" if not "%TEST_NAME%"=="CheckboxThemeSmoke" if not "%TEST_NAME%"=="LayerCompositionSmoke" if not "%TEST_NAME%"=="OrbitPresentationSmoke" if not "%TEST_NAME%"=="OrbitStageSmoke" if not "%TEST_NAME%"=="OrbitAudioSmoke" if not "%TEST_NAME%"=="OrbitGuideSmoke" if not "%TEST_NAME%"=="OrbitAnticipationSmoke" if not "%TEST_NAME%"=="RhythmGamePlanSmoke" if not "%TEST_NAME%"=="RaceAlphaSmoke" if not "%TEST_NAME%"=="SettingsRttiSmoke" if not "%TEST_NAME%"=="AudioEdges" if not "%TEST_NAME%"=="RunnerVisualCheck" if not "%TEST_NAME%"=="RunnerPlanSmoke" if not "%TEST_NAME%"=="BallPlanSmoke" if not "%TEST_NAME%"=="BallCircuitSmoke" if not "%TEST_NAME%"=="BreakoutPlanSmoke" if not "%TEST_NAME%"=="FireworksPlanSmoke" if not "%TEST_NAME%"=="FightingPlanSmoke" if not "%TEST_NAME%"=="MiningPlanSmoke" if not "%TEST_NAME%"=="TrainPlanSmoke" if not "%TEST_NAME%"=="NavalPlanSmoke" if not "%TEST_NAME%"=="BombActionPlanSmoke" if not "%TEST_NAME%"=="RacePlanSmoke" if not "%TEST_NAME%"=="OnlinePassSmoke" if not "%TEST_NAME%"=="StyleIntegrationSmoke" if not "%TEST_NAME%"=="SettingsLayoutSmoke" if not "%TEST_NAME%"=="SettingsFormSmoke" if not "%TEST_NAME%"=="AnimationArchitectureSmoke" if not "%TEST_NAME%"=="BreakoutActionSmoke" if not "%TEST_NAME%"=="CombatSmoke" exit /b 2
for %%I in ("%~dp0..") do set "TEST_ROOT=%%~fI"
set "TEST_OUTPUT=%TEST_ROOT%\Win64\NativeTests\%TEST_NAME%"
set "TEST_CHECKS="
if not "%~2"=="" if not "%~2"=="Debug" if not "%~2"=="Release" exit /b 2
if "%~2"=="Debug" set "TEST_CHECKS=-$R+ -$Q+"
if "%~2"=="Debug" set "TEST_OUTPUT=%TEST_OUTPUT%\Checked"
if not exist "%TEST_OUTPUT%\DCU" mkdir "%TEST_OUTPUT%\DCU"
set "LOCALAPPDATA=%TEST_OUTPUT%\TestUserData"
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if errorlevel 1 exit /b %errorlevel%
pushd "%TEST_ROOT%\Tests"
if errorlevel 1 exit /b %errorlevel%
dcc64 -B -Q %TEST_CHECKS% -E"%TEST_OUTPUT%" -NU"%TEST_OUTPUT%\DCU" -U"%BDS%\lib\Win64\release;%TEST_ROOT%\Source\Shared\Audio;%TEST_ROOT%\Source\Shared\Render;%TEST_ROOT%\Source\Shared\Settings;%TEST_ROOT%\Source\Shared\Common;%TEST_ROOT%\Source\Shared\Assets;%TEST_ROOT%\Source\Shared\UI;%TEST_ROOT%\Source\Shared\Host;%TEST_ROOT%\Source\Shared\Integrations;%TEST_ROOT%\Source\Composition;%TEST_ROOT%\Source\Shooting;%TEST_ROOT%\Source\Ball;%TEST_ROOT%\Source\Fireworks;%TEST_ROOT%\Source\Runner;%TEST_ROOT%\Source\Breakout;%TEST_ROOT%\Source\Race;%TEST_ROOT%\Source\BombAction;%TEST_ROOT%\Source\Fighting;%TEST_ROOT%\Source\Mining;%TEST_ROOT%\Source\Train;%TEST_ROOT%\Source\Naval;%TEST_ROOT%\Source\RhythmGame;%TEST_ROOT%\Source\Lib;%TEST_ROOT%\Source\Lib\Process" "%TEST_NAME%.dpr"
set "TEST_RESULT=%errorlevel%"
popd
if not "%TEST_RESULT%"=="0" exit /b %TEST_RESULT%
if /i "%~3"=="CompileOnly" exit /b 0
pushd "%TEST_ROOT%"
"%TEST_OUTPUT%\%TEST_NAME%.exe"
set "TEST_RESULT=%errorlevel%"
popd
exit /b %TEST_RESULT%
