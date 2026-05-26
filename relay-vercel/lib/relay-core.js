/** @typedef {Record<string, unknown>} JsonObject */

export const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

export const CLAUDE_MODELS = [
  "anthropic/claude-sonnet-4.6",
  "anthropic/claude-sonnet-4.5",
  "anthropic/claude-3.5-haiku",
];

export const SYSTEM_PROMPT = `You analyze cat face photos using the Feline Grimace Scale (FGS).
Score each feature 0, 1, or 2: ears, eyes, muzzle, whiskers, head posture.
Output only one JSON object with keys: earScore, eyeScore, muzzleScore, whiskerScore, headScore, totalScore, summary, careAdvice.
summary and careAdvice must be Traditional Chinese (繁體中文). No markdown.`;

export const USER_PROMPT =
  'Analyze this cat photo. Return only JSON: {"earScore":0,"eyeScore":0,"muzzleScore":0,"whiskerScore":0,"headScore":0,"totalScore":0,"summary":"","careAdvice":""}';

/** Minimal JPEG for /v1/probe */
export const TINY_JPEG_B64 =
  "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAABAAEDAREAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAb/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCdABmX/9k=";

export const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

export function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...CORS_HEADERS },
  });
}

export function extractJson(text) {
  let s = String(text || "").trim();
  if (s.startsWith("```")) {
    s = s.replace(/```json|```/g, "").trim();
  }
  const start = s.indexOf("{");
  const end = s.lastIndexOf("}");
  if (start >= 0 && end > start) s = s.slice(start, end + 1);
  return JSON.parse(s);
}

export function isClaude(model) {
  const m = String(model || "").toLowerCase();
  return m.includes("claude") || m.includes("anthropic");
}

function isRetryable(msg) {
  const lower = String(msg || "").toLowerCase();
  return (
    lower.includes("region") ||
    lower.includes("terms of service") ||
    lower.includes("prohibited") ||
    lower.includes("not available")
  );
}

function openRouterHeaders(apiKey) {
  return {
    Authorization: `Bearer ${apiKey}`,
    "Content-Type": "application/json",
    "HTTP-Referer": "https://cathealthai.com",
    "X-Title": "CatHealthAI_App",
  };
}

/**
 * @param {string} apiKey
 * @param {string} imageB64
 * @returns {Promise<{ ok: true, data: JsonObject } | { ok: false, status: number, error: JsonObject }>}
 */
export async function callOpenRouterFGS(apiKey, imageB64) {
  const userContent = [
    { type: "image_url", image_url: { url: `data:image/jpeg;base64,${imageB64}` } },
    { type: "text", text: USER_PROMPT },
  ];

  const providerPlans = [
    { order: ["amazon-bedrock"], allow_fallbacks: false },
    { order: ["google-vertex"], allow_fallbacks: false },
    { order: ["amazon-bedrock", "google-vertex", "anthropic"], allow_fallbacks: true },
    null,
  ];

  /** @type {JsonObject | null} */
  let lastErr = null;

  for (const provider of providerPlans) {
    /** @type {JsonObject} */
    const payload = {
      model: CLAUDE_MODELS[0],
      models: CLAUDE_MODELS,
      max_tokens: 1024,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: userContent },
      ],
    };
    if (provider) payload.provider = provider;

    const orRes = await fetch(OPENROUTER_URL, {
      method: "POST",
      headers: openRouterHeaders(apiKey),
      body: JSON.stringify(payload),
    });

    const orData = await orRes.json();

    if (!orRes.ok) {
      const err = orData?.error ?? orData;
      lastErr =
        typeof err === "object" && err !== null
          ? /** @type {JsonObject} */ (err)
          : { message: String(err) };
      if (isRetryable(lastErr.message)) continue;
      return { ok: false, status: orRes.status, error: lastErr };
    }

    if (orData.error) {
      lastErr =
        typeof orData.error === "object"
          ? orData.error
          : { message: String(orData.error) };
      if (isRetryable(lastErr.message)) continue;
      return {
        ok: false,
        status: Number(lastErr.code) || 502,
        error: lastErr,
      };
    }

    const model = orData.model || CLAUDE_MODELS[0];
    if (!isClaude(model)) {
      lastErr = { message: `non_claude_model: ${model}` };
      continue;
    }

    const text = orData.choices?.[0]?.message?.content || "";
    const out = extractJson(text);
    out.modelId = model;
    out.tier = "openrouter";
    return { ok: true, data: out };
  }

  return {
    ok: false,
    status: Number(lastErr?.code) || 403,
    error: lastErr || { message: "all_provider_routes_failed" },
  };
}
