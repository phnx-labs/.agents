#!/bin/bash
# Build default.yaml from the default preset manifest.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GROUPS_DIR="$SCRIPT_DIR/groups"
case "$#" in
  0)
    PRESET="$SCRIPT_DIR/presets/default.yaml"
    OUTPUT="$SCRIPT_DIR/default.yaml"
    OUTPUT_DIR="$SCRIPT_DIR"
    ;;
  2)
    PRESET="$1"
    OUTPUT="$2"
    OUTPUT_DIR="$(dirname "$OUTPUT")"
    if [ ! -d "$OUTPUT_DIR" ]; then
      echo "Error: output directory not found: $OUTPUT_DIR" >&2
      exit 2
    fi
    OUTPUT="$(cd "$OUTPUT_DIR" && pwd)/$(basename "$OUTPUT")"
    if [ "$OUTPUT" = "$SCRIPT_DIR/default.yaml" ]; then
      echo "Error: custom preset output cannot be default.yaml" >&2
      exit 2
    fi
    ;;
  *)
    echo "Usage: $0 [PRESET OUTPUT]" >&2
    exit 2
    ;;
esac
TEMP_OUTPUT=""

cleanup() {
  [ -z "$TEMP_OUTPUT" ] || rm -f "$TEMP_OUTPUT"
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

if [ ! -d "$GROUPS_DIR" ] || [ ! -f "$PRESET" ]; then
  echo "Error: permission groups or default preset not found"
  exit 1
fi

RUBY_BIN="$(command -v ruby 2>/dev/null || true)"
if [ -z "$RUBY_BIN" ]; then
  echo "Error: ruby is required to parse permission preset YAML" >&2
  exit 1
fi

TEMP_OUTPUT="$(mktemp "$OUTPUT.tmp.XXXXXX")"
"$RUBY_BIN" -rpsych -e '
  preset_path, groups_dir, output_path = ARGV

  begin
    preset = Psych.safe_load(
      File.binread(preset_path),
      permitted_classes: [],
      permitted_symbols: [],
      aliases: false,
      filename: preset_path,
    )
  rescue Psych::Exception => error
    warn "Error: invalid preset YAML: #{error.message}"
    exit 1
  end

  unless preset.is_a?(Hash)
    warn "Error: preset must be a YAML mapping"
    exit 1
  end

  includes = preset["includes"]
  unless includes.is_a?(Array)
    warn "Error: preset includes must be an array"
    exit 1
  end
  unless includes.all? { |entry| entry.is_a?(String) && !entry.empty? }
    warn "Error: preset includes entries must be nonempty strings"
    exit 1
  end

  seen = {}
  includes.each do |entry|
    if seen.key?(entry)
      warn "Error: duplicate preset include: #{entry}"
      exit 1
    end
    seen[entry] = true
  end

  invalid_include = includes.find { |entry| !/\A[0-9]{2}-[a-z0-9-]+\z/.match(entry) }
  unless invalid_include.nil?
    warn "Error: invalid preset include name: #{invalid_include}"
    exit 1
  end

  groups = includes.reject { |entry| entry == "00-local" }
  if groups.empty?
    warn "Error: default preset contains no groups"
    exit 1
  end

  File.open(output_path, "wb") do |output|
    groups.each do |group_name|
      group_path = File.join(groups_dir, "#{group_name}.yaml")
      unless File.file?(group_path)
        warn "Error: default preset references missing group #{group_name}"
        exit 1
      end
      output.write(File.binread(group_path))
    end
  end
' "$PRESET" "$GROUPS_DIR" "$TEMP_OUTPUT"

ALLOW_COUNT=$(grep -c '^[[:space:]]*-[[:space:]]*"' "$TEMP_OUTPUT" 2>/dev/null || true)
chmod 0644 "$TEMP_OUTPUT"
mv -f "$TEMP_OUTPUT" "$OUTPUT"
TEMP_OUTPUT=""
echo "Built $OUTPUT with $ALLOW_COUNT permission entries"
