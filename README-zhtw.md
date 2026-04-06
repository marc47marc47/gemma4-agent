# Gemma 4 Coding Agent

一個基於 Google Gemma 4 的可攜式 coding agent，類似 Claude Code / OpenAI Codex。

## 特點

- 🚀 **完全本地運行** - 不需要 API 金鑰，資料不離開你的電腦
- 💻 **跨平台** - 支援 Windows、macOS、Linux
- ⚡ **GPU 加速** - 自動偵測 NVIDIA CUDA / Apple Metal
- 🛠️ **完整 Agent 功能** - 檔案操作、終端命令、工具調用

## 系統需求

- **記憶體**: 至少 16GB RAM（建議 32GB）
- **硬碟空間**: 約 6GB（模型檔案）
- **GPU（可選）**:
  - NVIDIA GPU（支援 CUDA）
  - Apple Silicon（支援 Metal）
  - 或使用 CPU（較慢但可用）

## 快速開始

### 1. 使用 bootstrap 安裝

#### macOS / Linux / Git Bash

```bash
./bootstrap.sh
```

#### Windows PowerShell

```powershell
.\bootstrap.ps1
```

bootstrap 安裝程式會自動：
- 安裝 Node.js（若尚未安裝）
- 下載預編譯的 `llama.cpp` binaries
- 下載 Gemma 4 模型
- 安裝 OpenCode
- 在 `~/.local/bin` 建立 `gemma4-agent` 啟動器

如果 `llama.cpp` 的壓縮檔已經存在於快取中，bootstrap 會跳過下載，直接執行解壓。

安裝完成後，可直接執行：

```bash
gemma4-agent
```

在 Windows 上，啟動器 shim 會建立在：

```text
%USERPROFILE%\.local\bin\gemma4-agent.cmd
```

### 2. 開發者模式：手動編譯 llama.cpp

```bash
cd llama.cpp

# Windows (CUDA)
cmake -B build -DGGML_CUDA=ON -DLLAMA_CURL=ON
cmake --build build --config Release

# macOS (Apple Silicon)
cmake -B build -DGGML_METAL=ON -DLLAMA_CURL=ON
cmake --build build --config Release

# Linux (CUDA)
cmake -B build -DGGML_CUDA=ON -DLLAMA_CURL=ON
cmake --build build --config Release

# CPU only
cmake -B build -DLLAMA_CURL=ON
cmake --build build --config Release
```

### 3. 安裝 OpenCode

```bash
npm i -g opencode-ai
```

### 4. 安裝依賴並啟動

```bash
npm install
npm run dev
```

首次運行會自動下載 Gemma 4 E4B 模型（約 5.4GB）。

## 使用方式

```bash
# 啟動 agent
npm run dev

# 使用預設的 Unsloth GGUF
npm run dev

# 改用 Bartowski 的 GGUF
npm run dev -- --model-source bartowski

# 只下載模型
npm run dev -- --download-only

# 只啟動 llama-server（用於調試）
npm run dev -- --server-only

# 自訂埠口和上下文大小
npm run dev -- --port 8080 --context 65536
```

## 專案結構

```
gemma4-agent/
├── src/
│   └── launcher.ts       # 主程式入口
├── llama.cpp/            # llama.cpp 源碼
├── opencode/             # OpenCode 源碼（可選）
├── opencode.json         # 模型配置
├── package.json
└── tsconfig.json
```

## 配置

編輯 `opencode.json` 來調整模型設定：

```json
{
  "provider": {
    "gemma4-local": {
      "options": {
        "baseURL": "http://127.0.0.1:8089/v1"
      }
    }
  },
  "model": "gemma4-local/gemma4-e4b"
}
```

## 打包為執行檔

```bash
# 編譯 TypeScript
npm run build

# 打包為 Windows 執行檔
npm run pkg:win

# 打包為 macOS 執行檔
npm run pkg:mac

# 打包為 Linux 執行檔
npm run pkg:linux
```

## 技術架構

```
┌─────────────────────────────────────────────────────────────┐
│              gemma4-agent (Launcher)                        │
├─────────────────────────────────────────────────────────────┤
│  OpenCode (UI + Agent)                                      │
│  - Terminal UI                                              │
│  - Tool System (Read/Write/Edit/Bash/Glob/Grep)            │
├─────────────────────────────────────────────────────────────┤
│  llama.cpp server                                           │
│  - OpenAI-compatible API                                    │
│  - Gemma 4 inference                                        │
├─────────────────────────────────────────────────────────────┤
│  Gemma 4 E4B Model (GGUF)                                   │
│  - ~5.4GB (Q4_K_M quantization)                            │
│  - 32K context window                                       │
└─────────────────────────────────────────────────────────────┘
```

## 已知問題

- Ollama v0.20.0 的 Gemma 4 tool calling 有 bug，因此使用 llama.cpp
- 需要至少 32K context window 才能正常使用 coding agent 功能

## 授權

Apache 2.0

## 參考資源

- [OpenCode](https://github.com/anomalyco/opencode)
- [llama.cpp](https://github.com/ggml-org/llama.cpp)
- [Gemma 4](https://ai.google.dev/gemma)
