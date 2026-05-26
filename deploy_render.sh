#!/bin/bash
# Render Oregon 部署 Claude Relay（需先 render login）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ -f .bridge.env ]]; then
  # shellcheck disable=SC1091
  source <(grep -E '^OPENROUTER_API_KEY=' .bridge.env | sed 's/^/export /')
fi
: "${OPENROUTER_API_KEY:?請在 .bridge.env 設定 OPENROUTER_API_KEY}"

command -v render >/dev/null || brew install render
command -v docker >/dev/null || { echo "請安裝 Docker Desktop"; exit 1; }

render whoami >/dev/null 2>&1 || {
  echo "▶ 請在瀏覽器完成 Render 登入："
  render login --confirm
}

# 從 ~/.render/cli.yaml 還原 workspace（render login 後通常已寫入）
if [[ -z "${RENDER_WORKSPACE_ID:-}" ]] && [[ -f "$HOME/.render/cli.yaml" ]]; then
  RENDER_WORKSPACE_ID=$(grep '^workspace:' "$HOME/.render/cli.yaml" | awk '{print $2}')
fi
if [[ -n "${RENDER_WORKSPACE_ID:-}" ]]; then
  render workspace set "$RENDER_WORKSPACE_ID" --confirm >/dev/null 2>&1 || true
fi
if ! render services --confirm --output json >/dev/null 2>&1; then
  echo "❌ 無法連線 Render 或尚未選 workspace。請執行："
  echo "   render login"
  echo "   render workspaces --output json"
  echo "   render workspace set <你的_workspace_id> --confirm"
  exit 1
fi

SERVICE_NAME="${RENDER_SERVICE_NAME:-cathealthai-vision-proxy}"
SWIFT_FILE="$ROOT/CatHealthAI/CatHealthAI/Services/OpenRouterService.swift"

echo "▶ 建置 Docker 映像..."
docker build -f deploy/Dockerfile -t cathealthai-claude-relay:latest .

# 若已設定 DOCKERHUB_USER，推送到 Docker Hub 並用 image 部署
if [[ -n "${DOCKERHUB_USER:-}" ]]; then
  IMAGE="docker.io/${DOCKERHUB_USER}/cathealthai-claude-relay:latest"
  docker tag cathealthai-claude-relay:latest "$IMAGE"
  docker push "$IMAGE"
  echo "▶ 建立 Render Web Service（Docker 映像）..."
  render services create \
    --name "$SERVICE_NAME" \
    --type web_service \
    --image "$IMAGE" \
    --region oregon \
    --plan free \
    --health-check-path /health \
    --env-var "OPENROUTER_API_KEY=$OPENROUTER_API_KEY" \
  --confirm --output json
else
  echo "▶ 未設定 DOCKERHUB_USER，改用 Git repo 部署（需 RENDER_REPO_URL）"
  : "${RENDER_REPO_URL:?請 export RENDER_REPO_URL=https://github.com/你的帳號/CatHealthAI_v2_Final.git}"
  render services create \
    --name "$SERVICE_NAME" \
    --type web_service \
    --runtime docker \
    --repo "$RENDER_REPO_URL" \
    --region oregon \
    --plan free \
    --health-check-path /health \
    --env-var "OPENROUTER_API_KEY=$OPENROUTER_API_KEY" \
  --confirm --output json
fi

HOST="https://${SERVICE_NAME}.onrender.com"
RELAY_URL="${HOST}/v1/fgs"
echo "▶ 等待服務啟動（免費方案約 1–3 分鐘）..."
for i in $(seq 1 36); do
  code=$(curl -s -o /tmp/render_health.json -w "%{http_code}" "${HOST}/health" --max-time 15 || true)
  if [[ "$code" == "200" ]]; then
    echo "   health OK"
    break
  fi
  echo "   等待... ($i) status=$code"
  sleep 10
done

B64=$(python3 - <<'PY' 2>/dev/null || true
import base64, pathlib
p=pathlib.Path('/tmp/cat_test.b64')
print(p.read_text() if p.exists() else '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAABAAEDAREAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAb/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCdABmX/9k=')
PY
)
code=$(curl -s -o /tmp/render_fgs.json -w "%{http_code}" -X POST "$RELAY_URL" \
  -H "Content-Type: application/json" \
  -d "{\"image_base64\":\"$B64\"}" --max-time 120)
if [[ "$code" != "200" ]]; then
  echo "❌ Relay 測試失敗 HTTP $code"
  cat /tmp/render_fgs.json
  exit 1
fi

perl -i -pe "s|private let claudeRelayBaseURL: String\\? = .*|private let claudeRelayBaseURL: String? = \"$RELAY_URL\"|" "$SWIFT_FILE"
echo "✅ Relay 可用: $RELAY_URL"
echo "✅ 已更新 OpenRouterService.swift"
