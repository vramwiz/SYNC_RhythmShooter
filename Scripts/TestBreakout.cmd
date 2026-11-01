@echo off
call "%~dp0RunNativeTest.cmd" BreakoutPlanSmoke
exit /b %errorlevel%
