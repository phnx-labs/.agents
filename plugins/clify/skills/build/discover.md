# Stage 1 — Discover

Goal: resolve the target to a base URL and inventory its API surface, climbing the ladder from the
top (cheapest, most stable) down. Output a candidate endpoint list, each tagged with the rung it came
from and a confidence note.

## Steps

1. **Resolve the target.** From the user's phrasing (`stripe.com`, "the API behind app.linear.app", a
   docs URL), determine the product and its likely API host(s). Note the current year in any web query
   (weights are stale).

2. **Rung 1 — machine-readable spec first.** Search hard before inferring:
   - `WebSearch` for `<product> OpenAPI spec <year>`, `<product> API reference`, `<product> GraphQL schema`.
   - `WebFetch` common spec locations: `/openapi.json`, `/openapi.yaml`, `/swagger.json`, `/.well-known/`,
     `/api/schema`, a GraphQL introspection endpoint.
   - If a spec exists, it *is* the endpoint list — parse it into the candidate catalog and mostly skip
     rungs 2–4. This is the ideal path.

3. **Rung 1b — developer portal / docs.** If no formal spec, read the developer docs (`WebFetch` the API
   reference pages). Extract endpoints, methods, auth scheme, base URL, pagination style, rate limits.

4. **Decide whether to descend.** Only go to rungs 2–4 (authed probing / HAR capture) for capabilities
   the docs/spec don't cover, or when the target has no public API at all and the user wants the private
   web-app API wrapped. Hand those specific gaps to Stage 2 (`capture.md`).

5. **Emit the candidate catalog.** A JSON list: `{ method, path_template, base_url, summary, auth,
   params, rung, confidence }`. Write it to the build workspace (see `lib/env.sh` for the path).

## Output contract

- The base URL(s) and the auth scheme the API expects.
- The candidate endpoint catalog with a rung tag on every entry.
- An explicit list of gaps that require Stage 2 capture (or "none — spec was complete").

Return file:line / URL evidence for every endpoint claim. If you can't source it, mark it
`rung: infer` and low confidence — never present a guessed endpoint as documented.
