#!/usr/bin/env bash
# The repository's own invariants: the manifests agree with each other, every
# skill has the frontmatter a host needs to load it, and the plugin folder is
# something both directories — Anthropic's and OpenAI's — will accept.
#
# Whether the skills agree with gg is a separate question and a separate script,
# because it needs a gg binary; see check-skill-against-gg.sh.
#
# Needs jq, curl and node (for npx). SKIP_SCHEMA=1 skips the schema validation,
# which fetches the Agent Plugins schemas; everything else runs offline.
set -euo pipefail
cd "$(dirname "$0")/.."

# The repository root is the marketplace; ROOT is the plugin folder it lists,
# which is what the directories read and what people install.
ROOT=plugin
PLUGIN=$ROOT/.claude-plugin/plugin.json      # Claude Code
PORTABLE=$ROOT/plugin.json                   # Agent Plugins 1.0 + OpenAI
MCP=$ROOT/.mcp.json                          # Claude Code
MCPJ=$ROOT/mcp.json                          # Agent Plugins
MARKET=.claude-plugin/marketplace.json       # Claude Code, and Codex's legacy path
CODEX_MARKET=.agents/plugins/marketplace.json
REFERENCE=$ROOT/skills/gagarin/SKILL.md
ENDPOINT="https://mcp.gagarin.cloud/mcp"
# 1.0.0, not 1.1.0: the newer schema exists in the spec repository but is not
# published at agent-plugins.org yet, and OpenAI's portal names 1.0.0. The
# difference that matters is that 1.0.0 allows no \`extensions\` on a server, so
# mcp.json carries no OAuth hints; ChatGPT finds the authorization server
# through RFC 9728 discovery regardless.
SCHEMA_BASE="https://agent-plugins.org/schemas/1.0.0"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok  $*"; }

frontmatter() { awk '/^---$/{n++; next} n==1' "$1"; }

# grep -rnE over the Markdown in the given directories. Exit 1 is "nothing
# found"; anything above is an error, which must not read as a clean scan. BSD
# grep exits 1 for a missing path too, so check the directories first.
grep_md() {
  local pattern=$1 rc=0 out d
  shift
  for d in "$@"; do [ -d "$d" ] || fail "no $d/ to scan"; done
  out=$(grep -rnE "$pattern" --include='*.md' "$@") || rc=$?
  [ "$rc" -le 1 ] || fail "grep could not scan $*"
  printf '%s' "$out"
}

# A PNG's width and height: the IHDR's first two big-endian words, bytes 16 to 23.
png_dims() {
  [ "$(od -An -tx1 -N8 "$1" | tr -d ' \n')" = "89504e470d0a1a0a" ] || fail "$1 is not a PNG"
  od -An -tu1 -j16 -N8 "$1" | tr -s ' \n' ' ' \
    | awk '{print $1*16777216+$2*65536+$3*256+$4, $5*16777216+$6*65536+$7*256+$8}'
}

for f in "$PLUGIN" "$PORTABLE" "$MCP" "$MCPJ" "$MARKET" "$CODEX_MARKET"; do
  [ -f "$f" ] || fail "missing $f"
  jq empty "$f" 2>/dev/null || fail "invalid JSON: $f"
done
ok "JSON parses"

# ─── one version, one plugin, one endpoint ──────────────────────────────────

pv=$(jq -r .version "$PLUGIN")
xv=$(jq -r .version "$PORTABLE")
mv=$(jq -r '.plugins[] | select(.name=="gagarin") | .version' "$MARKET")

# Strict semver, no prerelease or build metadata: Claude Code only re-installs
# when this changes, OpenAI wants "an explicit semantic version", and anything
# exotic is a bet on how two hosts compare two of them.
echo "$pv" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
  || fail "plugin.json version '$pv' is not strict semver"
ok "version $pv is strict semver"

# A manifest disagreeing with another advertises a version somebody does not get.
[ "$pv" = "$xv" ] || fail "version mismatch: .claude-plugin/plugin.json=$pv plugin.json=$xv (scripts/bump-version.sh moves all three)"
[ "$pv" = "$mv" ] || fail "version mismatch: .claude-plugin/plugin.json=$pv marketplace.json=$mv"
[ "$(jq -r .name "$PLUGIN")" = gagarin ] && [ "$(jq -r .name "$PORTABLE")" = gagarin ] \
  || fail "both manifests must name the plugin 'gagarin'"
src=$(jq -r '.plugins[] | select(.name=="gagarin") | .source' "$MARKET")
[ "$src" = "./$ROOT" ] || fail "$MARKET source is '$src', not './$ROOT'"
csrc=$(jq -r '.plugins[] | select(.name=="gagarin") | .source.path' "$CODEX_MARKET")
[ "$csrc" = "./$ROOT" ] || fail "$CODEX_MARKET source.path is '$csrc', not './$ROOT'"
[ "$(jq -r .name "$MARKET")" = "$(jq -r .name "$CODEX_MARKET")" ] \
  || fail "the two marketplaces must share a name: it is the half after @ in 'gagarin@gagarin-cloud'"
jq -e '.plugins[] | select(.name=="gagarin") | .policy.installation and .policy.authentication and .category' "$CODEX_MARKET" >/dev/null \
  || fail "$CODEX_MARKET entry needs policy.installation, policy.authentication and category"
ok "manifests and marketplaces agree"

# The endpoint is the one thing a user cannot override; assert it verbatim, in
# both shapes. The portable one declares exactly one remote server, over
# streamable HTTP, with no headers: OpenAI's portal rejects a nonempty headers
# object, and a header here would be a credential in a public file.
jq -e --arg u "$ENDPOINT" '.mcpServers.gagarin.url == $u' "$MCP" >/dev/null \
  || fail "$MCP does not point at $ENDPOINT"
jq -e --arg u "$ENDPOINT" '
    (.mcpServers | length) == 1
    and .mcpServers.gagarin.type == "streamable-http"
    and .mcpServers.gagarin.url == $u
    and (.mcpServers.gagarin | has("headers") | not)' "$MCPJ" >/dev/null \
  || fail "$MCPJ must declare exactly one streamable-http server at $ENDPOINT, with no headers"
ok "mcp endpoint"

# ─── skills ─────────────────────────────────────────────────────────────────

# A skill's name must match its directory or clients skip it silently, and the
# description is what makes a host pick it: it had better say something.
skills=()
for f in $ROOT/skills/*/SKILL.md; do
  skills+=("$f")
  dir=$(basename "$(dirname "$f")")
  fm=$(frontmatter "$f")
  grep -qx "name: $dir" <<< "$fm" || fail "$f: frontmatter name must be '$dir', the directory it is in"
  grep -qE '^description: .{40,}' <<< "$fm" || fail "$f needs a description of real length"
done
[ -f "$REFERENCE" ] || fail "the reference skill $REFERENCE is missing"
ok "${#skills[@]} skills, each named for its directory"

# A skill is already a slash command in Claude Code and the only component Codex
# has. A command or an agent that wraps one would list the same thing twice.
for d in commands agents; do
  [ ! -e "$ROOT/$d" ] || fail "$ROOT/$d/ exists; procedures live in skills/ and nowhere else"
done
ok "no commands/ or agents/ beside the skills"

# ─── what Anthropic's directory review raised ───────────────────────────────

# The directory accepts scripts and programs only from organizations it has
# Verified, and there is no way to ask to become one. So the plugin folder holds
# Markdown, text, JSON, YAML and images, nothing starting with "#!", and the
# repository's own tooling lives outside it (scripts/, .github/).
while IFS= read -r f; do
  case "$f" in
    *.md|*.txt|*.json|*.yml|*.yaml|*/LICENSE|*/NOTICE|*/CHANGELOG|*.png|*.jpg|*.jpeg|*.gif|*.webp|*.ico) ;;
    *) fail "$f: the directory accepts only Markdown, text, JSON, YAML and images in the plugin folder" ;;
  esac
  case "$f" in
    *.png|*.jpg|*.jpeg|*.gif|*.webp|*.ico) continue ;;
  esac
  [ "$(head -c 2 "$f")" != "#!" ] || fail "$f: starts with #!; the directory refuses scripts"
  iconv -f UTF-8 -t UTF-8 "$f" >/dev/null 2>&1 || fail "$f: not UTF-8"
  # A NUL cannot survive a shell variable, so count them instead of grepping.
  [ "$(LC_ALL=C tr -cd '\0' < "$f" | wc -c)" -eq 0 ] || fail "$f: holds a NUL byte"
done < <(git ls-files --cached --others --exclude-standard "$ROOT")
ok "plugin folder holds only text and images"

# The plugin folder ships its own copy of the license, so the directories and an
# installed plugin see one; keep it the same file as the repository's.
cmp -s LICENSE "$ROOT/LICENSE" || fail "$ROOT/LICENSE differs from LICENSE; copy it over"
ok "license copy agrees"

# A frontmatter key the directory does not know is refused outright. Its list is
# not public; this is the Claude Code reference's set less what hands a component
# more power than text. Loosen it only when a re-validation has shown the key is
# accepted.
frontmatter_keys() { frontmatter "$1" | grep -oE '^[A-Za-z_][A-Za-z0-9_-]*:' | tr -d :; }
for f in "${skills[@]}"; do
  for k in $(frontmatter_keys "$f"); do
    case " name description allowed-tools " in
      *" $k "*) ;;
      *) fail "$f: frontmatter key '$k' is not one the directory accepts in skill frontmatter (name description allowed-tools)" ;;
    esac
  done
done
ok "frontmatter keys"

# Anything an agent is told to run must be a tool the user already has, never
# something fetched and piped into a shell: what runs then is not what was
# reviewed. The README may say it, for humans; the skills may not.
MD="$ROOT/skills"
FETCH='(curl|wget|irm|iwr|Invoke-RestMethod|Invoke-WebRequest)'
RUN='(sudo[[:space:]]+)?(sh|bash|zsh|dash|iex|pwsh|powershell|python3?|node|perl|ruby)'
for pattern in \
  "\\|[[:space:]]*${RUN}([[:space:]]|\`|\$)" \
  "(<|\\$)\\([[:space:]]*${FETCH}[[:space:]]" \
  "iex[[:space:]]*\\([[:space:]]*${FETCH}[[:space:]]" \
  "${FETCH}[[:space:]][^\`]*(-[A-Za-z]*[oO]|--output|-OutFile)[[:space:]][^\`]*(&&|;)[[:space:]]*(${RUN}[[:space:]]|\\./|&)"; do
  hits=$(grep_md "$pattern" $MD)
  [ -z "$hits" ] || fail "downloaded code run straight away; use a package manager or hand the one-liner to the user:
$hits"
done
ok "no download-and-run"

# allowed-tools runs what it names without asking the user, and the directory
# refuses anything beyond these from an organization it has not Verified.
for f in "${skills[@]}"; do
  line=$(frontmatter "$f" | grep -E '^allowed-tools:' || true)
  [ -n "$line" ] || continue
  tools=${line#allowed-tools:}
  [ -n "${tools// /}" ] || fail "$f: allowed-tools as a YAML list is not checked here; write it on one line"
  # One entry is a tool name with an optional (rule), which may hold spaces.
  while read -r t; do
    case "$t" in
      Read|Grep|Glob|LS) ;;
      *) fail "$f: allowed-tools pre-approves '$t'; only Read, Grep, Glob and LS are allowed" ;;
    esac
  done < <(echo "$tools" | grep -oE '[A-Za-z_]+(\([^)]*\))?')
done
ok "allowed-tools is read-only"

# A !`…` span runs before Claude sees the file, and aborts the command outside
# auto mode unless allowed-tools pre-approves it, which the check above forbids.
# Claude Code only recognises one at the start of a line or after whitespace.
hits=$(grep_md '(^|[[:space:]])!`|^```!' $MD)
[ -z "$hits" ] || fail "inline shell span; tell the agent to run the command instead:
$hits"
ok "no inline shell spans"

# The Claude listing icon: a square PNG, 512 to 2048 px a side, under 2 MB.
icon=$(jq -r '.icon // empty' "$PLUGIN")
[ -n "$icon" ] || fail "$PLUGIN has no icon"
icon=$ROOT/${icon#./}
[ -f "$icon" ] || fail "icon $icon does not exist"
read -r w h <<< "$(png_dims "$icon")"
[ "$w" = "$h" ] || fail "icon is ${w}x${h}, not square"
[ "$w" -ge 512 ] && [ "$w" -le 2048 ] || fail "icon is ${w} px a side, not 512 to 2048"
[ "$(wc -c < "$icon")" -lt 2097152 ] || fail "icon is 2 MB or more"
ok "icon ${w}x${h}"

for k in privacyPolicyUrl termsOfServiceUrl; do
  jq -e --arg k "$k" '.[$k] | type == "string" and startswith("https://")' "$PLUGIN" >/dev/null \
    || fail "$PLUGIN $k must be an https:// URL"
done
ok "privacy and terms links"

# ─── what OpenAI's plugin portal requires ───────────────────────────────────

OAI='.extensions["com.openai"]'

# A ZIP carrying app references or lifecycle hooks cannot be submitted at all,
# and these are the shapes they take.
for p in "$ROOT/hooks" "$ROOT/.app.json" "$ROOT/.codex-plugin"; do
  [ ! -e "$p" ] || fail "$p exists; hooks and app references make the plugin ineligible for the directory, and a .codex-plugin overlay is ignored once extensions.com.openai is set"
done
jq -e "$OAI | (has(\"apps\") or has(\"hooks\")) | not" "$PORTABLE" >/dev/null \
  || fail "$PORTABLE: extensions.com.openai must not declare apps or hooks"
ok "no hooks or app references"

# The onboarding skill runs after installation; it must be one of ours.
onboarding=$(jq -r "$OAI.onboardingSkill // empty" "$PORTABLE")
[ -n "$onboarding" ] || fail "$PORTABLE: extensions.com.openai.onboardingSkill is missing"
[ -f "$ROOT/${onboarding#./}" ] || fail "onboardingSkill $onboarding does not exist"
ok "onboarding skill"

# The listing: names fit their boxes, every URL is HTTPS, both images exist and
# are square.
I="$OAI.interface"
for k in displayName shortDescription; do
  n=$(jq -r "$I.$k // \"\" | length" "$PORTABLE")
  [ "$n" -ge 1 ] && [ "$n" -le 30 ] || fail "$PORTABLE: interface.$k must be 1 to 30 characters (is $n)"
done
n=$(jq -r "$I.longDescription // \"\" | length" "$PORTABLE")
[ "$n" -ge 1 ] && [ "$n" -le 4000 ] || fail "$PORTABLE: interface.longDescription must be 1 to 4000 characters (is $n)"
for k in developerName category; do
  [ -n "$(jq -r "$I.$k // empty" "$PORTABLE")" ] || fail "$PORTABLE: interface.$k is missing"
done
for k in websiteURL supportURL privacyPolicyURL termsOfServiceURL; do
  jq -e "$I.$k | type == \"string\" and startswith(\"https://\")" "$PORTABLE" >/dev/null \
    || fail "$PORTABLE: interface.$k must be an https:// URL"
done
jq -e "$I.defaultPrompt | type == \"array\" and length >= 1 and all(type == \"string\" and length > 0)" "$PORTABLE" >/dev/null \
  || fail "$PORTABLE: interface.defaultPrompt must be a non-empty array of strings"
jq -e "$I.brandColor | test(\"^#[0-9a-fA-F]{6}$\")" "$PORTABLE" >/dev/null \
  || fail "$PORTABLE: interface.brandColor must be a #rrggbb colour"
jq -e "$I.capabilities | type == \"array\" and length >= 1" "$PORTABLE" >/dev/null \
  || fail "$PORTABLE: interface.capabilities must be a non-empty array"
for k in composerIcon logo; do
  img=$(jq -r "$I.$k // empty" "$PORTABLE")
  [ -n "$img" ] || fail "$PORTABLE: interface.$k is missing"
  case "$img" in ./assets/*) ;; *) fail "interface.$k must live under ./assets/ (is $img)" ;; esac
  img=$ROOT/${img#./}
  [ -f "$img" ] || fail "$k $img does not exist"
  read -r w h <<< "$(png_dims "$img")"
  [ "$w" = "$h" ] || fail "$k is ${w}x${h}, not square"
  [ "$w" -ge 48 ] && [ "$w" -le 4096 ] || fail "$k is ${w} px a side, not 48 to 4096"
  [ "$(wc -c < "$img")" -lt 5242880 ] || fail "$k is 5 MiB or more"
  ok "$k ${w}x${h}"
done
ok "listing fits the portal"

# Review material: exactly five positive and three negative cases, each with a
# description and a prompt, the positives with the tools they trigger and the
# behaviour expected. The portal rejects reviewer credentials and instructions
# in the ZIP — they go in the dashboard form — and a client secret anywhere.
R="$OAI.review"
[ "$(jq "$R.test_cases.positive | length" "$PORTABLE")" = 5 ] || fail "$PORTABLE: review needs exactly five positive test cases"
[ "$(jq "$R.test_cases.negative | length" "$PORTABLE")" = 3 ] || fail "$PORTABLE: review needs exactly three negative test cases"
jq -e "$R.test_cases.positive | all(.description and .prompt and .tools_triggered and .expected_behavior | . != null and . != \"\")" "$PORTABLE" >/dev/null \
  || fail "$PORTABLE: every positive case needs description, prompt, tools_triggered and expected_behavior"
jq -e "$R.test_cases.negative | all(.description and .prompt | . != null and . != \"\")" "$PORTABLE" >/dev/null \
  || fail "$PORTABLE: every negative case needs description and prompt"
jq -e "$R.demo_recording_url | type == \"string\" and startswith(\"https://\")" "$PORTABLE" >/dev/null \
  || fail "$PORTABLE: review.demo_recording_url must be an https:// URL"
jq -e "$R.commerce == false" "$PORTABLE" >/dev/null || fail "$PORTABLE: review.commerce must be false; nothing is sold through the plugin"
for k in test_credentials reviewer_instructions clientSecret client_secret; do
  ! grep -q "\"$k\"" "$PORTABLE" "$MCPJ" || fail "'$k' belongs in the dashboard form, never in the package"
done
! grep -qiE 'bearer [A-Za-z0-9_-]{8,}|"authorization"' "$PORTABLE" "$MCPJ" "$MCP" \
  || fail "a credential-shaped string is in a manifest; this repository is public"
ok "review material"

# The two portable files validate against the Agent Plugins schemas they name.
# The schemas are fetched, not vendored: the point is to notice when upstream
# moves, which a copy here would hide.
if [ -z "${SKIP_SCHEMA:-}" ]; then
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  for s in plugin mcp; do
    curl -fsSL "$SCHEMA_BASE/$s.schema.json" -o "$tmp/$s.schema.json" || fail "could not fetch $SCHEMA_BASE/$s.schema.json (SKIP_SCHEMA=1 to skip)"
  done
  [ "$(jq -r '."$schema"' "$PORTABLE")" = "$SCHEMA_BASE/plugin.schema.json" ] || fail "$PORTABLE names a schema other than $SCHEMA_BASE/plugin.schema.json"
  [ "$(jq -r '."$schema"' "$MCPJ")" = "$SCHEMA_BASE/mcp.schema.json" ] || fail "$MCPJ names a schema other than $SCHEMA_BASE/mcp.schema.json"
  npx --yes ajv-cli@5 validate --spec=draft2020 -s "$tmp/plugin.schema.json" -d "$PORTABLE" >/dev/null 2>"$tmp/err" \
    || fail "$PORTABLE does not validate against the Agent Plugins schema:
$(cat "$tmp/err")"
  npx --yes ajv-cli@5 validate --spec=draft2020 -s "$tmp/mcp.schema.json" -d "$MCPJ" >/dev/null 2>"$tmp/err" \
    || fail "$MCPJ does not validate against the Agent Plugins schema:
$(cat "$tmp/err")"
  ok "portable manifests validate against the schemas"
else
  echo "  --  schema validation skipped (SKIP_SCHEMA set)"
fi

echo "All checks passed."
