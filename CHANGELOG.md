# Changelog - OpenCode on DGX Spark Setup Script

## Summary of Improvements

This document details all enhancements made to the `setup-opencode-minimax.sh` script to make it fully automated and production-ready.

## Major Changes

### 1. Automatic llama.cpp Building (NEW)
**Added `build_llamacpp()` function** that automatically:
- Detects if llama.cpp is already built (skips if present)
- Checks for required build tools (cmake, git, g++)
- Automatically finds compatible g++ compiler (g++-13, g++-12, or g++)
- Auto-detects CUDA installation (/usr/local/cuda, cuda-13, cuda-12)
- Clones llama.cpp repository if needed
- Configures CMake with CUDA support:
  - `GGML_CUDA=ON` - GPU acceleration
  - `GGML_RPC=ON` - Multi-node support
  - `GGML_CUDA_F16=ON` - FP16 optimization
  - `LLAMA_CURL=OFF` - Disable curl dependency
- Builds with all CPU cores (`-j$(nproc)`)
- Verifies successful build

**Benefits:**
- No manual building required
- Works on different CUDA versions
- Handles missing dependencies gracefully
- Fully restartable (skips if already done)

### 2. Fixed OpenCode Installation
**Before:** Used incorrect URL `https://opencode.sh/install.sh` → 404 error
**After:** Uses correct URL `https://opencode.ai/install`

**Enhanced PATH detection:**
- Checks `~/.opencode/bin` (primary location)
- Checks `~/.local/bin` (fallback)
- Automatically adds to `~/.zshrc` or `~/.bashrc`
- Exports to current session PATH

### 3. Fixed OpenCode Configuration
**Before:** Config included incompatible fields:
```json
{
  "temperature": 1.0,  // ❌ OpenCode expects boolean
  "topP": 0.95         // ❌ Not supported
}
```

**After:** Clean, compatible config:
```json
{
  "name": "MiniMax-M2.1 UD-Q2_K_XL",
  "tools": true  // ✅ Only supported fields
}
```

### 4. Increased Context Size
**Before:** 8K tokens (8,192)
**After:** 128K tokens (131,072)

The model was trained on 192K tokens, so 128K provides:
- Better long-form code generation
- More context for large codebases
- Fits well in GPU memory with headroom

### 5. Enhanced Status Reporting
Added llama.cpp status to `--status` command:
```
llama.cpp:
  Status: Built / Cloned, not built / Not installed
  Path: /home/user/llama.cpp
```

Shows complete system state at a glance.

### 6. Improved Help Documentation
**Enhanced `--help` output:**
- Clear step-by-step setup process
- Lists all requirements
- Shows what each option does
- More user-friendly formatting

### 7. Better Final Instructions
**Before:** Generic "run opencode"
**After:** Complete guidance:
1. How to ensure server is running
2. How to reload shell for PATH
3. How to navigate and use OpenCode
4. Server details (context, port, model info)
5. Status check command

## Script Flow

### Before
1. Download model ✓
2. Install OpenCode ❌ (wrong URL)
3. Generate config ⚠️ (incompatible format)
4. Launch server ❌ (requires manual llama.cpp build)

### After
1. Download model ✓
2. **Build llama.cpp ✓** (NEW - automatic)
3. Install OpenCode ✓ (fixed URL + PATH handling)
4. Generate config ✓ (fixed format)
5. Launch server ✓ (128K context)
6. Test inference ✓

## Configuration Changes

### Context Size
```bash
# Line 25
CTX_SIZE=8192      # Before
CTX_SIZE=131072    # After (128K)
```

### OpenCode Config Template
```bash
# Lines 172-194
# Removed temperature and topP fields
# These are not supported by OpenCode 1.1.15+
```

## New Functions

### `build_llamacpp()`
- **Lines 135-230**
- Handles complete llama.cpp build process
- Smart detection of compilers and CUDA
- Full error handling and reporting

### Enhanced `install_opencode()`
- **Lines 233-286**
- Better PATH detection
- Auto-updates shell RC files
- Clearer success/error messages

## Testing Performed

✅ Fresh install (no llama.cpp)
✅ Existing llama.cpp (skips build)
✅ OpenCode not in PATH (adds automatically)
✅ Config generation (correct format)
✅ Server launch with 128K context
✅ Inference testing
✅ Status reporting
✅ Help message display

## Compatibility

### Tested On
- **GPU:** NVIDIA GB10 (compute 12.1)
- **OS:** Ubuntu 24.04
- **CUDA:** 13.0
- **Compiler:** g++-13
- **OpenCode:** 1.1.15

### Should Work With
- Any NVIDIA GPU with 85GB+ VRAM
- Ubuntu 22.04+
- CUDA 12.0+
- g++ versions 11-13
- OpenCode 1.1.0+

## Usage Examples

### First-time Setup
```bash
./setup-opencode-minimax.sh
```
Automatically does everything!

### Just Download and Build
```bash
./setup-opencode-minimax.sh --download-only
```

### Restart Server
```bash
./setup-opencode-minimax.sh --launch-only
```

### Check Status
```bash
./setup-opencode-minimax.sh --status
```

## Files Modified

1. **setup-opencode-minimax.sh** - Main script (major enhancements)
2. **opencode.json** (generated) - Fixed config format
3. **README.md** - Updated documentation
4. **CHANGELOG.md** (this file) - New documentation

## Breaking Changes

None! Script is fully backward compatible:
- Skips steps that are already done
- Existing installations work fine
- Can be re-run safely

## Future Enhancements

Potential improvements:
- [ ] Support for different quantizations (Q4, Q5, etc.)
- [ ] Multi-GPU setup
- [ ] Automatic GPU memory detection
- [ ] Custom model selection
- [ ] Docker support
- [ ] Systemd service for auto-start

## Contributors

- Initial setup script: OpenCode-on-SPARK project
- Enhancements: Claude (Anthropic) + User collaboration
