# The Gagarin plugin

[Gagarin](https://gagarin.cloud) runs your containers on managed infrastructure.
There are no manifest files and no config files: the API is the only way state
changes, which is why neither you nor your agent can ever be out of sync with
what is actually running.

One plugin, three hosts:

| | |
|---|---|
| **Claude Code** | `/plugin marketplace add gagarin-cloud/plugin` then `/plugin install gagarin@gagarin-cloud` |
| **Codex CLI** | `codex plugin marketplace add gagarin-cloud/plugin`, then `/plugins` |
| **ChatGPT, Codex app** | search the Plugins Directory for *Gagarin Cloud* |

That gives you two things:

- **The skills.** `gagarin` is the whole product, written for an agent: the
  model, every command, every error code, and the mistakes worth not making.
  Beside it, four procedures: **`setup`** installs `gg` and signs you in,
  **`ship`** takes a repository to a working HTTPS URL, **`status`** reads what
  is actually running, **`ci`** wires a pipeline to deploy on push with a
  credential that can deploy but never destroy. In Claude Code they are
  `/gagarin:setup`, `/gagarin:ship`, `/gagarin:status` and `/gagarin:ci`; in
  Codex, `$setup` and so on. They ship here, not inside `gg`, so they can be
  newer than the `gg` you have; the reference skill says which version it
  assumes and tells an agent to check `gg version` before concluding a command
  does not exist.
- **The MCP server** at `https://mcp.gagarin.cloud/mcp` — the Gagarin API as
  tools, and the project's **memory**: the durable facts an agent keeps about a
  codebase so the next session does not rediscover them, reachable only here.
  A fact that changes takes a key and is replaced, not piled up; a memory is
  confirmed when checked, disputed when wrong, and `memory_review` says what to
  tidy. You sign in with GitHub or Google when the host asks; nothing is
  installed and no token passes through the agent.

## You still want the CLI

The MCP server is the same API in another shape, and it deliberately cannot do
four things: **build** an image, **push** one, open a **tunnel**, or **wait** for
a job. The first two shell out to docker where your source is, and a server on
the internet has neither. So `gg` is the larger surface, and the way to get an
image into the registry. In Codex and Claude Code the agent has a shell and
runs it; in ChatGPT on the web it does not, and operates what is already
running.

```
curl -fsSL https://gagarin.cloud/install.sh | sh
```

On Windows, in PowerShell:

```
irm https://gagarin.cloud/install.ps1 | iex
```

The script checks the download against the release checksums, installs to
`~/.local/bin` (Windows: `%LOCALAPPDATA%\Programs\gg`) without `sudo`, and never
edits your shell profile; if the directory is not on your `PATH` it prints the
line to add. `gg upgrade` (v0.54.0 and later) keeps it current.

Prefer a package manager? On macOS, `brew install --cask gagarin-cloud/tap/gg` —
a cask, so it is macOS only, and if you installed `gg` as a formula before that,
`brew uninstall gg` once first. On Windows, `scoop bucket add gagarin
https://github.com/gagarin-cloud/scoop-bucket` then `scoop install gagarin/gg`,
or `winget install Gagarin.gg`. Or `go install
github.com/gagarin-cloud/gg@latest`, or a `.deb`, `.rpm` or `.apk` from the
[releases page](https://github.com/gagarin-cloud/gg/releases).

The `setup` skill walks through it. If the machine has a package manager, setup
installs `gg` with it; otherwise it hands you the one-liner above to run
yourself, because the plugin never downloads and runs code on its own. Then
`gg login`, and a check of the rest of the toolchain:

- **docker**, running — required to build and push. `gg ship` cannot work
  without it.
- **git** — recommended. It is how `.gagarin.json` gets committed, and with a
  clean work tree `gg build` and `gg ship` tag the image with the commit's
  short hash instead of the clock.
- **gh** or **glab**, signed in — recommended once you want CI. It puts the
  deploy credential in the secret store without it passing through the agent's
  output, and lets the agent watch the pipeline run.
- **jq** — optional.

Setup installs only `gg`; for the rest it tells you what is missing and how to
get it.

## Any other agent

The reference skill is an [Agent Skills](https://agentskills.io) skill, which
Cursor, Copilot, Cline, Windsurf, Goose, opencode, Zed and about seventy others
read. Install it into any of them:

```
npx skills add gagarin-cloud/plugin -g
```

`-g` installs for your user; drop it to add the skill to one project instead.
`npx skills update` refreshes it later. Or copy `plugin/skills/gagarin/` to
`~/.agents/skills/gagarin/` yourself — that is all the installer does.

Or point any MCP client at `https://mcp.gagarin.cloud/mcp` and install nothing.

## Privacy

The plugin talks to Gagarin's own MCP server and downloads nothing itself: `gg`
arrives through your package manager, or through the installer you run. What
Gagarin keeps and why is in the [privacy policy](https://gagarin.cloud/privacy);
the [terms](https://gagarin.cloud/terms) cover the rest.

## License

MIT.
