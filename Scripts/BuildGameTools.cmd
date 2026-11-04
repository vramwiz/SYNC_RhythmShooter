@echo off
call "%~dp0BuildPreview.cmd" SYNC_RhythmGame %1 Local
exit /b %errorlevel%
