@echo off
call "%~dp0BuildPreview.cmd" SYNC_RhythmRace %1
exit /b %errorlevel%
