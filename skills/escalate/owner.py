#!/usr/bin/env python3
# owner.py — stdlib-only reader for ~/.agents/owner.md frontmatter.
#
# PyYAML is NOT installed on every box (verified: absent on mac-mini), so the
# owner profile is parsed with the standard library only. The schema is a
# constrained subset — top-level `key: value` scalars, a `channels:` list of
# flat `- key: value` maps, and a `policy:` map of `sev: [step, step@delay]`
# lists — which a small hand parser handles without a YAML dependency.
#
# Emits, on stdout, a JSON object the escalate mechanism consumes:
#   { "host", "telegram": {"account","target"}, "call": {"cmd"},
#     "quiet_hours", "default_severity", "channels": [...], "policy": {...} }
# Missing pieces are simply absent. Usage:  owner.py [path]   (default ~/.agents/owner.md)
import json, os, re, sys

def parse_frontmatter(text):
    m = re.match(r'^---\s*\n(.*?)\n---\s*(?:\n|$)', text, re.S)
    return m.group(1) if m else ""

def strip_inline_comment(v):
    # drop a trailing ' # comment' but keep '#' inside quotes
    out, q = [], None
    for ch in v:
        if q:
            out.append(ch)
            if ch == q: q = None
        elif ch in "\"'":
            q = ch; out.append(ch)
        elif ch == '#':
            break
        else:
            out.append(ch)
    return ''.join(out).strip()

def unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        return v[1:-1]
    return v

def parse(fm):
    data = {"channels": [], "policy": {}}
    lines = fm.split('\n')
    i, n = 0, len(lines)
    while i < n:
        raw = lines[i]
        line = raw.rstrip()
        if not line.strip() or line.lstrip().startswith('#'):
            i += 1; continue
        indent = len(line) - len(line.lstrip())
        s = line.strip()
        if indent == 0 and s == 'channels:':
            i += 1
            while i < n:
                l = lines[i]
                st = l.strip()
                if not st or st.startswith('#'): i += 1; continue
                ind = len(l) - len(l.lstrip())
                if ind == 0: break                    # back to top level
                if st.startswith('- '):               # new channel map
                    ch = {}
                    k, _, v = st[2:].partition(':')
                    if _: ch[k.strip()] = coerce(unquote(strip_inline_comment(v)))
                    i += 1
                    while i < n:                        # indented keys of this map
                        l2 = lines[i]; st2 = l2.strip()
                        if not st2 or st2.startswith('#'): i += 1; continue
                        ind2 = len(l2) - len(l2.lstrip())
                        if ind2 <= ind or st2.startswith('- '): break
                        k2, _2, v2 = st2.partition(':')
                        if _2: ch[k2.strip()] = coerce(unquote(strip_inline_comment(v2)))
                        i += 1
                    data["channels"].append(ch)
                else:
                    i += 1
            continue
        if indent == 0 and s == 'policy:':
            i += 1
            while i < n:
                l = lines[i]; st = l.strip()
                if not st or st.startswith('#'): i += 1; continue
                ind = len(l) - len(l.lstrip())
                if ind == 0: break
                k, _, v = st.partition(':')
                if _:
                    v = strip_inline_comment(v).strip()
                    if v.startswith('[') and v.endswith(']'):
                        items = [x.strip() for x in v[1:-1].split(',') if x.strip()]
                        data["policy"][k.strip()] = items
                i += 1
            continue
        if indent == 0 and ':' in s:                   # top-level scalar
            k, _, v = s.partition(':')
            data[k.strip()] = coerce(unquote(strip_inline_comment(v)))
        i += 1
    return data

def coerce(v):
    if isinstance(v, str):
        if v.lower() == 'true': return True
        if v.lower() == 'false': return False
    return v

def derive(data):
    out = {
        "quiet_hours": data.get("quiet_hours", ""),
        "default_severity": data.get("default_severity", "normal"),
        "name": data.get("name", ""),
        "timezone": data.get("timezone", ""),
        "channels": data.get("channels", []),
        "policy": data.get("policy", {}),
    }
    for ch in data.get("channels", []):
        if ch.get("transport") == "openclaw" and "telegram" not in out:
            out["host"] = ch.get("host", "")
            out["telegram"] = {"account": ch.get("account", "default"),
                               "target": str(ch.get("target", ""))}
        if (ch.get("transport") == "twilio" or ch.get("id") == "call") and "call" not in out:
            out["call"] = {"cmd": ch.get("cmd", "")}
    return out

def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.agents/owner.md")
    try:
        text = open(path).read()
    except Exception:
        print("{}"); return
    print(json.dumps(derive(parse(parse_frontmatter(text)))))

if __name__ == "__main__":
    main()
