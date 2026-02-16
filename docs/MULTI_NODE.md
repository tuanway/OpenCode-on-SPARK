# Multi-Node DGX Spark (llama.cpp RPC)

This repo supports llama.cpp RPC to extend effective GPU memory across multiple DGX Spark nodes. This is **memory expansion**, not tensor parallel or model sharding.

## Quick Start

### 1) Start rpc-server on each worker node
```bash
./setup-opencode-minimax.sh --rpc-worker
```

Defaults:
- Bind: `0.0.0.0`
- Port: `50052`

Override with:
```bash
./setup-opencode-minimax.sh --rpc-worker --rpc-bind 0.0.0.0 --rpc-port 50052
```

### 2) Start llama-server on the primary node with RPC targets
```bash
./setup-opencode-minimax.sh --launch-only --rpc 10.0.0.2:50052 --rpc 10.0.0.3:50052
```

Or use a comma-separated list:
```bash
./setup-opencode-minimax.sh --launch-only --rpc-hosts 10.0.0.2:50052,10.0.0.3:50052
```

## Notes

- The primary node still needs the model files and `llama-server`. Run full setup there first.
- Ensure all nodes can reach each other on the RPC port (default `50052`).
- `rpc-server` is included when `llama.cpp` is built with `-DGGML_RPC=ON` (already enabled by this repo).
- If you change the RPC port, pass the same port on workers and in the `--rpc` targets.

## Troubleshooting

If the server does not start:
```bash
tail -100 /tmp/llama-server-minimax-m2.1.log   # or: /tmp/llama-server-minimax-m2.5.log
```

If a worker RPC server fails:
```bash
tail -100 /tmp/llama-rpc-server.log
```
