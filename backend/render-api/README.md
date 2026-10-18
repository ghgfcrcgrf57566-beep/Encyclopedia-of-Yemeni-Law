# Render API migration (staged)

This is an isolated Render-compatible API scaffold. It does not replace or modify the existing Cloudflare Worker.

## Routes
- `GET /` and `GET /health`: health status.
- `POST /api/chat` and `POST /api/legal/ask`: Gemini-backed chat.

## Render service settings
- Runtime: Node
- Root directory: repository root
- Build command: `npm --prefix backend/render-api install`
- Start command: `npm --prefix backend/render-api start`
- Region suggestion: Singapore (test latency from Yemen); Frankfurt is an alternative.
- Health check path: `/health`
- Plan: Free for initial verification.

## Environment variables
- `GEMINI_API_KEY`: add as a secret in the Render dashboard; never commit it.
- `AI_MODEL`: `gemini-3.8-flash` (preserves the model configured in the current backend).
- `MAX_QUESTION_CHARS`: `1200`.

## Important limitation
This first stage does **not** connect to the current Cloudflare D1/Vectorize legal corpus. It returns `legal_database_connected: false` from health and labels chat replies as `gemini_fallback_no_law_database`. Do not point the production app at this service until the legal retrieval layer is migrated and tested. The existing Cloudflare service and app configuration must remain untouched during this stage.
