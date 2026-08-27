@echo off
REM Windows Task Scheduler action target.
REM Task Scheduler action: Program/script = full path to this .bat file
REM                        Start in       = this folder
REM Trigger: daily at 03:00 (must match poll_start_time in config.json)
cd /d "%~dp0"
python backup_fetch.py
