#!/bin/bash
#
# setup-opencode-minimax.sh
#
# Complete setup script for OpenCode + local GGUF models on NVIDIA GPUs:
# - Defaults to MiniMax-M2.1 UD-Q2_K_XL (~86GB)
# - Supports MiniMax-M2.5 (same quant subdirs, if available in your HF repo)
# - Builds llama.cpp with CUDA support (if not already built)
# - Installs OpenCode CLI
# - Configures OpenCode to use local llama.cpp server
# - Launches model server with 128K context
#
# This script is restartable - it will skip completed steps.
#
# Usage: ./setup-opencode-minimax.sh [OPTIONS]
#

set -e

# Configuration
MODEL="minimax-m2.1" # minimax-m2.1 | minimax-m2.5 | gpt-oss-120b

MODEL_REPO="unsloth/MiniMax-M2.1-GGUF"
MODEL_SUBDIR="UD-Q2_K_XL"
MODEL_NAME="MiniMax-M2.1-UD-Q2_K_XL"
MODEL_DIR_BASE="$HOME/models/minimax-m2.1"
MODEL_DIR="$MODEL_DIR_BASE/$MODEL_SUBDIR"
MODEL_URL_BASE="https://huggingface.co/$MODEL_REPO/resolve/main/$MODEL_SUBDIR"
MODEL_FILE_PREFIX="MiniMax-M2.1"
MODEL_DISPLAY_BASE="MiniMax-M2.1"

# Default quant
QUANT="UD-Q2_K_XL"

# Model file lists
MODEL_FILES_UD=(
    "MiniMax-M2.1-UD-Q2_K_XL-00001-of-00002.gguf"
    "MiniMax-M2.1-UD-Q2_K_XL-00002-of-00002.gguf"
)
MODEL_SIZES_UD=(
    49950511392  # ~50GB
    35967481120  # ~36GB
)

MODEL_FILES_UD_Q4_XL=(
    "MiniMax-M2.1-UD-Q4_K_XL-00001-of-00003.gguf"
    "MiniMax-M2.1-UD-Q4_K_XL-00002-of-00003.gguf"
    "MiniMax-M2.1-UD-Q4_K_XL-00003-of-00003.gguf"
)
# Sizes not enforced for UD-Q4_K_XL (files are large and sizes may vary slightly)
MODEL_SIZES_UD_Q4_XL=(0 0 0)

MODEL_FILES_UD_Q3_XL=(
    "MiniMax-M2.1-UD-Q3_K_XL-00001-of-00003.gguf"
    "MiniMax-M2.1-UD-Q3_K_XL-00002-of-00003.gguf"
    "MiniMax-M2.1-UD-Q3_K_XL-00003-of-00003.gguf"
)
# Sizes not enforced for UD-Q3_K_XL (files are large and sizes may vary slightly)
MODEL_SIZES_UD_Q3_XL=(0 0 0)

MODEL_FILES_GPT_OSS_120B_UD_Q4_XL=(
    "gpt-oss-120b-UD-Q4_K_XL-00001-of-00002.gguf"
    "gpt-oss-120b-UD-Q4_K_XL-00002-of-00002.gguf"
)
# Sizes not enforced for GPT-OSS-120B UD-Q4_K_XL (files are large and sizes may vary slightly)
MODEL_SIZES_GPT_OSS_120B_UD_Q4_XL=(0 0)

MODEL_FILES=("${MODEL_FILES_UD[@]}")
MODEL_SIZES=("${MODEL_SIZES_UD[@]}")
MODEL_KIND="gguf"
OPENCODE_MODEL_ID="minimax-m2.1"
OPENCODE_MODEL_DISPLAY="MiniMax-M2.1 ($QUANT)"
THINKING_MODE="normal"
THINKING_MODE_SET=false
MODEL_TEMPERATURE="1.0"
MODEL_TOP_P="0.95"
MODEL_MAX_TOKENS="4096"
LLAMA_CPP_DIR="$HOME/llama.cpp"
SERVER_PORT=8080
CTX_SIZE=131072
OPENCODE_CONFIG_DIR="$HOME/.config/opencode"
RPC_PORT=50052
RPC_BIND="0.0.0.0"
RPC_TARGETS=()
CHAT_TEMPLATE_FILE=""
LLAMA_SERVER_EXTRA_ARGS=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

build_sharded_gguf_file_list() {
    local prefix="$1"      # e.g. MiniMax-M2.1
    local subdir="$2"      # e.g. UD-Q2_K_XL
    local parts="$3"       # e.g. 2, 3

    MODEL_FILES=()
    local total
    total=$(printf "%05d" "$parts")
    for ((i=1; i<=parts; i++)); do
        local part
        part=$(printf "%05d" "$i")
        MODEL_FILES+=("${prefix}-${subdir}-${part}-of-${total}.gguf")
    done
}

discover_model_files_from_hf() {
    if [[ "$MODEL_KIND" != "gguf" ]]; then
        return 1
    fi

    if ! command -v curl &> /dev/null; then
        log_error "curl not found; cannot auto-discover model files"
        return 1
    fi
    if ! command -v jq &> /dev/null; then
        log_error "jq not found; cannot auto-discover model files"
        return 1
    fi

    local api_url="https://huggingface.co/api/models/$MODEL_REPO/tree/main/$MODEL_SUBDIR"
    log_info "Discovering model files from Hugging Face: $MODEL_REPO/$MODEL_SUBDIR"

    local listing
    if ! listing=$(curl -fsSL "$api_url" 2>/dev/null); then
        log_error "Failed to query Hugging Face model tree: $api_url"
        return 1
    fi

    local entries
    entries=$(echo "$listing" | jq -r '.[] | select(.type=="file" and (.path | endswith(".gguf"))) | [.path, (.size // 0)] | @tsv')
    if [[ -z "$entries" ]]; then
        log_error "No .gguf files found in $MODEL_REPO/$MODEL_SUBDIR"
        return 1
    fi

    MODEL_FILES=()
    MODEL_SIZES=()
    while IFS=$'\t' read -r path size; do
        [[ -z "$path" ]] && continue
        MODEL_FILES+=("${path##*/}")
        MODEL_SIZES+=("${size:-0}")
    done <<< "$entries"

    log_success "Discovered ${#MODEL_FILES[@]} model file(s) in $MODEL_SUBDIR"
    return 0
}

select_model_family() {
    case "$MODEL" in
        minimax-m2.1)
            MODEL_KIND="gguf"
            MODEL_REPO="unsloth/MiniMax-M2.1-GGUF"
            MODEL_DIR_BASE="$HOME/models/minimax-m2.1"
            MODEL_FILE_PREFIX="MiniMax-M2.1"
            MODEL_DISPLAY_BASE="MiniMax-M2.1"
            OPENCODE_MODEL_ID="minimax-m2.1"
            ;;
        minimax-m2.5)
            MODEL_KIND="gguf"
            MODEL_REPO="unsloth/MiniMax-M2.5-GGUF"
            MODEL_DIR_BASE="$HOME/models/minimax-m2.5"
            MODEL_FILE_PREFIX="MiniMax-M2.5"
            MODEL_DISPLAY_BASE="MiniMax-M2.5"
            OPENCODE_MODEL_ID="minimax-m2.5"
            ;;
        gpt-oss-120b)
            MODEL_KIND="gguf"
            MODEL_REPO="unsloth/gpt-oss-120b-GGUF"
            MODEL_DIR_BASE="$HOME/models/gpt-oss"
            MODEL_FILE_PREFIX="gpt-oss-120b"
            MODEL_DISPLAY_BASE="gpt-oss-120b"
            OPENCODE_MODEL_ID="gpt-oss-120b"
            QUANT="GPT-OSS-120B"
            ;;
        *)
            log_error "Unknown model: $MODEL"
            log_info "Supported models: minimax-m2.1, minimax-m2.5, gpt-oss-120b"
            exit 1
            ;;
    esac
}

# Check if a file is fully downloaded (by size)
check_file_complete() {
    local file="$1"
    local expected_size="$2"

    if [[ -f "$file" ]]; then
        if [[ "$expected_size" -le 0 ]]; then
            return 0
        fi
        local actual_size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
        if [[ "$actual_size" -ge "$expected_size" ]]; then
            return 0
        fi
    fi
    return 1
}

# Download a file with resume support
download_file() {
    local url="$1"
    local output="$2"
    local expected_size="$3"

    if check_file_complete "$output" "$expected_size"; then
        log_success "$(basename "$output") already downloaded"
        return 0
    fi

    log_info "Downloading $(basename "$output")..."
    wget -c -q --show-progress "$url" -O "$output"

    if check_file_complete "$output" "$expected_size"; then
        log_success "$(basename "$output") download complete"
        return 0
    else
        log_error "$(basename "$output") download incomplete"
        return 1
    fi
}

select_quant() {
    case "$QUANT" in
        UD-Q2_K_XL)
            MODEL_KIND="gguf"
            MODEL_SUBDIR="UD-Q2_K_XL"
            MODEL_NAME="${MODEL_FILE_PREFIX}-${MODEL_SUBDIR}"
            if [[ "$MODEL" == "minimax-m2.1" ]]; then
                build_sharded_gguf_file_list "$MODEL_FILE_PREFIX" "$MODEL_SUBDIR" 2
            else
                MODEL_FILES=()
            fi
            # Only enforce known sizes for MiniMax-M2.1 UD-Q2_K_XL.
            if [[ "$MODEL" == "minimax-m2.1" ]]; then
                MODEL_SIZES=("${MODEL_SIZES_UD[@]}")
            else
                MODEL_SIZES=()
            fi
            OPENCODE_MODEL_DISPLAY="$MODEL_DISPLAY_BASE ($QUANT)"
            ;;
        UD-Q4_K_XL)
            MODEL_KIND="gguf"
            MODEL_SUBDIR="UD-Q4_K_XL"
            MODEL_NAME="${MODEL_FILE_PREFIX}-${MODEL_SUBDIR}"
            if [[ "$MODEL" == "minimax-m2.1" ]]; then
                build_sharded_gguf_file_list "$MODEL_FILE_PREFIX" "$MODEL_SUBDIR" 3
                MODEL_SIZES=(0 0 0)
            else
                MODEL_FILES=()
                MODEL_SIZES=()
            fi
            OPENCODE_MODEL_DISPLAY="$MODEL_DISPLAY_BASE ($QUANT)"
            ;;
        UD-Q3_K_XL)
            MODEL_KIND="gguf"
            MODEL_SUBDIR="UD-Q3_K_XL"
            MODEL_NAME="${MODEL_FILE_PREFIX}-${MODEL_SUBDIR}"
            if [[ "$MODEL" == "minimax-m2.1" ]]; then
                build_sharded_gguf_file_list "$MODEL_FILE_PREFIX" "$MODEL_SUBDIR" 3
                MODEL_SIZES=(0 0 0)
            else
                MODEL_FILES=()
                MODEL_SIZES=()
            fi
            OPENCODE_MODEL_DISPLAY="$MODEL_DISPLAY_BASE ($QUANT)"
            ;;
        UD-Q6_K_XL|Q6_K_XL)
            MODEL_KIND="gguf"
            MODEL_SUBDIR="UD-Q6_K_XL"
            MODEL_NAME="${MODEL_FILE_PREFIX}-${MODEL_SUBDIR}"
            # Use Hugging Face tree discovery for Q6 files/shard counts.
            MODEL_FILES=()
            MODEL_SIZES=()
            OPENCODE_MODEL_DISPLAY="$MODEL_DISPLAY_BASE (UD-Q6_K_XL)"
            ;;
        GPT-OSS-120B)
            MODEL_KIND="gguf"
            MODEL_SUBDIR="UD-Q4_K_XL"
            MODEL_NAME="gpt-oss-120b-UD-Q4_K_XL"
            MODEL_FILES=("${MODEL_FILES_GPT_OSS_120B_UD_Q4_XL[@]}")
            MODEL_SIZES=("${MODEL_SIZES_GPT_OSS_120B_UD_Q4_XL[@]}")
            OPENCODE_MODEL_DISPLAY="gpt-oss-120b UD-Q4_K_XL"
            if ! $THINKING_MODE_SET; then
                THINKING_MODE="high"
            fi
            ;;
        *)
            log_error "Unknown quant: $QUANT"
            log_info "Supported options: UD-Q2_K_XL, UD-Q3_K_XL, UD-Q4_K_XL, UD-Q6_K_XL (or Q6_K_XL), GPT-OSS-120B"
            exit 1
            ;;
    esac

    if [[ "$MODEL_KIND" == "gguf" ]]; then
        MODEL_DIR="$MODEL_DIR_BASE/$MODEL_SUBDIR"
        MODEL_URL_BASE="https://huggingface.co/$MODEL_REPO/resolve/main/$MODEL_SUBDIR"
    fi

    case "$THINKING_MODE" in
        high)
            MODEL_TEMPERATURE="0.6"
            MODEL_TOP_P="0.9"
            MODEL_MAX_TOKENS="8192"
            ;;
        normal)
            MODEL_TEMPERATURE="1.0"
            MODEL_TOP_P="0.95"
            MODEL_MAX_TOKENS="4096"
            ;;
        *)
            log_error "Unknown thinking mode: $THINKING_MODE"
            log_info "Supported thinking modes: normal, high"
            exit 1
            ;;
    esac
}

# Download model files
download_model() {
    log_info "=== Downloading Model ($QUANT) ==="

    if [[ ${#MODEL_FILES[@]} -eq 0 ]]; then
        discover_model_files_from_hf
    fi

    mkdir -p "$MODEL_DIR"
    cd "$MODEL_DIR"

    local all_complete=true

    for i in "${!MODEL_FILES[@]}"; do
        local file="${MODEL_FILES[$i]}"
        local size="${MODEL_SIZES[$i]}"
        if check_file_complete "$file" "$size"; then
            log_success "$file already exists"
        else
            all_complete=false
        fi
    done

    if $all_complete; then
        log_success "Model already fully downloaded ($(du -sh "$MODEL_DIR" | cut -f1))"
        return 0
    fi

    # Download missing files in parallel
    log_info "Starting parallel downloads..."

    local pids=()

    for i in "${!MODEL_FILES[@]}"; do
        local file="${MODEL_FILES[$i]}"
        local size="${MODEL_SIZES[$i]}"
        if ! check_file_complete "$file" "$size"; then
            wget -c -q --show-progress "$MODEL_URL_BASE/$file" -O "$file" &
            pids+=($!)
        fi
    done

    # Wait for downloads
    local failed=false
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            failed=true
        fi
    done

    if $failed; then
        log_error "Some downloads failed. Re-run the script to resume."
        return 1
    fi

    log_success "Model download complete ($(du -sh "$MODEL_DIR" | cut -f1))"
}

# Build llama.cpp with CUDA support
build_llamacpp() {
    log_info "=== Building llama.cpp with CUDA ==="

    # Check if already built
    local server_bin="$LLAMA_CPP_DIR/build/bin/llama-server"
    if [[ -x "$server_bin" ]]; then
        log_success "llama.cpp already built at $LLAMA_CPP_DIR"
        return 0
    fi

    # Check for required tools
    if ! command -v cmake &> /dev/null; then
        log_error "cmake not found. Please install: sudo apt-get install cmake"
        return 1
    fi

    if ! command -v git &> /dev/null; then
        log_error "git not found. Please install: sudo apt-get install git"
        return 1
    fi

    # Find g++ compiler
    local gpp_compiler=""
    if command -v g++-13 &> /dev/null; then
        gpp_compiler="/usr/bin/g++-13"
    elif command -v g++-12 &> /dev/null; then
        gpp_compiler="/usr/bin/g++-12"
    elif command -v g++ &> /dev/null; then
        gpp_compiler=$(which g++)
    else
        log_error "g++ not found. Please install: sudo apt-get install g++"
        return 1
    fi
    log_info "Using compiler: $gpp_compiler"

    # Find CUDA
    local cuda_path=""
    if [[ -d "/usr/local/cuda" ]]; then
        cuda_path="/usr/local/cuda"
    elif [[ -d "/usr/local/cuda-13" ]]; then
        cuda_path="/usr/local/cuda-13"
    elif [[ -d "/usr/local/cuda-12" ]]; then
        cuda_path="/usr/local/cuda-12"
    else
        log_error "CUDA not found in /usr/local/cuda*"
        log_info "Please install CUDA toolkit or specify CUDA path"
        return 1
    fi
    log_info "Using CUDA: $cuda_path"

    # Clone llama.cpp if needed
    if [[ ! -d "$LLAMA_CPP_DIR" ]]; then
        log_info "Cloning llama.cpp..."
        git clone https://github.com/ggml-org/llama.cpp.git "$LLAMA_CPP_DIR"
    else
        log_info "llama.cpp repository already exists"
    fi

    cd "$LLAMA_CPP_DIR"

    # Configure with CMake
    log_info "Configuring build with CUDA support..."
    export PATH="$cuda_path/bin:$PATH"

    CUDAHOSTCXX="$gpp_compiler" cmake -B build \
        -DGGML_CUDA=ON \
        -DGGML_RPC=ON \
        -DGGML_CUDA_F16=ON \
        -DCMAKE_CUDA_HOST_COMPILER="$gpp_compiler" \
        -DLLAMA_CURL=OFF

    if [[ $? -ne 0 ]]; then
        log_error "CMake configuration failed"
        return 1
    fi

    # Build
    log_info "Building llama.cpp (this may take several minutes)..."
    export PATH="$cuda_path/bin:$PATH"
    cmake --build build -j$(nproc)

    if [[ $? -ne 0 ]]; then
        log_error "Build failed"
        return 1
    fi

    # Verify build
    if [[ -x "$server_bin" ]]; then
        log_success "llama.cpp built successfully"
        log_info "Server binary: $server_bin"
        return 0
    else
        log_error "Build completed but llama-server not found"
        return 1
    fi
}

# Install OpenCode
install_opencode() {
    log_info "=== Installing OpenCode ==="

    if command -v opencode &> /dev/null; then
        local version=$(opencode --version 2>/dev/null || echo "unknown")
        log_success "OpenCode already installed (version: $version)"
        return 0
    fi

    log_info "Installing OpenCode..."
    curl -fsSL https://opencode.ai/install | bash

    # Verify installation
    if command -v opencode &> /dev/null; then
        log_success "OpenCode installed successfully"
        return 0
    fi

    # Check common installation locations
    local opencode_path=""
    if [[ -f "$HOME/.opencode/bin/opencode" ]]; then
        opencode_path="$HOME/.opencode/bin"
    elif [[ -f "$HOME/.local/bin/opencode" ]]; then
        opencode_path="$HOME/.local/bin"
    fi

    if [[ -n "$opencode_path" ]]; then
        log_warn "OpenCode installed to $opencode_path - adding to PATH for this session"
        export PATH="$opencode_path:$PATH"

        # Update shell rc files if not already there
        local shell_rc=""
        if [[ -n "$ZSH_VERSION" ]]; then
            shell_rc="$HOME/.zshrc"
        elif [[ -n "$BASH_VERSION" ]]; then
            shell_rc="$HOME/.bashrc"
        fi

        if [[ -n "$shell_rc" ]] && [[ -f "$shell_rc" ]]; then
            if ! grep -q "/.opencode/bin" "$shell_rc" 2>/dev/null; then
                echo "" >> "$shell_rc"
                echo "# opencode" >> "$shell_rc"
                echo "export PATH=\"$opencode_path:\$PATH\"" >> "$shell_rc"
                log_info "Added OpenCode to PATH in $shell_rc"
            fi
        fi

        log_success "OpenCode installed successfully"
        return 0
    else
        log_error "OpenCode installation failed - binary not found"
        return 1
    fi
}

# Generate OpenCode configuration
generate_config() {
    log_info "=== Generating OpenCode Configuration ==="

    mkdir -p "$OPENCODE_CONFIG_DIR"

    local config_file="$OPENCODE_CONFIG_DIR/opencode.json"

    # Always regenerate to ensure correct settings
    cat > "$config_file" << JSONEOF
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "llama-cpp": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Local Model (llama.cpp)",
      "options": {
        "baseURL": "http://localhost:8080/v1"
      },
      "models": {
        "$OPENCODE_MODEL_ID": {
          "name": "$OPENCODE_MODEL_DISPLAY",
          "tools": true,
          "temperature": $MODEL_TEMPERATURE,
          "topP": $MODEL_TOP_P,
          "maxTokens": $MODEL_MAX_TOKENS
        }
      }
    }
  },
  "model": "llama-cpp/$OPENCODE_MODEL_ID"
}
JSONEOF

    log_success "OpenCode config written to $config_file"

    # Also create a project-local config if in a project directory
    if [[ -d ".git" ]] && [[ ! -f "opencode.json" ]]; then
        cp "$config_file" "./opencode.json"
        log_info "Also created local opencode.json in current directory"
    fi
}

# Check if llama-server is running
is_server_running() {
    if curl -s "http://localhost:$SERVER_PORT/health" &>/dev/null; then
        return 0
    fi
    return 1
}

# Launch llama.cpp server
launch_server() {
    log_info "=== Launching llama.cpp Server ==="

    local server_log="/tmp/llama-server-${OPENCODE_MODEL_ID}.log"

    # Check if server is already running
    if is_server_running; then
        log_success "llama-server already running on port $SERVER_PORT"
        return 0
    fi

    # Check if model exists
    local model_path=""
    if [[ ${#MODEL_FILES[@]} -gt 0 ]]; then
        model_path="$MODEL_DIR/${MODEL_FILES[0]}"
    else
        model_path=$(find "$MODEL_DIR" -maxdepth 3 -type f -name "*.gguf" | sort | head -1)
    fi
    if [[ ! -f "$model_path" ]]; then
        log_error "Model not found: $model_path"
        log_info "Run with --download-only first"
        return 1
    fi

    # Check if llama-server exists
    local server_bin="$LLAMA_CPP_DIR/build/bin/llama-server"
    if [[ ! -x "$server_bin" ]]; then
        log_error "llama-server not found at $server_bin"
        log_info "Please build llama.cpp first"
        return 1
    fi

    # Shutdown any existing server
    if [[ -x "$HOME/llamacpp-shutdown.sh" ]]; then
        "$HOME/llamacpp-shutdown.sh" 2>/dev/null || true
    fi

    # Launch server
    log_info "Starting llama-server..."
    log_info "  Model: $MODEL_NAME"
    log_info "  Port: $SERVER_PORT"
    log_info "  Context: $CTX_SIZE"
    if [[ ${#RPC_TARGETS[@]} -gt 0 ]]; then
        log_info "  RPC targets: ${RPC_TARGETS[*]}"
    fi

    local rpc_args=()
    if [[ ${#RPC_TARGETS[@]} -gt 0 ]]; then
        for target in "${RPC_TARGETS[@]}"; do
            rpc_args+=(--rpc "$target")
        done
    fi

    local tool_calling_args=(--jinja)
    if [[ -n "$CHAT_TEMPLATE_FILE" ]]; then
        tool_calling_args+=(--chat-template-file "$CHAT_TEMPLATE_FILE")
    fi

    # Ensure the OpenAI-compatible `/v1/models` id matches what OpenCode sends.
    local alias_args=()
    if "$server_bin" --help 2>&1 | grep -q -- "--alias"; then
        alias_args+=(--alias "$OPENCODE_MODEL_ID")
    fi

    if [[ ${#LLAMA_SERVER_EXTRA_ARGS[@]} -gt 0 ]]; then
        log_info "  Extra llama-server args: ${LLAMA_SERVER_EXTRA_ARGS[*]}"
    fi

    nohup "$server_bin" \
        -m "$model_path" \
        --host 0.0.0.0 \
        --port "$SERVER_PORT" \
        --ctx-size "$CTX_SIZE" \
        --n-gpu-layers 99 \
        "${alias_args[@]}" \
        "${rpc_args[@]}" \
        "${tool_calling_args[@]}" \
        "${LLAMA_SERVER_EXTRA_ARGS[@]}" \
        > "$server_log" 2>&1 &

    local server_pid=$!
    echo "$server_pid" > /tmp/llama-server.pid

    # Wait for server to be ready
    log_info "Waiting for server to initialize..."
    local max_wait=300  # 5 minutes for large model
    local waited=0

    while ! is_server_running; do
        sleep 2
        waited=$((waited + 2))

        # Check if process died
        if ! kill -0 "$server_pid" 2>/dev/null; then
            log_error "Server process died. Check $server_log"
            tail -20 "$server_log"
            return 1
        fi

        if [[ $waited -ge $max_wait ]]; then
            log_error "Server failed to start within ${max_wait}s"
            return 1
        fi

        printf "."
    done
    echo

    log_success "Server is ready!"
    log_info "API endpoint: http://localhost:$SERVER_PORT/v1/chat/completions"
}

# Launch rpc-server for multi-node
launch_rpc_server() {
    log_info "=== Launching llama.cpp RPC Server ==="

    local rpc_bin="$LLAMA_CPP_DIR/build/bin/rpc-server"
    if [[ ! -x "$rpc_bin" ]]; then
        log_error "rpc-server not found at $rpc_bin"
        log_info "Please build llama.cpp first"
        return 1
    fi

    # Check if already running
    if pgrep -f "rpc-server" &>/dev/null; then
        log_warn "rpc-server appears to be running already"
    fi

    log_info "Starting rpc-server..."
    log_info "  Bind: $RPC_BIND"
    log_info "  Port: $RPC_PORT"

    nohup "$rpc_bin" \
        -H "$RPC_BIND" \
        -p "$RPC_PORT" \
        > /tmp/llama-rpc-server.log 2>&1 &

    local rpc_pid=$!
    echo "$rpc_pid" > /tmp/llama-rpc-server.pid

    log_success "rpc-server started (PID: $rpc_pid)"
}

# Show status
show_status() {
    echo "=== Setup Status ==="
    echo

    # Model status
    echo "Model: $OPENCODE_MODEL_DISPLAY"
    if [[ -d "$MODEL_DIR" ]]; then
        local size=$(du -sh "$MODEL_DIR" 2>/dev/null | cut -f1)
        local ok=true
        if [[ ${#MODEL_FILES[@]} -gt 0 ]]; then
            for i in "${!MODEL_FILES[@]}"; do
                local file="${MODEL_FILES[$i]}"
                local fsize="${MODEL_SIZES[$i]}"
                if ! check_file_complete "$MODEL_DIR/$file" "$fsize"; then
                    ok=false
                    break
                fi
            done
        else
            if ! find "$MODEL_DIR" -maxdepth 3 -type f -name "*.gguf" | grep -q .; then
                ok=false
            fi
        fi
        if $ok; then
            echo -e "  Status: ${GREEN}Downloaded${NC} ($size)"
        else
            echo -e "  Status: ${YELLOW}Partial${NC} ($size)"
        fi
    else
        echo -e "  Status: ${RED}Not downloaded${NC}"
    fi
    echo "  Path: $MODEL_DIR"
    echo

    # llama.cpp status
    echo "llama.cpp:"
    local server_bin="$LLAMA_CPP_DIR/build/bin/llama-server"
    if [[ -x "$server_bin" ]]; then
        echo -e "  Status: ${GREEN}Built${NC}"
        echo "  Path: $LLAMA_CPP_DIR"
    elif [[ -d "$LLAMA_CPP_DIR" ]]; then
        echo -e "  Status: ${YELLOW}Cloned, not built${NC}"
        echo "  Path: $LLAMA_CPP_DIR"
    else
        echo -e "  Status: ${RED}Not installed${NC}"
    fi
    echo

    # OpenCode status
    echo "OpenCode:"
    if command -v opencode &> /dev/null; then
        local version=$(opencode --version 2>/dev/null || echo "installed")
        echo -e "  Status: ${GREEN}Installed${NC} ($version)"
    else
        echo -e "  Status: ${RED}Not installed${NC}"
    fi
    echo

    # Config status
    echo "Configuration:"
    if [[ -f "$OPENCODE_CONFIG_DIR/opencode.json" ]]; then
        echo -e "  Status: ${GREEN}Configured${NC}"
        echo "  Path: $OPENCODE_CONFIG_DIR/opencode.json"
    else
        echo -e "  Status: ${RED}Not configured${NC}"
    fi
    echo

    # Server status
    echo "llama-server:"
    if is_server_running; then
        echo -e "  Status: ${GREEN}Running${NC}"
        echo "  Endpoint: http://localhost:$SERVER_PORT"
        # Quick health check
        local health=$(curl -s "http://localhost:$SERVER_PORT/health" | head -c 100)
        echo "  Health: $health"
    else
        echo -e "  Status: ${RED}Not running${NC}"
    fi
    echo

    # RPC server status (multi-node)
    echo "rpc-server:"
    echo "  Port: $RPC_PORT"
    if pgrep -f "rpc-server" &>/dev/null; then
        local rpids=$(pgrep -f "rpc-server" | tr '\n' ' ')
        echo -e "  Status: ${GREEN}Running${NC} (PID: $rpids)"
    else
        echo -e "  Status: ${YELLOW}Not running${NC}"
    fi
    echo
}

# Test inference
test_inference() {
    log_info "=== Testing Inference ==="

    if ! is_server_running; then
        log_error "Server is not running"
        return 1
    fi

    log_info "Sending test request..."

    local response=$(curl -s "http://localhost:$SERVER_PORT/v1/chat/completions" \
        -H 'Content-Type: application/json' \
        -d '{
            "model": "'"$OPENCODE_MODEL_ID"'",
            "messages": [{"role": "user", "content": "Write a hello world function in Python."}],
            "max_tokens": 100,
            "temperature": '"$MODEL_TEMPERATURE"'
        }')

    local content=$(echo "$response" | jq -r '.choices[0].message.content // .error.message // "No response"')

    echo
    echo "Response:"
    echo "$content"
    echo

    if [[ "$content" != "No response" ]] && [[ "$content" != *"error"* ]]; then
        log_success "Inference working!"
    else
        log_error "Inference failed"
        return 1
    fi
}

# Main
main() {
    local download_only=false
    local launch_only=false
    local show_status_only=false
    local test_only=false
    local rpc_worker_only=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --model)
                MODEL="$2"
                shift 2
                ;;
            --download-only)
                download_only=true
                shift
                ;;
            --launch-only)
                launch_only=true
                shift
                ;;
            --status)
                show_status_only=true
                shift
                ;;
            --test)
                test_only=true
                shift
                ;;
            --rpc-worker)
                rpc_worker_only=true
                shift
                ;;
            --rpc-port)
                RPC_PORT="$2"
                shift 2
                ;;
            --rpc-bind)
                RPC_BIND="$2"
                shift 2
                ;;
            --rpc)
                RPC_TARGETS+=("$2")
                shift 2
                ;;
            --rpc-hosts)
                IFS=',' read -ra _hosts <<< "$2"
                for h in "${_hosts[@]}"; do
                    h_trim=$(echo "$h" | xargs)
                    if [[ -n "$h_trim" ]]; then
                        RPC_TARGETS+=("$h_trim")
                    fi
                done
                shift 2
                ;;
            --chat-template-file)
                CHAT_TEMPLATE_FILE="$2"
                shift 2
                ;;
            --llama-arg)
                LLAMA_SERVER_EXTRA_ARGS+=("$2")
                shift 2
                ;;
            --quant)
                QUANT="$2"
                shift 2
                ;;
            --thinking)
                THINKING_MODE="$2"
                THINKING_MODE_SET=true
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo
                echo "Complete setup script for OpenCode + local GGUF models on NVIDIA GPUs"
                echo
                echo "Options:"
                echo "  --model MODEL     Model family (minimax-m2.1, minimax-m2.5, gpt-oss-120b)"
                echo "  --download-only   Only download model, build llama.cpp, and install OpenCode"
                echo "  --launch-only     Only launch the server (assumes everything is installed)"
                echo "  --status          Show current setup status"
                echo "  --test            Test inference on running server"
                echo "  --rpc-worker      Start rpc-server for multi-node (no model or OpenCode setup)"
                echo "  --rpc-port PORT   RPC server port (default: 50052)"
                echo "  --rpc-bind HOST   RPC server bind address (default: 0.0.0.0)"
                echo "  --rpc HOST:PORT   Add a llama.cpp --rpc target (repeatable)"
                echo "  --rpc-hosts CSV   Comma-separated list of rpc targets"
                echo "  --chat-template-file PATH  Pass llama-server --chat-template-file"
                echo "  --llama-arg ARG   Extra llama-server arg (repeatable)"
                echo "  --quant QUANT     Quant option (UD-Q2_K_XL, UD-Q3_K_XL, UD-Q4_K_XL, UD-Q6_K_XL|Q6_K_XL, GPT-OSS-120B)"
                echo "  --thinking MODE   Thinking preset (normal, high)"
                echo "  --help            Show this help"
                echo
                echo "Without options, performs full setup:"
                echo "  1. Download model"
                echo "  2. Build llama.cpp with CUDA support (if not already built)"
                echo "  3. Install OpenCode CLI"
                echo "  4. Generate configuration (128K context)"
                echo "  5. Launch llama-server"
                echo "  6. Test inference"
                echo
                echo "Requirements:"
                echo "  - NVIDIA GPU with CUDA support"
                echo "  - ~90GB disk space for model"
                echo "  - ~85GB GPU memory"
                echo "  - cmake, g++, git, wget"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Back-compat: QUANT used as a model selector for GPT-OSS.
    if [[ "$QUANT" == "GPT-OSS-120B" ]]; then
        MODEL="gpt-oss-120b"
    fi

    select_model_family
    select_quant

    if $show_status_only; then
        show_status
        exit 0
    fi

    if $test_only; then
        test_inference
        exit $?
    fi

    if $rpc_worker_only; then
        build_llamacpp
        launch_rpc_server
        exit $?
    fi

    echo "=============================================="
    echo "  OpenCode + $MODEL_DISPLAY_BASE Setup Script"
    echo "=============================================="
    echo

    if $launch_only; then
        generate_config
        launch_server
        echo
        show_status
        exit 0
    fi

    # Full setup
    download_model
    echo

    build_llamacpp
    echo

    install_opencode
    echo

    generate_config
    echo

    if ! $download_only; then
        launch_server
        echo

        # Quick test
        sleep 2
        test_inference
    fi

    echo
    show_status

    echo
    log_success "Setup complete!"
    echo
    echo "To use OpenCode with $MODEL_DISPLAY_BASE:"
    echo "  1. Make sure the server is running:"
    echo "     ./setup-opencode-minimax.sh --launch-only"
    echo
    echo "  2. Reload your shell to add OpenCode to PATH:"
    echo "     exec zsh    (or: exec bash)"
    echo
    echo "  3. Navigate to a project and run OpenCode:"
    echo "     cd ~/your-project"
    echo "     opencode"
    echo
    echo "Server details:"
    echo "  - Context size: 128K tokens"
    echo "  - Port: $SERVER_PORT"
    echo "  - Model: $MODEL_DISPLAY_BASE"
    echo
    echo "Check status anytime:"
    echo "  ./setup-opencode-minimax.sh --status"
}

main "$@"
