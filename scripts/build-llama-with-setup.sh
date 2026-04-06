#!/bin/bash
#
# Gemma 4 Agent - llama.cpp Build Script
#
# This script:
# 1. Detects the operating system and hardware
# 2. Checks for required build tools (CMake, C++ compiler)
# 3. Installs missing dependencies (with user confirmation)
# 4. Builds llama.cpp with appropriate backend (CUDA/Metal/CPU)
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Linux*)     OS="linux";;
        Darwin*)    OS="macos";;
        MINGW*|MSYS*|CYGWIN*) OS="windows";;
        *)          OS="unknown";;
    esac
    echo "$OS"
}

# Detect architecture
detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  ARCH="x64";;
        arm64|aarch64) ARCH="arm64";;
        *)             ARCH="unknown";;
    esac
    echo "$ARCH"
}

# Detect GPU
detect_gpu() {
    local os="$1"

    # Check for NVIDIA GPU
    if command -v nvidia-smi &> /dev/null; then
        if nvidia-smi &> /dev/null; then
            echo "cuda"
            return
        fi
    fi

    # Check for Apple Silicon (Metal)
    if [[ "$os" == "macos" && "$(uname -m)" == "arm64" ]]; then
        echo "metal"
        return
    fi

    echo "cpu"
}

# Check if a command exists
check_command() {
    command -v "$1" &> /dev/null
}

# Check CMake
check_cmake() {
    if check_command cmake; then
        local version=$(cmake --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        success "CMake found: $version"
        return 0
    else
        warn "CMake not found"
        return 1
    fi
}

# Check C++ compiler
check_compiler() {
    local os="$1"

    if [[ "$os" == "windows" ]]; then
        # Check for MSVC or MinGW
        if check_command cl; then
            success "MSVC compiler found"
            return 0
        elif check_command g++; then
            success "MinGW G++ found"
            return 0
        elif check_command clang++; then
            success "Clang++ found"
            return 0
        fi
    else
        if check_command g++; then
            local version=$(g++ --version | head -1)
            success "G++ found: $version"
            return 0
        elif check_command clang++; then
            local version=$(clang++ --version | head -1)
            success "Clang++ found: $version"
            return 0
        fi
    fi

    warn "C++ compiler not found"
    return 1
}

# Check CUDA toolkit
check_cuda() {
    if check_command nvcc; then
        local version=$(nvcc --version | grep "release" | grep -oE '[0-9]+\.[0-9]+')
        success "CUDA toolkit found: $version"
        return 0
    else
        warn "CUDA toolkit not found (nvcc)"
        return 1
    fi
}

# Install dependencies based on OS
install_dependencies() {
    local os="$1"
    local gpu="$2"

    echo ""
    info "Installing build dependencies..."
    echo ""

    case "$os" in
        linux)
            install_linux_deps "$gpu"
            ;;
        macos)
            install_macos_deps
            ;;
        windows)
            install_windows_deps "$gpu"
            ;;
        *)
            error "Unsupported OS: $os"
            exit 1
            ;;
    esac
}

# Linux installation
install_linux_deps() {
    local gpu="$1"

    # Detect package manager
    if check_command apt-get; then
        PM="apt"
    elif check_command dnf; then
        PM="dnf"
    elif check_command pacman; then
        PM="pacman"
    elif check_command zypper; then
        PM="zypper"
    else
        error "No supported package manager found (apt, dnf, pacman, zypper)"
        exit 1
    fi

    info "Detected package manager: $PM"

    case "$PM" in
        apt)
            info "Updating package list..."
            sudo apt-get update

            info "Installing CMake and build essentials..."
            sudo apt-get install -y cmake build-essential git curl

            if [[ "$gpu" == "cuda" ]]; then
                info "Installing CUDA toolkit..."
                # Check if CUDA is already available via nvidia driver
                if ! check_command nvcc; then
                    warn "CUDA toolkit (nvcc) not found."
                    echo ""
                    echo "Please install CUDA toolkit manually:"
                    echo "  https://developer.nvidia.com/cuda-downloads"
                    echo ""
                    echo "Or install via apt (Ubuntu):"
                    echo "  sudo apt install nvidia-cuda-toolkit"
                    echo ""
                    read -p "Do you want to try installing nvidia-cuda-toolkit? [y/N] " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        sudo apt-get install -y nvidia-cuda-toolkit
                    fi
                fi
            fi
            ;;

        dnf)
            info "Installing CMake and development tools..."
            sudo dnf install -y cmake gcc-c++ git curl

            if [[ "$gpu" == "cuda" ]]; then
                warn "Please install CUDA toolkit manually from:"
                echo "  https://developer.nvidia.com/cuda-downloads"
            fi
            ;;

        pacman)
            info "Installing CMake and base-devel..."
            sudo pacman -S --needed --noconfirm cmake base-devel git curl

            if [[ "$gpu" == "cuda" ]]; then
                info "Installing CUDA..."
                sudo pacman -S --needed --noconfirm cuda
            fi
            ;;

        zypper)
            info "Installing CMake and development tools..."
            sudo zypper install -y cmake gcc-c++ git curl

            if [[ "$gpu" == "cuda" ]]; then
                warn "Please install CUDA toolkit manually from:"
                echo "  https://developer.nvidia.com/cuda-downloads"
            fi
            ;;
    esac
}

# macOS installation
install_macos_deps() {
    # Check for Homebrew
    if ! check_command brew; then
        info "Homebrew not found. Installing..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    info "Installing CMake via Homebrew..."
    brew install cmake

    # Xcode command line tools should provide clang++
    if ! check_command clang++; then
        info "Installing Xcode Command Line Tools..."
        xcode-select --install 2>/dev/null || true
        echo ""
        echo "Please complete the Xcode Command Line Tools installation dialog,"
        echo "then re-run this script."
        exit 1
    fi
}

# Windows installation (Git Bash / MSYS2)
install_windows_deps() {
    local gpu="$1"

    echo ""
    echo "Windows detected. Checking available package managers..."
    echo ""

    # Check for winget
    if check_command winget; then
        info "winget found. Using winget for installation."

        if ! check_cmake; then
            info "Installing CMake via winget..."
            winget install Kitware.CMake --silent --accept-package-agreements --accept-source-agreements
        fi

        # Check for Visual Studio Build Tools
        if ! check_command cl; then
            warn "Visual Studio Build Tools not found."
            echo ""
            echo "For best results on Windows, please install Visual Studio Build Tools:"
            echo ""
            echo "  Option 1: Visual Studio Build Tools (Recommended)"
            echo "    winget install Microsoft.VisualStudio.2022.BuildTools"
            echo "    Then run Visual Studio Installer and add 'Desktop development with C++'"
            echo ""
            echo "  Option 2: MinGW-w64 (Alternative)"
            echo "    winget install MSYS2.MSYS2"
            echo "    Then in MSYS2: pacman -S mingw-w64-x86_64-gcc mingw-w64-x86_64-cmake"
            echo ""
            read -p "Do you want to install Visual Studio Build Tools now? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                winget install Microsoft.VisualStudio.2022.BuildTools --silent --accept-package-agreements --accept-source-agreements
                echo ""
                warn "Please run Visual Studio Installer and add 'Desktop development with C++'"
                warn "Then re-run this script."
                exit 1
            fi
        fi

    elif check_command choco; then
        info "Chocolatey found. Using choco for installation."

        if ! check_cmake; then
            info "Installing CMake via Chocolatey..."
            choco install cmake -y
        fi

        if ! check_command cl && ! check_command g++; then
            info "Installing Visual Studio Build Tools via Chocolatey..."
            choco install visualstudio2022buildtools -y
            choco install visualstudio2022-workload-vctools -y
        fi

    elif check_command pacman; then
        # MSYS2
        info "MSYS2 detected. Using pacman for installation."

        pacman -S --needed --noconfirm \
            mingw-w64-x86_64-cmake \
            mingw-w64-x86_64-gcc \
            mingw-w64-x86_64-make \
            git curl

    else
        error "No supported package manager found (winget, choco, or MSYS2 pacman)"
        echo ""
        echo "Please install one of the following:"
        echo ""
        echo "  1. CMake: https://cmake.org/download/"
        echo "  2. Visual Studio Build Tools: https://visualstudio.microsoft.com/downloads/"
        echo "     (Select 'Desktop development with C++')"
        echo ""
        echo "Or install MSYS2: https://www.msys2.org/"
        echo ""
        exit 1
    fi

    if [[ "$gpu" == "cuda" ]] && ! check_cuda; then
        echo ""
        warn "CUDA toolkit not found."
        echo ""
        echo "Please install CUDA toolkit from:"
        echo "  https://developer.nvidia.com/cuda-downloads"
        echo ""
        echo "Make sure to add CUDA to your PATH after installation."
        echo ""
    fi
}

# Build llama.cpp
build_llama() {
    local gpu="$1"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local project_dir="$(dirname "$script_dir")"
    local llama_dir="$project_dir/llama.cpp"

    if [[ ! -d "$llama_dir" ]]; then
        error "llama.cpp directory not found at: $llama_dir"
        echo ""
        echo "Please run this script from the gemma4-agent directory,"
        echo "or clone llama.cpp first:"
        echo "  git clone https://github.com/ggml-org/llama.cpp.git"
        exit 1
    fi

    cd "$llama_dir"

    # Clean previous build if exists
    if [[ -d "build" ]]; then
        info "Cleaning previous build..."
        rm -rf build
    fi

    info "Configuring llama.cpp build..."
    echo ""

    # Build flags based on GPU
    local cmake_flags="-DLLAMA_CURL=ON"

    case "$gpu" in
        cuda)
            info "Building with CUDA support..."
            cmake_flags="$cmake_flags -DGGML_CUDA=ON"
            ;;
        metal)
            info "Building with Metal support..."
            cmake_flags="$cmake_flags -DGGML_METAL=ON"
            ;;
        cpu)
            info "Building CPU-only version..."
            ;;
    esac

    # Configure
    echo "Running: cmake -B build $cmake_flags"
    cmake -B build $cmake_flags

    echo ""
    info "Building llama.cpp (this may take a few minutes)..."
    echo ""

    # Detect number of CPU cores
    local jobs=4
    if check_command nproc; then
        jobs=$(nproc)
    elif check_command sysctl; then
        jobs=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
    fi

    # Build
    cmake --build build --config Release -j "$jobs"

    echo ""
    success "Build complete!"
    echo ""

    # Verify llama-server exists
    local server_path=""
    if [[ -f "build/bin/llama-server" ]]; then
        server_path="build/bin/llama-server"
    elif [[ -f "build/bin/llama-server.exe" ]]; then
        server_path="build/bin/llama-server.exe"
    elif [[ -f "build/bin/Release/llama-server.exe" ]]; then
        server_path="build/bin/Release/llama-server.exe"
    fi

    if [[ -n "$server_path" ]]; then
        success "llama-server built at: $llama_dir/$server_path"
    else
        warn "llama-server binary not found in expected location"
        echo "Please check the build output above for the actual location."
    fi
}

# Main
main() {
    echo ""
    echo "=============================================="
    echo "  Gemma 4 Agent - llama.cpp Build Script"
    echo "=============================================="
    echo ""

    # Detect system
    OS=$(detect_os)
    ARCH=$(detect_arch)
    GPU=$(detect_gpu "$OS")

    info "Detected OS: $OS"
    info "Detected Architecture: $ARCH"
    info "Detected GPU Backend: $GPU"
    echo ""

    # Check prerequisites
    echo "Checking prerequisites..."
    echo ""

    CMAKE_OK=false
    COMPILER_OK=false
    CUDA_OK=true

    if check_cmake; then
        CMAKE_OK=true
    fi

    if check_compiler "$OS"; then
        COMPILER_OK=true
    fi

    if [[ "$GPU" == "cuda" ]]; then
        if ! check_cuda; then
            CUDA_OK=false
        fi
    fi

    echo ""

    # Install missing dependencies
    if [[ "$CMAKE_OK" == false ]] || [[ "$COMPILER_OK" == false ]] || [[ "$CUDA_OK" == false ]]; then
        warn "Some dependencies are missing."
        echo ""
        read -p "Do you want to install missing dependencies? [Y/n] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            install_dependencies "$OS" "$GPU"
            echo ""

            # Re-check
            check_cmake && CMAKE_OK=true
            check_compiler "$OS" && COMPILER_OK=true
            [[ "$GPU" != "cuda" ]] || check_cuda && CUDA_OK=true
        fi
    fi

    # Verify all requirements met
    if [[ "$CMAKE_OK" == false ]] || [[ "$COMPILER_OK" == false ]]; then
        echo ""
        error "Required build tools are still missing."
        echo "Please install them manually and re-run this script."
        exit 1
    fi

    if [[ "$GPU" == "cuda" ]] && [[ "$CUDA_OK" == false ]]; then
        echo ""
        warn "CUDA toolkit not found. Building CPU-only version instead."
        GPU="cpu"
    fi

    echo ""
    info "All prerequisites satisfied. Starting build..."
    echo ""

    # Build llama.cpp
    build_llama "$GPU"

    echo ""
    echo "=============================================="
    echo "  Build Complete!"
    echo "=============================================="
    echo ""
    echo "Next steps:"
    echo "  1. Install OpenCode:  npm i -g opencode-ai"
    echo "  2. Run the agent:     npm run dev"
    echo ""
}

# Run main
main "$@"
