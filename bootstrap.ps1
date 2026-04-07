#Requires -Version 5.1
<#
.SYNOPSIS
    Gemma 4 Coding Agent - Bootstrap Installer for Windows

.DESCRIPTION
    This script installs gemma4-agent and all dependencies:
    1. Downloads and installs Node.js if not present
    2. Downloads llama.cpp prebuilt binaries
    3. Downloads the Gemma 4 model
    4. Installs OpenCode
    5. Creates launcher scripts

.EXAMPLE
    irm https://raw.githubusercontent.com/user/gemma4-agent/main/bootstrap.ps1 | iex

.EXAMPLE
    .\bootstrap.ps1
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$SkipModel
)

$ErrorActionPreference = "Stop"

# Configuration
$LLAMA_VERSION = "b8678"
$CUDA_VERSION = "13.1"
$LLAMA_RELEASE_URL = "https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_VERSION"
$MODEL_REPO = "unsloth/gemma-4-E4B-it-GGUF"
$MODEL_FILE = "gemma-4-E4B-it-Q4_K_M.gguf"
$MMPROJ_FILE = "mmproj-F16.gguf"

# Colors
function Write-Info { Write-Host "[INFO] $args" -ForegroundColor Cyan }
function Write-Success { Write-Host "[OK] $args" -ForegroundColor Green }
function Write-Warn { Write-Host "[WARN] $args" -ForegroundColor Yellow }
function Write-Err { Write-Host "[ERROR] $args" -ForegroundColor Red }

# Get install directory
function Get-InstallDir {
    $localAppData = $env:LOCALAPPDATA
    if (-not $localAppData) {
        $localAppData = Join-Path $env:USERPROFILE "AppData\Local"
    }
    return Join-Path $localAppData "gemma4-agent"
}

# Check if NVIDIA GPU is present
function Test-NvidiaGpu {
    try {
        $null = & nvidia-smi 2>$null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

# Check if a command exists
function Test-Command {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

# Install Node.js
function Install-NodeJS {
    if (Test-Command "node") {
        $version = & node --version
        Write-Success "Node.js found: $version"
        return
    }

    Write-Info "Installing Node.js..."

    if (Test-Command "winget") {
        & winget install OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements
    } elseif (Test-Command "choco") {
        & choco install nodejs-lts -y
    } else {
        Write-Err "Please install Node.js manually: https://nodejs.org"
        exit 1
    }

    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    Write-Success "Node.js installed"
}

# Download file with progress
function Get-FileWithProgress {
    param(
        [string]$Url,
        [string]$OutFile
    )

    Write-Host "   Downloading: $(Split-Path $Url -Leaf)"

    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
    $ProgressPreference = 'Continue'
}

# Download llama.cpp binaries
function Install-LlamaBinaries {
    param([string]$InstallDir)

    $binDir = Join-Path $InstallDir "bin"
    $tempDir = Join-Path $InstallDir "temp"

    New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

    $hasGpu = Test-NvidiaGpu

    $files = @()
    if ($hasGpu) {
        Write-Info "NVIDIA GPU detected, downloading CUDA $CUDA_VERSION binaries..."
        $files += "llama-$LLAMA_VERSION-bin-win-cuda-$CUDA_VERSION-x64.zip"
        $files += "cudart-llama-bin-win-cuda-$CUDA_VERSION-x64.zip"
    } else {
        Write-Info "No NVIDIA GPU detected, downloading CPU binaries..."
        $files += "llama-$LLAMA_VERSION-bin-win-cpu-x64.zip"
    }

    foreach ($file in $files) {
        $url = "$LLAMA_RELEASE_URL/$file"
        $archivePath = Join-Path $tempDir $file

        if (Test-Path $archivePath) {
            Write-Host "   Found cached archive, skipping download: $file"
        } else {
            Get-FileWithProgress -Url $url -OutFile $archivePath
        }

        Write-Host "   Extracting: $file"
        Expand-Archive -Path $archivePath -DestinationPath $binDir -Force
    }

    Write-Success "llama.cpp binaries installed"
}

# Download model
function Install-Model {
    param([string]$InstallDir)

    $modelDir = Join-Path $InstallDir "models"
    $modelPath = Join-Path $modelDir $MODEL_FILE

    New-Item -ItemType Directory -Force -Path $modelDir | Out-Null

    if (Test-Path $modelPath) {
        Write-Success "Model already exists: $modelPath"
        return
    }

    Write-Info "Downloading Gemma 4 E4B model (~5.4GB)..."
    Write-Host "   Repository: $MODEL_REPO"
    Write-Host "   File: $MODEL_FILE"

    $url = "https://huggingface.co/$MODEL_REPO/resolve/main/$MODEL_FILE"

    # Use curl for progress display
    & curl -L -o $modelPath --progress-bar $url

    Write-Success "Model downloaded"
}

function Install-Mmproj {
    param([string]$InstallDir)

    $modelDir = Join-Path $InstallDir "models"
    $mmprojPath = Join-Path $modelDir $MMPROJ_FILE

    New-Item -ItemType Directory -Force -Path $modelDir | Out-Null

    if (Test-Path $mmprojPath) {
        Write-Success "Vision projector already exists: $mmprojPath"
        return
    }

    Write-Info "Downloading Gemma 4 vision projector..."
    Write-Host "   Repository: $MODEL_REPO"
    Write-Host "   File: $MMPROJ_FILE"

    $url = "https://huggingface.co/$MODEL_REPO/resolve/main/$MMPROJ_FILE"
    & curl -L -o $mmprojPath --progress-bar $url

    Write-Success "Vision projector downloaded"
}

# Install OpenCode
function Install-OpenCode {
    if (Test-Command "opencode") {
        Write-Success "OpenCode already installed"
    } else {
        Write-Info "Installing OpenCode..."
        & npm install -g opencode-ai
        Write-Success "OpenCode installed"
    }

    # Configure OpenCode to use Gemma 4
    Set-OpenCodeConfig
}

# Configure OpenCode with Gemma 4 settings
function Set-OpenCodeConfig {
    $configDir = Join-Path $env:USERPROFILE ".opencode"
    $configFile = Join-Path $configDir "opencode.json"

    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    }

    Write-Info "Configuring OpenCode for Gemma 4..."

    $config = @'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "gemma4-local": {
      "name": "Gemma 4 (Local)",
      "npm": "@ai-sdk/openai-compatible",
      "env": [],
      "models": {
        "gemma4-e4b": {
          "id": "google_gemma-4-E4B-it-Q4_K_M",
          "name": "Gemma 4 E4B",
          "release_date": "2026-04-02",
          "attachment": true,
          "modalities": {
            "input": ["text", "image", "pdf"],
            "output": ["text"]
          },
          "reasoning": false,
          "temperature": true,
          "tool_call": true,
          "cost": { "input": 0, "output": 0 },
          "limit": { "context": 32768, "output": 8192 },
          "options": {}
        }
      },
      "options": {
        "baseURL": "http://127.0.0.1:8089/v1",
        "apiKey": "not-needed"
      }
    }
  },
  "model": "gemma4-local/gemma4-e4b"
}
'@

    Set-Content -Path $configFile -Value $config -Encoding UTF8
    Write-Success "OpenCode configured: $configFile"
}

# Create launcher script
function New-Launcher {
    param([string]$InstallDir)

    $binDir = Join-Path $InstallDir "bin"
    $modelDir = Join-Path $InstallDir "models"
    $launcherPath = Join-Path $InstallDir "gemma4-agent.cmd"

    $hasGpu = Test-NvidiaGpu
    $nglFlag = if ($hasGpu) { "-ngl 99" } else { "" }

    $content = @"
@echo off
setlocal

set "BIN_DIR=$binDir"
set "MODEL_DIR=$modelDir"
set "MODEL_FILE=$MODEL_FILE"
set "MMPROJ_FILE=$MMPROJ_FILE"
set "PORT=8089"

echo.
echo ========================================
echo   Gemma 4 Coding Agent
echo ========================================
echo.

echo Starting llama-server...
start "" "%BIN_DIR%\llama-server.exe" -m "%MODEL_DIR%\%MODEL_FILE%" --mmproj "%MODEL_DIR%\%MMPROJ_FILE%" --port %PORT% -c 32768 --jinja $nglFlag

echo Waiting for server to start...
timeout /t 15 /nobreak > nul

echo Starting OpenCode...
opencode

endlocal
"@

    Set-Content -Path $launcherPath -Value $content -Encoding ASCII

    Write-Success "Launcher created: $launcherPath"
}

function New-UserBinLauncher {
    param([string]$InstallDir)

    $userBinDir = Join-Path $env:USERPROFILE ".local\bin"
    $shimPath = Join-Path $userBinDir "gemma4-agent.cmd"

    New-Item -ItemType Directory -Force -Path $userBinDir | Out-Null

    $content = @"
@echo off
call "$InstallDir\gemma4-agent.cmd" %*
"@

    Set-Content -Path $shimPath -Value $content -Encoding ASCII
    Write-Success "Created launcher shim: $shimPath"
}

# Add to PATH
function Add-ToPath {
    param([string]$BinDir)

    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")

    if ($currentPath -notlike "*$BinDir*") {
        $newPath = if ([string]::IsNullOrWhiteSpace($currentPath)) { $BinDir } else { "$BinDir;$currentPath" }
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        $env:Path = "$BinDir;$env:Path"
        Write-Success "Added to PATH: $BinDir"
    } else {
        Write-Info "Already in PATH"
    }
}

# Main
function Main {
    Write-Host ""
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "     Gemma 4 Coding Agent - Bootstrap Installer       " -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host ""

    $installDir = Get-InstallDir
    $hasGpu = Test-NvidiaGpu

    Write-Info "Platform: Windows x64"
    Write-Info "GPU: $(if ($hasGpu) { 'NVIDIA CUDA' } else { 'CPU only' })"
    Write-Info "Install directory: $installDir"
    Write-Host ""

    # Create install directory
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null

    # Step 1: Node.js
    Write-Host "Step 1/5: Checking Node.js..." -ForegroundColor Yellow
    Install-NodeJS
    Write-Host ""

    # Step 2: llama.cpp
    Write-Host "Step 2/5: Installing llama.cpp..." -ForegroundColor Yellow
    Install-LlamaBinaries -InstallDir $installDir
    Write-Host ""

    # Step 3: Model
    if (-not $SkipModel) {
        Write-Host "Step 3/5: Downloading model..." -ForegroundColor Yellow
        Install-Model -InstallDir $installDir
        Install-Mmproj -InstallDir $installDir
    } else {
        Write-Host "Step 3/5: Skipping model download..." -ForegroundColor Yellow
    }
    Write-Host ""

    # Step 4: OpenCode
    Write-Host "Step 4/5: Installing OpenCode..." -ForegroundColor Yellow
    Install-OpenCode
    Write-Host ""

    # Step 5: Launcher
    Write-Host "Step 5/5: Creating launcher..." -ForegroundColor Yellow
    New-Launcher -InstallDir $installDir
    New-UserBinLauncher -InstallDir $installDir
    Add-ToPath -BinDir (Join-Path $env:USERPROFILE ".local\bin")
    Write-Host ""

    Write-Host "======================================================" -ForegroundColor Green
    Write-Host "              Installation Complete!                  " -ForegroundColor Green
    Write-Host "======================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "To start the agent, run:" -ForegroundColor White
    Write-Host "  gemma4-agent" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Or directly:" -ForegroundColor White
    Write-Host "  $env:USERPROFILE\.local\bin\gemma4-agent.cmd" -ForegroundColor Cyan
    Write-Host ""
}

# Run
Main
