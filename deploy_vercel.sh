#!/bin/bash
# 部署 Vercel Edge Relay（美東 iad1）→ OpenRouter Claude
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ -f .bridge.env ]]; then
  # shellcheck disable=SC1091
  source <(grep -E '^OPENROUTER_API_KEY=' .bridge.env | sed 's/^/export /')
fi
: "${OPENROUTER_API_KEY:?請在 .bridge.env 設定 OPENROUTER_API_KEY}"

SWIFT="$ROOT/CatHealthAI/CatHealthAI/Services/OpenRouterService.swift"
RELAY_DIR="$ROOT/relay-vercel"

command -v npx >/dev/null || { echo "❌ 需要 Node.js / npx"; exit 1; }

echo "▶ Vercel 登入（若尚未登入）..."
npx vercel whoami >/dev/null 2>&1 || npx vercel login

cd "$RELAY_DIR"
if [[ ! -f .vercel/project.json ]]; then
  echo "▶ 連結 Vercel 專案（首次）..."
  npx vercel link --yes 2>/dev/null || npx vercel link
fi

echo "▶ 設定 OPENROUTER_API_KEY（production）..."
printf '%s' "$OPENROUTER_API_KEY" | npx vercel env rm OPENROUTER_API_KEY production --yes 2>/dev/null || true
printf '%s' "$OPENROUTER_API_KEY" | npx vercel env add OPENROUTER_API_KEY production

echo "▶ 部署 Edge Functions（iad1）..."
DEPLOY_OUT=$(npx vercel deploy --prod --yes 2>&1) || { echo "$DEPLOY_OUT"; exit 1; }
echo "$DEPLOY_OUT"

VC_URL=$(echo "$DEPLOY_OUT" | grep -Eo 'https://[a-z0-9.-]+\.vercel\.app' | tail -1)
[[ -n "$VC_URL" ]] || { echo "❌ 無法解析部署 URL"; exit 1; }

RELAY_URL="${VC_URL}/v1/fgs"
echo "✅ Relay: $RELAY_URL"

if [[ -f "$SWIFT" ]]; then
  perl -i -pe "s|private let claudeRelayBaseURL = \".*\"|private let claudeRelayBaseURL = \"$RELAY_URL\"|" "$SWIFT"
  echo "✅ 已更新 OpenRouterService.swift"
fi

echo "▶ 探測 /health ..."
curl -sf "${VC_URL}/health" | python3 -m json.tool

echo "▶ 探測 /v1/probe（可能需 30–90s）..."
code=$(curl -s -o /tmp/vercel_probe.json -w "%{http_code}" "${VC_URL}/v1/probe" --max-time 120)
python3 -m json.tool /tmp/vercel_probe.json 2>/dev/null || cat /tmp/vercel_probe.json
echo "HTTP $code"

echo ""
echo "完成。Xcode ⌘R 測試 App。"
