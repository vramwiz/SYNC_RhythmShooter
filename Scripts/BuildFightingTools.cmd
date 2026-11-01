@echo off
call "%~dp0BuildPreview.cmd" SYNC_RhythmFighting %1
exit /b %errorlevel%
