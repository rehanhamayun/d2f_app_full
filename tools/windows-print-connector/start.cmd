@echo off
cd /d "%~dp0"
where py >nul 2>nul
if errorlevel 1 (
  python connector.py
) else (
  py -3 connector.py
)
if errorlevel 1 echo Connector did not start. Install Python 3.9 or later and check the message above.
pause
