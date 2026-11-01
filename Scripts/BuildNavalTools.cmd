@echo off
call "%~dp0BuildPreview.cmd" SYNC_RhythmNaval %1
exit /b %errorlevel%
