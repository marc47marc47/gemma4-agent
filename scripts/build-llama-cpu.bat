@echo off
REM Gemma 4 Agent - llama.cpp Build Script (CPU only)

setlocal enabledelayedexpansion

echo.
echo ==============================================
echo   Gemma 4 Agent - llama.cpp Build (CPU)
echo ==============================================
echo.

REM Find Visual Studio
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"

for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
    set "VS_PATH=%%i"
)

echo [INFO] Found Visual Studio at: %VS_PATH%
echo [INFO] Setting up environment...

call "%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1

set "SCRIPT_DIR=%~dp0"
set "LLAMA_DIR=%SCRIPT_DIR%..\llama.cpp"

cd /d "%LLAMA_DIR%"

if exist "build" rmdir /s /q build

echo.
echo [INFO] Configuring CMake (CPU only)...
cmake -B build

echo.
echo [INFO] Building (this takes a few minutes)...
cmake --build build --config Release -j %NUMBER_OF_PROCESSORS%

echo.
echo ==============================================
echo   Build Complete!
echo ==============================================

if exist "build\bin\Release\llama-server.exe" (
    echo [OK] llama-server: %LLAMA_DIR%\build\bin\Release\llama-server.exe
)

echo.
pause
