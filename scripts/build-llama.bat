@echo off
REM Gemma 4 Agent - llama.cpp Build Script for Windows
REM This script sets up Visual Studio environment and builds llama.cpp with CUDA

setlocal enabledelayedexpansion

echo.
echo ==============================================
echo   Gemma 4 Agent - llama.cpp Build Script
echo ==============================================
echo.

REM Find Visual Studio installation
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"

if not exist "%VSWHERE%" (
    echo [ERROR] Visual Studio not found.
    echo Please install Visual Studio or Visual Studio Build Tools.
    pause
    exit /b 1
)

REM Get VS installation path
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
    set "VS_PATH=%%i"
)

if not defined VS_PATH (
    echo [ERROR] C++ Build Tools not found in Visual Studio.
    echo Please install "Desktop development with C++" workload.
    pause
    exit /b 1
)

echo [INFO] Found Visual Studio at: %VS_PATH%

REM Setup Visual Studio environment
echo [INFO] Setting up Visual Studio environment...
call "%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1

if errorlevel 1 (
    echo [ERROR] Failed to setup Visual Studio environment.
    pause
    exit /b 1
)

REM Change to llama.cpp directory
set "SCRIPT_DIR=%~dp0"
set "PROJECT_DIR=%SCRIPT_DIR%.."
set "LLAMA_DIR=%PROJECT_DIR%\llama.cpp"

if not exist "%LLAMA_DIR%" (
    echo [ERROR] llama.cpp directory not found at: %LLAMA_DIR%
    pause
    exit /b 1
)

cd /d "%LLAMA_DIR%"

REM Clean previous build
if exist "build" (
    echo [INFO] Cleaning previous build...
    rmdir /s /q build
)

REM Check for CUDA
where nvcc >nul 2>&1
if %errorlevel% equ 0 (
    echo [INFO] CUDA detected. Building with CUDA support...
    set "CMAKE_FLAGS=-DGGML_CUDA=ON -DLLAMA_CURL=ON"
) else (
    echo [WARN] CUDA not found. Building CPU-only version...
    set "CMAKE_FLAGS=-DLLAMA_CURL=ON"
)

REM Configure CMake
echo.
echo [INFO] Configuring CMake...
echo Running: cmake -B build %CMAKE_FLAGS%
echo.

cmake -B build %CMAKE_FLAGS%
if errorlevel 1 (
    echo.
    echo [ERROR] CMake configuration failed.
    pause
    exit /b 1
)

REM Build
echo.
echo [INFO] Building llama.cpp (this may take several minutes)...
echo.

cmake --build build --config Release -j %NUMBER_OF_PROCESSORS%
if errorlevel 1 (
    echo.
    echo [ERROR] Build failed.
    pause
    exit /b 1
)

echo.
echo ==============================================
echo   Build Complete!
echo ==============================================
echo.

REM Find llama-server
if exist "build\bin\Release\llama-server.exe" (
    echo [OK] llama-server built at:
    echo      %LLAMA_DIR%\build\bin\Release\llama-server.exe
) else if exist "build\bin\llama-server.exe" (
    echo [OK] llama-server built at:
    echo      %LLAMA_DIR%\build\bin\llama-server.exe
) else (
    echo [WARN] llama-server.exe not found in expected location.
    echo        Please check the build output above.
)

echo.
echo Next steps:
echo   1. Install OpenCode: npm i -g opencode-ai
echo   2. Run the agent:    npm run dev
echo.
pause
