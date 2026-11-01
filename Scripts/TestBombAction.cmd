@echo off
call "%~dp0RunNativeTest.cmd" BombActionPlanSmoke
exit /b %errorlevel%
