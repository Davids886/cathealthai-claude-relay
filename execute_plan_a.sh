#!/bin/bash
# 方案 A：輪換 OpenRouter Key → 同步 Render → 探測 Claude
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

ENV_FILE="$ROOT/.bridge.env"
SVC="${RENDER_SERVICE_ID:-srv-d8ahkkf7f7vs73d5p5jg}"
RELAY_HOST="https://cathealthai-vision-proxy.onrender.com"

usage() {
  echo "用法: $0 [sk-or-v1-新KEY]"
  echo "  不帶參數：使用 .bridge.env 內現有 KEY 同步 Render 並探測"
  echo "  帶新 KEY：寫入 .bridge.env、更新 Render、觸發部署、探測"
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
: "${OPENROUTER_API_KEY:?請在 .bridge.env 設定 OPENROUTER_API_KEY 或傳入新 Key}"

echo "▶ 檢查 OpenRouter 額度..."
curl -sf "https://openrouter.ai/api/v1/credits" \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" | python3 -m json.tool

echo ""
echo "▶ 本機直測 Claude（判斷是否仍 TOS）..."
curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  -H "HTTP-Referer: https://cathealthai.com" -H "X-Title: CatHealthAI_App" \
  -d '{"model":"anthropic/claude-sonnet-4.6","messages":[{"role":"user","content":"say ok"}],"max_tokens":8}' \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('error',{}).get('message') or 'Claude OK: '+str(d.get('choices',[{}])[0].get('message',{}).get('content',''))[:40])"

RENDER_KEY=$(grep 'key:' "$HOME/.render/cli.yaml" 2>/dev/null | awk '/key:/{print $2; exit}')
if [[ -z "$RENDER_KEY" ]]; then
  echo "⚠️ 未找到 Render CLI key，請手動在 Dashboard 更新 OPENROUTER_API_KEY"
else
  echo ""
  echo "▶ 更新 Render OPENROUTER_API_KEY 並重新部署..."
  curl -sf -X PUT "https://api.render.com/v1/services/${SVC}/env-vars/OPENROUTER_API_KEY" \
    -H "Authorization: Bearer $RENDER_KEY" -H "Content-Type: application/json" \
    -d "{\"value\": \"${OPENROUTER_API_KEY}\"}" >/dev/null 2>&1 || \
  curl -sf -X POST "https://api.render.com/v1/services/${SVC}/env-vars" \
    -H "Authorization: Bearer $RENDER_KEY" -H "Content-Type: application/json" \
    -d "{\"envVar\": {\"key\": \"OPENROUTER_API_KEY\", \"value\": \"${OPENROUTER_API_KEY}\"}}" >/dev/null

  curl -sf -X POST "https://api.render.com/v1/services/${SVC}/deploys" \
    -H "Authorization: Bearer $RENDER_KEY" -H "Content-Type: application/json" \
    -d '{"clearCache":"do_not_clear"}' >/dev/null
  echo "✅ Render 已更新並觸發部署"
fi

echo ""
echo "▶ 等待 Relay probe（最多 6 分鐘）..."
for i in $(seq 1 24); do
  code=$(curl -s -o /tmp/plan_a_probe.json -w "%{http_code}" "${RELAY_HOST}/v1/probe" --max-time 90 || echo 000)
  ok=$(python3 -c "import json; d=json.load(open('/tmp/plan_a_probe.json')); print(d.get('ok', False))" 2>/dev/null || echo False)
  err=$(python3 -c "import json; d=json.load(open('/tmp/plan_a_probe.json')); print((d.get('error') or {}).get('message','')[:80])" 2>/dev/null || echo "")
  echo "   ($i) HTTP $code ok=$ok ${err}"
  [[ "$ok" == "True" ]] && break
  sleep 15
done
python3 -m json.tool /tmp/plan_a_probe.json 2>/dev/null || cat /tmp/plan_a_probe.json
echo ""
echo "申訴表單: https://forms.gle/yc2vyJiALz8Uhbmh7"
echo "申訴草稿: $ROOT/docs/openrouter_appeal_draft.txt"
