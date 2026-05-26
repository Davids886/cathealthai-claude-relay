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

export const config = {
  maxDuration: 60,
  regions: ["iad1"],
};

export default async function handler(req, res) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    return res.status(204).end();
  }

  if (req.method !== "POST") {
    return res.status(404).json({ error: "not_found" });
  }

  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey || !apiKey.startsWith("sk-or-")) {
    return res.status(500).json({ error: "missing_openrouter_key" });
  }

  const image_b64 = req.body?.image_base64;
  if (!image_b64) {
    return res.status(400).json({ error: "image_base64 required" });
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
            image_url: { url: `data:image/jpeg;base64,${image_b64}` },
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
    return res.status(orRes.status).json({ error: orData });
  }

  const model = orData.model || CLAUDE_MODELS[0];
  if (!isClaude(model)) {
    return res.status(502).json({ error: `non_claude_model: ${model}` });
  }

  const text = orData.choices?.[0]?.message?.content || "";
  try {
    const assessment = extractJson(text);
    assessment.modelId = model;
    assessment.tier = "claude";
    return res.status(200).json(assessment);
  } catch {
    return res.status(502).json({ error: "decode_failed", raw: text.slice(0, 200) });
  }
}
