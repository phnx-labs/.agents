# Stage 2 — Authenticate & capture

Goal: get legitimate access to the target the least-invasive way, and — for endpoints the docs didn't
cover — capture real traffic and turn it into an endpoint catalog. Every secret captured here is
persisted in `agents secrets` and read at runtime; none is ever written into the generated code.

## Auth, least-invasive first

1. **API key / token (rung 2).** If the service issues developer keys, have the user create one (guide
   them; don't ask them to paste it into chat — capture it directly into a bundle). Store it:
   ```bash
   agents secrets create clify.<slug>
   agents secrets add clify.<slug> <SERVICE>_TOKEN '<value>'
   ```
2. **OAuth (rung 2).** If the API uses OAuth, run the flow in `agents browser` against the real consent
   screen, then capture the resulting access/refresh token from the redirect or the app's storage
   (`agents browser evaluate --expression 'localStorage.getItem("...")'`). Store both tokens in the bundle.
3. **Logged-in session (rung 3).** If the capability is only reachable through the web app, use the
   persistent browser profile that is already logged in (screenshot first — skip login if the session is
   live). The session cookie/bearer is captured for replay and stored in the bundle.

## Capture the traffic (rungs 3–4)

1. Start a browser task and drive the app to exercise the target capability (navigate, click, submit).
2. Export the network log as HAR:
   ```bash
   agents browser har --with-bodies --out capture.har        # richest path (see SKILL capture note)
   # fallback until --with-bodies lands:
   agents browser requests --format har > capture.har
   #   then fill bodies per endpoint: agents browser responsebody "<url-substr>"
   ```
3. Reduce the HAR to an endpoint catalog:
   ```bash
   python3 lib/har_extract.py capture.har --host <api-host> --json-only > endpoints.json
   ```
   `har_extract.py` path-templates ids (`/users/123` → `/users/:id`), dedups by (method, template), and
   keeps one request/response sample per endpoint for schema inference.

4. **Rung 4 — content-script injection (last resort).** Only if a needed call never appears in traffic:
   read internal app state / call app methods via `agents browser evaluate`. Mark every rung-4 endpoint
   as brittle in the catalog.

## Output contract

- The `agents secrets` bundle name holding all credentials (e.g. `clify.<slug>`).
- `endpoints.json` merged with Stage 1's catalog — the full, deduped surface with rung tags.
- The auth header/cookie shape the generated http client must reproduce (which secret → which header).

Never echo a raw token into the report or the transcript. Reference it by bundle + key name only.
