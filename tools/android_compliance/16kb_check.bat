@echo off
setlocal enabledelayedexpansion

:: Android 15+ 16KB page size check - Windows wrapper around 16kb_check.sh.
::
:: Usage (from the repository root):
::   .\tools\android_compliance\16kb_check.bat <input-path|input-APK|input-APEX>
::
:: A Flutter release APK is at
::   apps\<app>\build\app\outputs\flutter-apk\app-<flavor>-release.apk
:: e.g. after `flutter build apk --flavor dev --release` in apps\mobile:
::   .\tools\android_compliance\16kb_check.bat apps\mobile\build\app\outputs\flutter-apk\app-dev-release.apk

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
    echo [ERROR] Git Bash ^(bash.exe^) was not found on your system. 1>&2
    echo Please install Git for Windows to run this checker on Windows. 1>&2
    exit /b 1
)

:: Run the original .sh script via Git Bash; its exit code is ours.
"%BASH_PATH%" "%~dp016kb_check.sh" %*
exit /b %ERRORLEVEL%
