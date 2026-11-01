@echo off
call "%~dp0RunNativeTest.cmd" TrainPlanSmoke
exit /b %errorlevel%
