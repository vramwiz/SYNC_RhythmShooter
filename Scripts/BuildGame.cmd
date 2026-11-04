@echo off
call "%~dp0BuildLocal.cmd" SYNC_RhythmGame %1
exit /b %errorlevel%
