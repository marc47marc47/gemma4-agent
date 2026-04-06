#Requires -Version 5.1
<#
.SYNOPSIS
    Gemma 4 Agent - llama.cpp Build Script for Windows

.DESCRIPTION
    This script:
    1. Checks for required build tools (CMake, C++ compiler)
    2. Installs missing dependencies using winget or choco
    3. Detects NVIDIA GPU for CUDA support
    4. Builds llama.cpp with appropriate backend

.EXAMPLE
    .\build-llama-with-setup.ps1

.EXAMPLE
    .\build-llama-with-setup.ps1 -Force

.NOTES
    Requires Administrator privileges for installing dependencies.
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$CpuOnly,
    [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"

# Colors
function Write-Info { Write-Host "[INFO] $args" -ForegroundColor Cyan }
function Write-Success { Write-Host "[OK] $args" -ForegroundColor Green }
function Write-Warn { Write-Host "[WARN] $args" -ForegroundColor Yellow }
function Write-Err { Write-Host "[ERROR] $args" -ForegroundColor Red }

# Check if running as Administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Check if a command exists
function Test-Command {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

# Detect NVIDIA GPU
function Test-NvidiaGpu {
    if (Test-Command "nvidia-smi") {
        try {
            $null = & nvidia-smi 2>$null
            return $true
        } catch {
            return $false
        }
    }
    return $false
}

# Check CMake
function Test-Cmake {
    if (Test-Command "cmake") {
        $version = & cmake --version | Select-Object -First 1
        Write-Success "CMake found: $version"
        return $true
    }
    Write-Warn "CMake not found"
    return $false
}

# Check C++ compiler (MSVC)
function Test-Compiler {
    # Check for Visual Studio Build Tools via vswhere
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"

    if (Test-Path $vswhere) {
        $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
        if ($vsPath) {
            Write-Success "Visual Studio Build Tools found at: $vsPath"
            return $true
        }
    }

    # Check for cl.exe in PATH
    if (Test-Command "cl") {
        Write-Success "MSVC compiler (cl.exe) found in PATH"
        return $true
    }

    # Check for g++ (MinGW)
    if (Test-Command "g++") {
        $version = & g++ --version | Select-Object -First 1
        Write-Success "MinGW G++ found: $version"
        return $true
    }

    Write-Warn "C++ compiler not found"
    return $false
}

# Check CUDA toolkit
function Test-Cuda {
    if (Test-Command "nvcc") {
        $version = & nvcc --version | Select-String "release" | ForEach-Object { $_ -match 'release (\d+\.\d+)' | Out-Null; $matches[1] }
        Write-Success "CUDA toolkit found: $version"
        return $true
    }

    # Check common CUDA installation paths
    $cudaPaths = @(
        "${env:ProgramFiles}\NVIDIA GPU Computing Toolkit\CUDA",
        "${env:CUDA_PATH}"
    )

    foreach ($path in $cudaPaths) {
        if ($path -and (Test-Path "$path\bin\nvcc.exe")) {
            Write-Success "CUDA toolkit found at: $path"
            return $true
        }
    }

    Write-Warn "CUDA toolkit (nvcc) not found"
    return $false
}

# Install dependencies using winget
function Install-WithWinget {
    param([string]$Backend)

    Write-Info "Using winget for installation..."

    # Install CMake
    if (-not (Test-Cmake)) {
        Write-Info "Installing CMake..."
        & winget install Kitware.CMake --silent --accept-package-agreements --accept-source-agreements
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    }

    # Install Visual Studio Build Tools
    if (-not (Test-Compiler)) {
        Write-Info "Installing Visual Studio 2022 Build Tools..."
        Write-Host ""
        Write-Host "This will install Visual Studio Build Tools with C++ support."
        Write-Host "The installation may take 10-20 minutes."
        Write-Host ""

        & winget install Microsoft.VisualStudio.2022.BuildTools --silent --accept-package-agreements --accept-source-agreements

        Write-Host ""
        Write-Warn "Visual Studio Build Tools installation initiated."
        Write-Warn "Please complete the following steps:"
        Write-Host ""
        Write-Host "  1. Open 'Visual Studio Installer' from Start Menu"
        Write-Host "  2. Click 'Modify' on Visual Studio Build Tools 2022"
        Write-Host "  3. Select 'Desktop development with C++'"
        Write-Host "  4. Click 'Modify' to install"
        Write-Host ""
        Write-Host "After installation completes, re-run this script."
        Write-Host ""

        Read-Host "Press Enter to open Visual Studio Installer..."

        $installerPath = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vs_installer.exe"
        if (Test-Path $installerPath) {
            Start-Process $installerPath
        } else {
            Start-Process "ms-windows-store://pdp/?ProductId=9MWCDN1D4C3F"
        }

        exit 0
    }

    # CUDA installation guidance
    if ($Backend -eq "cuda" -and -not (Test-Cuda)) {
        Write-Host ""
        Write-Warn "CUDA toolkit not found."
        Write-Host ""
        Write-Host "Please install CUDA toolkit manually:"
        Write-Host "  https://developer.nvidia.com/cuda-downloads"
        Write-Host ""
        Write-Host "Select: Windows > x86_64 > 11 > exe (network or local)"
        Write-Host ""

        $response = Read-Host "Do you want to open the CUDA download page? [Y/n]"
        if ($response -ne "n" -and $response -ne "N") {
            Start-Process "https://developer.nvidia.com/cuda-downloads"
        }

        Write-Host ""
        Write-Warn "After installing CUDA, re-run this script."
        exit 0
    }
}

# Install dependencies using Chocolatey
function Install-WithChoco {
    param([string]$Backend)

    Write-Info "Using Chocolatey for installation..."

    # Install CMake
    if (-not (Test-Cmake)) {
        Write-Info "Installing CMake..."
        & choco install cmake -y
        refreshenv
    }

    # Install Visual Studio Build Tools
    if (-not (Test-Compiler)) {
        Write-Info "Installing Visual Studio Build Tools..."
        & choco install visualstudio2022buildtools -y
        & choco install visualstudio2022-workload-vctools -y
        refreshenv
    }

    if ($Backend -eq "cuda" -and -not (Test-Cuda)) {
        Write-Warn "Please install CUDA toolkit manually from:"
        Write-Host "  https://developer.nvidia.com/cuda-downloads"
    }
}

# Setup Visual Studio environment
function Initialize-VsEnvironment {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"

    if (-not (Test-Path $vswhere)) {
        return $false
    }

    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null

    if (-not $vsPath) {
        return $false
    }

    $vcvarsPath = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"

    if (-not (Test-Path $vcvarsPath)) {
        return $false
    }

    Write-Info "Initializing Visual Studio environment..."

    # Run vcvars64.bat and capture environment variables
    $cmd = "`"$vcvarsPath`" && set"
    $output = & cmd /c $cmd 2>$null

    foreach ($line in $output) {
        if ($line -match "^([^=]+)=(.*)$") {
            $name = $matches[1]
            $value = $matches[2]
            [Environment]::SetEnvironmentVariable($name, $value, "Process")
        }
    }

    return $true
}

# Build llama.cpp
function Build-LlamaCpp {
    param([string]$Backend)

    $scriptDir = Split-Path -Parent $MyInvocation.ScriptName
    $projectDir = Split-Path -Parent $scriptDir
    $llamaDir = Join-Path $projectDir "llama.cpp"

    if (-not (Test-Path $llamaDir)) {
        Write-Err "llama.cpp directory not found at: $llamaDir"
        Write-Host ""
        Write-Host "Please clone llama.cpp first:"
        Write-Host "  git clone https://github.com/ggml-org/llama.cpp.git"
        exit 1
    }

    Push-Location $llamaDir

    try {
        # Clean previous build
        $buildDir = Join-Path $llamaDir "build"
        if (Test-Path $buildDir) {
            Write-Info "Cleaning previous build..."
            Remove-Item -Recurse -Force $buildDir
        }

        # Setup VS environment
        if (-not (Initialize-VsEnvironment)) {
            Write-Warn "Could not initialize Visual Studio environment."
            Write-Warn "Build may fail if not using Developer Command Prompt."
        }

        # CMake flags
        $cmakeFlags = @("-DLLAMA_CURL=ON")

        switch ($Backend) {
            "cuda" {
                Write-Info "Building with CUDA support..."
                $cmakeFlags += "-DGGML_CUDA=ON"
            }
            "cpu" {
                Write-Info "Building CPU-only version..."
            }
        }

        Write-Host ""
        Write-Info "Configuring CMake..."
        $configCmd = "cmake -B build $($cmakeFlags -join ' ')"
        Write-Host "Running: $configCmd"
        Write-Host ""

        & cmake -B build @cmakeFlags
        if ($LASTEXITCODE -ne 0) {
            throw "CMake configuration failed"
        }

        Write-Host ""
        Write-Info "Building llama.cpp (this may take several minutes)..."
        Write-Host ""

        $cpuCount = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors

        & cmake --build build --config Release -j $cpuCount
        if ($LASTEXITCODE -ne 0) {
            throw "Build failed"
        }

        Write-Host ""
        Write-Success "Build complete!"
        Write-Host ""

        # Find llama-server
        $serverPaths = @(
            "build\bin\Release\llama-server.exe",
            "build\bin\llama-server.exe",
            "build\Release\bin\llama-server.exe"
        )

        foreach ($path in $serverPaths) {
            $fullPath = Join-Path $llamaDir $path
            if (Test-Path $fullPath) {
                Write-Success "llama-server built at: $fullPath"
                break
            }
        }

    } finally {
        Pop-Location
    }
}

# Main
function Main {
    Write-Host ""
    Write-Host "=============================================="
    Write-Host "  Gemma 4 Agent - llama.cpp Build Script"
    Write-Host "  (Windows PowerShell)"
    Write-Host "=============================================="
    Write-Host ""

    # Detect GPU
    $hasNvidiaGpu = Test-NvidiaGpu
    $backend = if ($CpuOnly) { "cpu" } elseif ($hasNvidiaGpu) { "cuda" } else { "cpu" }

    Write-Info "Detected GPU Backend: $backend"
    Write-Host ""

    # Check prerequisites
    Write-Host "Checking prerequisites..."
    Write-Host ""

    $cmakeOk = Test-Cmake
    $compilerOk = Test-Compiler
    $cudaOk = if ($backend -eq "cuda") { Test-Cuda } else { $true }

    Write-Host ""

    # Install missing dependencies
    if (-not $SkipInstall -and (-not $cmakeOk -or -not $compilerOk -or -not $cudaOk)) {
        Write-Warn "Some dependencies are missing."
        Write-Host ""

        $response = Read-Host "Do you want to install missing dependencies? [Y/n]"
        if ($response -ne "n" -and $response -ne "N") {

            # Check for admin rights
            if (-not (Test-Administrator)) {
                Write-Warn "Installing dependencies requires Administrator privileges."
                Write-Host "Please re-run this script as Administrator."
                Write-Host ""
                Write-Host "Right-click PowerShell and select 'Run as Administrator'"
                exit 1
            }

            # Use winget or choco
            if (Test-Command "winget") {
                Install-WithWinget -Backend $backend
            } elseif (Test-Command "choco") {
                Install-WithChoco -Backend $backend
            } else {
                Write-Err "No package manager found (winget or choco)"
                Write-Host ""
                Write-Host "Please install dependencies manually:"
                Write-Host "  1. CMake: https://cmake.org/download/"
                Write-Host "  2. Visual Studio Build Tools: https://visualstudio.microsoft.com/downloads/"
                Write-Host "     (Select 'Desktop development with C++')"
                Write-Host ""
                exit 1
            }

            Write-Host ""

            # Re-check
            $cmakeOk = Test-Cmake
            $compilerOk = Test-Compiler
            $cudaOk = if ($backend -eq "cuda") { Test-Cuda } else { $true }
        }
    }

    # Verify requirements
    if (-not $cmakeOk -or -not $compilerOk) {
        Write-Host ""
        Write-Err "Required build tools are still missing."
        Write-Host "Please install them manually and re-run this script."
        exit 1
    }

    if ($backend -eq "cuda" -and -not $cudaOk) {
        Write-Warn "CUDA toolkit not found. Building CPU-only version instead."
        $backend = "cpu"
    }

    Write-Host ""
    Write-Info "All prerequisites satisfied. Starting build..."
    Write-Host ""

    # Build
    Build-LlamaCpp -Backend $backend

    Write-Host ""
    Write-Host "=============================================="
    Write-Host "  Build Complete!"
    Write-Host "=============================================="
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  1. Install OpenCode:  npm i -g opencode-ai"
    Write-Host "  2. Run the agent:     npm run dev"
    Write-Host ""
}

# Run
Main
