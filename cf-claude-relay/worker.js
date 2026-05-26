/**
 * CatHealthAI Claude Relay — 僅轉發至 OpenRouter Claude（Anthropic）
 * POST /v1/fgs  { "image_base64": "..." }
 */

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";
const CLAUDE_MODELS = [
  "anthropic/claude-sonnet-4.6",
  "anthropic/claude-sonnet-4.5",
  "anthropic/claude-3.5-haiku",
];

const SYSTEM_PROMPT = `你是一位精通貓咪行為學與臨床醫學的權威獸醫。請依 FGS 標準評分。
僅輸出 JSON：earScore, eyeScore, muzzleScore, whiskerScore, headScore, totalScore, summary, careAdvice。繁體中文。`;

const USER_PROMPT =
  '請分析貓咪照片，只回 JSON：{"earScore":0,"eyeScore":0,"muzzleScore":0,"whiskerScore":0,"headScore":0,"totalScore":0,"summary":"","careAdvice":""}';

function jsonResponse(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Access-Control-Allow-Origin": "*",
    },
  });
}

function extractJson(text) {
  let s = text.trim();
  if (s.startsWith("```")) {
    s = s.replace(/```json|```/g, "").trim();
  }
  const start = s.indexOf("{");
  const end = s.lastIndexOf("}");
  if (start >= 0 && end > start) s = s.slice(start, end + 1);
  return JSON.parse(s);
}

function isClaude(model) {
  const m = (model || "").toLowerCase();
  return m.includes("claude") || m.includes("anthropic");
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type",
        },
      });
    }

    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/v1/debug") {
      let egress = null;
      try {
        const ipRes = await fetch("https://api.ipify.org?format=json");
        egress = await ipRes.json();
      } catch (e) {
        egress = { error: String(e) };
      }
      return jsonResponse(200, {
        colo: request.cf?.colo ?? null,
        country: request.cf?.country ?? null,
        placement: "aws:us-east-1",
        egress,
      });
    }

    if (request.method !== "POST" || !url.pathname.startsWith("/v1/fgs")) {
      return jsonResponse(404, { error: "not_found" });
    }

    const apiKey = env.OPENROUTER_API_KEY;
    if (!apiKey || !apiKey.startsWith("sk-or-")) {
      return jsonResponse(500, { error: "missing_openrouter_key" });
    }

    let body;
    try {
      body = await request.json();
      if (!body.image_base64) {
        return jsonResponse(400, { error: "image_base64 required" });
      }
    } catch {
      return jsonResponse(400, { error: "invalid_json" });
    }

    const payload = {
      model: CLAUDE_MODELS[0],
      models: CLAUDE_MODELS,
      max_tokens: 1024,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        {
          role: "user",
          content: [
            {
              type: "image_url",
              image_url: {
                url: `data:image/jpeg;base64,${body.image_base64}`,
              },
            },
            { type: "text", text: USER_PROMPT },
          ],
        },
      ],
    };

    const orRes = await fetch(OPENROUTER_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://cathealthai.com",
        "X-Title": "CatHealthAI_App",
      },
      body: JSON.stringify(payload),
    });

    const orData = await orRes.json();
    if (!orRes.ok) {
      return jsonResponse(orRes.status, { error: orData });
    }

    const model = orData.model || CLAUDE_MODELS[0];
    if (!isClaude(model)) {
      return jsonResponse(502, {
        error: `non_claude_model: ${model}`,
      });
    }

    const text = orData.choices?.[0]?.message?.content || "";
    try {
      const assessment = extractJson(text);
      assessment.modelId = model;
      assessment.tier = "claude";
      return jsonResponse(200, assessment);
    } catch (e) {
      return jsonResponse(502, {
        error: "decode_failed",
        raw: text.slice(0, 200),
      });
    }
  },
};
