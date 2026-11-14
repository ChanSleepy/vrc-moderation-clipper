@echo off
REM This batch file runs a PowerShell script without administrative privileges.

REM The script "VRC_Locator.PS1" is called using its file name because it's in the same folder.
PowerShell -NoExit -ExecutionPolicy Bypass -File "VRChat_VoteKick_Clipper.ps1"

pause
