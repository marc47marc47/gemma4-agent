@echo off
REM Fix CUDA Visual Studio Integration
REM Run this script as Administrator

echo ==============================================
echo   Fixing CUDA Visual Studio Integration
echo ==============================================
echo.

set "CUDA_VS_INT=%CUDA_PATH%\extras\visual_studio_integration\MSBuildExtensions"
set "VS_BUILDTOOLS=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Microsoft\VC\v170\BuildCustomizations"
set "VS_COMMUNITY=C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Microsoft\VC\v170\BuildCustomizations"

echo Checking CUDA integration source...
if not exist "%CUDA_VS_INT%" (
    echo [ERROR] CUDA VS Integration not found at: %CUDA_VS_INT%
    echo Please reinstall CUDA Toolkit with Visual Studio Integration enabled.
    pause
    exit /b 1
)

echo [OK] Found CUDA integration files at: %CUDA_VS_INT%
echo.

REM Copy to BuildTools
if exist "%VS_BUILDTOOLS%" (
    echo Copying to Visual Studio BuildTools...
    copy /Y "%CUDA_VS_INT%\*.*" "%VS_BUILDTOOLS%\" >nul
    if errorlevel 1 (
        echo [ERROR] Failed to copy. Please run as Administrator.
        pause
        exit /b 1
    )
    echo [OK] Copied to BuildTools
) else (
    echo [SKIP] VS BuildTools not found
)

REM Copy to Community
if exist "%VS_COMMUNITY%" (
    echo Copying to Visual Studio Community...
    copy /Y "%CUDA_VS_INT%\*.*" "%VS_COMMUNITY%\" >nul
    if errorlevel 1 (
        echo [ERROR] Failed to copy. Please run as Administrator.
        pause
        exit /b 1
    )
    echo [OK] Copied to Community
) else (
    echo [SKIP] VS Community not found
)

echo.
echo ==============================================
echo   CUDA Integration Fixed!
echo ==============================================
echo.
echo Now you can run: scripts\build-llama.bat
echo.
pause
