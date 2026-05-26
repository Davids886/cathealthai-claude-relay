import {
  CORS_HEADERS,
  callOpenRouterFGS,
  jsonResponse,
} from "../lib/relay-core.js";

export const runtime = "edge";
export const preferredRegion = ["iad1"];

export async function POST(request) {
  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey?.startsWith("sk-or-")) {
    return jsonResponse({ error: "missing_openrouter_key" }, 500);
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const image_b64 = body?.image_base64;
  if (!image_b64 || typeof image_b64 !== "string") {
    return jsonResponse({ error: "image_base64 required" }, 400);
  }

  const result = await callOpenRouterFGS(apiKey, image_b64);
  if (!result.ok) {
    return jsonResponse({ error: result.error }, result.status);
  }
  return jsonResponse(result.data, 200);
}

export async function OPTIONS() {
  return new Response(null, { status: 204, headers: CORS_HEADERS });
}

export async function GET() {
  return jsonResponse({ error: "use_post", path: "/v1/fgs" }, 405);
}
