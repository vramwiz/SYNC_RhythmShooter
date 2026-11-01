@echo off
call "%~dp0RunNativeTest.cmd" NavalPlanSmoke
exit /b %errorlevel%
