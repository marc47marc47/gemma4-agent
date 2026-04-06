#!/usr/bin/env node
/**
 * Gemma 4 Coding Agent Launcher
 *
 * This launcher:
 * 1. Detects hardware (CUDA/Metal/CPU)
 * 2. Downloads the model if not present
 * 3. Starts llama-server
 * 4. Launches OpenCode connected to the local server
 */

import { spawn, execSync, type ChildProcess } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import { program } from 'commander';

// Configuration
const CONFIG = {
  MODEL_REPO: 'bartowski/google_gemma-4-E4B-it-GGUF',
  MODEL_FILE: 'google_gemma-4-E4B-it-Q4_K_M.gguf',
  MODEL_SIZE_GB: 5.4,
  LLAMA_PORT: 8089,
  CONTEXT_SIZE: 32768,
};

// Get cache directory based on platform
function getCacheDir(): string {
  const platform = process.platform;
  const home = os.homedir();

  if (platform === 'win32') {
    return process.env.LOCALAPPDATA
      ? path.join(process.env.LOCALAPPDATA, 'gemma4-agent', 'models')
      : path.join(home, 'AppData', 'Local', 'gemma4-agent', 'models');
  } else if (platform === 'darwin') {
    return path.join(home, 'Library', 'Caches', 'gemma4-agent', 'models');
  } else {
    return path.join(home, '.cache', 'gemma4-agent', 'models');
  }
}

// Get llama-server binary path
function getLlamaServerPath(): string {
  const platform = process.platform;
  const binDir = path.join(path.dirname(process.argv[1]), '..', 'llama-builds');
  const backend = detectBackend();

  let binaryName = 'llama-server';
  if (platform === 'win32') {
    binaryName = 'llama-server.exe';
  }

  // Try bundled binary first
  const bundledPath = path.join(binDir, `${platform}-${backend}`, binaryName);
  if (fs.existsSync(bundledPath)) {
    return bundledPath;
  }

  // Try local llama.cpp build (Ninja/default configuration - CUDA)
  const localBuildPath = path.join(process.cwd(), 'llama.cpp', 'build', 'bin', binaryName);
  if (fs.existsSync(localBuildPath)) {
    return localBuildPath;
  }

  // Try local llama.cpp build (Visual Studio Release configuration)
  const localBuildPathRelease = path.join(process.cwd(), 'llama.cpp', 'build', 'bin', 'Release', binaryName);
  if (fs.existsSync(localBuildPathRelease)) {
    return localBuildPathRelease;
  }

  // Fallback: assume llama-server is in PATH
  return binaryName;
}

// Detect hardware acceleration
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

// Check if model exists
function modelExists(): boolean {
  const modelPath = path.join(getCacheDir(), CONFIG.MODEL_FILE);
  return fs.existsSync(modelPath);
}

// Download model from HuggingFace
async function downloadModel(): Promise<void> {
  const cacheDir = getCacheDir();
  const modelPath = path.join(cacheDir, CONFIG.MODEL_FILE);

  // Ensure cache directory exists
  fs.mkdirSync(cacheDir, { recursive: true });

  console.log(`\n📥 Downloading Gemma 4 E4B model (~${CONFIG.MODEL_SIZE_GB}GB)...`);
  console.log(`   Repository: ${CONFIG.MODEL_REPO}`);
  console.log(`   File: ${CONFIG.MODEL_FILE}`);
  console.log(`   Destination: ${modelPath}\n`);

  try {
    // Use huggingface-cli if available
    const hfCommand = process.platform === 'win32' ? 'huggingface-cli.exe' : 'huggingface-cli';

    try {
      execSync(`${hfCommand} download ${CONFIG.MODEL_REPO} ${CONFIG.MODEL_FILE} --local-dir "${cacheDir}"`, {
        stdio: 'inherit',
      });
    } catch {
      // Fallback: try with curl/wget
      console.log('huggingface-cli not found, trying direct download...');
      const url = `https://huggingface.co/${CONFIG.MODEL_REPO}/resolve/main/${CONFIG.MODEL_FILE}`;

      if (process.platform === 'win32') {
        execSync(`curl -L -o "${modelPath}" "${url}"`, { stdio: 'inherit' });
      } else {
        execSync(`curl -L -o "${modelPath}" "${url}"`, { stdio: 'inherit' });
      }
    }

    console.log('\n✅ Model downloaded successfully!\n');
  } catch (error) {
    console.error('\n❌ Failed to download model.');
    console.error('Please download manually from:');
    console.error(`https://huggingface.co/${CONFIG.MODEL_REPO}/tree/main`);
    console.error(`And place "${CONFIG.MODEL_FILE}" in: ${cacheDir}`);
    process.exit(1);
  }
}

// Start llama-server
function startLlamaServer(): ChildProcess {
  const backend = detectBackend();
  const modelPath = path.join(getCacheDir(), CONFIG.MODEL_FILE);
  const serverPath = getLlamaServerPath();

  console.log(`\n🚀 Starting llama-server...`);
  console.log(`   Backend: ${backend.toUpperCase()}`);
  console.log(`   Model: ${modelPath}`);
  console.log(`   Port: ${CONFIG.LLAMA_PORT}`);
  console.log(`   Context: ${CONFIG.CONTEXT_SIZE} tokens\n`);

  const args = [
    '-m', modelPath,
    '--port', CONFIG.LLAMA_PORT.toString(),
    '-c', CONFIG.CONTEXT_SIZE.toString(),
    '--jinja',  // Required for Gemma 4 tool calling
  ];

  // Add GPU-specific flags
  if (backend === 'cuda' || backend === 'metal') {
    args.push('-ngl', '99');  // Offload all layers to GPU
  }

  const server = spawn(serverPath, args, {
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  server.stdout?.on('data', (data) => {
    const line = data.toString();
    if (line.includes('server is listening')) {
      console.log('✅ llama-server is ready!\n');
    }
  });

  server.stderr?.on('data', (data) => {
    // Only show errors, not progress
    const line = data.toString();
    if (line.includes('error') || line.includes('Error')) {
      console.error(`[llama-server] ${line}`);
    }
  });

  server.on('error', (err) => {
    console.error(`\n❌ Failed to start llama-server: ${err.message}`);
    console.error('\nMake sure llama.cpp is compiled and llama-server is available.');
    process.exit(1);
  });

  return server;
}

// Wait for llama-server to be ready
async function waitForServer(maxWaitMs = 60000): Promise<boolean> {
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

// Start OpenCode
function startOpenCode(): void {
  const opencodePath = process.platform === 'win32' ? 'opencode.cmd' : 'opencode';

  console.log('🤖 Starting OpenCode with Gemma 4...\n');
  console.log('─'.repeat(50));

  const opencode = spawn(opencodePath, [], {
    stdio: 'inherit',
    cwd: process.cwd(),
    env: {
      ...process.env,
      // Ensure OpenCode uses our config
      OPENCODE_CONFIG: path.join(process.cwd(), 'opencode.json'),
    },
  });

  opencode.on('error', (err) => {
    console.error(`\n❌ Failed to start OpenCode: ${err.message}`);
    console.error('\nMake sure OpenCode is installed:');
    console.error('  npm i -g opencode-ai');
    process.exit(1);
  });

  opencode.on('exit', (code) => {
    process.exit(code ?? 0);
  });
}

// Main entry point
async function main(): Promise<void> {
  program
    .name('gemma4-agent')
    .description('A portable coding agent powered by Gemma 4')
    .version('0.1.0')
    .option('--download-only', 'Only download the model, do not start the agent')
    .option('--server-only', 'Only start llama-server, do not start OpenCode')
    .option('--port <number>', 'Port for llama-server', CONFIG.LLAMA_PORT.toString())
    .option('--context <number>', 'Context size in tokens', CONFIG.CONTEXT_SIZE.toString())
    .parse();

  const options = program.opts();

  // Override config from CLI
  if (options.port) CONFIG.LLAMA_PORT = parseInt(options.port, 10);
  if (options.context) CONFIG.CONTEXT_SIZE = parseInt(options.context, 10);

  console.log('╔════════════════════════════════════════════════════╗');
  console.log('║           Gemma 4 Coding Agent v0.1.0              ║');
  console.log('╚════════════════════════════════════════════════════╝');

  // Check/download model
  if (!modelExists()) {
    await downloadModel();
    if (options.downloadOnly) {
      console.log('✅ Download complete. Exiting.');
      process.exit(0);
    }
  } else {
    console.log(`\n✅ Model found: ${path.join(getCacheDir(), CONFIG.MODEL_FILE)}`);
  }

  if (options.downloadOnly) {
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
    // Keep running
    await new Promise(() => {});
  }

  // Start OpenCode
  startOpenCode();
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
