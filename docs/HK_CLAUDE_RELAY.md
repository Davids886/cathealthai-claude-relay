# CatHealthAI — Vercel Edge Relay（免 VPN）

## 架構

```
iPhone App  →  https://<project>.vercel.app/v1/fgs
            →  Vercel Edge（iad1 美東）
            →  OpenRouter → anthropic/claude-sonnet-4.6
```

- **不再使用 Render**（`onrender.com` 已棄用）。
- App **不**內嵌 `sk-or-`；Key 只在 Vercel 環境變數 `OPENROUTER_API_KEY`。

## 部署

```bash
cd ~/CatHealthAI_v2_Final
# .bridge.env 內 OPENROUTER_API_KEY=sk-or-v1-...
./deploy_vercel.sh
```

首次會 `vercel login` / `vercel link`。完成後會更新 `OpenRouterService.swift` 的 Relay URL。

## 端點

| 路徑 | 說明 |
|------|------|
| `POST /v1/fgs` | body: `{"image_base64":"..."}` |
| `GET /health` | 健康檢查 |
| `GET /v1/probe` | 小圖測 Claude |

## 程式位置

| 路徑 | 說明 |
|------|------|
| `relay-vercel/api/*.js` | Vercel Edge Functions |
| `relay-vercel/lib/relay-core.js` | OpenRouter + provider 路由 |
| `vision_proxy_server.py` | 已停用（僅提示改用 Vercel） |

## 403 仍出現時

1. 輪換 OpenRouter Key：`./execute_plan_a.sh 'sk-or-v1-新KEY'`
2. [OpenRouter 申訴](https://forms.gle/yc2vyJiALz8Uhbmh7)（草稿：`docs/openrouter_appeal_draft.txt`）
