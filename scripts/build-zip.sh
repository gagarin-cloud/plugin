#!/usr/bin/env bash
# Package the plugin folder as the ZIP OpenAI's plugin submission portal takes.
#
# The ZIP holds the portable plugin and nothing else: plugin.json, mcp.json,
# skills/, assets/, README.md and LICENSE. Claude Code's manifests stay out —
# the portal reads plugin.json, and a stray .mcp.json beside mcp.json is one
# file too many to explain. The listing is checked against that allowlist
# afterwards, so a new file in the plugin folder is a decision here, not an
# accident in the upload.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT=plugin
version=$(jq -r .version "$ROOT/plugin.json")
out="dist/gagarin-plugin-$version.zip"

mkdir -p dist
rm -f "$out"
# From the index, not the working tree: check.sh validated what git knows
# about, and a gitignored scratch file whose name fits the allowlist must not
# ship unreviewed because it happened to be on disk.
(cd "$ROOT" && git ls-files -- plugin.json mcp.json skills assets README.md LICENSE | zip -q -X -D "../$out" -@)

bad=$(unzip -Z1 "$out" | grep -vE '^(plugin\.json|mcp\.json|README\.md|LICENSE|skills/[^/]+/|skills/[^/]+/SKILL\.md|assets/|assets/[^/]+\.png)$' || true)
if [ -n "$bad" ]; then
  echo "FAIL: the ZIP holds files the allowlist does not name:" >&2
  echo "$bad" >&2
  exit 1
fi

echo "$out ($(du -h "$out" | cut -f1 | tr -d ' '))"
