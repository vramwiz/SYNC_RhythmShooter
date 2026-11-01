@echo off
call "%~dp0BuildPreview.cmd" SYNC_RhythmBall %1
exit /b %errorlevel%
