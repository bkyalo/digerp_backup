@echo off
REM Windows Task Scheduler action target.
REM Task Scheduler action: Program/script = full path to this .bat file
REM                        Start in       = this folder
REM Trigger: daily at 03:30 (gives the remote backup server, which runs
REM its dump around 03:00, time to finish before we start polling)
cd /d "%~dp0"
python backup_fetch.py
