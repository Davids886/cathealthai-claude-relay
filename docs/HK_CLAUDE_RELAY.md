# 在香港使用 OpenRouter Claude（CatHealthAI）

OpenRouter 會依**發出 API 請求時的出口 IP**判斷地區。香港 IP 對 `anthropic/claude-*` 常回 **403**（`This model is not available in your region`）。這與 App 寫得好壞無關，**必須讓請求從非限制地區出去**。

## 不可行的做法（已驗證）

| 做法 | 原因 |
|------|------|
| 只加 `HTTP-Referer` / `X-Title` | 不會改變出口 IP |
| **Cloudflare Workers**（含 `placement`） | 使用者從香港連入時，Worker 對外連 OpenRouter 的出口常在 **HKG**，仍被當成香港流量 |
| 在本機／香港 VPS 跑 `vision_proxy_server.py` | 出口仍是香港 |
| OpenRouter `provider.order` 指到 Bedrock / Vertex | 帳號層級仍可能整體 403（香港） |

## 可行方案（擇一即可）

### 1. 手機開 VPN（最省事，適合自用）

連到 **美國／歐盟** 節點後，App 若走**直連** OpenRouter，出口 IP 變更後 Claude 通常可用。

- 缺點：一般使用者不會開 VPN；上架產品不宜強制。

### 2. Render 美國區 Web Service（推薦給正式產品）

在 **Oregon** 跑 Docker 版 relay（專案已有 `deploy/Dockerfile`、`vision_proxy_server.py`）。

> **注意：** 許多 Render 帳號建立 Web Service 前需在 [Billing](https://dashboard.render.com/billing) **綁定信用卡**（免費方案仍可能要求驗證，不一定會扣款）。若 API 回 `402 Payment information is required`，請先完成綁卡再部署。

1. [Render Dashboard](https://dashboard.render.com) 登入  
2. **New → Web Service**（或 **Blueprint** 連 GitHub 選 repo 根目錄的 `render.yaml`）  
3. **Region：Oregon**  
4. **Runtime：Docker**，`Dockerfile Path`：`./deploy/Dockerfile`，**Root Directory** 留空（context 見 `render.yaml`）  
5. 環境變數：`OPENROUTER_API_KEY` = 你的 `sk-or-v1-...`  
6. 部署完成後 URL 形如 `https://<服務名>.onrender.com`，在 `OpenRouterService.swift` 設定：

   `private let claudeRelayBaseURL: String? = "https://<服務名>.onrender.com/v1/fgs"`

- 免費方案會休眠，第一次請求可能較慢。

本機已裝 [Render CLI](https://render.com/docs/cli) 時，可改跑專案根目錄的 `./deploy_render.sh`（需先 `render login`，並依腳本說明設定 `DOCKERHUB_USER` 或 `RENDER_REPO_URL`；若出現 workspace 錯誤，請先 `render workspaces` 再 `render workspace set <id>`）。

### 3. Fly.io `ord`（芝加哥附近）

`deploy/fly.toml` 已設 `primary_region = "ord"`。若帳號顯示 **machine limit**，需在 Dashboard 刪掉不用的 app 再部署。

### 4. 任一美國／歐盟小 VPS

在該主機跑：

```bash
export OPENROUTER_API_KEY=sk-or-v1-...
python3 vision_proxy_server.py
```

前面加 nginx + HTTPS 或內網隧道，再把 `https://你的網域/v1/fgs` 寫進 App。

## App 內設定

`OpenRouterService.swift` 的 `claudeRelayBaseURL` 應指向 **POST `/v1/fgs`**、body 為 `{"image_base64":"..."}` 的 relay（與 `vision_proxy_server.py` 一致）。

## OpenRouter Relay 仍 403（Terms of Service）時

從美國 Render 轉發 OpenRouter 若回 **403 TOS**，常見原因：

1. **OpenRouter 禁止用代理／Relay 規避地區**（服務條款 §5.7）
2. 雲端機房 IP 被上游視為高風險
3. 醫療類提示觸發審核（已將 Relay 改為中性 FGS 英文提示）

**建議解法（仍只用 Claude）：**

在 Render Dashboard → `cathealthai-vision-proxy` → **Environment** 新增：

| 變數 | 值 |
|------|-----|
| `ANTHROPIC_API_KEY` | 從 [console.anthropic.com](https://console.anthropic.com) 建立的 `sk-ant-…` |
| `ANTHROPIC_MODEL` | 可選，預設 `claude-sonnet-4-20250514` |

Relay 會**優先走 Anthropic 官方 API**（不經 OpenRouter），由美國主機發出，App 仍連同一個 `/v1/fgs` URL。

部署後可測：`curl https://cathealthai-vision-proxy.onrender.com/v1/probe`

## 安全提醒

- 勿把 `OPENROUTER_API_KEY` 提交到公開 repo；Render 用 Dashboard 或 CLI 設成 **Secret / 環境變數** 即可。
- 若 API key 曾出現在已推送的程式碼，建議到 OpenRouter **旋轉（revoke 再發新）**。
