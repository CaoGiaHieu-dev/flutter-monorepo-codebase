@echo off
setlocal enabledelayedexpansion

:: Prioritize Git Bash standard installation paths to avoid WSL bash conflicts
set "BASH_PATH="
if exist "%PROGRAMFILES%\Git\bin\bash.exe" (
    set "BASH_PATH=%PROGRAMFILES%\Git\bin\bash.exe"
) else if exist "%PROGRAMFILES(x86)%\Git\bin\bash.exe" (
    set "BASH_PATH=%PROGRAMFILES(x86)%\Git\bin\bash.exe"
) else if exist "%LocalAppData%\Programs\Git\bin\bash.exe" (
    set "BASH_PATH=%LocalAppData%\Programs\Git\bin\bash.exe"
) else (
    where bash >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        set "BASH_PATH=bash"
    )
)

if "%BASH_PATH%"=="" (
    echo [ERROR] Git Bash ^(bash.exe^) was not found on your system.
    echo Please install Git for Windows to run this checker on Windows.
    exit /b 1
)

:: Run the original .sh script via Git Bash
"%BASH_PATH%" "%~dp016kb_ckeck.sh" %*
