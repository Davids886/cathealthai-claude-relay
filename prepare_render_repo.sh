#!/bin/bash
# 準備最小 Git 倉庫，供 Render 連 GitHub 部署（不含 API key）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

git init -b main 2>/dev/null || git init
git add deploy/Dockerfile deploy/fly.toml deploy/render.yaml deploy/vision_proxy_server.py \
  vision_proxy_server.py render.yaml docs/HK_CLAUDE_RELAY.md deploy_render.sh prepare_render_repo.sh
git add .gitignore 2>/dev/null || true
git commit -m "CatHealthAI Claude relay (Render Oregon)" 2>/dev/null || echo "（已 commit 或無變更）"

echo ""
echo "✅ 本機 Git 已就緒。"
echo "▶ 請到 https://github.com/new 建立新 repo（例如 cathealthai-claude-relay），然後："
echo ""
echo "   git remote add origin https://github.com/<你的帳號>/cathealthai-claude-relay.git"
echo "   git push -u origin main"
echo ""
echo "▶ 再到 Render：New → Blueprint 或 Web Service → 連該 repo，Region 選 Oregon"
echo "▶ 環境變數 OPENROUTER_API_KEY 在 Render Dashboard 設定（勿提交 .bridge.env）"
echo ""
echo "完成後執行（需已 render login 且 Billing 已綁卡）："
echo "   export RENDER_REPO_URL=https://github.com/<你的帳號>/cathealthai-claude-relay.git"
echo "   ./deploy_render.sh"
