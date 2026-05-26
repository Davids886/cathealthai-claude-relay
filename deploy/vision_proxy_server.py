#!/usr/bin/env python3
"""Claude-only FGS relay for Render / Fly (US region). POST /v1/fgs"""

from __future__ import annotations

import base64
import json
import os
import re
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

HOST = os.environ.get("VISION_PROXY_HOST", "0.0.0.0")
PORT = int(os.environ.get("VISION_PROXY_PORT", "8787"))
ENV_FILE = Path.home() / "CatHealthAI_v2_Final" / ".bridge.env"

OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
CLAUDE_MODELS = [
    "anthropic/claude-sonnet-4.6",
    "anthropic/claude-sonnet-4.5",
    "anthropic/claude-3.5-haiku",
]

SYSTEM_PROMPT = """你是一位精通貓咪行為學與臨床醫學的權威獸醫。請依 FGS 標準評分。
僅輸出 JSON：earScore, eyeScore, muzzleScore, whiskerScore, headScore, totalScore, summary, careAdvice。繁體中文。"""

USER_PROMPT = (
    '{"earScore":0,"eyeScore":0,"muzzleScore":0,"whiskerScore":0,"headScore":0,'
    '"totalScore":0,"summary":"","careAdvice":""}'
)


def load_env() -> None:
    if not ENV_FILE.is_file():
        return
    for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        k, v = k.strip(), v.strip().strip("'\"")
        if k and v and k not in os.environ:
            os.environ[k] = v


def extract_json(text: str) -> dict:
    s = text.strip()
    if s.startswith("```"):
        s = re.sub(r"```json|```", "", s).strip()
    start, end = s.find("{"), s.rfind("}")
    if start >= 0 and end > start:
        s = s[start : end + 1]
    return json.loads(s)


def is_claude(model: str) -> bool:
    m = model.lower()
    return "claude" in m or "anthropic" in m


def call_openrouter(api_key: str, image_b64: str) -> dict:
    payload = {
        "model": CLAUDE_MODELS[0],
        "models": CLAUDE_MODELS,
        "max_tokens": 1024,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {
                "role": "user",
                "content": [
                    {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{image_b64}"}},
                    {"type": "text", "text": f"請分析這張貓咪照片。只回傳 JSON：{USER_PROMPT}"},
                ],
            },
        ],
    }
    req = Request(
        OPENROUTER_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://cathealthai.com",
            "X-Title": "CatHealthAI_App",
        },
        method="POST",
    )
    with urlopen(req, timeout=120) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    if "error" in data:
        raise HTTPError(OPENROUTER_URL, 400, json.dumps(data["error"]), None, None)
    model = data.get("model", CLAUDE_MODELS[0])
    if not is_claude(model):
        raise ValueError(f"non_claude_model: {model}")
    text = data["choices"][0]["message"]["content"]
    out = extract_json(text)
    out["modelId"] = model
    return out


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        print(f"[relay] {fmt % args}", flush=True)

    def _json(self, status: int, body: dict) -> None:
        payload = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self) -> None:
        if self.path in ("/health", "/health/"):
            self._json(200, {"ok": True})
            return
        self._json(404, {"error": "not_found"})

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_POST(self) -> None:
        if self.path not in ("/v1/fgs", "/v1/fgs/"):
            self._json(404, {"error": "not_found"})
            return
        api_key = os.environ.get("OPENROUTER_API_KEY", "").strip()
        if not api_key.startswith("sk-or-"):
            self._json(500, {"error": "missing_openrouter_key"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(length).decode("utf-8"))
            image_b64 = body["image_base64"]
            base64.b64decode(image_b64, validate=True)
            result = call_openrouter(api_key, image_b64)
            self._json(200, result)
        except HTTPError as exc:
            err = exc.read().decode("utf-8", errors="replace") if hasattr(exc, "read") else str(exc)
            self._json(exc.code or 502, {"error": err[:800]})
        except Exception as exc:
            self._json(500, {"error": str(exc)})


def main() -> None:
    load_env()
    HTTPServer((HOST, PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
