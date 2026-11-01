@echo off
call "%~dp0BuildPreview.cmd" SYNC_RhythmTrain %1
exit /b %errorlevel%
