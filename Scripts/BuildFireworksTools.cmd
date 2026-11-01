@echo off
call "%~dp0BuildPreview.cmd" SYNC_RhythmFireworks %1
exit /b %errorlevel%
