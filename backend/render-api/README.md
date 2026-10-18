# Yemen Law Encyclopedia API (staged migration)

This isolated API scaffold does not replace or modify the Flutter app or the existing Cloudflare Worker.

## Vercel deployment

Create a separate Vercel project linked to this repository and select branch `feat/render-api-migration`.

- Framework preset: Other
- Root Directory: `backend/render-api`
- Build command: leave the default/empty (no build step is required)
- Output directory: leave empty/default
- Install command: leave the default (the package has no external dependencies)
- Do not change the existing Flutter app's Vercel project.

After deployment, add `GEMINI_API_KEY` as a secret environment variable in the new API project's Settings → Environment Variables, for Production and Preview. Never commit the key or share it in chat. Optional variables:
- `AI_MODEL`: defaults to `gemini-3.8-flash`; keep this value to preserve the configured model.
- `MAX_QUESTION_CHARS`: defaults to `1200`.

## API routes

- `GET /` and `GET /health`: health status.
- `POST /api/chat` and `POST /api/legal/ask`: Gemini-backed chat.
- `GET /api/health`: health status.

Health responses deliberately report `legal_database_connected: false` until local legal retrieval is migrated and verified.

## Render alternative

If deploying to Render instead, use the repository root as the root directory, build command `npm --prefix backend/render-api install`, start command `npm --prefix backend/render-api start`, and health check path `/health`. Render may require a payment method depending on the account.

## Important limitations

This is a staged migration. It does **not** connect to the current Cloudflare D1/Vectorize legal corpus, so replies are marked `gemini_fallback_no_law_database` and have no legal source citations. Do not point the production Flutter app at this service until legal retrieval, API compatibility, secret configuration, and endpoint tests are complete. Keep the existing app, Cloudflare service, and main branch untouched during this stage.
