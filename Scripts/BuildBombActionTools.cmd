@echo off
call "%~dp0BuildPreview.cmd" SYNC_RhythmBombAction %1
exit /b %errorlevel%
