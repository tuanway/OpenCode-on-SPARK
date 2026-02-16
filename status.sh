#!/bin/bash
#
# status.sh - Check status of local model setup and llama.cpp server
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Defaults
MODEL="minimax-m2.1" # minimax-m2.1 | minimax-m2.5 | gpt-oss-120b
SERVER_PORT=8080
RPC_PORT=50052
OPENCODE_CONFIG="$HOME/.config/opencode/opencode.json"

MODEL_DISPLAY_BASE="MiniMax-M2.1"
MODEL_DIR_BASE="$HOME/models/minimax-m2.1"
MODEL_VARIANTS=("UD-Q2_K_XL" "UD-Q3_K_XL" "UD-Q4_K_XL")
MODEL_FILE_PREFIX="MiniMax-M2.1"

# MiniMax-M2.1 known file lists (sizes only enforced for UD-Q2_K_XL)
MODEL_FILES_M21_UD_Q2=(
    "MiniMax-M2.1-UD-Q2_K_XL-00001-of-00002.gguf"
    "MiniMax-M2.1-UD-Q2_K_XL-00002-of-00002.gguf"
)
MODEL_SIZES_M21_UD_Q2=(
    49950511392
    35967481120
)
MODEL_FILES_M21_UD_Q3=(
    "MiniMax-M2.1-UD-Q3_K_XL-00001-of-00003.gguf"
    "MiniMax-M2.1-UD-Q3_K_XL-00002-of-00003.gguf"
    "MiniMax-M2.1-UD-Q3_K_XL-00003-of-00003.gguf"
)
MODEL_FILES_M21_UD_Q4=(
    "MiniMax-M2.1-UD-Q4_K_XL-00001-of-00003.gguf"
    "MiniMax-M2.1-UD-Q4_K_XL-00002-of-00003.gguf"
    "MiniMax-M2.1-UD-Q4_K_XL-00003-of-00003.gguf"
)

print_help() {
    echo "Usage: $0 [--model minimax-m2.1|minimax-m2.5|gpt-oss-120b]"
}

select_model() {
    case "$MODEL" in
        minimax-m2.1)
            MODEL_DISPLAY_BASE="MiniMax-M2.1"
            MODEL_DIR_BASE="$HOME/models/minimax-m2.1"
            MODEL_FILE_PREFIX="MiniMax-M2.1"
            ;;
        minimax-m2.5)
            MODEL_DISPLAY_BASE="MiniMax-M2.5"
            MODEL_DIR_BASE="$HOME/models/minimax-m2.5"
            MODEL_FILE_PREFIX="MiniMax-M2.5"
            ;;
        gpt-oss-120b)
            MODEL_DISPLAY_BASE="gpt-oss-120b"
            MODEL_DIR_BASE="$HOME/models/gpt-oss"
            MODEL_FILE_PREFIX="gpt-oss-120b"
            MODEL_VARIANTS=("UD-Q4_K_XL")
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} Unknown model: $MODEL"
            print_help
            exit 1
            ;;
    esac
}

check_file_complete() {
    local file="$1"
    local expected_size="$2"
    if [[ -f "$file" ]]; then
        if [[ "${expected_size:-0}" -le 0 ]]; then
            return 0
        fi
        local actual_size
        actual_size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
        if [[ "$actual_size" -ge "$expected_size" ]]; then
            return 0
        fi
    fi
    return 1
}

variant_expected_files() {
    local variant="$1"

    case "$MODEL" in
        minimax-m2.1)
            case "$variant" in
                UD-Q2_K_XL) printf "%s\n" "${MODEL_FILES_M21_UD_Q2[@]}"; return 0 ;;
                UD-Q3_K_XL) printf "%s\n" "${MODEL_FILES_M21_UD_Q3[@]}"; return 0 ;;
                UD-Q4_K_XL) printf "%s\n" "${MODEL_FILES_M21_UD_Q4[@]}"; return 0 ;;
            esac
            ;;
        minimax-m2.5)
            # Best-effort: assumes same naming convention as MiniMax-M2.1.
            if [[ "$variant" == "UD-Q2_K_XL" ]]; then
                printf "%s-%s-00001-of-00002.gguf\n" "$MODEL_FILE_PREFIX" "$variant"
                printf "%s-%s-00002-of-00002.gguf\n" "$MODEL_FILE_PREFIX" "$variant"
                return 0
            fi
            if [[ "$variant" == "UD-Q3_K_XL" || "$variant" == "UD-Q4_K_XL" ]]; then
                printf "%s-%s-00001-of-00003.gguf\n" "$MODEL_FILE_PREFIX" "$variant"
                printf "%s-%s-00002-of-00003.gguf\n" "$MODEL_FILE_PREFIX" "$variant"
                printf "%s-%s-00003-of-00003.gguf\n" "$MODEL_FILE_PREFIX" "$variant"
                return 0
            fi
            ;;
        gpt-oss-120b)
            printf "%s\n" \
                "gpt-oss-120b-UD-Q4_K_XL-00001-of-00002.gguf" \
                "gpt-oss-120b-UD-Q4_K_XL-00002-of-00002.gguf"
            return 0
            ;;
    esac

    return 1
}

variant_status() {
    local model_dir="$1"
    local variant="$2"

    local any_gguf
    any_gguf=$(find "$model_dir" -maxdepth 1 -type f -name "*.gguf" 2>/dev/null | head -1 || true)

    local expected
    expected=$(variant_expected_files "$variant" 2>/dev/null || true)
    if [[ -n "$expected" ]]; then
        local ok=true
        local any=false
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            if [[ -f "$model_dir/$f" ]]; then
                any=true
            fi
        done <<< "$expected"

        if $any; then
            while IFS= read -r f; do
                [[ -z "$f" ]] && continue
                local size=0
                if [[ "$MODEL" == "minimax-m2.1" && "$variant" == "UD-Q2_K_XL" ]]; then
                    if [[ "$f" == "${MODEL_FILES_M21_UD_Q2[0]}" ]]; then size="${MODEL_SIZES_M21_UD_Q2[0]}"; fi
                    if [[ "$f" == "${MODEL_FILES_M21_UD_Q2[1]}" ]]; then size="${MODEL_SIZES_M21_UD_Q2[1]}"; fi
                fi
                if ! check_file_complete "$model_dir/$f" "$size"; then
                    ok=false
                    break
                fi
            done <<< "$expected"

            if $ok; then
                echo "downloaded"
                return 0
            fi
            echo "partial"
            return 0
        fi
    fi

    if [[ -n "$any_gguf" ]]; then
        echo "downloaded"
        return 0
    fi

    echo "missing"
}

# Args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --model)
            MODEL="$2"
            shift 2
            ;;
        --help|-h)
            print_help
            exit 0
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} Unknown option: $1"
            print_help
            exit 1
            ;;
    esac
done

select_model

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                 OpenCode + Local Models Status               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo

# Model Status
echo -e "${CYAN}▸ Models: ${MODEL_DISPLAY_BASE}${NC}"
found_any=false

for v in "${MODEL_VARIANTS[@]}"; do
    model_dir="$MODEL_DIR_BASE/$v"
    if [[ -d "$model_dir" ]]; then
        found_any=true
        size=$(du -sh "$model_dir" 2>/dev/null | cut -f1)
        st=$(variant_status "$model_dir" "$v")

        echo "  Variant: $v"
        echo "  Path: $model_dir"
        if [[ "$st" == "downloaded" ]]; then
            echo -e "  Status: ${GREEN}✓ Downloaded${NC} ($size)"
        elif [[ "$st" == "partial" ]]; then
            echo -e "  Status: ${YELLOW}⋯ Partial${NC} ($size)"
        else
            echo -e "  Status: ${RED}✗ Missing files${NC} ($size)"
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

PIDS=$(pgrep -f "llama-server" 2>/dev/null || true)
if [[ -n "$PIDS" ]]; then
    echo -e "  Process: ${GREEN}✓ Running${NC} (PID: $PIDS)"
else
    echo -e "  Process: ${RED}✗ Not running${NC}"
fi

if curl -s "http://localhost:$SERVER_PORT/health" &>/dev/null; then
    echo -e "  Health: ${GREEN}✓ Responding${NC}"
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

