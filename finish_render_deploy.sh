#!/bin/bash
# 綁定 Render 信用卡後：推 GitHub + 建立 Oregon Relay + 更新 Swift
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ -f .bridge.env ]]; then
  # shellcheck disable=SC1091
  source <(grep -E '^OPENROUTER_API_KEY=' .bridge.env | sed 's/^/export /')
fi
: "${OPENROUTER_API_KEY:?請在 .bridge.env 設定 OPENROUTER_API_KEY}"

command -v render >/dev/null || brew install render
command -v gh >/dev/null || brew install gh
render whoami >/dev/null 2>&1 || render login --confirm

WS=$(grep '^workspace:' "$HOME/.render/cli.yaml" | awk '{print $2}')
[[ -n "$WS" ]] && render workspace set "$WS" --confirm >/dev/null

if ! gh auth status >/dev/null 2>&1; then
  echo "▶ 請在瀏覽器完成 GitHub 授權（裝置碼會顯示在下方）："
  gh auth login -h github.com -p https -w
fi

REPO_NAME="${GITHUB_REPO_NAME:-cathealthai-claude-relay}"
GH_USER=$(gh api user -q .login)
REPO_URL="https://github.com/${GH_USER}/${REPO_NAME}"

if ! gh repo view "$GH_USER/$REPO_NAME" >/dev/null 2>&1; then
  gh repo create "$REPO_NAME" --public --source=. --remote=origin --push
else
  git remote set-url origin "$REPO_URL.git" 2>/dev/null || git remote add origin "$REPO_URL.git"
  git push -u origin main
fi

KEY=$(grep 'key:' "$HOME/.render/cli.yaml" | awk '/key:/{print $2; exit}')
EXIST=$(curl -s "https://api.render.com/v1/services?name=cathealthai-vision-proxy" -H "Authorization: Bearer $KEY" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for x in d:
  s=x.get('service',x)
  if s.get('name')=='cathealthai-vision-proxy':
    print(s['id']); break
" 2>/dev/null || true)

if [[ -z "$EXIST" ]]; then
  echo "▶ 建立 Render Web Service（Oregon）..."
  curl -sf -X POST "https://api.render.com/v1/services" \
    -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
    -d "{
      \"type\": \"web_service\",
      \"name\": \"cathealthai-vision-proxy\",
      \"ownerId\": \"$WS\",
      \"repo\": \"$REPO_URL\",
      \"branch\": \"main\",
      \"serviceDetails\": {
        \"env\": \"docker\",
        \"region\": \"oregon\",
        \"plan\": \"free\",
        \"healthCheckPath\": \"/health\",
        \"envSpecificDetails\": {
          \"dockerfilePath\": \"./deploy/Dockerfile\",
          \"dockerContext\": \".\"
        }
      },
      \"envVars\": [{\"key\": \"OPENROUTER_API_KEY\", \"value\": \"$OPENROUTER_API_KEY\"}]
    }" >/dev/null
else
  echo "▶ 服務已存在，觸發重新部署..."
  curl -sf -X POST "https://api.render.com/v1/services/${EXIST}/deploys" \
    -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
    -d '{"clearCache":"do_not_clear"}' >/dev/null || true
fi

HOST="https://cathealthai-vision-proxy.onrender.com"
RELAY_URL="${HOST}/v1/fgs"
echo "▶ 等待 ${HOST} 就緒（免費方案首次約 2–5 分鐘）..."
for i in $(seq 1 40); do
  code=$(curl -s -o /dev/null -w "%{http_code}" "${HOST}/health" --max-time 20 || echo 000)
  [[ "$code" == "200" ]] && break
  echo "   ($i/40) health=$code"
  sleep 15
done

B64=$(python3 -c "import pathlib; p=pathlib.Path('/tmp/cat_test.b64'); print(p.read_text() if p.exists() else '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAABAAEDAREAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAb/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCdABmX/9k=')" )
code=$(curl -s -o /tmp/render_fgs.json -w "%{http_code}" -X POST "$RELAY_URL" \
  -H "Content-Type: application/json" -d "{\"image_base64\":\"$B64\"}" --max-time 120)
if [[ "$code" != "200" ]]; then
  echo "❌ Relay 測試 HTTP $code（部署可能仍在進行，稍後再試）"
  cat /tmp/render_fgs.json 2>/dev/null | head -c 300
  exit 1
fi

SWIFT="$ROOT/CatHealthAI/CatHealthAI/Services/OpenRouterService.swift"
perl -i -pe "s|private let claudeRelayBaseURL: String\\? = .*|private let claudeRelayBaseURL: String? = \"$RELAY_URL\"|" "$SWIFT"
echo "✅ Relay: $RELAY_URL"
echo "✅ 已更新 OpenRouterService.swift — 請 Xcode ⌘R"
