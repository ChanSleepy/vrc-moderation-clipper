@echo off
REM Launches the VRChat Moderation Clipper (kicks, warnings, bans, etc.).
REM Adapted from the launcher in https://github.com/Elocin-Anagram/VRC_World_Location
REM
REM %~dp0 is the folder this .bat file is in, so the script is found even if
REM the .bat is started from a shortcut or "Run as administrator".
REM -NoExit keeps the window open so any error message stays visible.

PowerShell -NoExit -ExecutionPolicy Bypass -File "%~dp0VRChat_Moderation_Clipper.ps1"

pause
