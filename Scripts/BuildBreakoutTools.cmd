@echo off
call "%~dp0BuildPreview.cmd" SYNC_RhythmBreakout %1
exit /b %errorlevel%
