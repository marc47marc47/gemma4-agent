#!/bin/bash
#
# Download prebuilt llama.cpp CUDA binaries for Windows.
#
# This avoids building llama.cpp locally. The script downloads:
# - cudart-llama-bin-win-cuda-13.1-x64.zip
# - llama-b8672-bin-win-cuda-13.1-x64.zip
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_command() {
    command -v "$1" >/dev/null 2>&1
}

download_file() {
    local url="$1"
    local output="$2"

    if [[ -f "$output" ]]; then
        warn "File already exists, skipping: $output"
        return 0
    fi

    info "Downloading $(basename "$output")"

    if check_command curl; then
        curl -L --fail --progress-bar -o "$output" "$url"
        return 0
    fi

    if check_command wget; then
        wget -O "$output" "$url"
        return 0
    fi

    error "Neither curl nor wget is available."
    exit 1
}

main() {
    local script_dir
    local project_dir
    local release_tag
    local base_url

    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    project_dir="$(dirname "$script_dir")"

    release_tag="${LLAMA_CPP_RELEASE_TAG:-b8672}"
    base_url="https://github.com/ggml-org/llama.cpp/releases/download/${release_tag}"

    local files=(
        "cudart-llama-bin-win-cuda-13.1-x64.zip"
        "llama-b8672-bin-win-cuda-13.1-x64.zip"
    )

    echo ""
    echo "=============================================="
    echo "  Gemma 4 Agent - Download CUDA llama.cpp"
    echo "=============================================="
    echo ""

    info "Release tag: ${release_tag}"
    info "Destination: ${project_dir}"
    echo ""

    for file in "${files[@]}"; do
        download_file "${base_url}/${file}" "${project_dir}/${file}"
    done

    echo ""
    success "Download complete."
    echo ""
    echo "Downloaded files:"
    for file in "${files[@]}"; do
        echo "  - ${project_dir}/${file}"
    done
    echo ""
    echo "Next step:"
    echo "  Extract the zip files, then place the llama binaries where the launcher can find them."
    echo ""
}

main "$@"
