#!/usr/bin/env bash
# Show which Ollama workers are up and have the pool model. Run on the gateway host.
# Usage: ./check-pool.sh [nginx conf path]
set -uo pipefail

CONF="${1:-/etc/nginx/conf.d/ollama-pool.conf}"
MODEL="${MODEL:-llama3.1:8b}"

# Active (uncommented) server lines inside the upstream block.
mapfile -t HOSTS < <(sed -n '/upstream ollama_pool/,/}/p' "$CONF" | grep -E '^\s*server ' | awk '{print $2}' | tr -d ';')

for host in "${HOSTS[@]}"; do
  if tags="$(curl -fsS -m 3 "http://${host}/api/tags" 2>/dev/null)"; then
    if grep -q "\"${MODEL}\"" <<<"$tags"; then
      echo "UP        ${host}"
    else
      echo "NO MODEL  ${host}  (run: OLLAMA_HOST=${host} ollama pull ${MODEL})"
    fi
  else
    echo "DOWN      ${host}"
  fi
done

if curl -fsS -m 3 http://127.0.0.1:11500/api/tags >/dev/null 2>&1; then
  echo "POOL      127.0.0.1:11500 answering"
else
  echo "POOL      127.0.0.1:11500 not answering (is nginx running?)"
fi
