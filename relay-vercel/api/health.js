import { jsonResponse } from "../lib/relay-core.js";

export const runtime = "edge";
export const preferredRegion = ["iad1"];

export async function GET() {
  return jsonResponse({
    ok: true,
    backend: "openrouter",
    platform: "vercel-edge",
    region: "iad1",
  });
}

export async function OPTIONS() {
  return new Response(null, {
    status: 204,
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, OPTIONS",
    },
  });
}
