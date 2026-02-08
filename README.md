# OpenCode on DGX Spark

Run [OpenCode](https://opencode.ai) with local LLMs on NVIDIA DGX Spark using llama.cpp.

This repository provides scripts to set up a complete local AI coding assistant environment on DGX Spark hardware, using MiniMax-M2.1 as the underlying model.

## Overview

- **Hardware**: NVIDIA DGX Spark with GB10 GPU (128GB unified memory)
- **Model**: [MiniMax-M2.1](https://huggingface.co/unsloth/MiniMax-M2.1-GGUF) - 456B MoE (21B active), optimized for coding and agentic tasks
- **Quantization**: UD-Q2_K_XL (~86GB, default), Q6_K, UD-Q6_K_XL, UD-Q4_K_XL
- **Runtime**: [llama.cpp](https://github.com/ggml-org/llama.cpp) with CUDA backend
- **Frontend**: [OpenCode](https://opencode.ai) - AI coding assistant CLI

## Quick Start

```bash
# Clone this repo
git clone https://github.com/rick-stevens-ai/OpenCode-on-SPARK.git
cd OpenCode-on-SPARK

# Run full setup (download model, install OpenCode, configure, launch)
./setup-opencode-minimax.sh

# Once complete, start coding!
opencode
```

## What the Setup Script Does

The script automates the entire setup process:

1. **Downloads MiniMax-M2.1 quantization** (default: UD-Q2_K_XL, ~86GB, 2 files) from HuggingFace
   - Supports resume if interrupted
   - Verifies file integrity

2. **Builds llama.cpp with CUDA support** (if not already built)
   - Automatically detects CUDA installation
   - Finds compatible g++ compiler (g++-13, g++-12, or g++)
   - Configures with CUDA, RPC, and FP16 support
   - Compiles with all CPU cores

3. **Installs OpenCode** if not already present
   - Downloads from official source (opencode.ai)
   - Automatically adds to PATH in ~/.zshrc or ~/.bashrc
   - Detects installation in ~/.opencode/bin or ~/.local/bin

4. **Generates configuration** (`~/.config/opencode/opencode.json`)
   - Configures llama.cpp as the provider
   - Sets up tool calling support
   - Compatible with OpenCode 1.1.15+

5. **Launches llama-server** with optimal settings
   - GPU acceleration (all layers offloaded)
   - Jinja templates for proper chat formatting
   - **128K context window** (131,072 tokens)

## Usage

```bash
# Full setup (first time)
./setup-opencode-minimax.sh

# Full setup with Q6_K quant (larger, higher quality)
./setup-opencode-minimax.sh --quant Q6_K

# Full setup with UD-Q6_K_XL quant (larger, higher quality)
./setup-opencode-minimax.sh --quant UD-Q6_K_XL

# Full setup with UD-Q4_K_XL quant (4-bit XL)
./setup-opencode-minimax.sh --quant UD-Q4_K_XL

# Check status
./status.sh

# Shutdown server
./shutdown.sh

# Download only (no server launch)
./setup-opencode-minimax.sh --download-only

# Launch server only (after download)
./setup-opencode-minimax.sh --launch-only

# Launch Q6_K server only (after download)
./setup-opencode-minimax.sh --launch-only --quant Q6_K

# Launch UD-Q6_K_XL server only (after download)
./setup-opencode-minimax.sh --launch-only --quant UD-Q6_K_XL

# Launch UD-Q4_K_XL server only (after download)
./setup-opencode-minimax.sh --launch-only --quant UD-Q4_K_XL

# Test inference
./setup-opencode-minimax.sh --test
```

## Multi-Node (DGX Spark)

You can extend GPU memory across multiple DGX Spark nodes using llama.cpp RPC (memory expansion, not tensor parallel).

### 1) Start rpc-server on each worker node
```bash
./setup-opencode-minimax.sh --rpc-worker
```

### 2) Start llama-server on the primary node with RPC targets
```bash
./setup-opencode-minimax.sh --launch-only --rpc 10.0.0.2:50052 --rpc 10.0.0.3:50052
```

You can also pass a comma-separated list:
```bash
./setup-opencode-minimax.sh --launch-only --rpc-hosts 10.0.0.2:50052,10.0.0.3:50052
```

Note: The primary node still needs the model files and `llama-server`. Run full setup there first.

See `docs/MULTI_NODE.md` for details.

### UD-Q6_K_XL on Two DGX Sparks (Example)

On the worker node:
```bash
./setup-opencode-minimax.sh --rpc-worker
```

On the primary node:
```bash
# Download model/build/config for UD-Q6_K_XL
./setup-opencode-minimax.sh --quant UD-Q6_K_XL --download-only

# Launch with one worker attached
./setup-opencode-minimax.sh --launch-only --quant UD-Q6_K_XL --rpc 10.0.0.2:50052
```

If you have two workers, add another `--rpc` target:
```bash
./setup-opencode-minimax.sh --launch-only --quant UD-Q6_K_XL --rpc 10.0.0.2:50052 --rpc 10.0.0.3:50052
```

## Scripts

| Script | Description |
|--------|-------------|
| `setup-opencode-minimax.sh` | Full setup: download, install, configure, launch |
| `status.sh` | Show status of model, server, and configuration |
| `shutdown.sh` | Clean shutdown of llama-server |

## Requirements

### Hardware
- NVIDIA GPU with 85GB+ VRAM (tested on DGX Spark GB10)
- ~90GB disk space for model
- Multi-core CPU for faster compilation

### Software (automatically checked/installed by script)
- Ubuntu 22.04+ or similar Linux
- CUDA 12.0+ or 13.0+
- cmake, g++, git, wget

The script will automatically:
- Detect and use your CUDA installation
- Find a compatible g++ compiler (g++-13, g++-12, or g++)
- Clone and build llama.cpp with CUDA support
- Install OpenCode CLI

**No manual building required!**

## Model Information

### MiniMax-M2.1

| Property | Value |
|----------|-------|
| Architecture | Mixture of Experts (MoE) |
| Total Parameters | 456B |
| Active Parameters | 21B |
| Quantization | UD-Q2_K_XL (default), Q6_K, UD-Q6_K_XL, UD-Q4_K_XL |
| Size on Disk | ~86GB |
| Context Length | Up to 1M tokens |
| License | Modified-MIT |

**Optimized for:**
- Multi-language code generation
- Tool use and function calling
- Long-horizon planning
- Agentic workflows

### Performance on DGX Spark

| Metric | Value |
|--------|-------|
| Inference Speed | ~30-35 tokens/second |
| Memory Usage | ~86GB of 128GB |
| Startup Time | ~2-3 minutes |

## Configuration

The setup script creates `~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "llama-cpp": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "MiniMax-M2.1 (llama.cpp)",
      "options": {
        "baseURL": "http://localhost:8080/v1"
      },
      "models": {
        "minimax-m2.1": {
          "name": "MiniMax-M2.1 UD-Q2_K_XL",
          "tools": true,
          "temperature": 1.0,
          "topP": 0.95
        }
      }
    }
  },
  "model": "llama-cpp/minimax-m2.1"
}
```

### Customizing

The script uses 128K context by default. To change it, edit `CTX_SIZE` in the script:

```bash
# Edit setup-opencode-minimax.sh
# Change: CTX_SIZE=131072
# To:     CTX_SIZE=196608  # For 192K context (model's training size)

# Then restart the server
./setup-opencode-minimax.sh --launch-only
```

Or launch manually with custom settings:

```bash
~/llama.cpp/build/bin/llama-server \
  -m ~/models/minimax-m2.1/MiniMax-M2.1-UD-Q2_K_XL-00001-of-00002.gguf \
  --ctx-size 196608 \
  --n-gpu-layers 99 \
  --port 8080 \
  --jinja
```

## Troubleshooting

### Server won't start

Check the log file:
```bash
tail -100 /tmp/llama-server-minimax-m2.1.log
```

### Out of memory

The UD-Q2_K_XL quantization requires ~86GB. If you have less memory, try a smaller quantization:
- `UD-IQ2_XXS` (~50GB)
- `UD-IQ1_M` (~40GB)

### Slow inference

Ensure GPU layers are enabled:
```bash
# Check GPU usage
nvidia-smi

# Verify all layers on GPU
grep "offloading" /tmp/llama-server-minimax-m2.1.log
```

### OpenCode can't connect

Verify the server is running:
```bash
curl http://localhost:8080/health
```

### OpenCode command not found

OpenCode is installed to `~/.opencode/bin`. Reload your shell:
```bash
exec zsh    # or: exec bash
```

Or manually add to PATH:
```bash
export PATH="$HOME/.opencode/bin:$PATH"
```

### Configuration error about temperature

If you see an error about temperature being a number instead of boolean, the config format has been updated. Re-run:
```bash
./setup-opencode-minimax.sh --launch-only
```

This will regenerate the config with the correct format.

## Alternative Models

The setup script is configured for MiniMax-M2.1, but you can adapt it for other models:

| Model | Size | Notes |
|-------|------|-------|
| Qwen3-Coder-30B-A3B | ~20GB | Smaller, faster, good for coding |
| DeepSeek-V3 | ~400GB | Requires multi-node RPC |
| Llama-3.1-70B | ~40GB | General purpose |

## Related Projects

- [spark-multi-node](https://github.com/rick-stevens-ai/spark-multi-node) - Multi-node inference scripts for DGX Spark
- [llama.cpp](https://github.com/ggml-org/llama.cpp) - LLM inference engine
- [OpenCode](https://github.com/sst/opencode) - AI coding assistant

## License

MIT License - see [LICENSE](LICENSE)

## Acknowledgments

- [Unsloth](https://github.com/unsloth/unsloth) for optimized GGUF quantizations
- [MiniMax](https://www.minimax.io/) for releasing M2.1 to open source
- [ggml-org](https://github.com/ggml-org) for llama.cpp
