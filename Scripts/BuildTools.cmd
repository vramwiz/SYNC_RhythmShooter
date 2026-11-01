@echo off
call "%~dp0BuildPreview.cmd" SYNC_RhythmShooter %1
exit /b %errorlevel%
