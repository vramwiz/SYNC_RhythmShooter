@echo off
call "%~dp0BuildPreview.cmd" SYNC_RhythmRunner %1
exit /b %errorlevel%
