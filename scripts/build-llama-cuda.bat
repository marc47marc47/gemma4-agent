@echo off
REM Gemma 4 Agent - llama.cpp Build Script (CUDA)
REM This version explicitly specifies CUDA compiler path

setlocal enabledelayedexpansion

echo.
echo ==============================================
echo   Gemma 4 Agent - llama.cpp Build (CUDA)
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

REM Set CUDA paths explicitly
set "CUDA_PATH=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.2"
set "CUDA_TOOLKIT_ROOT_DIR=%CUDA_PATH%"
set "PATH=%CUDA_PATH%\bin;%PATH%"

echo [INFO] CUDA Path: %CUDA_PATH%

REM Verify nvcc
where nvcc >nul 2>&1
if errorlevel 1 (
    echo [ERROR] nvcc not found in PATH
    pause
    exit /b 1
)
echo [OK] nvcc found

set "SCRIPT_DIR=%~dp0"
set "LLAMA_DIR=%SCRIPT_DIR%..\llama.cpp"

cd /d "%LLAMA_DIR%"

if exist "build" (
    echo [INFO] Cleaning previous build...
    rmdir /s /q build
)

echo.
echo [INFO] Configuring CMake with CUDA...
echo.

REM Use Ninja generator instead of Visual Studio for better CUDA compatibility
cmake -B build ^
    -DGGML_CUDA=ON ^
    -DCMAKE_CUDA_COMPILER="%CUDA_PATH%\bin\nvcc.exe" ^
    -DCMAKE_CUDA_ARCHITECTURES=86 ^
    -G "Ninja"

if errorlevel 1 (
    echo.
    echo [WARN] Ninja build failed, trying Visual Studio generator...
    rmdir /s /q build 2>nul

    cmake -B build ^
        -DGGML_CUDA=ON ^
        -DCMAKE_CUDA_COMPILER="%CUDA_PATH%\bin\nvcc.exe" ^
        -G "Visual Studio 17 2022" ^
        -T cuda="%CUDA_PATH%"

    if errorlevel 1 (
        echo.
        echo [ERROR] CMake configuration failed.
        echo.
        echo Please run as Administrator:
        echo   scripts\fix-cuda-vs-integration.bat
        echo.
        pause
        exit /b 1
    )
)

echo.
echo [INFO] Building llama.cpp with CUDA (this may take several minutes)...
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
echo   CUDA Build Complete!
echo ==============================================

if exist "build\bin\Release\llama-server.exe" (
    echo [OK] llama-server: %LLAMA_DIR%\build\bin\Release\llama-server.exe
) else if exist "build\bin\llama-server.exe" (
    echo [OK] llama-server: %LLAMA_DIR%\build\bin\llama-server.exe
)

echo.
pause
