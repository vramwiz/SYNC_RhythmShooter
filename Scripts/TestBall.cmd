@echo off
call "%~dp0RunNativeTest.cmd" BallPlanSmoke
exit /b %errorlevel%
