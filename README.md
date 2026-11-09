# gagarin-cloud/plugin

The [Gagarin](https://gagarin.cloud) plugin — one folder that Claude Code, Codex
and ChatGPT all install — and the marketplace that serves it. The plugin itself
is in [`plugin/`](plugin/), and its [README](plugin/README.md) is the one for
users: what it gives you, how to install it in each host, how to install `gg`,
privacy.

```
/plugin marketplace add gagarin-cloud/plugin        # Claude Code
/plugin install gagarin@gagarin-cloud

codex plugin marketplace add gagarin-cloud/plugin   # Codex CLI
```

In ChatGPT and the Codex app, search the Plugins Directory for Gagarin.

This repository used to be `gagarin-cloud/claude-plugin`. It was renamed on
2026-11-09 when the same folder started serving OpenAI's hosts too; the old
repository still exists and still installs, but is not updated.

## Layout

One tree, two manifest formats. Anthropic reads `.claude-plugin/plugin.json`
and `.mcp.json`; OpenAI and everything that speaks
[Agent Plugins](https://agent-plugins.org) read `plugin.json` and `mcp.json`.
Both read `skills/`. Anthropic's directory accepts only Markdown, text, JSON,
YAML and images from an organization it has not Verified, and nothing that
starts with `#!`, so the plugin folder holds exactly that and everything else
about this repository lives beside it:

- `plugin/` — the plugin: both manifests, the skills, the icons, README and
  license. This is what the directories read and what people install.
- `.claude-plugin/marketplace.json` — the marketplace, with `plugin/` as its
  one entry. Codex reads this path too.
- `.agents/plugins/marketplace.json` — the same entry in Codex's native shape,
  which carries an install policy and a category the Claude one does not.
- `scripts/` — the checks below, `bump-version.sh` and `build-zip.sh`.
- `.github/workflows/ci.yml` — runs them, and uploads the ZIP for OpenAI's
  portal as an artifact on every push to `main`.
- `skills.sh.json` — tells `npx skills add` to install the reference skill
  only, so the short-named ones below do not land in `~/.agents/skills/`.

## Five skills, no commands, no agents

`plugin/skills/gagarin/SKILL.md` is the reference: the whole product written
for an agent. Beside it, four procedures — `setup`, `ship`, `status`, `ci` —
that used to be Claude Code commands and subagents. They are skills now because
a skill is the one component every host has: in Claude Code a plugin skill is
already `/gagarin:setup`, Codex has nothing else, and ChatGPT loads them with
the MCP server. A command or an agent that wrapped one would list the same
thing twice, so there are none, and `scripts/check.sh` refuses a `commands/` or
`agents/` directory.

The skill used to ship inside the `gg` binary, on the reasoning that
co-location stopped it describing a flag the CLI did not have. It did not
really: shipping together is not the same as agreeing. So `gg` no longer
carries it, and CI checks the thing that was actually wanted —
`scripts/check-skill-against-gg.sh` installs the latest released `gg`, reads
its command tree, and fails if any skill names a command, subcommand or flag
that does not exist. It runs on every change and once a day, because the skills
can go stale without anyone touching this repo.

The consequence to keep in mind: **the skill can be newer than someone's
`gg`.** It says which version it assumes, and tells an agent to check
`gg version` before concluding a command does not exist.

## Checks

`scripts/check.sh` is the repository's own invariants plus every finding either
directory review has raised, replayed so none of them comes back unnoticed: the
three versions agree, the endpoint is the one endpoint, every skill is named
for its directory, the file types the plugin folder may hold, the frontmatter
keys a skill may carry, no download-and-run in anything an agent is told to
do, read-only `allowed-tools`, the icons' shapes, the listing's length limits
and HTTPS links, exactly five positive and three negative review cases, no
hooks or app references (which make a ZIP ineligible), nothing
credential-shaped in a manifest, and both portable files validated against the
Agent Plugins schemas with `ajv`. The portal's rules are
`scripts/check_portable_manifest.py`, and `test_check_portable_manifest.py`
feeds each one the manifest that breaks it — a check nothing has ever seen
fail is not a check. `claude plugin validate .` covers Anthropic's
manifests, and `claude plugin validate ./plugin --strict` is the run its portal
mirrors.

`scripts/build-zip.sh` packages `plugin/` as the ZIP OpenAI's portal takes —
`plugin.json`, `mcp.json`, `skills/`, `assets/`, README and license, nothing
else — and fails if the listing holds anything the allowlist does not name.

`scripts/bump-version.sh [major|minor|patch]` moves the version in all three
manifests, which is what makes Claude Code re-install for people who have it
and names the next ZIP.

## Submitting to OpenAI's directory

The ZIP is the package; the rest happens at platform.openai.com/plugins and
needs a verified developer identity, a reviewer account that can sign in to
Gagarin without MFA, the demo video `review.demo_recording_url` points at, and
the domain-verification token the portal shows, which `mcp.gagarin.cloud`
serves at `/.well-known/openai-apps-challenge` once it is set in the server's
environment. The MCP server itself is rescanned by OpenAI daily, so a tool
change there goes live without a new ZIP; a change to anything in `plugin/`
is a new ZIP and a new review.

## License

MIT.
