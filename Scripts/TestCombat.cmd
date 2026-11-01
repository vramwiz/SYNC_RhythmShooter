@echo off
call "%~dp0RunNativeTest.cmd" CombatSmoke
exit /b %errorlevel%
