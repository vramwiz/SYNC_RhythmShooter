@echo off
call "%~dp0RunNativeTest.cmd" MiningPlanSmoke
exit /b %errorlevel%
