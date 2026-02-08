#!/bin/bash
#
# status.sh - Check status of MiniMax-M2.1 setup and server
#

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
MODEL_DIR_BASE="$HOME/models/minimax-m2.1"
MODEL_VARIANTS=("UD-Q2_K_XL" "UD-Q3_K_XL" "UD-Q4_K_XL")
MODEL_FILES_UD=(
    "MiniMax-M2.1-UD-Q2_K_XL-00001-of-00002.gguf"
    "MiniMax-M2.1-UD-Q2_K_XL-00002-of-00002.gguf"
)
MODEL_SIZES_UD=(
    49950511392
    35967481120
)
MODEL_FILES_UD_Q4_XL=(
    "MiniMax-M2.1-UD-Q4_K_XL-00001-of-00003.gguf"
    "MiniMax-M2.1-UD-Q4_K_XL-00002-of-00003.gguf"
    "MiniMax-M2.1-UD-Q4_K_XL-00003-of-00003.gguf"
)
MODEL_SIZES_UD_Q4_XL=(0 0 0)
MODEL_FILES_UD_Q3_XL=()
MODEL_SIZES_UD_Q3_XL=()
SERVER_PORT=8080
RPC_PORT=50052
OPENCODE_CONFIG="$HOME/.config/opencode/opencode.json"

# Check if file is complete
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

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           OpenCode + MiniMax-M2.1 Status                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo

# Model Status
echo -e "${CYAN}▸ Models: MiniMax-M2.1${NC}"
found_any=false

for v in "${MODEL_VARIANTS[@]}"; do
    model_dir="$MODEL_DIR_BASE/$v"
    if [[ "$v" == "UD-Q2_K_XL" ]]; then
        files=("${MODEL_FILES_UD[@]}")
        sizes=("${MODEL_SIZES_UD[@]}")
    elif [[ "$v" == "UD-Q3_K_XL" ]]; then
        files=("${MODEL_FILES_UD_Q3_XL[@]}")
        sizes=("${MODEL_SIZES_UD_Q3_XL[@]}")
    else
        files=("${MODEL_FILES_UD_Q4_XL[@]}")
        sizes=("${MODEL_SIZES_UD_Q4_XL[@]}")
    fi

    if [[ -d "$model_dir" ]]; then
        found_any=true
        size=$(du -sh "$model_dir" 2>/dev/null | cut -f1)
        ok=true
        if [[ ${#files[@]} -gt 0 ]]; then
            for i in "${!files[@]}"; do
                if ! check_file_complete "$model_dir/${files[$i]}" "${sizes[$i]}"; then
                    ok=false
                    break
                fi
            done
        else
            if ! find "$model_dir" -maxdepth 3 -type f -name "*.gguf" | grep -q .; then
                ok=false
            fi
        fi

        echo "  Variant: $v"
        echo "  Path: $model_dir"
        if $ok; then
            echo -e "  Status: ${GREEN}✓ Downloaded${NC} ($size)"
        else
            echo -e "  Status: ${YELLOW}⋯ Partial${NC} ($size)"
        fi
        echo
    fi
done

if ! $found_any; then
    echo -e "  Status: ${RED}✗ Not downloaded${NC}"
    echo "  Path: $MODEL_DIR_BASE"
    echo
fi

# OpenCode Status
echo -e "${CYAN}▸ OpenCode CLI${NC}"
if command -v opencode &> /dev/null; then
    version=$(opencode --version 2>/dev/null || echo "unknown")
    echo -e "  Status: ${GREEN}✓ Installed${NC} (v$version)"

    # Check if in PATH
    which_path=$(which opencode 2>/dev/null)
    echo "  Path: $which_path"
else
    echo -e "  Status: ${RED}✗ Not installed${NC}"
    echo "  Install: curl -fsSL https://opencode.sh/install.sh | sh"
fi
echo

# Configuration Status
echo -e "${CYAN}▸ Configuration${NC}"
if [[ -f "$OPENCODE_CONFIG" ]]; then
    echo -e "  Status: ${GREEN}✓ Configured${NC}"
    echo "  Path: $OPENCODE_CONFIG"

    # Show configured model
    model=$(grep -o '"model"[[:space:]]*:[[:space:]]*"[^"]*"' "$OPENCODE_CONFIG" 2>/dev/null | tail -1 | cut -d'"' -f4)
    if [[ -n "$model" ]]; then
        echo "  Default Model: $model"
    fi
else
    echo -e "  Status: ${RED}✗ Not configured${NC}"
    echo "  Run: ./setup-opencode-minimax.sh"
fi
echo

# Server Status
echo -e "${CYAN}▸ llama-server${NC}"
echo "  Port: $SERVER_PORT"

# Check if process is running
PIDS=$(pgrep -f "llama-server" 2>/dev/null || true)
if [[ -n "$PIDS" ]]; then
    echo -e "  Process: ${GREEN}✓ Running${NC} (PID: $PIDS)"
else
    echo -e "  Process: ${RED}✗ Not running${NC}"
fi

# Check if server responds
if curl -s "http://localhost:$SERVER_PORT/health" &>/dev/null; then
    health=$(curl -s "http://localhost:$SERVER_PORT/health")
    echo -e "  Health: ${GREEN}✓ Responding${NC}"

    # Get model info
    model_id=$(curl -s "http://localhost:$SERVER_PORT/v1/models" 2>/dev/null | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
    if [[ -n "$model_id" ]]; then
        echo "  Loaded Model: $model_id"
    fi

    echo "  Endpoint: http://localhost:$SERVER_PORT/v1/chat/completions"
else
    echo -e "  Health: ${RED}✗ Not responding${NC}"
fi
echo

# RPC Server Status (multi-node)
echo -e "${CYAN}▸ rpc-server${NC}"
echo "  Port: $RPC_PORT"

RPC_PIDS=$(pgrep -f "rpc-server" 2>/dev/null || true)
if [[ -n "$RPC_PIDS" ]]; then
    echo -e "  Process: ${GREEN}✓ Running${NC} (PID: $RPC_PIDS)"
else
    echo -e "  Process: ${YELLOW}⋯ Not running${NC}"
fi
echo

# GPU Status
echo -e "${CYAN}▸ GPU${NC}"
if command -v nvidia-smi &> /dev/null; then
    gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    gpu_mem=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)

    if [[ -n "$gpu_name" ]]; then
        echo "  Device: $gpu_name"
        if [[ -n "$gpu_mem" ]]; then
            used=$(echo "$gpu_mem" | cut -d',' -f1 | tr -d ' ')
            total=$(echo "$gpu_mem" | cut -d',' -f2 | tr -d ' ')
            # Handle N/A or non-numeric values
            if [[ "$used" =~ ^[0-9]+$ ]] && [[ "$total" =~ ^[0-9]+$ ]] && [[ "$total" -gt 0 ]]; then
                pct=$((used * 100 / total))
                echo "  Memory: ${used}MiB / ${total}MiB (${pct}%)"
            else
                echo "  Memory: Unified memory (shared with system)"
            fi
        fi
    fi
else
    echo -e "  Status: ${YELLOW}nvidia-smi not available${NC}"
fi
echo

# Quick Actions
echo -e "${CYAN}▸ Quick Actions${NC}"
if curl -s "http://localhost:$SERVER_PORT/health" &>/dev/null; then
    echo "  • Stop server:  ./shutdown.sh"
    echo "  • Use OpenCode: opencode"
    echo "  • Test API:     curl http://localhost:$SERVER_PORT/v1/chat/completions \\"
    echo "                    -H 'Content-Type: application/json' \\"
    echo "                    -d '{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"Hi\"}]}'"
else
    echo "  • Start server: ./setup-opencode-minimax.sh --launch-only"
    echo "  • Full setup:   ./setup-opencode-minimax.sh"
fi
echo
