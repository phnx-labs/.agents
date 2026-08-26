#!/bin/bash

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRATCH_DIR="$ROOT_DIR/.agents/scratch"
mkdir -p "$SCRATCH_DIR"
TEST_DIR="$(mktemp -d "$SCRATCH_DIR/permissions-test.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

RUBY_BIN="$(command -v ruby 2>/dev/null || true)"
[ -n "$RUBY_BIN" ] || fail "ruby is required to parse permission YAML"

assert_tracked_default_unchanged() {
  cmp -s "$TEST_DIR/tracked-default.before" "$SCRIPT_DIR/default.yaml" \
    || fail "$1 changed tracked default.yaml"
}

assert_no_temporary_output() {
  local output="$1"
  local leaked_temp

  for leaked_temp in "$output".tmp.*; do
    [ ! -e "$leaked_temp" ] || fail "failed build leaked temporary output $leaked_temp"
  done
}

expect_build_failure() {
  local preset="$1"
  local output="$2"
  local expected_message="$3"
  local label="$4"
  local stdout_path="$TEST_DIR/$label.stdout"
  local stderr_path="$TEST_DIR/$label.stderr"

  if /bin/bash "$SCRIPT_DIR/build.sh" "$preset" "$output" >"$stdout_path" 2>"$stderr_path"; then
    fail "build.sh accepted $label preset"
  fi
  grep -Fq "$expected_message" "$stderr_path" \
    || fail "$label failure did not contain: $expected_message"
  [ ! -e "$output" ] || fail "$label failure created its output"
  assert_no_temporary_output "$output"
  assert_tracked_default_unchanged "$label failure"
}

cp "$SCRIPT_DIR/default.yaml" "$TEST_DIR/tracked-default.before"
/bin/bash "$SCRIPT_DIR/build.sh" "$SCRIPT_DIR/presets/default.yaml" "$TEST_DIR/default-first.yaml" >/dev/null
/bin/bash "$SCRIPT_DIR/build.sh" "$SCRIPT_DIR/presets/default.yaml" "$TEST_DIR/default-second.yaml" >/dev/null
cmp -s "$TEST_DIR/default-first.yaml" "$TEST_DIR/default-second.yaml" \
  || fail "default preset output changed between consecutive scratch builds"
cmp -s "$TEST_DIR/default-first.yaml" "$SCRIPT_DIR/default.yaml" \
  || fail "tracked default.yaml is stale"
assert_tracked_default_unchanged "default scratch builds"
"$RUBY_BIN" -e 'abort "generated output mode is not 0644" unless (File.stat(ARGV.fetch(0)).mode & 0777) == 0644' "$TEST_DIR/default-first.yaml"
printf 'PASS tracked default.yaml is current without being rebuilt\n'

if /bin/bash "$SCRIPT_DIR/build.sh" "$SCRIPT_DIR/presets/sandbox.yaml" "$SCRIPT_DIR/./default.yaml" \
  >"$TEST_DIR/custom-default.stdout" 2>"$TEST_DIR/custom-default.stderr"; then
  fail "build.sh allowed a custom preset to overwrite default.yaml"
fi
assert_tracked_default_unchanged "rejected custom default output"
printf 'PASS custom preset cannot target default.yaml\n'

if /bin/bash "$SCRIPT_DIR/build.sh" "$SCRIPT_DIR/presets/sandbox.yaml" \
  >"$TEST_DIR/one-argument.stdout" 2>"$TEST_DIR/one-argument.stderr"; then
  fail "build.sh accepted a custom preset without an explicit output"
fi
grep -Fq 'Usage:' "$TEST_DIR/one-argument.stderr" \
  || fail "one-argument failure did not print usage"
assert_tracked_default_unchanged "one-argument failure"
printf 'PASS custom preset requires an explicit output without changing default.yaml\n'

cp "$SCRIPT_DIR/presets/default.yaml" "$TEST_DIR/missing-group-preset.yaml"
printf '  - 98-missing-regression-group\n' >> "$TEST_DIR/missing-group-preset.yaml"
expect_build_failure "$TEST_DIR/missing-group-preset.yaml" "$TEST_DIR/missing-output.yaml" \
  "missing group 98-missing-regression-group" "missing-group"
printf 'PASS missing later group fails without changing default.yaml\n'

/bin/bash "$SCRIPT_DIR/build.sh" "$SCRIPT_DIR/presets/sandbox.yaml" "$TEST_DIR/sandbox.yaml" >/dev/null
[ -s "$TEST_DIR/sandbox.yaml" ] || fail "custom sandbox build produced no output"
assert_no_temporary_output "$TEST_DIR/sandbox.yaml"
assert_tracked_default_unchanged "successful custom build"
printf 'PASS successful custom build writes only its explicit output\n'

cat >"$TEST_DIR/flow-array.yaml" <<'YAML'
includes: [00-header, 01-core]
YAML
/bin/bash "$SCRIPT_DIR/build.sh" "$TEST_DIR/flow-array.yaml" "$TEST_DIR/flow-array-output.yaml" >/dev/null
cat "$SCRIPT_DIR/groups/00-header.yaml" "$SCRIPT_DIR/groups/01-core.yaml" >"$TEST_DIR/flow-array-expected.yaml"
cmp -s "$TEST_DIR/flow-array-expected.yaml" "$TEST_DIR/flow-array-output.yaml" \
  || fail "flow-array preset did not preserve include order"
assert_no_temporary_output "$TEST_DIR/flow-array-output.yaml"
assert_tracked_default_unchanged "flow-array build"
printf 'PASS flow-array includes preserve order\n'

cat >"$TEST_DIR/top-level-sequence.yaml" <<'YAML'
- 00-header
YAML
expect_build_failure "$TEST_DIR/top-level-sequence.yaml" "$TEST_DIR/top-level-sequence-output.yaml" \
  "preset must be a YAML mapping" "top-level-sequence"

cat >"$TEST_DIR/missing-includes.yaml" <<'YAML'
name: missing-includes
YAML
expect_build_failure "$TEST_DIR/missing-includes.yaml" "$TEST_DIR/missing-includes-output.yaml" \
  "preset includes must be an array" "missing-includes"

cat >"$TEST_DIR/block-scalar.yaml" <<'YAML'
includes: |
  00-header
YAML
expect_build_failure "$TEST_DIR/block-scalar.yaml" "$TEST_DIR/block-scalar-output.yaml" \
  "preset includes must be an array" "block-scalar"

cat >"$TEST_DIR/empty-string.yaml" <<'YAML'
includes: [00-header, ""]
YAML
expect_build_failure "$TEST_DIR/empty-string.yaml" "$TEST_DIR/empty-string-output.yaml" \
  "preset includes entries must be nonempty strings" "empty-string"

cat >"$TEST_DIR/non-string.yaml" <<'YAML'
includes: [00-header, 42]
YAML
expect_build_failure "$TEST_DIR/non-string.yaml" "$TEST_DIR/non-string-output.yaml" \
  "preset includes entries must be nonempty strings" "non-string"

cat >"$TEST_DIR/alias.yaml" <<'YAML'
groups: &groups
  - 00-header
includes: *groups
YAML
expect_build_failure "$TEST_DIR/alias.yaml" "$TEST_DIR/alias-output.yaml" \
  "invalid preset YAML" "alias"
printf 'PASS malformed and aliased preset shapes fail closed without residue\n'

cat >"$TEST_DIR/duplicate-include.yaml" <<'YAML'
includes: [00-header, 00-header]
YAML
expect_build_failure "$TEST_DIR/duplicate-include.yaml" "$TEST_DIR/duplicate-include-output.yaml" \
  "duplicate preset include: 00-header" "duplicate-include"

cat >"$TEST_DIR/parent-include.yaml" <<'YAML'
includes: [../99-deny]
YAML
expect_build_failure "$TEST_DIR/parent-include.yaml" "$TEST_DIR/parent-include-output.yaml" \
  "invalid preset include name: ../99-deny" "parent-include"

cat >"$TEST_DIR/absolute-include.yaml" <<'YAML'
includes: [/tmp/99-deny]
YAML
expect_build_failure "$TEST_DIR/absolute-include.yaml" "$TEST_DIR/absolute-include-output.yaml" \
  "invalid preset include name: /tmp/99-deny" "absolute-include"

cat >"$TEST_DIR/child-include.yaml" <<'YAML'
includes: [30-paths/child]
YAML
expect_build_failure "$TEST_DIR/child-include.yaml" "$TEST_DIR/child-include-output.yaml" \
  "invalid preset include name: 30-paths/child" "child-include"

cat >"$TEST_DIR/dot-include.yaml" <<'YAML'
includes: [.]
YAML
expect_build_failure "$TEST_DIR/dot-include.yaml" "$TEST_DIR/dot-include-output.yaml" \
  "invalid preset include name: ." "dot-include"

cat >"$TEST_DIR/dot-dot-include.yaml" <<'YAML'
includes: [..]
YAML
expect_build_failure "$TEST_DIR/dot-dot-include.yaml" "$TEST_DIR/dot-dot-include-output.yaml" \
  "invalid preset include name: .." "dot-dot-include"

cat >"$TEST_DIR/extension-include.yaml" <<'YAML'
includes: [30-paths.extra]
YAML
expect_build_failure "$TEST_DIR/extension-include.yaml" "$TEST_DIR/extension-include-output.yaml" \
  "invalid preset include name: 30-paths.extra" "extension-include"
printf 'PASS duplicate and unsafe include names fail before publication without residue\n'

"$RUBY_BIN" - "$SCRIPT_DIR" <<'RUBY'
require "psych"

def load_yaml(path)
  Psych.safe_load(
    File.binread(path),
    permitted_classes: [],
    permitted_symbols: [],
    aliases: false,
    filename: path,
  )
end

permissions_dir = ARGV.fetch(0)
blanket_allows = load_yaml(File.join(permissions_dir, "groups", "30-paths.yaml"))
deny_path = File.join(permissions_dir, "groups", "99-deny.yaml")
deny_document = load_yaml(deny_path)
raise "99-deny: document is not a mapping" unless deny_document.is_a?(Hash)
denies = deny_document.fetch("deny")
raise "99-deny: deny is not an array" unless denies.is_a?(Array)
raise "99-deny: deny entries must be strings" unless denies.all? { |rule| rule.is_a?(String) }
raise "99-deny: deny matrix is empty" if denies.empty?
raise "99-deny: Bash deny remains" if denies.any? { |rule| rule.start_with?("Bash(") }
raise "99-deny: duplicate rules" unless denies.uniq == denies
raise "99-deny: incomplete Read/Edit/Write triplet" unless (denies.length % 3).zero?

credential_paths = denies.each_slice(3).map do |triplet|
  parsed = triplet.map do |rule|
    match = /\A(Read|Edit|Write)\((.+)\)\z/.match(rule)
    raise "99-deny: invalid file-tool rule #{rule.inspect}" if match.nil?
    [match[1], match[2]]
  end
  tools = parsed.map(&:first)
  paths = parsed.map(&:last)
  raise "99-deny: triplet tool order is #{tools.inspect}" unless tools == %w[Read Edit Write]
  raise "99-deny: triplet paths differ #{paths.inspect}" unless paths.uniq.length == 1
  paths.first
end
raise "99-deny: duplicate credential paths" unless credential_paths.uniq == credential_paths

presets = {}
["default", "sandbox"].each do |preset_name|
  preset_path = File.join(permissions_dir, "presets", "#{preset_name}.yaml")
  preset = load_yaml(preset_path)
  presets[preset_name] = preset
  includes = preset.fetch("includes")

  raise "#{preset_name}: missing 30-paths" unless includes.include?("30-paths")
  deny_includes = includes.select { |name| name.start_with?("99-deny") }
  raise "#{preset_name}: deny include must be exactly 99-deny, got #{deny_includes.inspect}" unless deny_includes == ["99-deny"]
  raise "#{preset_name}: missing 12-self" unless includes.include?("12-self")
  raise "#{preset_name}: references nonexistent 16-mcp" if includes.include?("16-mcp")
  raise "#{preset_name}: duplicate manifest entries" unless includes.uniq == includes
  includes.each do |group_name|
    next if group_name == "00-local"
    group_path = File.join(permissions_dir, "groups", "#{group_name}.yaml")
    raise "#{preset_name}: missing group #{group_name}" unless File.file?(group_path)
  end

  %w[Bash Read Write Edit].each do |tool|
    raise "#{preset_name}: missing blanket #{tool}" unless blanket_allows.include?(tool)
  end

  puts "PASS #{preset_name} preset has blanket tools and the canonical ordered credential matrix"
end
obsolete_deny_name = ["99-deny", "sandbox"].join("-")
raise "obsolete sandbox deny group remains" if File.exist?(File.join(permissions_dir, "groups", "#{obsolete_deny_name}.yaml"))

default_common = presets.fetch("default").fetch("includes") - ["00-local", "99-deny"]
sandbox_common = presets.fetch("sandbox").fetch("includes") - ["99-deny"]
raise "default and sandbox manifests drifted" unless default_common == sandbox_common
puts "PASS default and sandbox manifests have identical shared groups"

default_groups = presets.fetch("default").fetch("includes").reject { |name| name == "00-local" }
expected_default = default_groups.map do |group_name|
  File.binread(File.join(permissions_dir, "groups", "#{group_name}.yaml"))
end.join
generated_default = File.binread(File.join(permissions_dir, "default.yaml"))
raise "default.yaml differs from the default preset manifest" unless generated_default == expected_default
puts "PASS default.yaml exactly matches the default preset manifest"
load_yaml(File.join(permissions_dir, "default.yaml"))
puts "PASS generated and source permission YAML parses"

maintenance_contract = File.read(File.join(permissions_dir, "AGENTS.md"))
raise "OpenCode blanket Read translation is inaccurate" unless maintenance_contract.include?('| `"Read"` | same | `{ "*": "allow" }` | n/a |')
raise "OpenCode credential Read translation is inaccurate" unless maintenance_contract.include?('| `deny: "Read(~/.ssh/**)"` | same | `{ "~/.ssh/**": "deny" }` | n/a |')
raise "OpenCode no-read-gating claim remains" if maintenance_contract.include?("no read gating")
puts "PASS OpenCode read translations match its ordered permission map"
RUBY

guard_path="$ROOT_DIR/hooks/pre-tool-use/12-direct-file-credential-guard.sh"
[ -x "$guard_path" ] || fail "direct-file credential guard is missing or not executable"
grep -qF 'permissions/groups/99-deny.yaml' "$guard_path" || fail "direct-file credential guard does not derive from 99-deny.yaml"
grep -qF 'script: pre-tool-use/12-direct-file-credential-guard.sh' "$ROOT_DIR/agents.yaml" || fail "direct-file credential guard is not registered"
grep -qF 'matcher: ^(Read|read_file|Edit|edit_file|search_replace|MultiEdit|Write|write_file)$' "$ROOT_DIR/agents.yaml" || fail "direct-file credential guard matcher is incomplete or unanchored"
printf 'PASS canonical credential matrix is enforced by the registered direct-file guard\n'

protected_changes="$(GIT_MASTER=1 git -C "$ROOT_DIR" status --porcelain -- \
  hooks/pre-tool-use/git-guard.sh \
  hooks/pre-tool-use/rm-guard.sh \
  hooks/pre-tool-use/secrets-guard.sh \
  hooks/pre-tool-use/large-file-add-guard.sh \
  hooks/pre-tool-use/public-artifact-guard.sh \
  rules/subrules/truly-agentic-git-workflow/main-branch-guard.sh \
  rules/subrules/truly-agentic-git-workflow/hooks.yaml \
  rules/subrules/gh-merge-guard/merge-guard.sh \
  rules/subrules/gh-merge-guard/hooks.yaml)"
[ -z "$protected_changes" ] || fail "existing destructive hook code changed"
printf 'PASS existing destructive hook code is outside the diff\n'

printf 'PASS permissions regression contract\n'
