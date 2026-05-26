#!/usr/bin/env python3
"""Claude FGS relay — Anthropic 直連（優先）或 OpenRouter。POST /v1/fgs"""

from __future__ import annotations

import base64
import json
import os
import re
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

HOST = os.environ.get("VISION_PROXY_HOST", "0.0.0.0")
PORT = int(os.environ.get("VISION_PROXY_PORT", "8787"))
ENV_FILE = Path.home() / "CatHealthAI_v2_Final" / ".bridge.env"

OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"
ANTHROPIC_VERSION = "2023-06-01"

CLAUDE_MODELS = [
    "anthropic/claude-sonnet-4.6",
    "anthropic/claude-sonnet-4.5",
    "anthropic/claude-3.5-haiku",
]
ANTHROPIC_VISION_MODEL = os.environ.get("ANTHROPIC_MODEL", "claude-sonnet-4-20250514")

# 中性描述，降低 OpenRouter / Anthropic 內容審核誤判
SYSTEM_PROMPT = """You analyze cat face photos using the Feline Grimace Scale (FGS).
Score each feature 0, 1, or 2: ears, eyes, muzzle, whiskers, head posture.
Output only one JSON object with keys: earScore, eyeScore, muzzleScore, whiskerScore, headScore, totalScore, summary, careAdvice.
summary and careAdvice must be Traditional Chinese (繁體中文). No markdown."""

USER_PROMPT = (
    "Analyze this cat photo. Return only JSON: "
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


def parse_upstream_error(raw: str | bytes) -> tuple[int, dict]:
    if isinstance(raw, bytes):
        raw = raw.decode("utf-8", errors="replace")
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return 502, {"error": raw[:500]}
    if isinstance(data, dict) and "error" in data:
        err = data["error"]
        if isinstance(err, str):
            try:
                err = json.loads(err)
            except json.JSONDecodeError:
                pass
        if isinstance(err, dict):
            inner = err.get("error", err)
            if isinstance(inner, dict):
                code = inner.get("code", 502)
                return int(code) if str(code).isdigit() else 502, inner
            return 502, {"message": str(err)}
    return 502, data


def call_anthropic_direct(api_key: str, image_b64: str) -> dict:
    payload = {
        "model": ANTHROPIC_VISION_MODEL,
        "max_tokens": 1024,
        "system": SYSTEM_PROMPT,
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": image_b64,
                        },
                    },
                    {"type": "text", "text": USER_PROMPT},
                ],
            }
        ],
    }
    req = Request(
        ANTHROPIC_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "x-api-key": api_key,
            "anthropic-version": ANTHROPIC_VERSION,
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urlopen(req, timeout=120) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    blocks = data.get("content") or []
    text = ""
    for block in blocks:
        if block.get("type") == "text":
            text += block.get("text", "")
    out = extract_json(text)
    out["modelId"] = data.get("model", ANTHROPIC_VISION_MODEL)
    out["tier"] = "anthropic-direct"
    return out


def call_openrouter(api_key: str, image_b64: str) -> dict:
    user_content = [
        {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{image_b64}"}},
        {"type": "text", "text": USER_PROMPT},
    ]
    provider_plans = [
        {"order": ["amazon-bedrock"], "allow_fallbacks": False},
        {"order": ["google-vertex"], "allow_fallbacks": False},
        {"order": ["amazon-bedrock", "google-vertex", "anthropic"], "allow_fallbacks": True},
        None,
    ]
    last_err: dict | None = None
    for provider in provider_plans:
        payload: dict = {
            "model": CLAUDE_MODELS[0],
            "models": CLAUDE_MODELS,
            "max_tokens": 1024,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user_content},
            ],
        }
        if provider is not None:
            payload["provider"] = provider
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
        try:
            with urlopen(req, timeout=120) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except HTTPError as exc:
            body = exc.read() if hasattr(exc, "read") else b""
            _, err = parse_upstream_error(body)
            last_err = err if isinstance(err, dict) else {"message": str(err)}
            msg = (last_err.get("message") or "").lower()
            if "region" in msg or "terms of service" in msg or "prohibited" in msg:
                continue
            raise HTTPError(OPENROUTER_URL, exc.code, json.dumps(last_err), None, None) from exc
        if "error" in data:
            err = data["error"]
            last_err = err if isinstance(err, dict) else {"message": str(err)}
            msg = (last_err.get("message") or "").lower()
            if "region" in msg or "terms of service" in msg or "prohibited" in msg:
                continue
            code = last_err.get("code", 403)
            raise HTTPError(OPENROUTER_URL, int(code), json.dumps(last_err), None, None)
        model = data.get("model", CLAUDE_MODELS[0])
        if not is_claude(model):
            last_err = {"message": f"non_claude_model: {model}"}
            continue
        text = data["choices"][0]["message"]["content"]
        out = extract_json(text)
        out["modelId"] = model
        out["tier"] = "openrouter"
        return out
    code = last_err.get("code", 403) if isinstance(last_err, dict) else 403
    raise HTTPError(
        OPENROUTER_URL,
        int(code) if str(code).isdigit() else 403,
        json.dumps(last_err or {"message": "all_provider_routes_failed"}),
        None,
        None,
    )


def analyze_image(image_b64: str) -> dict:
    anthropic_key = os.environ.get("ANTHROPIC_API_KEY", "").strip()
    openrouter_key = os.environ.get("OPENROUTER_API_KEY", "").strip()

    if anthropic_key.startswith("sk-ant-"):
        return call_anthropic_direct(anthropic_key, image_b64)
    if openrouter_key.startswith("sk-or-"):
        return call_openrouter(openrouter_key, image_b64)
    raise ValueError("missing_api_key: set ANTHROPIC_API_KEY or OPENROUTER_API_KEY")


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
            backend = "anthropic" if os.environ.get("ANTHROPIC_API_KEY", "").startswith("sk-ant-") else "openrouter"
            self._json(200, {"ok": True, "backend": backend})
            return
        if self.path in ("/v1/probe", "/v1/probe/"):
            try:
                backend = "anthropic" if os.environ.get("ANTHROPIC_API_KEY", "").startswith("sk-ant-") else "openrouter"
                key = os.environ.get("ANTHROPIC_API_KEY") or os.environ.get("OPENROUTER_API_KEY", "")
                if backend == "anthropic":
                    payload = {
                        "model": ANTHROPIC_VISION_MODEL,
                        "max_tokens": 8,
                        "messages": [{"role": "user", "content": "reply ok"}],
                    }
                    req = Request(
                        ANTHROPIC_URL,
                        data=json.dumps(payload).encode(),
                        headers={
                            "x-api-key": key,
                            "anthropic-version": ANTHROPIC_VERSION,
                            "Content-Type": "application/json",
                        },
                        method="POST",
                    )
                else:
                    payload = {
                        "model": CLAUDE_MODELS[0],
                        "messages": [{"role": "user", "content": "reply ok"}],
                        "max_tokens": 8,
                    }
                    req = Request(
                        OPENROUTER_URL,
                        data=json.dumps(payload).encode(),
                        headers={
                            "Authorization": f"Bearer {key}",
                            "Content-Type": "application/json",
                            "HTTP-Referer": "https://cathealthai.com",
                            "X-Title": "CatHealthAI_App",
                        },
                        method="POST",
                    )
                with urlopen(req, timeout=60) as resp:
                    raw = resp.read().decode()[:300]
                self._json(200, {"ok": True, "backend": backend, "sample": raw})
            except HTTPError as exc:
                body = exc.read().decode(errors="replace") if hasattr(exc, "read") else str(exc)
                code, err = parse_upstream_error(body)
                self._json(code, {"ok": False, "backend": backend, "error": err})
            except Exception as exc:
                self._json(500, {"ok": False, "error": str(exc)})
            return
        self._json(404, {"error": "not_found"})

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_POST(self) -> None:
        if self.path not in ("/v1/fgs", "/v1/fgs/"):
            self._json(404, {"error": "not_found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(length).decode("utf-8"))
            image_b64 = body["image_base64"]
            base64.b64decode(image_b64, validate=True)
            result = analyze_image(image_b64)
            self._json(200, result)
        except HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace") if hasattr(exc, "read") else str(exc)
            code, err = parse_upstream_error(body.encode() if isinstance(body, str) else body)
            self._json(exc.code or code, {"error": err})
        except Exception as exc:
            self._json(500, {"error": str(exc)})


def main() -> None:
    load_env()
    HTTPServer((HOST, PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
