#!/bin/bash
# 方案 A：輪換 OpenRouter Key → 部署 Vercel Edge → 探測 Claude
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

ENV_FILE="$ROOT/.bridge.env"

usage() {
  echo "用法: $0 [sk-or-v1-新KEY]"
  echo "  不帶參數：用 .bridge.env 的 KEY 執行 deploy_vercel.sh"
  echo "  帶新 KEY：寫入 .bridge.env 後部署"
  exit 1
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

if [[ -n "${1:-}" ]]; then
  NEW_KEY="$1"
  [[ "$NEW_KEY" == sk-or-* ]] || { echo "❌ Key 須以 sk-or- 開頭"; exit 1; }
  if grep -q '^OPENROUTER_API_KEY=' "$ENV_FILE" 2>/dev/null; then
    sed -i '' "s|^OPENROUTER_API_KEY=.*|OPENROUTER_API_KEY=$NEW_KEY|" "$ENV_FILE"
  else
    echo "OPENROUTER_API_KEY=$NEW_KEY" >> "$ENV_FILE"
  fi
  echo "✅ 已寫入 $ENV_FILE"
fi

# shellcheck disable=SC1091
source <(grep -E '^OPENROUTER_API_KEY=' "$ENV_FILE" | sed 's/^/export /')
: "${OPENROUTER_API_KEY:?請設定 OPENROUTER_API_KEY}"

echo "▶ 檢查 OpenRouter 額度..."
curl -s "https://openrouter.ai/api/v1/credits" \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" | python3 -m json.tool || echo "（credits API 無回應，繼續）"

echo ""
echo "▶ 本機直測 Claude..."
curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  -H "HTTP-Referer: https://cathealthai.com" -H "X-Title: CatHealthAI_App" \
  -d '{"model":"anthropic/claude-sonnet-4.6","messages":[{"role":"user","content":"say ok"}],"max_tokens":8}' \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('error',{}).get('message') or 'Claude OK')"

echo ""
exec "$ROOT/deploy_vercel.sh"
