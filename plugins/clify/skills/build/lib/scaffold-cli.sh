#!/usr/bin/env bash
# scaffold-cli.sh — lay down the deterministic TypeScript CLI skeleton for a clify build.
#
# Produces only the parts that must be identical across every generated CLI: the
# bin wiring, a secrets-backed http client, and the commander bootstrap that
# auto-loads command modules. The per-endpoint command modules under src/commands/
# are authored by the agent (Stage 3) against this skeleton — this script never
# writes business logic.
set -euo pipefail

NAME="" ; OUT="" ; BASE_URL="" ; SECRET_BUNDLE=""
usage() {
  echo "usage: scaffold-cli.sh --name <slug> --out <dir> --base-url <url> [--secret-bundle <name>]" >&2
  exit 2
}
while [ $# -gt 0 ]; do
  case "$1" in
    --name)          NAME="$2"; shift 2;;
    --out)           OUT="$2"; shift 2;;
    --base-url)      BASE_URL="$2"; shift 2;;
    --secret-bundle) SECRET_BUNDLE="$2"; shift 2;;
    -h|--help)       usage;;
    *) echo "unknown arg: $1" >&2; usage;;
  esac
done
[ -n "$NAME" ] && [ -n "$OUT" ] && [ -n "$BASE_URL" ] || usage

# Enforce the slug invariant HERE — npm package names must be lowercase, so this
# can't depend on the caller passing an already-normalized slug. Lowercase,
# collapse any non-alnum run to '-', trim leading/trailing '-'.
NAME=$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's#[^a-z0-9]+#-#g; s#^-+|-+$##g')
[ -n "$NAME" ] || { echo "scaffold-cli.sh: --name did not reduce to a usable slug (all non-ascii?) — pass an explicit --name" >&2; exit 2; }

PKG="clify-$NAME"
TOKEN_ENV="$(printf '%s' "$NAME" | tr '[:lower:]-' '[:upper:]_')_TOKEN"
# Env-var names may not begin with a digit (slug like '2fa' → '2FA_TOKEN' is invalid).
case "$TOKEN_ENV" in [0-9]*) TOKEN_ENV="_$TOKEN_ENV";; esac
mkdir -p "$OUT/src/commands"

cat > "$OUT/package.json" <<JSON
{
  "name": "$PKG",
  "version": "0.1.0",
  "description": "clify-generated CLI for $NAME",
  "type": "module",
  "bin": { "$PKG": "dist/index.js" },
  "scripts": {
    "build": "tsc",
    "dev": "tsx src/index.ts"
  },
  "dependencies": { "commander": "^12.1.0" },
  "devDependencies": { "typescript": "^5.5.0", "tsx": "^4.16.0", "@types/node": "^22.0.0" }
}
JSON

cat > "$OUT/tsconfig.json" <<'JSON'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ES2022",
    "moduleResolution": "node",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "declaration": false
  },
  "include": ["src/**/*.ts"]
}
JSON

# http.ts — the single source of auth + base URL. Reads the token from the env
# that `agents secrets exec <bundle>` injects; the token is NEVER written here.
# JSON-quote the base URL so it is a safe TS string literal (portable to bash 3.2,
# unlike ${var@Q}).
BASE_URL_JSON=$(printf '%s' "$BASE_URL" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
cat > "$OUT/src/http.ts" <<TS
const BASE_URL = $BASE_URL_JSON;
const TOKEN_ENV = "$TOKEN_ENV";

export interface HttpOpts {
  method?: string;
  query?: Record<string, string | number | boolean | undefined>;
  body?: unknown;
}

export async function http(path: string, opts: HttpOpts = {}): Promise<unknown> {
  const token = process.env[TOKEN_ENV];
  if (!token) {
    throw new Error(
      \`Missing \${TOKEN_ENV}. Run via: agents secrets exec ${SECRET_BUNDLE:-clify.$NAME} -- $PKG ...\`,
    );
  }
  const url = new URL(path.replace(/^\//, ""), BASE_URL.endsWith("/") ? BASE_URL : BASE_URL + "/");
  for (const [k, v] of Object.entries(opts.query ?? {})) {
    if (v !== undefined) url.searchParams.set(k, String(v));
  }
  const res = await fetch(url, {
    method: opts.method ?? "GET",
    headers: {
      Authorization: \`Bearer \${token}\`,
      "Content-Type": "application/json",
    },
    body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
  });
  const text = await res.text();
  const data = text ? safeJson(text) : null;
  if (!res.ok) {
    throw new Error(\`\${res.status} \${res.statusText}: \${typeof data === "string" ? data : JSON.stringify(data)}\`);
  }
  return data;
}

function safeJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}
TS

# index.ts — commander bootstrap that auto-registers every src/commands/*.ts module.
cat > "$OUT/src/index.ts" <<'TS'
#!/usr/bin/env node
import { Command } from "commander";
import { readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const program = new Command();
program.name(process.env.CLIFY_BIN ?? "clify-cli").description("clify-generated CLI");

// Each command module exports: register(program: Command): void
const here = dirname(fileURLToPath(import.meta.url));
const cmdDir = join(here, "commands");
for (const file of readdirSync(cmdDir)) {
  if (!file.endsWith(".js") || file.startsWith("_")) continue;
  const mod = await import(join(cmdDir, file));
  if (typeof mod.register === "function") mod.register(program);
}

await program.parseAsync(process.argv);
TS

# _example.ts — the pattern the agent copies for each real endpoint (ignored by index.ts).
cat > "$OUT/src/commands/_example.ts" <<'TS'
import type { Command } from "commander";
import { http } from "../http.js";

// Copy this shape per endpoint from schema.json. Keep it thin: typed args →
// http() → print JSON. No business logic, no fallbacks.
export function register(program: Command): void {
  const resource = program.command("charges").description("charges resource");
  resource
    .command("list")
    .description("List charges [rung1]")
    .option("--limit <n>", "max results", (v) => parseInt(v, 10))
    .action(async (opts) => {
      const data = await http("/charges", { query: { limit: opts.limit } });
      console.log(JSON.stringify(data, null, 2));
    });
}
TS

echo "scaffolded $PKG at $OUT (token env: $TOKEN_ENV, bundle: ${SECRET_BUNDLE:-clify.$NAME})"
