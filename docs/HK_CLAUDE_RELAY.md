# 在香港使用 OpenRouter Claude（CatHealthAI）

## 上架架構（用戶免 VPN、免 Anthropic Key）

```
iPhone App  →  https://cathealthai-vision-proxy.onrender.com/v1/fgs
              →  OpenRouter（OPENROUTER_API_KEY 只在伺服器）
              →  anthropic/claude-sonnet-4.6
```

- App **不**內嵌 `sk-or-` / `sk-ant-`。
- 用戶在香港直連 **Relay** 即可；Relay 在 **Render Oregon** 對 OpenRouter 發請求，避開「香港 IP 直連 Claude」的 region 403。

## 目前狀態

| 項目 | 狀態 |
|------|------|
| Render Relay | `https://cathealthai-vision-proxy.onrender.com` |
| App | `OpenRouterService.swift` 固定呼叫上述 `/v1/fgs` |
| OpenRouter 帳戶 Claude 模型 | 可能回 **403 TOS**（帳戶／上游政策，與 VPN 無關） |

若 `/v1/probe` 或 App 分析回 403 `Terms Of Service`：

1. 到 [OpenRouter Keys](https://openrouter.ai/keys) 確認帳戶可存取 Anthropic 模型。  
2. 若認為誤判，填寫 [申訴表單](https://forms.gle/yc2vyJiALz8Uhbmh7)。  
3. 無需申請 Anthropic `sk-ant-`；也**不要**要求終端用戶開 VPN。

## 不可行的做法（已驗證）

| 做法 | 原因 |
|------|------|
| App 直連 OpenRouter（香港 IP） | Claude **region 403** |
| Cloudflare Worker（香港用戶） | 出口常在 **HKG**，仍 403 |
| 僅加 Header、不改架構 | 不改出口 IP |

## Render 部署

1. Repo：`https://github.com/Davids886/cathealthai-claude-relay`  
2. 環境變數：`OPENROUTER_API_KEY=sk-or-v1-...`  
3. Region：**Oregon**，Docker：`deploy/Dockerfile`  
4. 本機推送後自動部署，或執行 `./finish_render_deploy.sh`

測試：

```bash
curl -s https://cathealthai-vision-proxy.onrender.com/health
curl -s https://cathealthai-vision-proxy.onrender.com/v1/probe
```

## 開發自測

- 可用 VPN 測 App UI；上架用戶只連 Relay。  
- 本地：`export OPENROUTER_API_KEY=... && python3 vision_proxy_server.py`（香港本機仍無法直測 Claude，除非改連 Render）。
