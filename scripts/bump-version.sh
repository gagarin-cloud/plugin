#!/usr/bin/env bash
# Bump the plugin's version in every manifest that carries one: Claude Code's
# plugin.json, the portable plugin.json and the marketplace entry. Claude Code
# re-installs when the number changes, and the ZIP for OpenAI's portal is named
# after it.
#
# Plain semver, tracking nothing. The version used to encode the gg release the
# skill was vendored from, back when it was a copy; the skill lives here now, so
# there is nothing to track and the number is simply ours.
set -euo pipefail

cd "$(dirname "$0")/.."

PLUGIN=plugin/.claude-plugin/plugin.json
PORTABLE=plugin/plugin.json
MARKET=.claude-plugin/marketplace.json

part=patch
[ $# -gt 0 ] && part=$1
case "$part" in
  major|minor|patch) ;;
  -h|--help) sed -n '2,9p' "$0"; echo; echo "usage: $0 [major|minor|patch]"; exit 0 ;;
  *) echo "usage: $0 [major|minor|patch]" >&2; exit 2 ;;
esac

current=$(jq -r .version "$PLUGIN")
IFS=. read -r ma mi pa <<< "$current"

case "$part" in
  major) new="$((ma + 1)).0.0" ;;
  minor) new="$ma.$((mi + 1)).0" ;;
  patch) new="$ma.$mi.$((pa + 1))" ;;
esac

tmp=$(mktemp); jq --arg v "$new" '.version = $v' "$PLUGIN" > "$tmp"; mv "$tmp" "$PLUGIN"
tmp=$(mktemp); jq --arg v "$new" '.version = $v' "$PORTABLE" > "$tmp"; mv "$tmp" "$PORTABLE"
tmp=$(mktemp); jq --arg v "$new" '(.plugins[] | select(.name=="gagarin") | .version) = $v' "$MARKET" > "$tmp"; mv "$tmp" "$MARKET"

echo "$current -> $new"
