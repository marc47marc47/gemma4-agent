#!/bin/bash
#
# Gemma 4 Coding Agent - Bootstrap Script
#
# This script installs gemma4-agent and all dependencies:
# 1. Downloads and installs Node.js if not present
# 2. Installs the gemma4-agent package
# 3. Downloads llama.cpp prebuilt binaries
# 4. Downloads the Gemma 4 model
# 5. Installs OpenCode
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/user/gemma4-agent/main/bootstrap.sh | bash
#   or
#   ./bootstrap.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
LLAMA_VERSION="b8678"
LLAMA_RELEASE_URL="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_VERSION}"
CUDA_VERSION="13.1"
MODEL_REPO="unsloth/gemma-4-E4B-it-GGUF"
MODEL_FILE="gemma-4-E4B-it-Q4_K_M.gguf"
MMPROJ_FILE="mmproj-F16.gguf"

# Detect OS and architecture
detect_os() {
    case "$(uname -s)" in
        Linux*)     echo "linux";;
        Darwin*)    echo "darwin";;
        MINGW*|MSYS*|CYGWIN*) echo "win32";;
        *)          echo "unknown";;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  echo "x64";;
        arm64|aarch64) echo "arm64";;
        *)             echo "unknown";;
    esac
}

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
    if [[ "$os" == "darwin" && "$(uname -m)" == "arm64" ]]; then
        echo "metal"
        return
    fi

    echo "cpu"
}

# Get install directory
get_install_dir() {
    local os="$1"

    if [[ "$os" == "win32" ]]; then
        echo "${LOCALAPPDATA:-$HOME/AppData/Local}/gemma4-agent"
    elif [[ "$os" == "darwin" ]]; then
        echo "$HOME/Library/Application Support/gemma4-agent"
    else
        echo "$HOME/.local/share/gemma4-agent"
    fi
}

# Check command exists
check_command() {
    command -v "$1" &> /dev/null
}

# Install Node.js if not present
install_nodejs() {
    if check_command node; then
        local version=$(node --version)
        success "Node.js found: $version"
        return 0
    fi

    info "Node.js not found. Installing..."

    local os=$(detect_os)

    if [[ "$os" == "darwin" ]]; then
        if check_command brew; then
            brew install node
        else
            error "Please install Homebrew first: https://brew.sh"
            exit 1
        fi
    elif [[ "$os" == "linux" ]]; then
        if check_command apt-get; then
            curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
            sudo apt-get install -y nodejs
        elif check_command dnf; then
            sudo dnf install -y nodejs
        elif check_command pacman; then
            sudo pacman -S --noconfirm nodejs npm
        else
            error "Please install Node.js manually: https://nodejs.org"
            exit 1
        fi
    elif [[ "$os" == "win32" ]]; then
        if check_command winget; then
            winget install OpenJS.NodeJS.LTS --silent
        elif check_command choco; then
            choco install nodejs-lts -y
        else
            error "Please install Node.js manually: https://nodejs.org"
            exit 1
        fi
    fi

    success "Node.js installed"
}

# Download llama.cpp binaries
download_llama() {
    local os="$1"
    local arch="$2"
    local gpu="$3"
    local install_dir="$4"

    local bin_dir="${install_dir}/bin"
    local cache_dir="${install_dir}/cache"
    mkdir -p "$bin_dir"
    mkdir -p "$cache_dir"

    local files=()

    if [[ "$os" == "win32" ]]; then
        if [[ "$gpu" == "cuda" ]]; then
            files+=("llama-${LLAMA_VERSION}-bin-win-cuda-${CUDA_VERSION}-x64.zip")
            files+=("cudart-llama-bin-win-cuda-${CUDA_VERSION}-x64.zip")
        else
            files+=("llama-${LLAMA_VERSION}-bin-win-cpu-x64.zip")
        fi
    elif [[ "$os" == "darwin" ]]; then
        if [[ "$arch" == "arm64" ]]; then
            files+=("llama-${LLAMA_VERSION}-bin-macos-arm64.tar.gz")
        else
            files+=("llama-${LLAMA_VERSION}-bin-macos-x64.tar.gz")
        fi
    elif [[ "$os" == "linux" ]]; then
        files+=("llama-${LLAMA_VERSION}-bin-ubuntu-x64.tar.gz")
    fi

    if [[ ${#files[@]} -eq 0 ]]; then
        error "No prebuilt binaries available for: $os-$arch-$gpu"
        exit 1
    fi

    info "Installing llama.cpp binaries (${LLAMA_VERSION})..."

    for file in "${files[@]}"; do
        local url="${LLAMA_RELEASE_URL}/${file}"
        local archive_path="${cache_dir}/${file}"

        # Skip download if the archive is already cached, but still extract it.
        if [[ -f "$archive_path" ]]; then
            echo "   Found cached archive, skipping download: $file"
        else
            echo "   Downloading: $file"
            curl -L -o "$archive_path" --progress-bar "$url"
        fi

        # Extract
        echo "   Extracting: $file"
        if [[ "$file" == *.zip ]]; then
            # Use unzip on all platforms (available in Git Bash on Windows)
            unzip -o "$archive_path" -d "$bin_dir"
        else
            tar -xzf "$archive_path" -C "$bin_dir"
        fi
    done

    # Make binaries executable
    if [[ "$os" != "win32" ]]; then
        chmod +x "$bin_dir"/*
    fi

    success "llama.cpp binaries installed"
}

# Download model
download_model() {
    local install_dir="$1"
    local model_dir="${install_dir}/models"
    local model_path="${model_dir}/${MODEL_FILE}"

    mkdir -p "$model_dir"

    if [[ -f "$model_path" ]]; then
        success "Model already exists: $model_path"
        return 0
    fi

    info "Downloading Gemma 4 E4B model (~5.4GB)..."
    echo "   Repository: $MODEL_REPO"
    echo "   File: $MODEL_FILE"

    # Try huggingface-cli first
    if check_command huggingface-cli; then
        huggingface-cli download "$MODEL_REPO" "$MODEL_FILE" --local-dir "$model_dir"
    else
        # Fallback to curl
        local url="https://huggingface.co/${MODEL_REPO}/resolve/main/${MODEL_FILE}"
        curl -L -o "$model_path" --progress-bar "$url"
    fi

    success "Model downloaded"
}

download_mmproj() {
    local install_dir="$1"
    local model_dir="${install_dir}/models"
    local mmproj_path="${model_dir}/${MMPROJ_FILE}"

    mkdir -p "$model_dir"

    if [[ -f "$mmproj_path" ]]; then
        success "Vision projector already exists: $mmproj_path"
        return 0
    fi

    info "Downloading Gemma 4 vision projector..."
    echo "   Repository: $MODEL_REPO"
    echo "   File: $MMPROJ_FILE"

    if check_command huggingface-cli; then
        huggingface-cli download "$MODEL_REPO" "$MMPROJ_FILE" --local-dir "$model_dir"
    else
        local url="https://huggingface.co/${MODEL_REPO}/resolve/main/${MMPROJ_FILE}"
        curl -L -o "$mmproj_path" --progress-bar "$url"
    fi

    success "Vision projector downloaded"
}

# Install OpenCode
install_opencode() {
    if check_command opencode; then
        success "OpenCode already installed"
    else
        info "Installing OpenCode..."
        npm install -g opencode-ai
        success "OpenCode installed"
    fi

    # Configure OpenCode to use Gemma 4
    configure_opencode
}

# Configure OpenCode with Gemma 4 settings
configure_opencode() {
    local config_dir="$HOME/.opencode"
    local config_file="${config_dir}/opencode.json"

    mkdir -p "$config_dir"

    info "Configuring OpenCode for Gemma 4..."

    cat > "$config_file" << 'EOF'
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
EOF

    success "OpenCode configured: $config_file"
}

# Create launcher script
create_launcher() {
    local os="$1"
    local install_dir="$2"

    local bin_dir="${install_dir}/bin"
    local model_dir="${install_dir}/models"
    local server_binary="llama-server"
    [[ "$os" == "win32" ]] && server_binary="llama-server.exe"

    local launcher_path="${install_dir}/gemma4-agent"
    [[ "$os" == "win32" ]] && launcher_path="${install_dir}/gemma4-agent.cmd"

    if [[ "$os" == "win32" ]]; then
        cat > "$launcher_path" << EOF
@echo off
setlocal

set "BIN_DIR=${bin_dir}"
set "MODEL_DIR=${model_dir}"
set "MODEL_FILE=${MODEL_FILE}"
set "MMPROJ_FILE=${MMPROJ_FILE}"
set "PORT=8089"

echo Starting Gemma 4 Coding Agent...

start "" "%BIN_DIR%\\${server_binary}" -m "%MODEL_DIR%\\%MODEL_FILE%" --mmproj "%MODEL_DIR%\\%MMPROJ_FILE%" --port %PORT% -c 32768 --jinja -ngl 99

timeout /t 10 /nobreak > nul

opencode

endlocal
EOF
    else
        cat > "$launcher_path" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${SCRIPT_DIR}/bin"
MODEL_DIR="${SCRIPT_DIR}/models"
EOF
        cat >> "$launcher_path" << EOF
MODEL_FILE="${MODEL_FILE}"
MMPROJ_FILE="${MMPROJ_FILE}"
PORT=8089

echo "Starting Gemma 4 Coding Agent..."

"\${BIN_DIR}/llama-server" -m "\${MODEL_DIR}/\${MODEL_FILE}" --mmproj "\${MODEL_DIR}/\${MMPROJ_FILE}" --port \${PORT} -c 32768 --jinja -ngl 99 &
SERVER_PID=\$!

cleanup() {
    echo "Shutting down..."
    kill \$SERVER_PID 2>/dev/null
    exit 0
}

trap cleanup SIGINT SIGTERM

sleep 10

opencode

cleanup
EOF
        chmod +x "$launcher_path"
    fi

    success "Launcher created: $launcher_path"
}

create_user_bin_link() {
    local os="$1"
    local install_dir="$2"
    local user_bin_dir="$HOME/.local/bin"

    mkdir -p "$user_bin_dir"

    if [[ "$os" == "win32" ]]; then
        local shim_path="${user_bin_dir}/gemma4-agent"
        local shim_cmd_path="${user_bin_dir}/gemma4-agent.cmd"

        cat > "$shim_path" << EOF
#!/bin/bash
cmd.exe //c "\"${install_dir}/gemma4-agent.cmd\" $*"
EOF
        chmod +x "$shim_path"

        cat > "$shim_cmd_path" << EOF
@echo off
call "${install_dir}\gemma4-agent.cmd" %*
EOF

        success "Created launchers in $user_bin_dir"
    else
        local launcher_path="${install_dir}/gemma4-agent"
        local link_path="${user_bin_dir}/gemma4-agent"

        ln -sfn "$launcher_path" "$link_path"
        success "Linked launcher: $link_path -> $launcher_path"
    fi
}

# Add to PATH
add_to_path() {
    local install_dir="$1"
    local os="$2"
    local user_bin_dir="$HOME/.local/bin"

    if [[ "$os" == "win32" ]]; then
        local shell_rc=""
        if [[ -f "$HOME/.bashrc" ]]; then
            shell_rc="$HOME/.bashrc"
        elif [[ -f "$HOME/.zshrc" ]]; then
            shell_rc="$HOME/.zshrc"
        elif [[ -f "$HOME/.profile" ]]; then
            shell_rc="$HOME/.profile"
        fi

        if [[ -n "$shell_rc" ]]; then
            local export_line="export PATH=\"${user_bin_dir}:\$PATH\""
            if ! grep -Fq "$user_bin_dir" "$shell_rc" 2>/dev/null; then
                echo "" >> "$shell_rc"
                echo "# Gemma 4 Agent" >> "$shell_rc"
                echo "$export_line" >> "$shell_rc"
                success "Added $user_bin_dir to PATH in $shell_rc"
            fi
        else
            echo ""
            echo "Add this to your shell profile:"
            echo "  export PATH=\"${user_bin_dir}:\$PATH\""
        fi
    else
        local shell_rc=""
        if [[ -f "$HOME/.zshrc" ]]; then
            shell_rc="$HOME/.zshrc"
        elif [[ -f "$HOME/.bashrc" ]]; then
            shell_rc="$HOME/.bashrc"
        fi

        if [[ -n "$shell_rc" ]]; then
            local export_line="export PATH=\"${user_bin_dir}:\$PATH\""
            if ! grep -Fq "$user_bin_dir" "$shell_rc" 2>/dev/null; then
                echo "" >> "$shell_rc"
                echo "# Gemma 4 Agent" >> "$shell_rc"
                echo "$export_line" >> "$shell_rc"
                success "Added $user_bin_dir to PATH in $shell_rc"
            fi
        fi
    fi
}

# Main
main() {
    echo ""
    echo "╔════════════════════════════════════════════════════╗"
    echo "║     Gemma 4 Coding Agent - Bootstrap Installer     ║"
    echo "╚════════════════════════════════════════════════════╝"
    echo ""

    # Detect system
    local os=$(detect_os)
    local arch=$(detect_arch)
    local gpu=$(detect_gpu "$os")
    local install_dir=$(get_install_dir "$os")

    info "Detected: $os / $arch / $gpu"
    info "Install directory: $install_dir"
    echo ""

    # Create install directory
    mkdir -p "$install_dir"

    # Step 1: Node.js
    echo "Step 1/5: Checking Node.js..."
    install_nodejs
    echo ""

    # Step 2: llama.cpp
    echo "Step 2/5: Installing llama.cpp..."
    download_llama "$os" "$arch" "$gpu" "$install_dir"
    echo ""

    # Step 3: Model
    echo "Step 3/5: Downloading model..."
    download_model "$install_dir"
    download_mmproj "$install_dir"
    echo ""

    # Step 4: OpenCode
    echo "Step 4/5: Installing OpenCode..."
    install_opencode
    echo ""

    # Step 5: Launcher
    echo "Step 5/5: Creating launcher..."
    create_launcher "$os" "$install_dir"
    create_user_bin_link "$os" "$install_dir"
    add_to_path "$install_dir" "$os"
    echo ""

    echo "╔════════════════════════════════════════════════════╗"
    echo "║              Installation Complete!                ║"
    echo "╚════════════════════════════════════════════════════╝"
    echo ""
    echo "To start the agent, run:"
    echo "  ${HOME}/.local/bin/gemma4-agent"
    echo ""
    echo "Or after restarting your terminal:"
    echo "  gemma4-agent"
    echo ""
}

# Run
main "$@"
