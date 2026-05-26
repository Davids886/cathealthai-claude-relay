#!/bin/bash
# 一鍵部署 Claude Relay（美國出口），並寫入 OpenRouterService.swift
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ -f .bridge.env ]]; then
  # shellcheck disable=SC1091
  source <(grep -E '^OPENROUTER_API_KEY=' .bridge.env | sed 's/^/export /')
fi
: "${OPENROUTER_API_KEY:?請在 .bridge.env 設定 OPENROUTER_API_KEY}"

SWIFT_FILE="$ROOT/CatHealthAI/CatHealthAI/Services/OpenRouterService.swift"
RELAY_URL=""

test_relay() {
  local url="$1"
  local code
  code=$(curl -s -o /tmp/relay_test.json -w "%{http_code}" -X POST "$url" \
    -H "Content-Type: application/json" \
    -d "{\"image_base64\":\"$(cat /tmp/cat_test.b64 2>/dev/null || echo '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAABAAEDAREAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAb/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCdABmX/9k=')\"}" \
    --max-time 120)
  if [[ "$code" == "200" ]]; then
    python3 -c "import json;d=json.load(open('/tmp/relay_test.json')); assert 'totalScore' in d or 'earScore' in d; print('OK', d.get('modelId',''))" 2>/dev/null && return 0
  fi
  python3 -c "import json;d=json.load(open('/tmp/relay_test.json')); print('FAIL', $code, str(d)[:200])" 2>/dev/null || echo "FAIL $code"
  return 1
}

patch_swift_url() {
  local url="$1"
  perl -i -pe "s|private let claudeRelayBaseURL: String\\? = .*|private let claudeRelayBaseURL: String? = \"$url\"|" "$SWIFT_FILE"
  echo "✅ 已更新 claudeRelayBaseURL → $url"
}

echo "▶ [1/3] Cloudflare Worker（hostname placement）"
if command -v npx >/dev/null; then
  (cd cf-claude-relay && npx wrangler deploy) || true
  CF_URL="https://cathealthai-claude-relay.cathealthai.workers.dev/v1/fgs"
  if test_relay "$CF_URL"; then
    RELAY_URL="$CF_URL"
  else
    echo "   Worker 仍被地區限制（colo 可能仍為 HKG）"
  fi
fi

if [[ -z "$RELAY_URL" ]]; then
  echo "▶ [2/3] Vercel 美東 (iad1)"
  if command -v npx >/dev/null; then
    cd relay-vercel
    printf '%s' "$OPENROUTER_API_KEY" | npx vercel env add OPENROUTER_API_KEY production --yes 2>/dev/null || true
    DEPLOY_OUT=$(npx vercel deploy --prod --yes 2>&1) || true
    echo "$DEPLOY_OUT"
    VC_URL=$(echo "$DEPLOY_OUT" | grep -Eo 'https://[a-z0-9.-]+\.vercel\.app' | tail -1)
    cd "$ROOT"
    if [[ -n "${VC_URL:-}" ]]; then
      V_URL="${VC_URL}/api/fgs"
      if test_relay "$V_URL"; then
        RELAY_URL="$V_URL"
      fi
    fi
  fi
fi

if [[ -z "$RELAY_URL" ]]; then
  echo "▶ [3/3] Fly.io Oregon"
  if command -v flyctl >/dev/null; then
    cp vision_proxy_server.py deploy/vision_proxy_server.py
    flyctl secrets set "OPENROUTER_API_KEY=$OPENROUTER_API_KEY" --app cathealthai-claude-relay 2>/dev/null || true
    if flyctl deploy --remote-only --app cathealthai-claude-relay 2>&1; then
      F_URL="https://cathealthai-claude-relay.fly.dev/v1/fgs"
      if test_relay "$F_URL"; then
        RELAY_URL="$F_URL"
      fi
    else
      echo "   Fly 部署失敗（常見：免費方案機器數上限）"
    fi
  fi
fi

if [[ -n "$RELAY_URL" ]]; then
  patch_swift_url "$RELAY_URL"
  xcodebuild -project CatHealthAI/CatHealthAI.xcodeproj -scheme CatHealthAI -destination 'generic/platform=iOS' build 2>&1 | tail -3
  echo ""
  echo "✅ Relay 可用: $RELAY_URL"
  echo "▶ 請在 Xcode 按 ⌘R 在真機測試 FGS 分析"
else
  echo ""
  echo "❌ 自動部署的 Relay 仍無法通過 Claude 地區檢查。"
  echo "   Cloudflare Worker 出口仍在香港（/v1/debug 可見 colo: HKG）。"
  echo "   請手動：Render Dashboard → New Web Service → Docker → region: Oregon"
  echo "   環境變數 OPENROUTER_API_KEY，URL 填入 OpenRouterService.swift"
  exit 1
fi
