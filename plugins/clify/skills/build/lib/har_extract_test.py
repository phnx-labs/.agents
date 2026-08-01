"""Tests for har_extract.py — the path-templating + dedup logic is the part that
can silently break, so it's what we cover. Run: python3 har_extract_test.py
"""
import json
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).parent
SCRIPT = HERE / "har_extract.py"
FIXTURE = HERE / "testdata" / "sample.har"


def run(*args):
    out = subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True, text=True, check=True,
    )
    return json.loads(out.stdout)


def test_collapses_ids_into_one_endpoint():
    cat = run(str(FIXTURE))
    keys = {(c["method"], c["host"], c["path_template"]) for c in cat}
    # /users/1 and /users/2 must collapse to a single templated endpoint...
    assert ("GET", "api.example.com", "/users/:id") in keys, keys
    # ...that recorded both hits.
    ep = next(c for c in cat if c["method"] == "GET" and c["path_template"] == "/users/:id")
    assert ep["count"] == 2, ep


def test_post_is_distinct_from_get_and_captures_body():
    cat = run(str(FIXTURE))
    post = next(c for c in cat if c["method"] == "POST" and c["path_template"] == "/users")
    assert post["request_sample"] == '{"name":"c"}', post
    assert post["query_keys"] == ["team"], post
    assert post["status"] == 201, post


def test_json_only_drops_html_and_images():
    full = run(str(FIXTURE))
    jsonly = run(str(FIXTURE), "--json-only")
    assert any(c["path_template"] == "/dashboard" for c in full)
    assert all(c["path_template"] != "/dashboard" for c in jsonly)
    assert all(c["path_template"] != "/logo.png" for c in jsonly)


def test_host_filter():
    cat = run(str(FIXTURE), "--host", "api.example.com")
    assert cat
    assert all(c["host"] == "api.example.com" for c in cat)


if __name__ == "__main__":
    failures = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print(f"ok   {name}")
            except AssertionError as e:
                failures += 1
                print(f"FAIL {name}: {e}")
    sys.exit(1 if failures else 0)
