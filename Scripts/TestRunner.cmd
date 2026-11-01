@echo off
call "%~dp0RunNativeTest.cmd" RunnerPlanSmoke
exit /b %errorlevel%
