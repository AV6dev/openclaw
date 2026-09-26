#!/usr/bin/env bash
# Turn a Linux PC into an Ollama worker for the research pool.
# Usage: sudo ./setup-worker-linux.sh [bind-ip]
#   bind-ip defaults to this machine's Tailscale IP. Pass a LAN IP only on a trusted network:
#   Ollama has no authentication, so anyone who can reach the port can use it.
set -euo pipefail

MODEL="${MODEL:-llama3.1:8b}"
PORT=11434

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo." >&2
  exit 1
fi

BIND_IP="${1:-}"
if [[ -z "$BIND_IP" ]]; then
  if command -v tailscale >/dev/null 2>&1; then
    BIND_IP="$(tailscale ip -4 | head -n1)"
  fi
fi
if [[ -z "$BIND_IP" ]]; then
  echo "No Tailscale IP found. Install Tailscale, or pass the LAN IP to bind to." >&2
  exit 1
fi

if ! command -v ollama >/dev/null 2>&1; then
  curl -fsSL https://ollama.com/install.sh | sh
fi

# Listen on the chosen interface instead of loopback only.
# KEEP_ALIVE keeps the model loaded between jobs; NUM_PARALLEL=1 avoids splitting RAM between jobs.
mkdir -p /etc/systemd/system/ollama.service.d
cat >/etc/systemd/system/ollama.service.d/worker.conf <<EOF
[Service]
Environment="OLLAMA_HOST=${BIND_IP}:${PORT}"
Environment="OLLAMA_KEEP_ALIVE=30m"
Environment="OLLAMA_NUM_PARALLEL=1"
EOF

systemctl daemon-reload
systemctl enable --now ollama
systemctl restart ollama

# Wait for the server, then pull the pool model.
for _ in $(seq 1 30); do
  if curl -fsS "http://${BIND_IP}:${PORT}/api/tags" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
OLLAMA_HOST="${BIND_IP}:${PORT}" ollama pull "$MODEL"

echo
echo "Worker ready: ${BIND_IP}:${PORT} (model ${MODEL})"
echo "Add this line to the upstream block in nginx-ollama-pool.conf on the gateway host:"
echo "    server ${BIND_IP}:${PORT} max_fails=1 fail_timeout=60s;"
