import {
  TINY_JPEG_B64,
  callOpenRouterFGS,
  jsonResponse,
} from "../lib/relay-core.js";

export const runtime = "edge";
export const preferredRegion = ["iad1"];

export async function GET() {
  return runProbe();
}

export async function POST() {
  return runProbe();
}

async function runProbe() {
  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey?.startsWith("sk-or-")) {
    return jsonResponse({ ok: false, error: "missing_openrouter_key" }, 500);
  }

  const result = await callOpenRouterFGS(apiKey, TINY_JPEG_B64);
  if (!result.ok) {
    return jsonResponse(
      { ok: false, backend: "openrouter", platform: "vercel-edge", error: result.error },
      result.status
    );
  }
  return jsonResponse({
    ok: true,
    backend: "openrouter",
    platform: "vercel-edge",
    modelId: result.data.modelId,
  });
}

export async function OPTIONS() {
  return new Response(null, {
    status: 204,
    headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET, POST, OPTIONS" },
  });
}
