@echo off
call "%~dp0RunNativeTest.cmd" RacePlanSmoke
exit /b %errorlevel%
