#!/usr/bin/env node
/**
 * Gemma 4 Coding Agent Launcher
 *
 * This launcher:
 * 1. Downloads llama.cpp prebuilt binaries if not present
 * 2. Downloads the model if not present
 * 3. Detects hardware (CUDA/Metal/CPU)
 * 4. Starts llama-server
 * 5. Launches OpenCode connected to the local server
 */

import { spawn, execSync, type ChildProcess } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import { program } from 'commander';

// ============================================================================
// Configuration
// ============================================================================

type ModelSource = 'bartowski' | 'unsloth';

const MODEL_PRESETS: Record<ModelSource, { repo: string; file: string }> = {
  bartowski: {
    repo: 'bartowski/google_gemma-4-E4B-it-GGUF',
    file: 'google_gemma-4-E4B-it-Q4_K_M.gguf',
  },
  unsloth: {
    repo: 'unsloth/gemma-4-E4B-it-GGUF',
    file: 'gemma-4-E4B-it-Q4_K_M.gguf',
  },
};

// llama.cpp release version
const LLAMA_VERSION = 'b8678';
const LLAMA_RELEASE_URL = `https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_VERSION}`;
const CUDA_VERSION = '13.1';

// Binary presets for each platform/backend
const LLAMA_BINARIES: Record<string, { files: string[]; extractDir?: string }> = {
  'win32-cuda': {
    files: [
      `llama-${LLAMA_VERSION}-bin-win-cuda-${CUDA_VERSION}-x64.zip`,
      `cudart-llama-bin-win-cuda-${CUDA_VERSION}-x64.zip`,
    ],
  },
  'win32-cpu': {
    files: [`llama-${LLAMA_VERSION}-bin-win-cpu-x64.zip`],
  },
  'darwin-metal': {
    files: [`llama-${LLAMA_VERSION}-bin-macos-arm64.tar.gz`],
  },
  'darwin-cpu': {
    files: [`llama-${LLAMA_VERSION}-bin-macos-x64.tar.gz`],
  },
  'linux-cpu': {
    files: [`llama-${LLAMA_VERSION}-bin-ubuntu-x64.tar.gz`],
  },
};

const CONFIG = {
  MODEL_SIZE_GB: 5.4,
  LLAMA_PORT: 8089,
  CONTEXT_SIZE: 32768,
  MODEL_SOURCE: 'unsloth' as ModelSource,
};

// ============================================================================
// Path Utilities
// ============================================================================

function getBaseDir(): string {
  // When running from npm/installed, use home directory
  // When running in dev, use current directory
  const platform = process.platform;
  const home = os.homedir();

  if (platform === 'win32') {
    return process.env.LOCALAPPDATA
      ? path.join(process.env.LOCALAPPDATA, 'gemma4-agent')
      : path.join(home, 'AppData', 'Local', 'gemma4-agent');
  } else if (platform === 'darwin') {
    return path.join(home, 'Library', 'Application Support', 'gemma4-agent');
  } else {
    return path.join(home, '.local', 'share', 'gemma4-agent');
  }
}

function getModelDir(): string {
  return path.join(getBaseDir(), 'models');
}

function getBinDir(): string {
  return path.join(getBaseDir(), 'bin');
}

function getModelConfig(): { repo: string; file: string } {
  return MODEL_PRESETS[CONFIG.MODEL_SOURCE];
}

// ============================================================================
// Hardware Detection
// ============================================================================

function detectBackend(): 'cuda' | 'metal' | 'cpu' {
  const platform = process.platform;
  const arch = process.arch;

  // macOS Apple Silicon -> Metal
  if (platform === 'darwin' && arch === 'arm64') {
    return 'metal';
  }

  // Check for NVIDIA GPU
  if (platform === 'win32' || platform === 'linux') {
    try {
      execSync('nvidia-smi', { stdio: 'ignore' });
      return 'cuda';
    } catch {
      // nvidia-smi not found or failed
    }
  }

  return 'cpu';
}

function getPlatformKey(): string {
  const platform = process.platform;
  const backend = detectBackend();
  return `${platform}-${backend}`;
}

// ============================================================================
// Download Utilities
// ============================================================================

function downloadFile(url: string, destPath: string): void {
  console.log(`   Downloading: ${path.basename(url)}`);

  const curlArgs = ['-L', '-o', destPath, '--progress-bar', url];

  try {
    execSync(`curl ${curlArgs.join(' ')}`, { stdio: 'inherit' });
  } catch (error) {
    throw new Error(`Failed to download ${url}`);
  }
}

function extractArchive(archivePath: string, destDir: string): void {
  const ext = archivePath.toLowerCase();

  fs.mkdirSync(destDir, { recursive: true });

  if (ext.endsWith('.zip')) {
    // Windows: use PowerShell to extract
    if (process.platform === 'win32') {
      execSync(
        `powershell -Command "Expand-Archive -Path '${archivePath}' -DestinationPath '${destDir}' -Force"`,
        { stdio: 'inherit' }
      );
    } else {
      execSync(`unzip -o "${archivePath}" -d "${destDir}"`, { stdio: 'inherit' });
    }
  } else if (ext.endsWith('.tar.gz') || ext.endsWith('.tgz')) {
    execSync(`tar -xzf "${archivePath}" -C "${destDir}"`, { stdio: 'inherit' });
  } else {
    throw new Error(`Unknown archive format: ${archivePath}`);
  }
}

// ============================================================================
// llama.cpp Binary Management
// ============================================================================

function getLlamaServerPath(): string {
  const platform = process.platform;
  const binDir = getBinDir();
  const binaryName = platform === 'win32' ? 'llama-server.exe' : 'llama-server';

  // Check installed binary
  const installedPath = path.join(binDir, binaryName);
  if (fs.existsSync(installedPath)) {
    return installedPath;
  }

  // Check local build (for development)
  const localPaths = [
    path.join(process.cwd(), 'llama.cpp', 'build', 'bin', binaryName),
    path.join(process.cwd(), 'llama.cpp', 'build', 'bin', 'Release', binaryName),
    path.join(process.cwd(), 'bin', binaryName),
  ];

  for (const p of localPaths) {
    if (fs.existsSync(p)) {
      return p;
    }
  }

  // Not found
  return installedPath; // Will trigger download
}

function llamaBinaryExists(): boolean {
  const serverPath = getLlamaServerPath();
  return fs.existsSync(serverPath);
}

async function downloadLlamaBinaries(): Promise<void> {
  const platformKey = getPlatformKey();
  const binConfig = LLAMA_BINARIES[platformKey];

  if (!binConfig) {
    console.error(`\n❌ No prebuilt binaries available for: ${platformKey}`);
    console.error('Please build llama.cpp manually or use a supported platform.');
    process.exit(1);
  }

  const binDir = getBinDir();
  const tempDir = path.join(getBaseDir(), 'temp');
  fs.mkdirSync(binDir, { recursive: true });
  fs.mkdirSync(tempDir, { recursive: true });

  console.log(`\n📦 Downloading llama.cpp binaries (${LLAMA_VERSION})...`);
  console.log(`   Platform: ${platformKey}`);
  console.log(`   Destination: ${binDir}\n`);

  for (const file of binConfig.files) {
    const url = `${LLAMA_RELEASE_URL}/${file}`;
    const archivePath = path.join(tempDir, file);

    // Download
    downloadFile(url, archivePath);

    // Extract
    console.log(`   Extracting: ${file}`);
    extractArchive(archivePath, binDir);

    // Cleanup archive
    fs.unlinkSync(archivePath);
  }

  // Make binaries executable on Unix
  if (process.platform !== 'win32') {
    const binaries = fs.readdirSync(binDir).filter(f => !f.includes('.'));
    for (const bin of binaries) {
      const binPath = path.join(binDir, bin);
      fs.chmodSync(binPath, 0o755);
    }
  }

  // Cleanup temp dir
  fs.rmSync(tempDir, { recursive: true, force: true });

  console.log('\n✅ llama.cpp binaries installed successfully!\n');
}

// ============================================================================
// Model Management
// ============================================================================

function modelExists(): boolean {
  const modelPath = path.join(getModelDir(), getModelConfig().file);
  return fs.existsSync(modelPath);
}

async function downloadModel(): Promise<void> {
  const modelDir = getModelDir();
  const modelConfig = getModelConfig();
  const modelPath = path.join(modelDir, modelConfig.file);

  fs.mkdirSync(modelDir, { recursive: true });

  console.log(`\n📥 Downloading Gemma 4 E4B model (~${CONFIG.MODEL_SIZE_GB}GB)...`);
  console.log(`   Source: ${CONFIG.MODEL_SOURCE}`);
  console.log(`   Repository: ${modelConfig.repo}`);
  console.log(`   File: ${modelConfig.file}`);
  console.log(`   Destination: ${modelPath}\n`);

  try {
    // Try huggingface-cli first
    const hfCommand = process.platform === 'win32' ? 'huggingface-cli.exe' : 'huggingface-cli';

    try {
      execSync(`${hfCommand} download ${modelConfig.repo} ${modelConfig.file} --local-dir "${modelDir}"`, {
        stdio: 'inherit',
      });
    } catch {
      // Fallback to curl
      console.log('huggingface-cli not found, using curl...');
      const url = `https://huggingface.co/${modelConfig.repo}/resolve/main/${modelConfig.file}`;
      downloadFile(url, modelPath);
    }

    console.log('\n✅ Model downloaded successfully!\n');
  } catch (error) {
    console.error('\n❌ Failed to download model.');
    console.error('Please download manually from:');
    console.error(`https://huggingface.co/${modelConfig.repo}/tree/main`);
    console.error(`And place "${modelConfig.file}" in: ${modelDir}`);
    process.exit(1);
  }
}

// ============================================================================
// Server Management
// ============================================================================

function startLlamaServer(): ChildProcess {
  const backend = detectBackend();
  const modelConfig = getModelConfig();
  const modelPath = path.join(getModelDir(), modelConfig.file);
  const serverPath = getLlamaServerPath();

  console.log(`\n🚀 Starting llama-server...`);
  console.log(`   Binary: ${serverPath}`);
  console.log(`   Backend: ${backend.toUpperCase()}`);
  console.log(`   Model: ${modelPath}`);
  console.log(`   Port: ${CONFIG.LLAMA_PORT}`);
  console.log(`   Context: ${CONFIG.CONTEXT_SIZE} tokens\n`);

  const args = [
    '-m', modelPath,
    '--port', CONFIG.LLAMA_PORT.toString(),
    '-c', CONFIG.CONTEXT_SIZE.toString(),
    '--jinja',
  ];

  // Add GPU-specific flags
  if (backend === 'cuda' || backend === 'metal') {
    args.push('-ngl', '99');
  }

  const server = spawn(serverPath, args, {
    stdio: ['ignore', 'pipe', 'pipe'],
    env: {
      ...process.env,
      // Ensure CUDA libraries can be found on Windows
      PATH: `${getBinDir()}${path.delimiter}${process.env.PATH}`,
    },
  });

  server.stdout?.on('data', (data) => {
    const line = data.toString();
    if (line.includes('server is listening') || line.includes('listening on')) {
      console.log('✅ llama-server is ready!\n');
    }
  });

  server.stderr?.on('data', (data) => {
    const line = data.toString();
    // Show CUDA detection and errors
    if (line.includes('CUDA') || line.includes('error') || line.includes('Error')) {
      console.log(`[llama-server] ${line.trim()}`);
    }
  });

  server.on('error', (err) => {
    console.error(`\n❌ Failed to start llama-server: ${err.message}`);
    console.error('Run with --download-only to re-download binaries.');
    process.exit(1);
  });

  return server;
}

async function waitForServer(maxWaitMs = 120000): Promise<boolean> {
  const startTime = Date.now();
  const url = `http://127.0.0.1:${CONFIG.LLAMA_PORT}/health`;

  while (Date.now() - startTime < maxWaitMs) {
    try {
      const response = await fetch(url);
      if (response.ok) {
        return true;
      }
    } catch {
      // Server not ready yet
    }
    await new Promise(resolve => setTimeout(resolve, 1000));
  }

  return false;
}

// ============================================================================
// OpenCode Integration
// ============================================================================

function getOpencodeConfigDir(): string {
  return path.join(os.homedir(), '.opencode');
}

function getOpencodeConfigPath(): string {
  return path.join(getOpencodeConfigDir(), 'opencode.json');
}

function ensureOpencodeConfig(): void {
  const configDir = getOpencodeConfigDir();
  const configPath = getOpencodeConfigPath();

  // Ensure .opencode directory exists
  fs.mkdirSync(configDir, { recursive: true });

  // Gemma 4 provider config
  const gemma4Config = {
    $schema: 'https://opencode.ai/config.json',
    provider: {
      'gemma4-local': {
        name: 'Gemma 4 (Local)',
        npm: '@ai-sdk/openai-compatible',
        env: [],
        models: {
          'gemma4-e4b': {
            id: 'google_gemma-4-E4B-it-Q4_K_M',
            name: 'Gemma 4 E4B',
            release_date: '2026-04-02',
            attachment: false,
            reasoning: false,
            temperature: true,
            tool_call: true,
            cost: { input: 0, output: 0 },
            limit: { context: CONFIG.CONTEXT_SIZE, output: 8192 },
            options: {},
          },
        },
        options: {
          baseURL: `http://127.0.0.1:${CONFIG.LLAMA_PORT}/v1`,
          apiKey: 'not-needed',
        },
      },
    },
    model: 'gemma4-local/gemma4-e4b',
  };

  // Check if config exists and try to merge
  let finalConfig = gemma4Config;
  if (fs.existsSync(configPath)) {
    try {
      const existing = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
      // Merge: add gemma4-local provider and set as default model
      finalConfig = {
        ...existing,
        provider: {
          ...existing.provider,
          ...gemma4Config.provider,
        },
        model: gemma4Config.model,
      };
    } catch {
      // If parse fails, use our config
    }
  }

  fs.writeFileSync(configPath, JSON.stringify(finalConfig, null, 2));
  console.log(`✅ OpenCode config updated: ${configPath}`);
}

function startOpenCode(): void {
  const isWindows = process.platform === 'win32';
  const opencodePath = isWindows ? 'opencode.cmd' : 'opencode';

  // Ensure opencode config exists with gemma4 settings
  ensureOpencodeConfig();

  console.log('🤖 Starting OpenCode with Gemma 4...\n');
  console.log('─'.repeat(50));

  const opencode = spawn(opencodePath, [], {
    stdio: 'inherit',
    cwd: process.cwd(),
    shell: isWindows,
  });

  opencode.on('error', (err) => {
    console.error(`\n❌ Failed to start OpenCode: ${err.message}`);
    console.error('\nInstall OpenCode with: npm i -g opencode-ai');
    process.exit(1);
  });

  opencode.on('exit', (code) => {
    process.exit(code ?? 0);
  });
}

// ============================================================================
// Main Entry Point
// ============================================================================

async function main(): Promise<void> {
  program
    .name('gemma4-agent')
    .description('A portable coding agent powered by Gemma 4')
    .version('0.1.0')
    .option('--download-only', 'Download binaries and model, then exit')
    .option('--server-only', 'Only start llama-server, do not start OpenCode')
    .option('--model-source <source>', 'Model source: bartowski or unsloth', CONFIG.MODEL_SOURCE)
    .option('--port <number>', 'Port for llama-server', CONFIG.LLAMA_PORT.toString())
    .option('--context <number>', 'Context size in tokens', CONFIG.CONTEXT_SIZE.toString())
    .option('--force-download', 'Force re-download of binaries and model')
    .parse();

  const options = program.opts<{
    downloadOnly?: boolean;
    serverOnly?: boolean;
    modelSource?: string;
    port?: string;
    context?: string;
    forceDownload?: boolean;
  }>();

  // Validate model source
  if (options.modelSource) {
    if (options.modelSource !== 'bartowski' && options.modelSource !== 'unsloth') {
      console.error(`Invalid model source: ${options.modelSource}`);
      console.error('Valid values: bartowski, unsloth');
      process.exit(1);
    }
    CONFIG.MODEL_SOURCE = options.modelSource;
  }

  if (options.port) CONFIG.LLAMA_PORT = parseInt(options.port, 10);
  if (options.context) CONFIG.CONTEXT_SIZE = parseInt(options.context, 10);

  console.log('╔════════════════════════════════════════════════════╗');
  console.log('║           Gemma 4 Coding Agent v0.1.0              ║');
  console.log('╚════════════════════════════════════════════════════╝');

  const backend = detectBackend();
  console.log(`\n🔍 Detected: ${process.platform} / ${process.arch} / ${backend.toUpperCase()}`);

  // Download llama.cpp binaries if needed
  if (options.forceDownload || !llamaBinaryExists()) {
    await downloadLlamaBinaries();
  } else {
    console.log(`\n✅ llama-server found: ${getLlamaServerPath()}`);
  }

  // Download model if needed
  if (options.forceDownload || !modelExists()) {
    await downloadModel();
  } else {
    console.log(`✅ Model found: ${path.join(getModelDir(), getModelConfig().file)}`);
  }

  if (options.downloadOnly) {
    console.log('\n✅ All downloads complete. Exiting.');
    process.exit(0);
  }

  // Start llama-server
  const server = startLlamaServer();

  // Handle cleanup
  const cleanup = () => {
    console.log('\n\n🛑 Shutting down...');
    server.kill();
    process.exit(0);
  };

  process.on('SIGINT', cleanup);
  process.on('SIGTERM', cleanup);

  // Wait for server to be ready
  console.log('⏳ Waiting for llama-server to be ready...');
  const serverReady = await waitForServer();

  if (!serverReady) {
    console.error('\n❌ llama-server failed to start within timeout.');
    server.kill();
    process.exit(1);
  }

  if (options.serverOnly) {
    console.log('\n✅ llama-server is running. Press Ctrl+C to stop.');
    await new Promise(() => {});
  }

  // Start OpenCode
  startOpenCode();
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
