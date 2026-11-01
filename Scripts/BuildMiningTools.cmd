@echo off
call "%~dp0BuildPreview.cmd" SYNC_RhythmMining %1
exit /b %errorlevel%
