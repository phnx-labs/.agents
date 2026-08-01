# Stage 3 — Generate

Goal: turn the endpoint catalog into a **command schema**, then emit a CLI (and optionally an MCP
server) from that one schema so the two never drift.

## 1. Infer the command schema

From the merged catalog, build a single schema object:

```
{
  name: "<slug>",
  base_url: "...",
  auth: { secret_bundle: "clify.<slug>", header: "Authorization", scheme: "Bearer {SERVICE_TOKEN}" },
  resources: [
    { name: "charges", commands: [
      { name: "list",   method: "GET",  path: "/charges",      params: [{name:"limit", type:"number", in:"query"}], rung: 1 },
      { name: "get",    method: "GET",  path: "/charges/:id",  params: [{name:"id", type:"string", in:"path", required:true}], rung: 1 },
      { name: "create", method: "POST", path: "/charges",      params: [/* typed body fields */], rung: 1 }
    ]}
  ]
}
```

- Group endpoints into **resources** (usually the first path segment) with CRUD-ish **commands**.
- Infer param **types** from the request/response samples (string/number/boolean/enum/object). Mark
  path params required; give query params sensible names.
- Carry the **rung** onto every command so `--help` can flag brittle (rung 3–4) ones.
- Write the schema to the workspace (`schema.json`) — it is the single source both emitters read.

## 2. Scaffold the deterministic skeleton

```bash
bash lib/scaffold-cli.sh --name <slug> --out <workspace>/clify-<slug> \
     --base-url "<base_url>" --secret-bundle clify.<slug>
```

This produces the parts that must be identical across every generated CLI: `package.json` (with the
`clify-<slug>` bin), `tsconfig.json`, `src/index.ts` (commander bootstrap that auto-loads command
modules), and `src/http.ts` (a fetch wrapper that reads the token from the secrets-injected env and
sets the auth header). **Do not** hand-write these.

## 3. Author one command module per endpoint

For each command in the schema, write `src/commands/<resource>.<command>.ts` against the skeleton's
`http()` helper and commander registration convention (see the scaffolded `src/commands/_example.ts`).
Keep them thin: parse typed args → call `http()` → print JSON. No business logic, no fallbacks.

## 4. Optional — `--mcp` emit

If `--mcp` was passed, emit an MCP server from the **same** `schema.json`: one tool per command, typed
input schema from the same params. Register it (`agents mcp add <slug> -- node <path>/mcp.js` or
`mcporter config add`). Do not re-derive the surface — read `schema.json`.

## Output contract

- `schema.json` (the source of truth), a built `clify-<slug>` package, and (if `--mcp`) an MCP server.
- Every command module compiles (`tsc --noEmit` clean) before Stage 4 runs.

Reuse the scaffold; never duplicate the http/auth wiring into individual command modules.
