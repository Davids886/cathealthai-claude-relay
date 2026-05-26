#!/usr/bin/env python3
"""
CatHealthAI FGS Relay — 已遷移至 Vercel Edge（relay-vercel/）

本檔不再用於生產部署。請使用：
  cd relay-vercel && ../deploy_vercel.sh

端點（部署後）：
  POST /v1/fgs   {"image_base64": "..."}
  GET  /health
  GET  /v1/probe

環境變數（Vercel Dashboard）：OPENROUTER_API_KEY=sk-or-v1-...
"""

raise SystemExit(
    "vision_proxy_server.py 已停用。請部署 relay-vercel/：\n"
    "  ./deploy_vercel.sh\n"
)
