#!/usr/bin/env python3
"""SessionStart hook: tell the agent which credentials it can already reach.

The failure this prevents: an agent stops and asks the human for an API key or
a login that already sits in a secrets bundle or a signed-in browser profile on
this machine, because nothing told it they exist. Injecting a value-free
catalog at session start lets it self-serve with `secrets exec` or
`browser start --profile` instead of idling on the human.

Prints nothing when the machine has no bundles and no signed-in profiles. The
header is stripped from transcripts by agents-cli (session/prompt.ts) like the
other injected blocks.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import credential_catalog  # noqa: E402

MAX_BUNDLES = 40


def render(catalog: dict, host: str) -> str:
    bundles, logins = catalog["bundles"], catalog["logins"]
    if not bundles and not logins:
        return ""
    out = [
        "## Credentials you can reach",
        "Check here before asking the human for a password, token, API key or login.",
        "Values are never shown; run a command under a bundle instead.",
        "",
    ]
    if bundles:
        out.append(f"Secrets bundles on {host} (`secrets exec <bundle> -- <cmd>`):")
        width = max(len(b["name"]) for b in bundles[:MAX_BUNDLES])
        for b in bundles[:MAX_BUNDLES]:
            keys = f"{b['keys']} key" + ("" if b["keys"] == 1 else "s")
            line = f"- {b['name'].ljust(width)}  {keys}"
            if b["description"]:
                line += f"  {b['description'][:90]}"
            out.append(line)
        if len(bundles) > MAX_BUNDLES:
            out.append(f"- … {len(bundles) - MAX_BUNDLES} more: `secrets list`")
        out.append("")
    if logins:
        out.append("Signed-in browser profiles (`browser start --profile <profile>`):")
        by_profile: dict[str, list[str]] = {}
        for r in logins:
            who = f"{r['service']} as {r['account']}" if r["account"] else r["service"]
            by_profile.setdefault(r["profile"], []).append(who)
        for profile in sorted(by_profile):
            out.append(f"- {profile}: " + ", ".join(by_profile[profile]))
        out.append("")
    out.append("Other machines hold their own bundles: `secrets list --hosts <a,b>`.")
    return "\n".join(out)


def main() -> int:
    host = os.uname().nodename.split(".")[0]
    text = render(credential_catalog.build(), host)
    if text:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
