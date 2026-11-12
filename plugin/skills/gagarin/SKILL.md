---
name: gagarin
description: Deploy and operate applications on Gagarin with the gg CLI — ship a service from a Dockerfile, provision postgres, qdrant, valkey, iggy, rabbitmq, s3 or external-credential resources, wire what may reach what, put a service on the internet, give CI its own credential, start jobs from an application's own code with the Go, Node or Python SDK, read status and logs, roll back, tear things down, and keep what a session learned in the project's memory. Use whenever the user asks to deploy, host, run or operate an application, or mentions Gagarin or gg. Gagarin runs container images on managed infrastructure; the user never needs to know about Kubernetes, ingress, TLS, or the underlying cloud.
---

# Deploying with Gagarin

Gagarin runs your services. You drive it with the `gg` CLI, a thin wrapper over
the Gagarin API. There is exactly one way to change anything: call the API.
There is no manifest file and no config file. The one file you will commit is
a note of which project the repository is, and it changes nothing — see "Which
project this repository is".

Everything below is the whole product. Read "The ten rules" and the command map
first; they are the parts that stop you getting it wrong.

## The ten rules

1. **Everything is named for its project.** `shop` is a project; `shop/web` is a
   service or a resource inside it. Nothing is inferred from the directory you
   stand in. There is no default project to configure — a command that does not
   name one is refused with the shape it should have had.
2. **Every write is asynchronous, except `gg run`.** A command that exits zero
   recorded a demand; it did not watch it come true. `gg status <project>` reads
   the cluster and is the only thing that can answer "is it up". The one
   exception is `gg run`, and it is an exception because a run *ends*: it waits,
   prints what the run wrote, and exits with the script's own code. Nothing else
   here has an end to wait for.
3. **Gagarin runs images from its own registry only.** `gg ship` is build, push
   and deploy fused; the three exist separately for CI. Somebody else's image
   comes in with `gg registry copy`.
4. **A service is private until `gg domain add`**, and a deploy can neither give
   an address nor take one away.
5. **A private service is default-denied.** Until the *caller* declares
   `gg deps add`, its calls are dropped — which hangs, rather than failing fast.
6. **`gg deps add <service> <resource>` opens the route *and* hands over the
   credentials.** Connecting a database is that one call, not a call plus a
   deploy.
7. **A deploy replaces the environment and nothing else.** Dependencies, the
   domain, the volume and the size all survive a deploy that forgets to mention
   them. Env is the one thing you must restate every time.
   **A credential never goes in a deploy env.** Env is for plain, single-service
   config: a port, a log level, a sibling's URL. A database password arrives
   with `gg deps add`; a third-party key is an `external` resource. See "What
   does not go in env" below.
   **And no secret value ever passes through your output** — not the
   terminal, not this chat, not a summary or a commit. A command that takes one
   reads it from a file (`--env-file`, `--input NAME=FILE`, `"$(cat FILE)"`),
   never `K=value` typed on a command line; a command that produces one writes
   it to a file or pipes it into the store it is for (`> .env.db`,
   `| gh secret set`). Reach for `--names` before values. Never ask your human
   to paste a secret into the chat.
8. **If a resource type exists, use it** (`postgres`, `qdrant`, `valkey`,
   `iggy`, `rabbitmq`, `s3`, `external`). If one does not, an ordinary service with a volume is the normal
   path, not a workaround.
9. **You can deploy; you cannot destroy.** Deleting anything, taking an address
   away, withdrawing a dependency with `gg deps rm`, and handing a project over
   with `gg transfer` all answer `approval_required` and email the account owner
   a button, every time the approval window has lapsed, which approves only once
   they are signed in. No flag grants this to an agent. Adding is always free: `gg deps add` and `gg domain add` need nobody.
10. **Errors are meant to be branched on.** gg prints `[code] message` and
    usually a `hint:` line. Act on the code, never on the prose.

## Command map

| | |
|---|---|
| `gg whoami` | which account this machine acts as — **run this first, always** |
| `gg login` / `gg login --new` | get this machine access — relay the link and code, then run it again once approved |
| `gg login --ref CODE` | the same, for a human a friend invited: the code (8 letters and digits) is added to the link so the new account is matched to the friend |
| `gg creds` / `creds create --name N` / `creds revoke ID` | what has access; mint one for CI; take one away |
| `gg registry login` | log docker in (CI, or docker installed after gg) |
| `gg projects` | every project you can reach, and your role on it |
| `gg init PROJECT` | create a project |
| `gg ship P/SVC:PORT` | build the current directory, push it, run it — tagged with the commit when the tree is clean |
| `gg build P/IMAGE[:TAG]` / `gg push P/IMAGE:TAG` / `gg deploy P/SVC:PORT IMAGE:TAG` | the same three steps apart, which is what CI wants |
| `gg run P/JOB IMAGE:TAG` | run an image to completion as a job, wait, print what it wrote, exit with its code |
| `gg run P/JOB IMAGE:TAG --schedule "0 3 * * *"` | run it on a schedule instead of now; returns at once |
| the SDK (Go, Node, Python) | start runs from an application's own code — see "From code: the SDK" |
| `gg registry copy P/IMAGE SOURCE` | bring an image you did not build into the project |
| `gg resource add P/NAME TYPE` | provision postgres, qdrant, valkey, iggy, rabbitmq, s3 or external |
| `gg resource add P/db postgres --ext vector --ext postgis` | the postgres extensions it should have, one `--ext` each — the whole set, every time you pass it |
| `gg resource public P/NAME` | make an `s3` bucket listable and readable by anyone; `gg resource private P/NAME` undoes it |
| `gg resource secrets P/NAME > .env.NAME` | its connection values, into a file for something outside the project — never printed |
| `gg resource secrets P/NAME --names` | just the variable names it publishes, no values |
| `gg resource rotate P/NAME` | new credentials, and everything holding them rolls |
| `gg resource rotate P/NAME --set K="$(cat FILE)"` | change one value an external publishes, keeping the rest; the value comes from a file |
| `gg rollback P/NAME` | put a previous revision back — a service's deploy, or an external's values |
| `gg connect P/NAME` | that resource on this machine, for as long as the command runs |
| `gg resource backup` / `backups` / `restore P/NEW --source OLD` | postgres, qdrant and iggy recovery |
| `gg deps add P/SVC NAME...` / `deps ls` / `deps rm` | what a service may reach, and whose credentials it holds (`rm` needs a human) |
| `gg domain add P/SVC [DOMAIN]` / `domain ls P` / `domain rm` | addresses on the internet |
| `gg status PROJECT` | desired vs actual, addresses, sizes, today's cost |
| `gg metrics P[/SVC] [--window 1h\|24h\|7d\|30d]` | usage from real numbers: every service now, or one service's current, average, peak and limit over a window. See Metrics |
| `gg logs P/SVC` | recent logs |
| `gg history P/SVC` / `gg rollback P/SVC [--to N]` | every deploy; put one back |
| alerts (no gg command) | push-notify a member's own devices when a service goes down, runs short of memory, CPU or disk, or answers with 5xx; the human turns it on with the switch at my.gagarin.cloud/projects/P/alerts, which also sends a test. See Alerts |
| `gg referral` | the account's invite link and code (once it has topped up), and who signed up through it and what it earned; in MCP, `referrals` |
| `gg members P` / `gg share P EMAIL [--role viewer]` / `gg unshare P EMAIL` | who can reach it |
| `gg transfer P EMAIL` | offer the project, and its bill, to a member (they accept by email) |
| `gg destroy P` or `P/NAME` | delete a project, a service or a resource (needs a human) |
| `gg eject P -o file.yaml` | the Kubernetes manifests, so you can leave (external and s3 keys are placeholders; `--with-secrets` includes them) |
| `gg recipe snap P [--dry-run]` | publish a project as a recipe, owner only; `--version`, `--as`, `--source`, `--notes`. Dry run first |
| `gg recipe show RECIPE[@VERSION]` / `recipe ls` | read a recipe (`--format json` for the manifest); the ones this account published |
| `gg recipe install RECIPE[@VERSION] NEW_PROJECT --input NAME=FILE` | deploy a recipe into a new project, one env file per declared input |
| `gg recipe diff P` / `recipe update P [--to V] [--force]` | what a newer version changes; apply it (removals need a human) |
| `gg recipe rm RECIPE[@VERSION]` | delete a recipe or one version (needs a human) |
| `gg version` | which gg this is |

Three environment variables override the credential file, and exist for CI:
`GAGARIN_TOKEN` (a credential), `GAGARIN_API` (control plane URL), and
`GAGARIN_REGISTRY` (registry host). There is nothing else to export.

## First moves in any session

Run `gg whoami` before anything else. It answers three different questions at
once, and each has a different next step:

| what happens | what it means | do this |
|---|---|---|
| the shell cannot find `gg` | not installed | see "Installing gg" — unless you already hold Gagarin MCP tools, in which case call `whoami` there and read "If you cannot install gg" for what they cannot do |
| `[unauthorized]`, or it says there are no credentials | installed, no access | see "Getting access" |
| it names an account | ready | carry on; `gg projects` says what already exists |

Then read `.gagarin.json` at the repository root, if there is one — it says
which project this repository already is — and `gg projects` before assuming a
project exists or that you may write to it. A `viewer` role means every deploy
will be refused, and that is worth knowing before the attempt rather than
after. Project names are unique only within one account, so two rows can share
a name — the id column tells them apart.

Once per session, before the first build or CI change, check the rest of the
toolchain — docker running, git, and `gh` or `glab` signed in — as "What else
the machine should have" describes. Only a stopped docker blocks a ship.

## Which project this repository is: `.gagarin.json`

Gagarin infers nothing from the directory you stand in, and gg stopped guessing
the project from the directory's name on purpose: that made a command whose
target was invisible in the command. So the repository carries a note instead,
at its root, and you are the one who writes it:

```json
{ "project": { "id": "3cnciet6", "name": "shop" } }
```

Write it once you have created the project or settled on an existing one.
Five rules, each for a reason:

- **It is a note for the next session, not configuration.** Nothing reads it —
  not gg, not the MCP server, not the platform. You read it, and then you still
  name the project in every command and every tool call, so the target stays
  visible in the command.
- **Identity only, never desired state.** The one other key is `"tour"`, the
  onboarding steps the human has already been shown (see "After the first
  address"). No services, ports, env or domains:
  Gagarin holds those, and a copy in the repository would be the stale one. If
  the file disagrees with `gg projects`, the API is right — fix the file and
  tell the user.
- **Prefer the id in calls.** Names are unique only within an account, so a
  project shared with the user can carry the same name as one of their own;
  the id cannot collide. Everything that takes a project name takes its id.
- **Commit it.** The id is already public in every hostname and image path,
  and a teammate's agent needs it as much as your next session does.
- **Read it first**, before `gg projects` and before asking. If it is absent
  and the user named no project, `gg projects` before `gg init` — the project
  may already exist.

Where the id comes from: `gg init shop` prints `project shop created (id
3cnciet6), runs in fr-par-1`; `gg projects` prints a row per project — name, id,
cluster, role; and the first line of `gg status shop` reads
`project shop  (id 3cnciet6)  fr-par-1`, ending with the cluster. None of them has a JSON flag; read the column.

**A project has a place.** Each project runs on one cluster, chosen when it is
created and never changed; `gg status` shows it (`fr-par-1`). It is part of the
project's generated addresses, `<service>-<project id>.<cluster>.apps.gagarin.cloud`
(for example `web-3cnciet6.fr-par-1.apps.gagarin.cloud`), so never build one by
hand from the id alone: read it from `gg status` or `gg domain ls`.

## Project memory

Every project has a memory: small durable facts about the codebase that the
next session would otherwise have to rediscover — an overview, the
architecture, a decision and why it went that way, a convention, a gotcha, a
howto, a reference, the state of a piece of work. It is reachable only through
Gagarin's MCP server (see "If you cannot install gg"); there is no `gg` command
for it. Every memory tool takes the project, which is what `.gagarin.json` is
for.

| tool | when |
|---|---|
| `memory_briefing` | first, when starting work on a project — a primer packed to a token budget |
| `memory_search` | before exploring the code for something a past session may already have found |
| `memory_get` / `memory_related` | one memory in full, by id or by key; what it links to |
| `remember` | one durable fact per memory, in English |
| `memory_update` | edit, pin, archive, confirm or dispute one |
| `memory_link` / `memory_unlink` | say that two are related, or that they are not |
| `memory_review` | housekeeping: likely duplicates, orphans, stale and disputed memories, how close the project is to its cap |

- **Brief yourself before you read the code, and search before you go
  looking.** That is what it is for. When you know the task, pass `focus` (what
  you are about to work on) and `paths` (the files you will touch) to
  `memory_briefing`, and the relevant memories come first.
- **Give a fact that changes a `key`.** What is deployed now, the current
  schema version: `remember` it as a `state` memory with a key such as
  `deploy/current`, and the next `remember` with the same key replaces it and
  keeps its links. Do not search for the old one and supersede it by hand.
- **Say when a memory is right or wrong.** One you checked against the code or
  the cluster gets `confirm: true`, which resets its age. One that proves wrong
  gets `dispute: true` — it is marked ⚠ and ranks lower until someone confirms,
  edits or archives it — or a fix, or an archive; do not leave it to mislead the
  next session. A briefing that counts disputed memories, or a `remember` that
  warns the project is near its cap, is the cue to call `memory_review` and tidy.
- **Remember what a future session could not cheaply rediscover**: why a
  decision went the way it did, a gotcha that cost time, where the deploy
  differs from the obvious — which port, which Dockerfile quirk, which
  variables the application insists on. Not what the repository already says,
  not what is true only of this conversation, and **never a credential or a
  secret** — not as a value, not in a tag. Title, body and source are
  encrypted at rest with a key Gagarin holds; tags, file paths and kind are
  not.
- **A `remember` refused with a list of near-duplicates** is telling you the
  fact is already there. Update or link those; do not reword it to get past
  the check.
- Reading needs `viewer` on the project; writing needs `editor`. Memories in
  use are billed at $0.10 per 1,000 a month — a few cents for most projects —
  and capped per project. Reading is free, and archiving a memory that is no
  longer true stops it being counted, so archive rather than leave it stale.
- **If the MCP server is not connected in this session, memory is simply
  unavailable.** Carry on with `gg`; it is not an error, and nothing else
  waits on it.

## Installing gg

If your client is already connected to Gagarin's MCP server you may not need
`gg` at all — read "If you cannot install gg" below first, because the one thing
it cannot do is build an image, and that is often the whole task.

Use a package manager the machine already has. You may run these yourself:

- macOS: `brew install --cask gagarin-cloud/tap/gg`. It is a **cask**, not a
  formula, and casks do not work on Linux. If `brew install
  gagarin-cloud/tap/gg` (no `--cask`) put an older `gg` there, homebrew will not
  replace one kind with the other on its own: run `brew uninstall gg` once,
  then install the cask.
- Windows: `scoop bucket add gagarin https://github.com/gagarin-cloud/scoop-bucket`
  then `scoop install gagarin/gg`, or `winget install Gagarin.gg`.
- Any platform with a Go toolchain: `go install github.com/gagarin-cloud/gg@latest`

If `go install` succeeds but the shell still cannot find `gg`, its bin directory
(`go env GOPATH`/bin) is not on `PATH`. Say so and let the user fix their
profile; do not edit their shell configuration yourself.

With none of those, the install is the human's to run, not yours: **never
download a script or a binary and run it.** Point them at the one-line installer
on https://gagarin.cloud (a shell one-liner on macOS and Linux, a PowerShell one
on Windows) and say what it does: it verifies the download against the release's
`checksums.txt`, installs to `~/.local/bin` (Windows: `%LOCALAPPDATA%\Programs\gg`,
added to their `PATH`) without `sudo`, and never edits a shell profile. On Linux a
`.deb`, `.rpm` or `.apk` from https://github.com/gagarin-cloud/gg/releases works
too; installing one needs `sudo`, so that is theirs to run as well.

If `~/.local/bin` is not on `PATH`, the installer prints the `export` line to add.
Call `gg` by its full path (`~/.local/bin/gg`) for the rest of your session and
tell your human the line; do not edit their profile yourself.

Do not download from a host you guessed, and do not carry on without `gg`.

`gg` shells out to **docker** for `build`, `push` and `registry copy` (the last
needs `buildx`). Nothing else needs it. A machine with no docker can still
deploy an image that is already in the registry, roll back, and read state.

**Run `docker info` before the first `gg ship`.** If it fails, ask your human to
start Docker Desktop, OrbStack or colima (or install one) and wait until
`docker info` succeeds; do not start or install it yourself. gg v0.51.0 and
later check this before any request and refuse with `docker_not_installed`,
`docker_not_running` or `docker_permission_denied`, each with the fix in its
hint. Relay the hint; do not retry until the human says docker is up, and do not
run gg with `sudo` to get round a permission error.

This skill is not part of the binary. It lives in `gagarin-cloud/plugin` and
is installed separately — in Claude Code, Codex and ChatGPT as a plugin,
elsewhere with `npx skills add gagarin-cloud/plugin -g`. So it can
be newer than the `gg` you are holding: **if a command here is refused as
unknown, check `gg version` and upgrade before concluding the command does not
exist.** `gg version` also prints, on stderr, "gg vX is available (you have vY)"
when you are behind (`GAGARIN_NO_UPDATE_CHECK=1` silences it). Upgrade with
`gg upgrade`, which upgrades the way `gg` was installed: brew, scoop, winget and
`go install` are handed to that tool, script and archive installs replace
themselves after checking the checksum, and `.deb`/`.rpm`/`.apk` installs print a
`sudo` command for your human. `gg upgrade --dry-run` previews it. `gg upgrade`
itself needs v0.54.0; on an older `gg` it does not exist, so use the per-manager
command (`brew upgrade --cask gagarin-cloud/tap/gg`, `scoop update gg`,
`winget upgrade Gagarin.gg`, `go install ...@latest`) or, for an installer or
archive install, have your human run the installer again as "Installing gg"
says. Everything else documented here is present in gg
v0.42.0 and later.

## What else the machine should have

`gg` itself shells out to one thing, docker. The rest of this skill leans on a
few more tools without checking for them, so check once, early, rather than
meeting each one as a failure halfway through a deploy:

| tool | needed for | without it |
|---|---|---|
| `gg` | everything | see "Installing gg" |
| `docker`, running | `gg ship`, `gg build`, `gg push` | deploy an image already in the registry; read state; roll back |
| `docker buildx` | `gg registry copy` | bring the image in from a machine that has it |
| `git` | committing `.gagarin.json`; `gg build` and `gg ship` tagging the image with the commit; knowing which forge the repository lives on | it all still deploys, but nothing ties an image to the source it came from, and the next session has no note of the project |
| `gh` (GitHub) or `glab` (GitLab), signed in | putting a CI credential in the secret store without it touching disk or the transcript; watching the pipeline you wrote run | the human sets the secret in the web UI themselves, and you cannot see whether the first run went green |
| `jq` | pulling one value out of `--format json` | read the JSON yourself; nothing in gg requires it |

Only the forge CLI that matches the repository matters: `git remote get-url
origin` says whether it is GitHub or GitLab. Check what is there, and whether
the forge CLI is signed in, with:

```
command -v git docker gh glab jq
docker info >/dev/null 2>&1 && echo "docker is up"
git rev-parse --is-inside-work-tree && git remote get-url origin
gh auth status        # or: glab auth status
```

What to do about a missing one:

- **Do not install docker, git or a forge CLI yourself, and do not sign in for
  your human.** Say which is missing, what it costs them, and the install
  command for their platform (`brew install gh`, `winget install GitHub.cli`,
  `sudo apt install gh`; `glab` the same way). `gh auth login` and `glab auth
  login` are theirs to run, like `gg login`.
- **Only docker blocks a ship.** Everything else degrades: say what is lost and
  carry on with the task.
- **Not a git repository** is not a failure either. Deploy it; then mention that
  `.gagarin.json` only helps the next session if it is committed somewhere.

## If you cannot install gg: the MCP server

Gagarin also answers MCP at `https://mcp.gagarin.cloud/mcp`. An MCP client —
Claude Code, Claude Desktop, Cursor, Codex, ChatGPT — connects to that URL and
installs nothing: your human signs in with GitHub or Google when the client
asks for it, and no secret passes through you. It is this same API in another
shape, so everything above still holds — the naming, the asynchrony, the
default-denied graph, the human's approval before anything is destroyed.

**It is a smaller surface than `gg`, and the gap is images.** Over MCP you can
deploy an image that is already in the registry, run a job, read status and
logs, declare dependencies, add an address, roll back, and manage resources,
people, credentials and the bill. Four things are deliberately absent:

- **No build and no push.** `gg ship`, `gg build`, `gg push` and
  `gg registry copy` shell out to docker where the source is, and a server on
  the internet has neither your source tree nor your docker.
- **No tunnel.** `gg connect` binds a port on *this* machine; there is no local
  anything at the other end of an MCP call.
- **No waiting for a job.** `run` answers the revision naming the run and
  returns, as every other write does. `status` is the only place an exit code
  appears.
- **No list of resource types, sizes or scopes.** The engine owns those and its
  refusals name them; a second copy here would be wrong the day one is added.

So: **if `gg` is installed, use it.** It does everything the MCP server does and
the four things it cannot. Reach for MCP when you cannot install a binary, or
when the work is purely operational — reading state, rolling back, wiring deps,
managing addresses. If a task needs an image built and you hold only MCP tools,
say so and install `gg` rather than reporting a deploy you were unable to make.

There is a third way into the same API, and it is for neither you nor a
person: **application code uses the SDK** (Go, Node, Python) — see "From code:
the SDK".

## Getting access

`gg login` is one command whether this is the first machine on a new account or
the fifth on an old one. There is no separate signup and no address to ask for:
the human signs in with GitHub or Google, and a new account starts with $5 on it
and no card asked for.

1. **`gg login`** prints a link and a code, remembers the request, and exits.
2. **Give the user the link and the code as printed.** The link is the one to
   open; the plain address and the code under it are the fallback for when the
   link does not open. Say what they will do there: sign in with GitHub or
   Google, check that the page shows the same code and this machine's name, and
   approve. Then wait for them to tell you they have.
3. **`gg login` again.** It collects the request the first run made — it does
   not ask for a new one — stores the credential in
   `~/.config/gagarin/credentials.json`, logs `docker` in to the registry, and
   says which account this machine now acts as. Confirm with `gg whoami`.

If the second run fails:

- `[authorization_pending]` — it waited a minute and nobody had approved yet.
  It prints the link and code again: pass them on again if the user seems not to
  have them, and once they say they approved, run `gg login` again. Do not run
  it in a loop.
- `[expired_token]` — nobody approved within fifteen minutes, and the request is
  gone. Run `gg login` for a fresh link and pass it on straight away.
- `[access_denied]` — the user declined on the page, and the request is gone.
  Ask them why before running it again, and do not retry on your own.
- `[github_account_too_new]` — the user signed in with a GitHub account under
  30 days old, which Gagarin does not accept yet. The request is kept: tell them
  to open the same link and choose **Continue with Google**, then run `gg login`
  again once they say they approved.

`gg login --new` throws away a request nobody approved and asks for a new code —
for when the user lost the link, or it was meant for a different account.

Do not open the link yourself, and do not approve it on the user's behalf in a
browser you control: the approval is theirs, and it is the only thing standing
between an agent and an account. The account is whichever one they sign in to;
if they use more than one, let them pick.

The moment an account is created it gets its balance and the address the
provider verified joins Gagarin's customer list; https://gagarin.cloud/privacy
says what that list is for.

You never handle the credential yourself. Do not read that file, do not echo it,
and never ask the user for a token — if you find yourself wanting a secret to
make `gg` work, you are doing this wrong. The exceptions are CI and an
application that starts jobs, and each gets its own — "Setting up CI" below, and
"From code: the SDK".

If `docker` was installed after Gagarin, `gg registry login` does that half on
its own.

## Setting up CI

**Never run `gg login` in CI, and never copy this machine's credential into
it.** A pipeline gets one of its own, minted from the one you already hold.

### 1. Mint the credential

`gg creds create --name "github actions: acme/web"` prints the secret to
**stdout alone on its line**, and everything else to stderr. Never run it on
its own, which would put the secret in your output: pipe it straight into the
secret store, so nothing touches disk or the transcript:

```
gh secret set GAGARIN_TOKEN --body "$(gg creds create --name "github actions: acme/web" 2>/dev/null)"
```

On GitLab, the same with `glab`:

```
glab variable set GAGARIN_TOKEN --masked --value "$(gg creds create --name "gitlab ci: acme/web" 2>/dev/null)"
```

**Without `gh` or `glab` signed in, do not mint it yourself** — there is no way
from here to a secret store that does not pass through your output. Ask your
human to run `gg creds create --name "…"` in their own terminal and paste it
into the repository's CI settings, or to install and sign in to the forge CLI
first.

Name it after where it will live. `gg creds` is a list somebody reads months
later deciding what is still wanted, and "token" tells them nothing then.

What you just minted is **deliberately weaker than what you hold**:

- It can deploy. **It cannot destroy** — a pipeline holding it cannot delete a
  project, a service or a database, and no flag turns that on.
- It **expires**: 90 days by default, 365 maximum, and there is no never.
- It **cannot mint another**, so a leaked one cannot issue its own replacements
  while you are busy revoking it.
- It is **shown once**. Gagarin keeps a hash. Lose it and you revoke it and mint
  another; no command reads one back.

### 2. Give it to the pipeline

CI reads `GAGARIN_TOKEN` from the environment and needs nothing else: no
`gg login`, no credentials file, no home directory, no interactive anything.

### 3. The workflow

The shape that matters: install gg, log docker in, publish on every commit,
release on the ones you mean.

```yaml
name: deploy
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    env:
      GAGARIN_TOKEN: ${{ secrets.GAGARIN_TOKEN }}
    steps:
      - uses: actions/checkout@v4

      - name: install gg
        run: go install github.com/gagarin-cloud/gg@latest

      - name: log docker in to the gagarin registry
        run: gg registry login

      - name: build and publish
        run: gg build acme/web:${{ github.sha }} --push

      - name: release
        run: gg deploy acme/web:8080 web:${{ github.sha }} --env-file .env.production

      - name: say what the cluster is doing
        run: gg status acme
```

Six things about that are load-bearing:

- **`gg registry login` is not optional.** `gg build --push`, `gg push` and
  `gg registry copy` all shell out to docker, and docker has no idea what a
  Gagarin credential is until that runs. The failure without it is a `401` out
  of `docker push`, whose hint says exactly this.
- **Tag with the commit, explicitly.** `gg build` with no tag uses the short
  hash when the checkout is clean and the clock when it is not — and a
  pipeline that generates a file or two before the build is not clean. Pass
  `${{ github.sha }}` so the tag never depends on that: it is what makes a
  deploy reproducible and a rollback explicable.
- **`gg push` requires the tag** where `gg build` does not — a push moves
  something that already exists, and "whichever one I built last" is not a name.
- **The deploy step is separate on purpose.** Publishing on every commit and
  releasing on some of them is the whole reason build, push and deploy are three
  verbs. A workflow that only ever wants all three can run `gg ship` instead.
- **`.env.production` is committed, so it holds no secrets.** It is config:
  ports, log levels, sibling URLs. The keys the service needs are `external`
  resources, created once with `gg resource add` and wired with `gg deps add`;
  they survive every deploy CI makes, and CI never holds them. If you are about
  to put a credential in a CI secret so the workflow can pass it with `--env`,
  make it an external instead.
- **`gg status` at the end is a report, not a gate.** The deploy returned when
  the demand was recorded; the pod may still be pulling. Do not write a polling
  loop in CI — if you want a gate, gate on your own health check against the
  service's address.

Everything else works identically in any CI: the token in the environment, `gg`
on the PATH, docker available if you build. GitLab, Buildkite and Cloud Build
need no special handling.

**Watch the first run** if the forge CLI is there, once your human has pushed —
that push is theirs to make. Give `gh` the run's id, because without one it
asks which run, and you cannot answer a prompt:

```
id=$(gh run list --workflow deploy.yml --limit 1 --json databaseId -q '.[0].databaseId')
gh run watch "$id" --exit-status
gh run view "$id" --log-failed        # only if it failed
```

On GitLab, `glab ci status --live` follows the pipeline for the current branch
and `glab ci trace <job>` prints a job's log. Then `gg status` for what the
deploy step actually did.

### 4. Afterwards

```
gg creds              what has access, which are minted, when each expires
gg creds revoke 7     immediately, and needing no approval
```

Revoking needs no human because taking access away is always safe — a machine
you no longer trust should not wait on an inbox. Rotate a CI credential by
minting the new one, updating the secret, then revoking the old id.

If you are tempted to set `XDG_CONFIG_HOME` to a scratch directory and run
`gg login` again for a second credential: that used to be the only way and it
is not any more.

## Recipe: an application from nothing

The end-to-end, in the order that avoids every window where something is broken.

```
gg init shop                                  once, per application

gg resource add shop/db postgres --size m     the database, before the thing that needs it
gg ship shop/api:8080 --deps db               builds ., pushes, runs it, and it
                                              starts already holding DB_URL
gg ship shop/web:3000 --env API=http://api:8080
gg deps add shop/web api                      web may now call api
gg domain add shop/web                        the one thing the browser opens
gg status shop                                and only now tell the user a URL
```

Notes on each step, in the order they bite:

- **After `gg init`, write `.gagarin.json`** with the id it printed, and commit
  it — see "Which project this repository is". Skip `gg init` when the note or
  `gg projects` says the project already exists.
- **A Dockerfile per service.** Gagarin deploys images, so a service without one
  cannot be deployed. Writing it is a normal part of this job. Do not set a
  platform or architecture: Gagarin reports what its own nodes run, and gg builds
  for that.
- **Run `gg ship` from the directory holding that service's Dockerfile**, or
  point `--context` at it — `gg ship shop/api:8080 --context ./api` from a
  monorepo root. `--file` names the Dockerfile when it is not called that, or
  lives outside the context directory.
- **Commit before you ship, if you can.** With no tag given — and `gg ship`
  never takes one — gg tags the image with the short hash of the commit
  (`web:3f9c2ab`), so `gg history` says which code each revision ran and a
  rollback names what it puts back. Only when the work tree is clean: any
  modified or untracked file in the repository, inside the build context or
  not, and it falls back to a clock tag (`web:1761830000`) and says so on
  stderr. Ignored files do not count. No git or no repository is the clock too,
  silently. Either way the tag is printed; read it from the output rather than
  predicting it. Do not commit the user's work just to get a hash: ask, or
  ship with the clock. (gg v0.55.0 and older always use the clock.)
- **The number after the colon is the port the container listens on.** It
  defaults to 8080. Say it anyway when you know it: a service answering on the
  wrong port is a hang, not an error.
- **`--deps db` on the first ship** means the pod never starts into a window
  where it cannot reach the database and does not hold its password. On later
  ships it is optional and harmless.
- **Private services talk over `http://<service-name>:<port>`** — the service
  name, no project prefix, no scheme guessing.
- **`gg domain add` for the service the user's browser opens, and nothing else.**
  Do not expose a database, a worker or an internal API "so it can be tested".
  Ask the user before putting anything on the internet they did not ask to.
- **`gg status` before you promise anything.** `gg ship` says nothing about where
  a service answers, deliberately — an address exists as a string long before
  anything is listening on it.

### When to use the three steps instead

```
gg build  shop/web:v3 --context ./web    make an image, run nothing
gg build  shop/web:v3 --push             ...and upload it in the same call
gg push   shop/web:v3                    publish it, release nothing
gg deploy shop/web:8080 web:v3           release one that already exists
```

That is CI, and it is also the only way to run an image you did not just build —
one copied in with `gg registry copy`, or a tag somebody else pushed.

## After the first address: show them around

A first deploy that answers is where most people stop, and the three things that
keep a project healthy are one step past it. So once `gg status` shows the first
service answering, give the human its URL, and then offer one next step per
turn, in this order:

1. **The graph.** Point them at `https://my.gagarin.cloud/projects/<id>`: what
   is running, and what may reach what. Nothing to run, so this one is a
   sentence and a link.
2. **Alerts.** Ask whether the human wants a push on their phone when the
   service goes down, a deploy will not start, a container keeps crashing, or
   one runs short of memory, CPU or disk.
   If yes, they open `https://my.gagarin.cloud/projects/<id>/alerts` on that
   phone and turn on "Notify me about this project", which allows notifications
   and opts them in at once; the same page sends a test. On an iPhone they add
   the console to the Home Screen first and open it from there. There is no gg
   command for alerts. With the MCP server connected you may check with
   `alerts` first, and send `test_alerts` once they say it is on.
3. **Memory.** `remember` two or three facts this session would otherwise lose:
   why that port, why that size, what the Dockerfile works around. Then tell
   the human the project keeps them, and the next session starts from them.

Rules, each for a reason:

- **One step per turn, one sentence and one action.** A wall of next steps
  reads as homework, and the human came for an address.
- **Stop when they say no or change the subject.** Do not bring a skipped step
  back later in the same session.
- **Alerts are the human's switch, not yours.** They reach a person's phone,
  and only that person's browser can allow them.
- **Skip what is done, and read "done" from state.** With the MCP server,
  `alerts` says whether alerts are on and how many devices they reach; without
  it, the human's answer is the state. `memory_briefing` says whether the
  project already holds memories. What was said earlier in a conversation is
  not state.
- **Note what they have seen in `.gagarin.json`.** The graph leaves no trace you
  can read back, so record each step as it happens: add its name to `"tour"`,
  `{ "project": { … }, "tour": ["graph", "alerts", "memory"] }`. A step in the
  list is not offered again, in this session or the next. Commit it with the
  rest of the note.

## Services

A service is a container image that runs, with a port, a size, an environment,
optionally a volume, whatever it is allowed to reach, and whatever addresses it
answers on. Only the first two of those are set by a deploy. An image that runs
to completion instead of serving — a migration, a backfill — is a **job**, not a
service: see "Jobs" below, and do not deploy one as a service, because a
service that exits is restarted forever and reads as failing.

### The environment

```
gg deploy shop/web:8080 web:v3 --env-file .env
gg deploy shop/web:8080 web:v3 --env-file .env --env DEBUG=false
gg ship   shop/web:8080 --env-file .env
```

- `--env-file` is **not** picked up automatically. If the user has a `.env` and
  wants it used, pass the flag; never assume a file should be read.
- Precedence: `--env` beats every file, later `--env-file` beats earlier ones,
  and **a resource's injected variable beats all of it** (see "Resources").
- There is **no interpolation**. `B=${A}` sets `B` to the literal `${A}`.
- Env is **replaced on every deploy, not merged.** To remove a variable, deploy
  without it. To keep one, keep passing it.
- The file supplies **values only**. It cannot name services, set ports or say
  what is public. If you find yourself wanting to put deployment structure in a
  file, stop — Gagarin holds that itself.

Environment is the one thing a deploy still replaces wholesale, because it is
part of what a revision ran with and is what a rollback puts back. Everything
else that could be lost by forgetting to restate it has been moved out of a
deploy for exactly that reason.

### What does not go in env

**No secrets. Not an API key, not a password, not a token, not a connection
string with a password in it.** A deploy env is for configuration that is
harmless to read and owned by this one service: `PORT`, `LOG_LEVEL`,
`NODE_ENV`, `API=http://api:8080`. Anything that would hurt in the wrong hands
belongs on the graph instead:

| it is | where it goes |
|---|---|
| a Gagarin database, cache, queue or bucket | `gg deps add P/SVC RESOURCE`. The credentials arrive by themselves, and are never copied into env |
| a third-party key (Stripe, OpenAI, SMTP, a webhook secret) | `gg resource add P/NAME external --env-file .env.NAME`, then `gg deps add` |
| config several services share, or that should change without a deploy | an `external` too, even when it is not secret |

Why a secret in a deploy env is the wrong place, every time:

- **It is copied into every revision.** History keeps each deploy's env so a
  rollback can put it back, so a key you rotated is still stored, alongside every
  older one, for as long as those revisions exist.
- **It cannot be changed on its own.** A deploy replaces the whole env, so
  rotating one key means restating all of them, and the API will not hand them
  back: `status` and `history` return the variable *names* (`env_keys`), never
  the values. Whoever rotates it needs the full `.env` file, or deletes every
  key they forget.
- **It is a copy per service.** Three services using one key means three
  deploys to rotate it, and the one you forget keeps authenticating with a
  revoked key. An external is one row: `gg resource rotate --set` changes one
  key, every holder is restarted, and `gg rollback P/NAME` undoes it.
- **It lives in a file on someone's machine and in CI**, because it has to be
  restated on every deploy. An external is stated once.

**What you do as an agent:**

- A credential for a service becomes an `external`, from a file your human
  writes (see the external section). Do not ask for it in chat, do not pass it
  with `--env`, and do not put it in a `.env` that a deploy reads.
- If a `.env` you were asked to deploy with holds secrets, say so before
  deploying, and offer to move them out. Do not quietly ship them, and do not
  quietly drop them either: the service would start without them.
- If a service already has a secret in its deploy env (`env_keys` in
  `gg status` names it), say so and offer the move below. Do **not** try to
  reconstruct its environment to redeploy: the values are not readable through
  the API, and a guess deletes every key you leave out.

Moving a secret out of a deploy env, without a moment where the service lacks
it:

```
gg resource add shop/stripe external --env-file .env.stripe   # holds API_KEY
gg deps add shop/web stripe          # web now also holds STRIPE_API_KEY
gg deploy shop/web:8080 web:v3 --env-file .env   # the same .env, minus STRIPE_API_KEY
```

The injected variable beats the deploy env, so the order is safe: `web` holds
the key the whole way through, and the last deploy only removes the stale copy.
Name the resource for how the application reads it: `stripe` with `API_KEY`
publishes `STRIPE_API_KEY`. After the move, the old value is still stored in the
history revisions that carried it. Rotate the key at the provider if it ever went
anywhere it should not have.

### Size

Every service and every resource runs at a size, and `s` is what you get if you
say nothing at creation.

| | reserved | ceiling | price |
|---|---|---|---|
| `s` | 100m CPU / 256 MiB | 0.5 vCPU / 1 GB, shared | $10/month |
| `m` | 1 vCPU / 2 GB | same — dedicated | $30/month |
| `l` | 2 vCPU / 4 GB | same — dedicated | $60/month |

```
gg deploy shop/web:8080 web:v3 --size m
gg ship shop/web:8080 --size m
gg resource add shop/db postgres --size m
```

- **`s` is shared; `m` and `l` are dedicated.** An `s` service may burst to its
  ceiling but is only guaranteed the reservation, which is why it costs a third
  of `m`. An `m` or `l` reserves exactly what it is promised and is the last
  thing evicted when a node runs short.
- **Omitting `--size` keeps the size the service already has.** It does not reset
  to `s`. Changing a size is therefore always deliberate.
- **Changing a size restarts the service** — a new pod with new limits. Expect a
  few seconds of downtime, and do not do it while something depends on it.
- **Which to pick.** Start at `s`: it runs a small API, a worker, a static site,
  a database you develop against. Move to `m` when something is OOM-killed —
  `gg status` says so and names the size to move to — or when you already know
  the workload: server-side-rendered Next.js, a JVM, a large in-process cache, a
  postgres a real application depends on. Do not reach for `l` speculatively.
- `gg status` shows the size every service is running at, and the day's accrued
  cost at the bottom of the table.

### Volumes

```
gg ship shop/db:5432 --volume /var/lib/postgresql/data --volume-size 20
```

A directory that survives restarts. **Set once, at the deploy that creates the
service**; a later deploy cannot move it or resize it, and asking is refused with
`volume_immutable`. The default ceiling is 10 GB. A rollback across a change of
volume is refused for the same reason.

Use this for anything stateful that has no resource type — see "Anything we do
not have a type for".

## Jobs: what runs to completion

```
gg build shop/migrate:v3 --context ./migrations
gg run   shop/migrate migrate:v3 --deps db --env-file .env
gg run   shop/migrate migrate:v3 --detach        submit and return
gg run   shop/migrate migrate:v3 --timeout 5m    stop it at five minutes
gg run   shop/migrate migrate:v3 --ttl 30m       remove it half an hour after it ends
```

A job is a service that ends. It has an image, an environment, a size and a
place on the graph, and **no port, no address and no volume**: it listens on
nothing, nothing can declare that it needs one, and it keeps nothing between
runs. Durable data belongs in a resource the job reaches with `--deps`.

- **`gg run` is the one command that waits.** It submits the run, follows it,
  prints what the run wrote, and **exits with the script's own exit code**. Read
  the code: zero means the script finished; anything else is the script's
  failure, and the last line names it. `--detach` returns at once instead, and
  `gg status` then reports how the run ended.
- **Every `gg run` is one run**, recorded as a revision exactly like a deploy.
  Running twice runs twice. `gg history` lists the runs; `gg rollback` runs an
  earlier revision again.
- **A run that fails is not retried**, and its exit code is reported once. Fix
  the script and run again; the platform will not re-run a half-applied
  migration on its own.
- **A run is stopped at its timeout, which is sixty minutes unless you set
  one.** `--timeout 5m` takes a Go duration (`45s`, `5m`, `1m30s`, `1h`) from
  one second to sixty minutes, in whole seconds; over MCP it is
  `timeout_seconds`, 1 to 3600. Left out, a job keeps the timeout its last run
  was given, and a new job gets sixty minutes; to go back to the default, say
  `60m` (or 3600) outright. The clock starts when the run gets a machine, not
  when the script starts, so pulling the image uses some of it; waiting for a
  machine uses none. A run that never gets a machine is given up on after its
  timeout plus thirty minutes, and its status says nothing ran and nothing was
  billed. At the deadline the run is sent SIGTERM, and killed thirty seconds
  later if it is still running. `gg status` says so when that is why it ended:
  "the run was stopped at its timeout of 5 minutes, counted from when it got a
  machine; gg run --timeout gives it up to 60 minutes" (at the ceiling: "...after
  60 minutes, counted from when it got a machine, which is the most a job may
  take").
  Something that needs longer than an hour is a service.
- **A finished run is removed after its TTL, eight hours unless you set one.**
  `--ttl 30m` takes a duration from one minute to eight hours; over MCP it is
  `ttl_seconds`, 60 to 28800 (`invalid_ttl` outside that). Left out, a job keeps
  the TTL it has, and a new job gets eight hours. It counts from when the run
  **ended**, not from when it got a machine as the timeout does. On expiry a
  one-shot job is deleted outright: its row, history and runs go, it leaves
  `gg status`, and its name is free again (a reused name starts at revision 1).
  `gg logs` still has what the run wrote while the job exists. So read the
  outcome with `gg run` (which waits) or `gg status` before the TTL passes, and
  there is nothing to `gg destroy` afterwards.
- **Its image is any image in the project's space** — build one with
  `gg build`, or run the service's own image with a different entrypoint baked
  into a second Dockerfile. `gg run` does not build.
- **A job is billed for the time it runs**, at its size, not for existing: by
  the minute, from when its container starts. Waiting for a machine and pulling
  the image are not billed. A hung run costs at most its timeout.
- **A run can sit `pending` without being stuck.** With no machine yet, `gg
  status` says "waiting for a machine with room for it — the cluster adds one
  within a few minutes unless it is at its limit; nothing is billed until it
  starts". Keep waiting; it is not a failure.
- **Kinds do not change.** A name that is a job stays a job (`not_a_service`),
  and a name that is a service cannot be run as a job (`not_a_job`). Give the
  job its own name.

Use a job for anything the user describes as "run this once" or "run this
before deploying": migrations, seeds, imports, one-off reports. The shape for a
deploy that needs a migration first is two commands, in this order:

```
gg run    shop/migrate migrate:v3 --deps db     # exits non-zero if it failed: stop here
gg deploy shop/api:8080 api:v3
```

### On a schedule

```
gg run shop/report report:v2 --schedule "0 3 * * *" --tz Europe/Berlin
gg run shop/report report:v3                     next firing runs v3; schedule kept
gg run shop/sync   sync:v1   --schedule "*/5 * * * *" --deps db
```

Use this for anything the user describes as "every night", "every hour", "on
Mondays": a nightly import, a report, a cleanup, a sync. It is still a job —
same image, environment, size, timeout and graph — with one more property.

- **`--schedule` is five cron fields** (minute hour day-of-month month
  day-of-week) **or a descriptor**: `@hourly`, `@daily`, `@weekly`, `@monthly`,
  `@yearly`. It may fire as often as every minute. `@every` and a
  `CRON_TZ=`/`TZ=` prefix are refused (`invalid_schedule`).
- **`--tz` is the zone the schedule is read in**, an IANA name like
  `Europe/Berlin`; UTC when left out. Ask the user which zone they mean when they
  say "at 3am" — the default is UTC, not their laptop's zone.
- **A scheduled `gg run` does not wait**, because nothing runs now: it prints
  the schedule and the next firing and returns, whatever `--detach` says. There
  is no exit code to read. `gg status` is how you learn how each firing ended.
- **Each firing is a run** like any other: not retried when it fails, stopped
  at its timeout, billed for the time it ran. A schedule waiting between
  firings costs nothing. **Runs never overlap**: a firing that comes while the
  previous run is still going is not started beside it — it waits, and starts
  the moment that run ends; several firings missed that way start once. A job
  that takes longer than its interval therefore runs back to back, not in
  parallel.
- **`gg run` again without `--schedule` keeps the schedule** and changes what
  the next firing runs — the image, `--env`, `--size`, `--timeout`, `--ttl`. A firing
  already going keeps what it started with. `--schedule` again changes when;
  `--tz` alone changes the zone.
- **`--schedule` on a one-shot job makes it scheduled**, between runs only:
  while its run is still going it is refused `job_running`.
- **A schedule cannot be removed.** `gg run` means "run this", so a
  `--schedule off` would fire a run when all you wanted was for the schedule to
  stop — the one thing the command could not avoid doing. To stop a scheduled
  job, destroy it (a human approves) and, if it should still exist as a one-shot
  job, run it again without `--schedule`. Do not look for a flag to pause or
  clear a schedule; there is none.
- **`--ttl` on a scheduled job applies to each firing**, counted from when it
  ended, and the job stays: only that firing's run is removed. `gg status` still
  reports the last firing, reading "(removed after its ttl)", and `gg logs` keeps
  what it wrote.
- **A failed firing alerts** whoever opted in to the project's alerts, once,
  and a later firing that succeeds resolves it. Nobody else is watching a run
  at three in the morning, so when you set up a schedule for someone who has
  them off, suggest the switch at `https://my.gagarin.cloud/projects/P/alerts`.
- Over MCP, `run` takes `schedule`, `time_zone` and `ttl_seconds`, and `status`
  carries `schedule`, `time_zone` and `actual.schedule` (`next_at`,
  `last_scheduled_at`, `suspended`).

### From code: the SDK

`gg run` is for a person or a pipeline, and `--schedule` for a clock. When
**a program** decides that a job should run — on a request, a queue message, a
user's click — it starts the run with the SDK. **Never shell out to `gg` from an
application**: it would need gg installed in the image and a login on a machine
nobody signs in to. The SDK is the same API as a library, in three languages,
each with no runtime dependencies:

```
npm install @gagarin-cloud/sdk              Node 18+, TypeScript types included
pip install gagarin                         Python 3.9+
go get github.com/gagarin-cloud/sdk/go      Go 1.22+
```

Each one reads `GAGARIN_TOKEN` (and `GAGARIN_API`, `GAGARIN_REGISTRY`) from the
environment, exactly as gg does. The four job calls are `run` (submit; returns
the run's `revision` at once), `wait` (until that revision ends), `runAndWait`
(both, which is `gg run`) and `logs`.

```ts
import { Gagarin, GagarinError } from "@gagarin-cloud/sdk";

const gg = new Gagarin();
const name = `export-${id}`;                       // one name per run; see below
try {
  const sub = await gg.jobs.run("shop", name, {
    image: "export:v4", env: { EXPORT_ID: id }, deps: ["files"], timeoutSeconds: 900,
  });
  const run = await gg.jobs.wait("shop", name, sub.revision);
  if (run.phase !== "done") { /* failed: run.exit_code, and gg.jobs.logs("shop", name) */ }
} catch (e) {
  if (e instanceof GagarinError && e.code === "payment_required") { /* … */ }
  throw e;
}
```

```python
from gagarin import Gagarin, GagarinError

gg = Gagarin()
res = gg.jobs.run_and_wait("shop", f"export-{id}", image="export:v4",
                           env={"EXPORT_ID": id}, deps=["files"], timeout_seconds=900)
res.exit_code                                     # what gg run would exit with
```

```go
c, err := gagarin.NewClient()   // import gagarin "github.com/gagarin-cloud/sdk/go"
res, err := c.Jobs.RunAndWait(ctx, "shop", "export-"+id, gagarin.RunOptions{
	Image: "export:v4", Env: map[string]string{"EXPORT_ID": id},
	Deps: []string{"files"}, TimeoutSeconds: 900,
})
if gagarin.IsCode(err, "payment_required") { /* … */ }
res.ExitCode()
```

Everything in "Jobs" above still holds, because it is the same call:

- **The image must already be in the registry.** The SDK neither builds nor
  pushes; `gg build` and `gg push` (or CI) put it there first. A bare
  `repo:tag` is expanded to the project's registry space for you.
- **`env` is the run's complete environment**, not merged with the last one;
  leave it out and the run has none. **`deps` adds** to what the job already
  declares. Both follow rule 7: no credential goes in `env` — a job reaches its
  database or bucket through `deps`.
- **The timeout is at most 3600 seconds and starts when the run gets a
  machine.** Every call is a new run, billed for the time it runs.
- **The TTL is `ttlSeconds` (Node), `ttl_seconds` (Python), `TTLSeconds` (Go)**,
  60 to 28800 (`MIN_TTL_SECONDS`/`MAX_TTL_SECONDS`, `MinTTLSeconds`/`MaxTTLSeconds`
  in Go); leave it out for the job's current one, eight hours on a new job. It
  counts from when the run ended and then removes a one-shot job, so `wait` or
  `runAndWait` and read the run (and `logs`) before it goes. After that, `get`
  and `wait` on the name fail `not_found` ("nothing named … in project …"), which
  looks the same as a job that never existed. A scheduled firing is the
  exception: the job stays, and its last run reads `expired: true`
  (`Expired` in Go) with phase, exit code and times intact.
- **Refusals are a typed error carrying the API's `code`**, `message` and
  fix hint: `GagarinError` in Node and Python, `*gagarin.Error` with
  `gagarin.IsCode` in Go. Branch on the code, as in "Error codes".
- **It does not destroy anything.** Destroying is a human's approval, and the
  SDK leaves it out.

**One name per run that may overlap another.** Starting a run on a job **stops
that job's run still going** — a new revision is what the job is now. So an
application that may start a second run before the first has ended must give
each its own job name: a fixed prefix and a short id of the work (`export-7f3a`),
never raw user input, and within `^[a-z][a-z0-9-]{1,29}$`. If only a fixed number
should run at once, a name per lane (`export-1` … `export-4`) is the alternative,
and the application must not start a lane that is busy. A `wait` on a run that a
newer one replaced fails with `superseded` (`gagarin.ErrSuperseded` in Go) —
the symptom of two runs sharing a name. A finished job costs nothing and
removes itself after its TTL, eight hours unless the run asks for less, which
frees its name; nothing needs `gg destroy`, so per-run names do not pile up.

**The application needs a credential of its own**, minted the way CI's is and
delivered the way every other secret is — as an `external` resource, never in
`--env`. Name the resource `gagarin` and the key `TOKEN`, and the service holds
exactly the `GAGARIN_TOKEN` the SDK reads:

```
printf 'TOKEN=%s\n' "$(gg creds create --name "shop/api: starts jobs" 2>/dev/null)" > .env.gagarin
gg resource add shop/gagarin external --env-file .env.gagarin
gg deps add shop/api gagarin
rm .env.gagarin
```

The token never reaches the terminal or the transcript. Tell the user what it is:

- **It can deploy and run anything in the account**, not only this project, and
  it **cannot destroy**. Anyone who can read the service's environment holds it.
- **It expires** — 90 days unless `--expires` says otherwise, 365 at most. Before
  then, mint a new one the same way into `.env.gagarin` and
  `gg resource rotate shop/gagarin --env-file .env.gagarin`; the service rolls with
  it. Never `--set TOKEN=…`: that puts the token on a command line.
- **`gg creds revoke ID` stops it**, and `gg creds` lists it under the name you
  gave it.

## Dependencies: what may reach what

Every service in a project is default-denied. A private service is reachable
only from services that have declared they need it, and **an undeclared call is
dropped rather than refused** — it does not fail fast, it hangs until the client
gives up, which for a database driver can be thirty seconds or forever.

**A hang between two of your own services is a missing `gg deps` far more often
than it is a bug in the application.**

```
gg deps ls  shop/api            what it reaches today
gg deps add shop/api db cache   and these as well
gg deps rm  shop/api cache      and no longer that one (needs a human)
```

- **Withdrawing needs a human's approval; adding does not.** `gg deps rm` is
  gated the way `gg destroy` and `gg domain rm` are: it answers
  `approval_required` and emails the account owner a sentence naming the edge.
  The asymmetry is the point — opening a path breaks nothing, and closing one
  breaks something *silently*, because the calls that used to arrive are dropped
  rather than refused. Ask the user before you request that approval, and tell
  them what will stop being able to reach what.
- **The direction matters.** The declaration goes on the *caller*. If `api`
  queries `db`, it is `api` that needs `db`, never the other way round. Backwards
  is refused, not quietly accepted.
- **Reaching a resource also hands over its credentials.** `gg deps add shop/api
  db` gives `api` `DB_URL`, `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD` and
  `DB_DATABASE`, and the command prints which ones arrived. Connecting is this
  one call; it used to be two, and that is no longer necessary.
- **`--deps` on a deploy or a ship only ever adds.** It exists so a service that
  cannot start without a database can be declared and deployed together.
  Forgetting it on the next deploy changes nothing. Withdrawing is `gg deps rm`,
  there and nowhere else. (If you are working from memory and reach for
  `--needs`: it is gone. It replaced the whole set on every deploy, so a redeploy
  that forgot it silently withdrew an edge — and because an undeclared call
  hangs, the service did not break, it went quiet.)
- **Public URLs are not covered by this.** One service calling another's public
  `https://` address arrives the way a stranger's browser does and is allowed.
  The guarantee is about private, in-project addresses.
- **Withdrawing applies to new connections, not open ones.** `gg deps rm` closes
  the path for anything that connects afterwards, but a client holding a
  keep-alive connection — every HTTP client, every driver pool — keeps using it
  until it reconnects. That is how Kubernetes network policy works. If you need
  the old path gone now, redeploy the caller: a new pod has no old connections.
- `gg destroy` on something another service still needs is refused, and names
  what depends on it. `gg deps rm` that first.

`gg status` ends every service's row with a REACHES column, so checking the
graph costs nothing — do it *before* you go debugging a hang.

### Reaching the outside world

Outbound is unrestricted, with one exception you need before you build on it:
**the mail ports — 25, 465 and 587 — are blocked.** A connection to any of them
times out, from every service, and it cannot be opened per-account.

So **do not build anything that speaks SMTP.** If the user wants their
application to send email, reach for a provider's HTTPS API — Resend, Postmark,
SendGrid, SES, any of them. That is a normal way to send mail, not a workaround,
and it is what Gagarin itself does. Prefer the provider's official SDK to
hand-rolled HTTP.

The reason, if the user asks: a service that can open those ports can relay spam
if it is ever compromised, and a hosting account that relays spam gets suspended
— which would take every other project on the platform down with it.

If you find yourself debugging a hanging SMTP connection, stop. It is not the
user's code and it is not DNS. It is this.

## Resources: what a project *has*

A resource is provisioned rather than deployed. There is no image to choose, no
version to pass and no Dockerfile.

```
gg resource add shop/db postgres --size m --storage 20 --ext vector
gg resource add shop/vectors qdrant
gg resource add shop/cache valkey
gg resource add shop/events iggy
gg resource add shop/jobs rabbitmq
gg resource add shop/files s3
gg resource add shop/openai external --env-file .env.openai
```

| type | what it is | storage | backups |
|---|---|---|---|
| `postgres` | PostgreSQL 17, with the extensions you ask for (`vector`, `postgis`, …) | on a volume; survives restarts | nightly, kept 14 days |
| `qdrant` | vector database, for retrieval | on a volume; survives restarts | nightly, kept 14 days |
| `iggy` | Apache Iggy, a persistent message-streaming log | on a volume (10 GB unless `--storage`); survives restarts | nightly, kept 14 days — see the durability caveat |
| `rabbitmq` | RabbitMQ 4.4.0 with the management plugin, a message broker for work queues | on a volume (10 GB unless `--storage`); durable queues and persistent messages survive restarts | **none** |
| `valkey` | in-memory store, redis protocol | **none — a restart loses everything** | none, by design |
| `s3` | an S3-compatible bucket, for files — private until `gg resource public` | **objects on durable storage; it runs nothing** | **none** |
| `external` | a third-party API, run by nobody here | **none — it runs nothing at all** | nothing to back up |

The types are named for what actually runs, not for the products they stand in
for — an honesty you can pass on when somebody asks.

- **`qdrant` is Qdrant**, Apache-licensed, and it is what an application does
  retrieval against: embeddings in, nearest neighbours out. Three things about
  it are unlike every other type, and all three will bite an agent that assumes
  otherwise.
  - **The credential is not in the URL.** `<NAME>_URL` is a bare
    `http://vectors:6333`; the key arrives separately as `<NAME>_API_KEY` and
    travels as an `api-key` header. Every client takes it as its own argument —
    `QdrantClient(url=os.environ["VECTORS_URL"], api_key=os.environ["VECTORS_API_KEY"])`.
  - **It answers on two ports.** `<NAME>_PORT` is 6333 (HTTP/REST) and
    `<NAME>_GRPC_PORT` is 6334. The Python, JS, Java and .NET clients want the
    URL; the official **Go and Rust clients speak only gRPC** and want the host
    and 6334. Both are published so neither has to be guessed.
  - **There is no MongoDB here, and no document store either.** If a user wants
    documents rather than vectors, Gagarin has no type for it — run one as an
    ordinary service with a volume.

  - **Qdrant or `vector` on a postgres?** Both store embeddings. If the
    application wants relational tables and embeddings in one database —
    joined in one query, written in one transaction — ask for the `vector`
    extension on its postgres (see "Postgres extensions" below). That is the
    default for an application that already needs a postgres and adds
    retrieval: one resource, one set of credentials, one backup. Reach for
    `qdrant` when the vectors *are* the product — the search is what the
    application is for, and it deserves a database of its own.

  Gagarin ran a `ferretdb` type from 2026-09-04 to 2026-09-06 and it is **gone**:
  it promised MongoDB compatibility and did not keep the promise past the simple
  cases. There is no alias and no migration path. If a user names it, say it was
  removed and offer the service-with-a-volume route.
- **`iggy` is Apache Iggy**, Apache-licensed: a persistent message-streaming
  log, what an application publishes events to and consumes from in order. One
  pod, one volume (10 GB by default; `--storage` is accepted), private like every
  resource, so it is reached only by services that declare it with `deps`.
  - **It answers on two ports.** `<NAME>_PORT` is 8090, the TCP binary protocol
    every Iggy SDK speaks, and `<NAME>_HTTP_PORT` is 3000, for REST. QUIC and
    WebSocket are off.
  - **The credential is in the URL.** `<NAME>_URL` is the connection string the
    SDKs read, `iggy://root:<password>@events:8090` for a resource called
    `events`; `_USER` is always `root`.
  - **A backup can miss recent messages unless the topic is persisted.** The
    backup is taken while the server keeps running, so only topics created with
    `--durability persisted` are guaranteed complete. A topic with the default
    durability may be missing its newest messages, the ones not yet flushed to
    disk. Have producers create topics with `--durability persisted` for
    anything the user would want back from a backup, and say so when you set one
    up.
- **`rabbitmq` is RabbitMQ** 4.4.0 with the management plugin: a message broker,
  what an application publishes jobs to and workers consume from. One pod, one
  volume at `/var/lib/rabbitmq` (10 GB by default; `--storage` is accepted),
  private like every resource, so it is reached only by services that declare it
  with `deps`. Add it, then let the worker reach it: `gg resource add shop/jobs
  rabbitmq`, then `gg deps add shop/worker jobs`.
  - **It answers on two ports.** `<NAME>_PORT` is 5672, AMQP, the protocol every
    client speaks, and `<NAME>_HTTP_PORT` is 15672, the management UI and HTTP
    API.
  - **The credential is in the URL.** `<NAME>_URL` is
    `amqp://app:<password>@jobs:5672/%2F` for a resource called `jobs` (the
    `%2F` is the default vhost `/`), and it goes straight to the client: pika,
    amqplib, amqp091-go, or a Celery `broker_url`. `_USER` is always `app`.
  - **There are no backups.** `gg resource backup` answers `backup_unsupported`.
    Unlike iggy, there is nothing to recommend that makes a backup complete,
    because there is no backup. What survives a restart is only what is durable:
    declare queues `durable` and publish messages `persistent` (delivery mode 2)
    for anything the user wants to outlive the pod. A transient queue or message
    is gone on a restart, which happens on a node drain, not only when somebody
    asks.
  - **Declare queues and exchanges from application code, at startup.** The
    broker keeps no copy elsewhere, so a fresh one (a destroyed and re-added
    resource, or a lost volume) must be rebuildable by just starting the
    application. Declaring is idempotent when the arguments match, so every
    producer and consumer can do it on every start. Do not create topology by
    hand in the management UI and leave it there.
  - **Choose it for work queues, routing and fan-out to workers**; choose
    `iggy` for an append-only log that consumers replay from an offset. If the
    user wants to re-read history, it is iggy; if each message is a job to be
    done once and then forgotten, it is rabbitmq.
- **`valkey` is a cache, not a database.** `--storage` is refused (`no_storage`)
  rather than quietly ignored, and everything in it is gone when the pod restarts
  — which happens on a node drain, not only when somebody asks. Do not put a
  session store there that a user would notice losing, and do not tell anyone
  their data is safe in it. Valkey is the BSD-licensed fork of Redis; `redis://`
  URLs, `redis-cli` and every client library work unchanged.
- **Storage can grow, never shrink.** Restate the resource with a bigger
  `--storage` to raise the ceiling — `gg resource add shop/db postgres --storage
  40` on an existing `db` grows it and changes nothing else. A smaller number is
  refused with `volume_immutable`.
- **One instance, one volume, no failover.** A size change or a restart is a
  brief outage. There is no point-in-time recovery. Say that plainly if a user
  asks whether their data is safe, rather than implying an SLA nobody is on the
  hook for.
- **A resource cannot be deployed over.** `gg deploy shop/db` against one is
  refused with `not_a_service`, which is telling you the name is already a
  database. Nor can a resource declare dependencies: it is reached, it does not
  reach.
- **A managed resource cannot be rolled back**, because Gagarin mints its
  credentials and there is no earlier value of the user's to go back to. An
  **external can** — its values are theirs — and `gg rollback P/NAME` is how a
  config change is undone. See the external section below. An `s3` cannot
  either, for the same reason.

### Postgres extensions

A `postgres` takes **extensions**: the set of postgres extensions the database
should have, named exactly as `CREATE EXTENSION` names them.

```
gg resource add shop/db postgres --ext vector --ext postgis    create it with both, or restate it
```

Over MCP it is the `extensions` list on `add_resource`; on the API it is the
`extensions` field of the resource's PUT body,
`{"type":"postgres","extensions":["vector","postgis"]}`. `--ext` takes one name
and is repeated, like `--deps` and `--env` — not a comma-separated list. The
rules are the same everywhere:

- **It is the whole set, not a delta.** `--ext vector` on a postgres that has
  `vector` and `postgis` asks for postgis to go. To add one, restate every one it
  already has plus the new one — `gg status` lists what it has.
- **Leave it out and the extensions stay as they are**, exactly like `--size`.
  An empty list (`[]`, or `--ext ""`) means none.
- **Only a postgres has them.** `extensions` on any other type is refused with
  `no_extensions`.
- **On create, they exist before the database is first ready.** Adding one to
  an existing postgres is **immediate, on the running server, with no
  restart** — every postgres runs the same image with all of them compiled in.
- **Dropping one asks no one** — the one removal that does not, because a drop
  refuses rather than loses anything, so a drop that succeeds cost nothing.
  **It is never CASCADE**: a column, an index, a view or a SQL-standard
  function that uses the extension — a `vector` column, say — stops it. **And
  it is refused while the extension's own tables hold the user's data**:
  pg_cron's jobs (`cron.job`) and their run history, pg_partman's partition
  config (`partman.part_config`), a spatial reference system the user added to
  PostGIS's `spatial_ref_sys`. Nothing depends on those tables, so without the
  guard a plain DROP would delete every scheduled job. Either refusal is
  `extensions_failed` (HTTP 409), carrying postgres's own reason — "column e
  of table items depends on type vector", or "extension pg_cron holds 1 row(s)
  of your data in cron.job; remove them first if losing them is what you
  mean". It is one transaction, so a refused change changes nothing — not the
  extensions, and not the rest of what the command restated. To really drop
  it, remove what is in the way first — and ask your human before deleting
  their jobs or data to do it. A plpgsql function that uses the extension is
  not tracked by postgres, so it breaks when next called; nothing is lost, and
  adding the extension back mends it.
- **Requirements are added for you.** Asking for `earthdistance` also gives
  `cube`.
- **Ask the platform; do not run `CREATE EXTENSION` by hand** for anything in
  the catalogue below. `app` is a superuser in its own pod and *can*, but what
  it creates that way is not recorded in `extensions`: the platform does not
  know about it, the status does not show it, and nothing keeps it. Asking the
  platform records it and keeps it.

**The catalogue — everything `extensions` accepts:**

| name | what it is for |
|---|---|
| `vector` | pgvector: vector columns with HNSW and IVFFlat indexes, for embeddings |
| `postgis` | PostGIS: geometry and geography types, spatial indexes and functions (no raster) |
| `pg_cron` | scheduled SQL, run by the database itself (jobs run in database `app`) |
| `pg_partman` | partition management, created in schema `partman` |
| `pgaudit` | audit logging to the resource's log (set `pgaudit.log` to turn it on) |

Plus the contrib extensions that ship with postgres: `pg_stat_statements`,
`pg_trgm`, `pgcrypto`, `uuid-ossp`, `citext`, `hstore`, `ltree`, `unaccent`,
`fuzzystrmatch`, `btree_gin`, `btree_gist`, `cube`, `earthdistance` (adds
`cube`), `intarray`, `tablefunc`, `amcheck`, `pg_buffercache`.

- **"pgvector" is called `vector`.** That is its name in postgres, and asking
  for `pgvector` is refused with a hint saying so. There is no pgvector
  resource type: embeddings in a postgres are this extension.
- **Not offered:** timescaledb (its licence forbids exactly a hosted service),
  raster, `dblink`/`postgres_fdw`/`file_fdw`, untrusted languages. Any name
  outside the catalogue is refused with `unknown_extension`, and the hint lists
  every name that is offered.
- Nothing else about the postgres changes: the same connection variables, sizes,
  storage, price, rotation and nightly backups.

### Connecting one: the single call

```
gg deps add shop/api db
```

That declares the dependency **and** puts the database's connection variables in
`api`'s environment. It prints what arrived:

```
api reaches db, and nothing else.

api now holds DB_DATABASE, DB_HOST, DB_PASSWORD, DB_PORT, DB_URL, DB_USER
  in its environment, from the resources it reaches. Values: gg resource secrets.
```

Or declare it on the deploy, so the service never starts without them:
`gg deploy shop/api:8080 api:v3 --deps db`.

**The variables are named after the resource, not the protocol** — the resource's
own name, upper-cased with dashes as underscores, plus a suffix:

| suffix | postgres | valkey | qdrant | iggy | rabbitmq |
|---|---|---|---|---|---|
| `<NAME>_URL` | `postgres://…?sslmode=disable` | `redis://:pass@…` | `http://vectors:6333` | `iggy://root:pass@events:8090` | `amqp://app:pass@jobs:5672/%2F` |
| `<NAME>_HOST` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `<NAME>_PORT` | 5432 | 6379 | 6333 | 8090 | 5672 |
| `<NAME>_GRPC_PORT` | — | — | 6334 | — | — |
| `<NAME>_HTTP_PORT` | — | — | — | 3000 | 15672 |
| `<NAME>_USER` | ✅ | — | — | `root` | `app` |
| `<NAME>_PASSWORD` | ✅ | ✅ | — | ✅ | ✅ |
| `<NAME>_API_KEY` | — | — | ✅ | — | — |
| `<NAME>_DATABASE` | ✅ | — | — | — | — |

An `s3` bucket publishes none of these. It publishes five of its own:
`<NAME>_ENDPOINT`, `<NAME>_REGION`, `<NAME>_BUCKET`, `<NAME>_ACCESS_KEY_ID` and
`<NAME>_SECRET_ACCESS_KEY` — see its section below. While it is public it also
publishes `<NAME>_PUBLIC_URL`.

A postgres called `db` publishes `DB_URL`; one called `orders-db` publishes
`ORDERS_DB_URL`; a valkey called `cache` publishes `CACHE_URL` and no
`CACHE_USER`, because valkey has no users. A type omits the suffixes it has no
answer for rather than publishing them empty — so an absent `VECTORS_PASSWORD`
is not a bug, it is a qdrant having no password. Two consequences, and both are
the point: a service can reach two databases without a collision, and there is
one vocabulary of suffixes rather than a different set per type.

**These are not the names your framework expects, and that is deliberate.** There
is no `DATABASE_URL`, no `PGHOST`, no `REDIS_URL`, no `QDRANT_URL` unless the
resource happens to be called `qdrant`. The first thing to try is to have the
application read `DB_URL` — one line in the app, and nothing about it can go
stale.

If you genuinely cannot change the application, read the value out and pass it
under the name it wants:

```
gg deploy shop/api:8080 api:v3 --deps db \
  --env DATABASE_URL="$(gg resource secrets shop/db --format json | jq -r .env.DB_URL)"
```

Note what that is: **a copy**, and the only stale thing in the model. `$DB_URL`
alone would not work — the injected variables exist inside the pod, not in the
shell running `gg`. Say so rather than leaving a second copy of a password in a
deploy nobody remembers making.

Four rules that follow, and each one fails quietly if you get it wrong:

- **Injected variables outrank your own.** Set `DB_URL` on a deploy while the
  service also reaches a resource called `db`, and the resource wins. It is the
  one place something beats what a deploy said, and the reason is that only the
  resource knows the real password.
- **Nothing is copied into the stored environment.** The platform unions these in
  every time it renders the pod, from the graph as it stands then. They cannot go
  stale, no redeploy can forget them, and **a rollback restores the image and the
  environment you deployed with, never an old password.** `gg deps rm` takes them
  away just as surely.
- **Holding the credentials is not enough.** The network policy is a separate
  boundary from the environment. You cannot get the credentials without the
  declaration that opens the route, so this is no longer a trap — but do not
  conclude from a working password that the route is open for some *other*
  service you did not declare.
- **`gg resource secrets` is for reading the values from outside the graph** —
  checking what an application is being handed, or wiring up a client that runs
  outside Gagarin. The values name the in-project host, which this machine
  cannot reach: to actually connect from here, `gg connect` opens a tunnel and
  prints them rewritten for it. You do not need either to connect a service in
  the same project. Treat the output as a live credential: do not echo it into
  a chat, a commit, or a summary.
- **`--names` when the question is "what does it publish"**, which it usually
  is: what a bundle holds, or what a key is called before you change it. It
  asks a different endpoint, so the values are not fetched rather than merely
  not printed — nothing secret passes through you. `gg status` cannot answer
  this: it prints `DB_*`, the prefix rule rather than the contents.

```
gg resource secrets shop/db --names         # just the names — reach for this first
gg resource secrets shop/db > .env.db       # KEY=VALUE lines into a file, for --env-file
gg resource secrets shop/db --format json | jq -r .env.DB_URL > db.url   # one value, into a file
```

### Meddling from this machine: `gg connect`

```
gg connect shop/db
```

A resource is not on the internet, and stays off it. When a human needs psql
against the real database — a migration to babysit, a row to look at — this
opens a tunnel from this machine and prints the same variables a service would
hold, rewritten to point at 127.0.0.1:

```
db is a postgres. The tunnel is up:

  DB_HOST=127.0.0.1
  DB_URL=postgres://app:…@127.0.0.1:5432/app?sslmode=disable
  ...
```

- **It lasts exactly as long as the command.** Ctrl-C closes the tunnel and
  every connection through it. Nothing is exposed, and there is nothing to
  undo afterwards.
- **It is for the machine gg runs on, never for services.** A service reaches
  a resource by declaring it — `gg deps add shop/api db` — which needs no
  tunnel and survives any command exiting. Do not leave `gg connect` running
  as plumbing under an application.
- **Every port the resource answers on gets a local end** — a qdrant tunnels
  6333 and 6334 at once, an iggy 8090 and 3000, and a rabbitmq 5672 and
  15672 (the management UI is then at `http://127.0.0.1:<local port>`). Each prefers its own number and quietly takes a free
  one when that is busy; `--port` pins the primary, and is refused rather than
  moved when the port is taken.
- **An external is refused** (`not_tunnelable`), and an s3 is refused by `gg`
  itself ("publishes no port to tunnel to"): nothing runs, so there is nothing
  to tunnel to. Their values are `gg resource secrets`.
- **The resource must be running.** A stopped one refuses with
  `tunnel_unavailable`, and `gg status` says what it is waiting on.
- The printed values are live credentials on a local port, and the same rule
  as secrets applies: do not echo them into a chat, a commit, or a summary.

### `external`: a third-party key as a node on the graph

An OpenAI account, a Stripe key, a bucket somewhere else. Not something Gagarin
runs — something your services need a credential for.

```
gg resource add shop/openai external --env-file .env.openai
gg deps add shop/bot openai
```

An `.env.openai` holding `API_KEY` and `BASE_URL` makes `bot` hold
`OPENAI_API_KEY` and `OPENAI_BASE_URL`. Same naming rule as every other type, so
**write the keys without the prefix** — `API_KEY`, not `OPENAI_API_KEY`, which is
refused rather than doubled.

**This is where every third-party credential goes. A deploy env is not an
alternative.** Why not `--env OPENAI_API_KEY=…` on the deploy? Because a key on a
deploy is a copy. Three services using one key means three copies, rotating
it means three deploys, and a deploy you forget leaves a service authenticating
with a revoked key. As a resource it is one row and rotating is one command.

- **Use `--env-file`, not `--env`.** A key on the command line goes into the shell
  history and into the transcript of every agent that ran the command. Ask your
  human to write the key into `.env.NAME` themselves; do not ask for it in chat.
  If they paste one anyway, write it to the file without repeating it, and tell
  them it is now in this chat's history, so it should be rotated at the provider.
- **Restating an external is refused** once it exists (`already_exists`). That
  refusal is deliberate: restating from an old `.env` would roll the key
  *backwards*, and the failure would be an authentication error nobody would
  connect to the command they ran. Changing values is `gg resource rotate`, and
  changing *one* of them is `gg resource rotate --set K="$(cat FILE)"`, which
  leaves the rest alone and keeps the value off the command line.
- **It runs nothing.** No container, no port, no size, no storage, no backups,
  nothing to become ready. `gg status` shows it as `◆` and leaves every
  container column a dash; what it publishes is `gg resource secrets P/NAME
  --names`.
- **Declaring an external does NOT restrict egress.** This is the one thing not to
  get wrong when you explain it. Everything in a project can already reach the
  whole internet — the mail ports are the only exception. What the declaration
  grants is the credentials and a line on the graph saying who uses them. It is
  **not** a firewall: an undeclared service can still call `api.openai.com`, it
  just has no key. `gg status` marks these edges `◆` for exactly this reason.
- **What it is genuinely worth:** the project's dependencies become legible, and
  destroying an external is refused while anything still declares it, so a key
  cannot be dropped out from under a running service.

### An external is also where shared config belongs

Not only third-party credentials. **Anything several services read, or that
changes without a deploy, belongs in an external** — feature flags, a log level,
a region, an API base URL, a tuning constant.

```
gg resource add shop/config external --env-file .env.shared
gg deps add shop/web config
gg deps add shop/worker config          # both hold CONFIG_LOG_LEVEL

gg resource rotate shop/config --set LOG_LEVEL=debug   # both roll, with the new value
gg rollback shop/config                                # both roll back
```

**Why this beats `--env` on each deploy:** the same argument as for a key. An
env on a deploy is a copy, so two services sharing a setting is two copies that
can disagree, and changing it is two deploys with one you can forget. Resolved
from the graph it is one row, one command, and every holder restarts.

**The editing model is the sharper difference, and it is the one that decides
this for you.** A service's environment can be changed only by `gg deploy`, and
a deploy **replaces it wholesale** — every variable not restated is gone. That
is deliberate, not an oversight: the revision records exactly what the service
ran with, which is what makes a rollback mean something. The cost is that
changing one variable requires having all of them.

|  | service env | external |
|---|---|---|
| changed by | `gg deploy`, and only a deploy | `gg resource rotate` |
| granularity | wholesale — anything omitted is **lost** | one key at a time |
| needs the other values in hand | **yes** | no |
| undo | `gg rollback P/SVC`, with the deploy | `gg rollback P/config` |

**For you this is a hard edge, not an inconvenience.** Working without the
project's `.env` file — from the console's Agent tab, or any session handed a
task rather than a repository — you cannot safely change one variable on a
service. The only route is to read the whole environment back out of
`gg history` and restate it, which drops anything you misread and pulls **every**
value the service holds, secrets included, through your transcript.

`gg resource rotate P/config --set KEY=value` has neither problem: it touches the
one key, needs nothing else in hand, and reads no other value. **So when a user
asks you to change a setting and you do not have their env file, the answer is
an external — and if the setting is currently in a deploy env, say so and offer
to move it.**

And to find out what a bundle holds before you change one key of it:

```
gg resource secrets shop/config --names      # names only; no values fetched
```

Use `--names` by default. Without it the command prints live credentials, and
in your case that means into a transcript. `gg status` will not answer this
either — it lists the resource and nothing about its contents.

The full lifecycle is there, which is what makes it safe to recommend:

| | |
|---|---|
| set it | `gg resource add P/config external --env-file .env` |
| change one value | `gg resource rotate P/config --set LOG_LEVEL=debug` |
| remove one | `gg resource rotate P/config --unset REGION` |
| see what it was | `gg history P/config` |
| put it back | `gg rollback P/config [--to N]` |
| see what keys it has | `gg resource secrets P/config --names` — no values fetched |
| read the values | `gg resource secrets P/config` — live credentials; prefer `--names` |
| who uses it | `gg status P` — and destroying it is refused while anyone does |

**Where the line is.** Config *owned by one service* stays in its `gg deploy
--env`, because that is the half a service rollback restores. Injected values
are re-derived from the resources as they stand now — deliberately, so nobody is
ever rolled back onto a rotated password — so `gg rollback shop/web` will not
undo a config change. Undo it at the resource.

Three properties to state when asked, because they are constraints and not
oversights:

- **The prefix is not optional.** A resource named `config` publishes
  `CONFIG_LOG_LEVEL`, never a bare `LOG_LEVEL`. Name the resource so the prefix
  reads the way the application wants it.
- **A dependent cannot override a value.** Injected beats the service's own env
  of the same name. Two services needing different values is two resources.
- **Every dependent gets every key** in the bundle. Split by audience, not by
  topic: one resource per set of services that should hold the same things.

### `s3`: a bucket for files

User uploads, generated files, ML artifacts, static assets an app serves
itself. Gagarin's object storage, as an S3-compatible bucket that is private
until you say otherwise.

```
gg resource add shop/files s3
gg deps add shop/web files
```

`web` now holds `FILES_ENDPOINT`, `FILES_REGION`, `FILES_BUCKET`,
`FILES_ACCESS_KEY_ID` and `FILES_SECRET_ACCESS_KEY` (same prefix rule as every
other type). There is **no `_URL`, `_HOST`, `_PORT`, `_USER` or `_PASSWORD`** —
an S3 client takes these five settings separately. Any S3 client library works
(boto3, the AWS SDKs, …); **pass the endpoint and the region explicitly**, or it
will look for AWS. The endpoint is `https`.

- **`--size`, `--storage` and `--env` are all refused** (`no_size`,
  `no_storage`, `no_env`). A Gagarin without object storage configured answers
  `object_storage_unavailable` (HTTP 501); report it.
- **It runs nothing.** No pod, no port, no volume, no logs. Gagarin mints its
  key, like postgres — unlike an external.
- **A bucket is private by default.** Only its own key can read or write it;
  another project's key cannot.
- **`gg resource public P/NAME` makes the whole bucket listable and readable by
  anyone**, no key needed. Writes still need the key. Every dependent then gets
  `<NAME>_PUBLIC_URL` (`https://<bucket>.s3.fr-par.scw.cloud`) and is restarted
  for it; `gg resource private P/NAME` undoes it and the variable goes away. Both
  are idempotent, need the editor role and a deploy-scope credential, and
  `publish_failed` changed nothing, so run it again. The public address also
  shows in `gg status` among the project's domains.
  - **Only make public what is genuinely meant to be public.** Listing exposes
    every object name in the bucket, not just the ones the app links to, and
    anything fetched while it was open stays fetched. User uploads that are
    meant to stay private belong in a private bucket, served by the app (which
    proxies them or hands out its own signed links). Ask the user before
    running it.
  - **Browsers on any site can read it.** Making a bucket public also sets a
    CORS rule: any origin, `GET` and `HEAD` only, no credentials. So
    `fetch()` of an object or the listing, web fonts, ES modules and
    `<img crossorigin>` (and reading a canvas) work. It adds no exposure, since
    a public object was already readable with curl, and writes still need the
    key. `gg resource private` removes it. A bucket made public before this
    existed gets it by running `gg resource public` again. The tenant cannot
    set CORS itself.
  - **Egress is not metered per bucket yet.** Say so to the user when a public
    bucket is going to carry heavy traffic (a download host, a busy site's
    images).
- **Declaring it does NOT restrict the network.** It is reached over the
  internet, not inside the cluster, so — exactly like an external — the
  declaration hands over the key and nothing more. It is not a firewall. `gg
  status` marks these edges `◇`.
- **There are no backups.** Objects sit on durable storage but Gagarin takes no
  copy, and `gg resource backup` answers `backup_unsupported`. If losing the
  data would matter, keep a copy somewhere else.
- **`gg connect` does not work**: it publishes no port, and `gg` says so. Read
  the values with `gg resource secrets`.
- **It costs $0.03 per GB-month** of what it actually holds, measured hourly,
  rounded up to whole GB and prorated per minute. There is no running charge,
  and requests and traffic are not billed.
- **Not deployable, not rollback-able, no `gg domain`.** `gg deploy` over it is
  `not_a_service`, as is `gg rollback` (Gagarin mints its key). Its public
  address comes from `gg resource public`, not from a domain.
- **Destroying it** needs the human's email approval, is refused while anything
  still declares it, cuts the key off at once, and permanently deletes every
  object shortly after.

A bucket the user already has somewhere else is still an `external`.

### Rotating credentials

```
gg resource rotate shop/db                                        a database
gg resource rotate shop/openai --set API_KEY="$(cat new.key)"     one of an external's values
gg resource rotate shop/openai --env-file .env.new                all of them
```

Everything holding the old credential is restarted with the new one, and the
command names what it rolled. Nothing but variable *names* is printed;
`gg resource secrets` reads the values, into a file.

**Who supplies the new value is the only difference between the types.** For
`postgres`, `qdrant`, `valkey`, `iggy`, `rabbitmq` and `s3`, Gagarin mints one and `--env` is refused — a
password you chose is one the running server has never heard of. For an
`external` the values are yours, so one of `--set`, `--unset`, `--env-file` or
`--env` is required.

**An external usually holds more than one value, and the two ways of changing
them mean different things. Reach for `--set`.**

| | what it means |
|---|---|
| `--set K=V`, `--unset K` | change these, leave every other key exactly as it is |
| `--env`, `--env-file` | the bundle is now precisely this; anything not in it **stops being published** |

`--env API_KEY=sk-new` on an external that also holds `BASE_URL` takes `BASE_URL`
away from every dependent. That is the correct meaning of that request — it is
the one to use after a provider migration where every value is new — and the
wrong one for the far commoner job of replacing a single key. Reading the bundle
back and restating it is not the answer either: that is the stale-file path, and
it is how a key gets rolled backwards.

The command names what stopped being published, so a loss is visible at the
moment it happens rather than from a dependent that can no longer authenticate.
The two flags cannot be combined — they say the same thing in incompatible
words.

`--unset` names a key **without** the resource's prefix, the way it was set:
`--unset BASE_URL` on `shop/openai`, not `OPENAI_BASE_URL`. A key the resource
does not publish is refused rather than quietly doing nothing, because a no-op
reported as a success is how somebody believes a secret is gone when it is not.

| type | what happens | cost |
|---|---|---|
| `postgres` | the running server is told immediately | none |
| `qdrant` | the pod is replaced; the key is read at startup | a few seconds away; **the data survives** |
| `iggy` | the running server is told the new root password first and it is recorded, then the pod restarts and dependents roll | a few seconds away; **nothing stored is lost**, a graceful stop flushes |
| `rabbitmq` | the running server is told the new password first, then the pod restarts and dependents roll | a few seconds away; **nothing stored is lost** |
| `valkey` | the pod is replaced; the password is read at startup | **the cache is emptied** |
| `s3` | a new key is issued and recorded, dependents restart, then the old key is revoked at once | **not zero-downtime:** their S3 calls fail for the seconds the restart takes; **the objects survive** |
| `external` | nothing of ours runs, so nothing of ours restarts | none |

**An s3 rotation can revoke late.** If the answer says `old_credential_revoked:
false`, the old key still works: tell the user, and run the rotation again — it
revokes the leftover key first.

**If it fails, nothing changed.** The old credential is still in use and the
command is safe to run again — say that, rather than leaving the user wondering
what a half-failed rotation left behind. There is no half.

**Rotate after a leak, and say so plainly.** If a key has been in a chat log, a
commit or a screenshot, this is the fix and it is one command. For an external,
note that Gagarin forgets the old value but cannot *revoke* it — that is a thing
to do in the third party's own console, and the user has to do it.

### Backup and recovery

Postgres, qdrant and iggy are backed up nightly and kept fourteen days — postgres as a
`pg_dump`, qdrant as a tar of its per-collection snapshots with the aliases
beside them.

**An iggy backup is taken while the server keeps running.** Only topics created
with `--durability persisted` are guaranteed complete; a topic with the default
durability may be missing its newest messages, the ones not yet flushed to disk.
Recommend `--durability persisted` for anything the user would want back. Valkey keeps nothing by design, an external has nothing here to
keep, and an s3 bucket is not copied: its objects are on durable storage, but
`gg resource backup` answers `backup_unsupported`. A rabbitmq is in the same case: it is not backed up at all, so its
durability is only what survives a restart (durable queues, persistent messages).

```
gg resource backups shop/db     what is stored, newest last
gg resource backup  shop/db     take one now — do this before a risky migration
```

**Any postgres backup restores into any postgres.** A dump carries its
extensions and every postgres has every one available, so a database that used
`vector` or `postgis` comes back with them; the restored resource's
`extensions` are read back from the database. There is nothing to ask for
before restoring.

`gg resource backup` reads the database and writes an object; it is safe at any
time and the nightly schedule keeps running regardless.

**A restore creates a NEW resource — it never overwrites an existing one.** That
is the platform's rule, not a convention: the name you give must not exist yet,
and the platform creates the resource itself, which is exactly why a restore
needs no human approval and can be reached for at three in the morning.

```
gg resource restore shop/db2 --source db   new resource, filled from db's newest dump
gg deps add shop/api db2                   hands api DB2_URL and the rest
gg deps rm  shop/api db                    and stop it reading the old one
                                           (this one needs a human's click)
gg destroy  shop/db                        once everything reads from db2 — the only
                                           step that destroys data, and the only one
                                           that asks a human
```

- **The variables change with the name.** `db2` publishes `DB2_URL`, not
  `DB_URL`, so an application reading `DB_URL` finds nothing after the `deps rm`.
  Either name the new resource what the old one was called — possible only once
  the old one is destroyed — or expect to touch the application. This is the one
  place the per-resource naming costs something, and it is worth knowing before
  three in the morning.
- The old resource **may already be destroyed** when you restore: its backups
  outlive it by fourteen days and `--source db` still finds them.
- `--backup <key>` from `gg resource backups` restores an exact point instead of
  the newest.
- **The platform does the restore, not the command.** It creates the new
  resource as the backup's type — recorded with every backup, so there is
  nothing to say even for a destroyed source — then starts it and pours the data
  in on its own. `gg resource restore` waits and prints each step by default;
  stopping it stops nothing. With `--no-wait` it returns at once, and `gg status`
  shows the restore under the resource until it is done, or why it failed.
  **Do not `deps add` anything to the new resource before it is done.**
- A failed restore leaves a resource holding nothing worth keeping: destroy it
  and restore again under a new name once the cause is fixed.
- `gg resource backups shop/db` works on a destroyed resource too, and shows what
  it left.

### Anything we do not have a type for

Four types will never cover everything. Run it as an ordinary service with a
volume:

```
gg registry copy shop/clickhouse clickhouse/clickhouse-server
gg deploy shop/analytics:8123 clickhouse --volume /var/lib/clickhouse --volume-size 50
gg deps add shop/api analytics
```

Everything else behaves the same way: a private address by name, a volume that
survives restarts, and the same refusal to delete it while something still needs
it. The only difference is who decides — for a resource the platform picks the
image, the version and the port and carries them; here you pick them, and
upgrades, tuning and consequences are yours.

**If a type exists, use the resource. If it does not, this is the normal path,
not a workaround.** Gagarin has no type for ClickHouse, Cassandra, DuckDB or a
document store, and that is not an error.

Never write a one-line Dockerfile that only says `FROM` in order to get an image
in. `gg registry copy` is the same thing, done properly, and it copies every
architecture the source published rather than whatever your laptop cached.

## Recipes: a project other people can deploy

A recipe is a published snapshot of a project: its services, jobs, resources,
dependencies and sizes. Anyone who has the recipe's 8-character id can deploy it
into a **new** project of their own. It is never installed into an existing
project. Its deploy page is `https://my.gagarin.cloud/deploy/<recipe-id>`, and
a publisher can put this badge in a README:

```
[![Deploy to Gagarin](https://gagarin.cloud/deploy-button.svg)](https://my.gagarin.cloud/deploy/<id>)
```

Recipes are not part of `.gagarin.json`. That file still only names the project.

### Publishing: `gg recipe snap`

```
gg recipe snap shop --dry-run                       what would be published, and the floor
gg recipe snap shop                                 publish, at the floor version
gg recipe snap shop --version 1.2.0 --as shop-kit   pick the version and the name
gg recipe snap shop --source https://github.com/acme/shop --notes "faster checkout"
```

Only the project's owner can snap. **Run `--dry-run` first**, and show the user
the floor and what will be published before you publish. A recipe version is
immutable once it exists.

**Env in a recipe never holds secrets.** Plain env on a service or a job is
copied as it is, so anything secret-shaped must not be there. Secrets belong in
an `external` resource. A recipe keeps the external's variable names and never
their values, and each name becomes an input the deployer supplies. If snap
answers `env_looks_secret`, it names the variables:

```
gg resource add shop/stripe external --env-file stripe.env
gg deps add shop/api stripe
gg deploy shop/api:8080 api:v3                      restate the env without them
gg recipe snap shop                                 and snap again
```

Do not rename a variable to get past the check. Move the value to an external.

### The floor

Each snap has a lowest allowed version, worked out from the previous one:

- a removal, a rename, a volume change or a type change forces a **major**
- an addition, or a bigger monthly bill, forces at least a **minor**
- anything else is free, and may be a patch

Omit `--version` to take the floor. A version below it is refused
`version_below_floor`, and the dry run prints the reasons.

### Reading

```
gg recipe show a1b2c3d4                  the graph, inputs, monthly cost, deploy URL
gg recipe show a1b2c3d4@1.2.0            one version
gg recipe show a1b2c3d4 --format json    the manifest, for reading by a program
gg recipe ls                             the recipes this account published
```

`show` works on any recipe id, not only your own. Read it before you install,
and tell the user what it will cost and which inputs it wants.

### Installing: `gg recipe install`

```
gg recipe install a1b2c3d4 shop --input stripe=stripe.env
gg recipe install a1b2c3d4@1.2.0 shop --input stripe=stripe.env --input mail=mail.env
```

Always a new project: `NEW_PROJECT` must not exist yet. Pass one `--input
NAME=FILE` for every input the recipe declares, which `gg recipe show` lists.
Each file is an env file. **Never put a value on the command line.** Ask the
human for the values, write them to the file, make sure the file is
gitignored, and delete it when the install finishes. gg refuses up front when a
declared input has no `--input`, and it never prints what a file holds. The
install copies the images into the new project, then starts everything. It ends
with the project's status, so follow the usual rule and read it before you
promise a URL.

### Updating

```
gg recipe diff shop                      what the newest version would change
gg recipe diff shop --to 1.3.0
gg recipe update shop                    apply it
gg recipe update shop --to 1.3.0 --input mail=mail.env
gg recipe update shop --force            overwrite what was changed by hand
```

An update is the patch between two versions, not a reinstall. Always `diff`
first and tell the user what changes. A new input needs its `--input` file, the
same as an install. An update that **removes** something needs a human's
approval, like any destroy. If the project was changed by hand where the patch
also changes it, the update refuses with a conflict. Ask the user before you
pass `--force`, because it overwrites their change.

### Removing

```
gg recipe rm a1b2c3d4@1.2.0              one version
gg recipe rm a1b2c3d4                    the recipe, and every version
```

This needs a human's approval, like every destroy: follow "Destroying things".
Projects already installed from the recipe keep running.

## Addresses

A service is private until it is given an address, and one command gives it
either kind:

```
gg domain add shop/web                     an address gagarin generates
gg domain add shop/web shop.example.com    a name the user owns, as well
gg domain ls  shop                         every address, and who each is waiting on
```

The generated one is idempotent and instant: Gagarin holds the wildcard record
and the wildcard certificate for the project's cluster, so there is nothing to coordinate and nobody to
wait for.

**A name the user owns is two steps, and only the first is Gagarin's.** The
command makes the service answer for the name; making the name *resolve* here is
a DNS record the user creates at their registrar, and Gagarin cannot do it for
them. The command prints the exact record — pass it on verbatim rather than
paraphrasing it.

**Nothing is served over HTTPS on that name until the record exists.** Let's
Encrypt proves control by fetching the domain over the internet, so a certificate
cannot be ordered before DNS points here. That is the normal first state, not a
fault: do not retry the command hoping it resolves, because the missing piece is
on their side. `gg status` says which of the two of you it is waiting on:

| reading | who acts |
|---|---|
| waiting for DNS | **them** — the record does not exist at the zone's own nameservers |
| DNS points elsewhere | **them** — it resolves, but not to Gagarin |
| waiting for cache revalidation | **nobody** — the record is right; a resolver is still holding its old answer, and it clears within the zone's negative TTL |
| issuing certificate | Gagarin — nothing for them to do |
| ok | nobody |

Gagarin orders the certificate only once the zone's own nameservers point the name
here, so claiming a name before creating the record is harmless. On `waiting for
cache revalidation`, do not touch the DNS record and do not retry; tell the user it
clears by itself (often 15–60 minutes) and the certificate follows.

The generated address only ever reads `ok` or `issuing certificate`. It is never
waiting on the user, because there is nothing for them to do about it.

- **A deploy never changes an address**, in either direction. Forgetting a flag
  would otherwise take a live site down while the owner's DNS still looked right.
- **Both addresses answer.** A service with a custom domain keeps its generated
  one, so existing links do not break and there is something to test against
  while DNS propagates.
- **A custom domain brings the generated one with it.** Claiming a name for a
  private service makes it public in the same call. Say out loud that you are
  putting it on the internet.
- **One domain, one service, across all of Gagarin.** A name somebody else holds
  is refused, and the refusal does not say who holds it.
- **A subdomain is told a CNAME to the cluster's name**, such as
  `CNAME fr-par-1.apps.gagarin.cloud`, not to the old shared `apps.gagarin.cloud`.
  Pass on the target the command prints; it depends on the project's cluster.
- **An apex domain gets an A record, not a CNAME** — DNS does not permit a CNAME
  at an apex. The command prints the right one; do not "correct" it.

### Taking an address away

```
gg domain rm shop/web shop.example.com    release a name they own
gg domain rm shop/web                     make the service private again
```

**Both need a human's approval, every time** — the same emailed click `gg
destroy` and `gg deps rm` need. This is destructive in the way deleting something is: what breaks
is invisible from the terminal and obvious to whoever was using the address. Do
not run either unless the user asked for it in those words.

Releasing the generated address while a custom name is still declared is refused
(`domain_attached`) — that would leave their DNS pointing at a host Gagarin no
longer serves. Release the custom name first.

## Reading state

`gg status <project>` reports desired state and actual cluster state side by
side. Trust it over your own memory of what you deployed: it reads the cluster,
not just the database.

```
project shop  (id 7f3a9c2e)  fr-par-1

     SERVICE  KIND      SIZE  READY  PORT  REACHES      IMAGE
  ●  web      service   s     1/1    8080  api          web:1757030400
  ●  └ https://web-7f3a9c2e.fr-par-1.apps.gagarin.cloud
  ●  api      service   m     1/1    4000  db, openai◆  api:1757030112
  ●  db       postgres  m     1/1    5432  —            postgres:17
  ◆  openai   external  —     —      —     —            —
  ◇  files    s3        —     —      —     —            —

  ● running   ◆ external (runs nothing; declaring it grants its variables, not egress)
  ◇ bucket (runs nothing; reached over the internet, so declaring it grants its key, not a network path)
  $0.412 today so far
```

What to read, in the order it matters:

1. **Lines beginning `!`, when there are any, come before the table because they
   change what the table means.** There are two:
   - **"this project is suspended and nothing is running: …"** — every service
     shows `◌` and `0/0`, and writes are refused with `project_suspended`. If the
     reason is credit, the user fixes it at https://my.gagarin.cloud/billing and
     services restart by themselves within a few minutes. Anything else is a
     decision Gagarin made, and only support can lift it — do not tell the user
     to add credit, because it will not help. **Nothing has been deleted**: the
     data, the addresses and the certificates are all still there.
   - **"the reconciler last ran … ago"** — Gagarin reporting on itself. The rows
     are still an accurate reading of the cluster, but nothing is closing the gap
     between them and what was asked for. Tell the user; there is nothing an
     agent can do from here.
2. **The state mark.**
   - `●` **running** — the cluster is running what was asked for, and something
     answers on the declared port.
   - `◐` **starting** — in flight: pulling, booting, waiting on an ingress. The
     cluster has not given up and neither should you.
   - `○` **failing** — either nothing is in the cluster at all, or Kubernetes has
     stopped calling this a rollout in progress. Waiting will not fix it.
   - `◌` **stopped** — the project is suspended. See the `!` line.
   - `◆` **external** — runs nothing, so it has no state to be in.
   - `◇` **bucket** — an `s3`: runs nothing either, and its edges read `files◇`.
   - `✓` **done** — a job whose latest run finished with exit code 0. A job
     whose run failed is `○`, and the line under the table gives its exit code.
   - `◷` **scheduled** — a scheduled job that has not fired yet. Waiting, not
     wrong: its line says when it fires next.
3. **`◐` and `○` print the cluster's own explanation below the table.** Read it
   before changing anything.
4. **READY counts pods of the revision you asked for.** A redeploy that will not
   start reads `0/1` even while the previous version is still serving traffic.
   That is the honest number: the service is answering, but not with what you
   shipped. For a job the cell is the latest run's phase instead — `done`,
   `failed`, `running`, `pending` — its PORT is a dash, and the line under the
   row says which run, when, how long, the exit code, and for a failed run the
   cluster's reason: `○  └ run 4 failed 2 minutes ago after 3s, exit 2: the
   container exited with code 2`. A scheduled job's cell also carries its
   schedule (`⏱ 0 3 * * *`), and its line ends with when it fires next
   (`· next in 21h`) or that the schedule is suspended with the project. A scheduled firing whose TTL
   passed still shows, ending "(removed after its ttl)"; `gg logs` keeps its
   output. A one-shot job past its TTL is not listed at all.
5. **Addresses hang under their service**, marked `●` when there is nothing left
   to do and `○` with who is holding it up when there is. An address that is fine
   says nothing more than its own URL.
6. **KIND and VOLUME columns appear only when the project has something to put in
   them**; SIZE is always there.
7. **The last line is the day's accrued cost**, in thousandths of a dollar.

Other readers:

```
gg projects                 every project you can reach, its id, and your role
gg logs shop/web            recent logs; needs a running pod (logs_unavailable if not).
                            For a job: what its latest run wrote
gg history shop/web         every deploy, newest first, the live one marked →
gg deps ls shop/web         what it may reach
gg domain ls shop           every address and its state
gg creds                    every credential, the one you are using marked *
```

When somebody wants to understand how their services fit together, point them at
the project's page on https://my.gagarin.cloud — its right half is a live
dependency graph. That is for the human; read the plain output yourself.

Describe services at the altitude Gagarin does: "web is public on port 8080 at
<url>; worker is private." Give every address a service answers on, not just one.
Do not introduce Kubernetes vocabulary — namespaces, ingresses, pods and service
accounts are not part of this model, and mentioning them is a regression.

## Undoing a deploy

```
gg history  shop/web          revision numbers, images, when, and who —
                              an image tagged with a short hash is that commit
gg rollback shop/web          put the previous deploy back
gg rollback shop/web --to 3   a particular revision
gg rollback shop/config       put an external's previous values back
```

- **A rollback is a deploy.** It goes through the same write gate and is recorded
  as a *new* revision naming the one it restored. Nothing leaves the history, so
  changing your mind is another rollback rather than a lost record.
- **It restores the image and the environment**, exactly as that revision had
  them. A variable added since is gone afterwards.
- **It does not restore the dependency graph, the domain or the volume.** Those
  are standing declarations about the shape of the project rather than parts of
  the artifact, and putting yesterday's image back says nothing about them.
- **It never restores an old password.** Resource variables come from the graph
  at pod-start, not from the revision.
- **It is refused across a change of volume** (`volume_immutable`). Deploy the
  configuration you want instead.

Prefer a rollback to a corrective deploy when something you just shipped is
broken and you do not yet know why: one call, a state that provably ran, and the
evidence left intact for afterwards.

## Alerts

A project can tell its members when something breaks. Alerts are Web Push
notifications from the console (https://my.gagarin.cloud), which is also a PWA.
Each member opts in per project for themselves, viewers included, and the
notifications go only to that member's own devices. There is no topic, server
or token to set up.

**A human turns alerts on, in the console.** The project's Alerts tab,
`https://my.gagarin.cloud/projects/P/alerts`, has one switch, "Notify me about
this project", which allows notifications on that device and opts the member in
at once, and sends a test from the same page. Point the human there, on the
phone they want the push on. Turning the switch off there opts them out.

There is no gg command for alerts (`gg metrics` is for the numbers, below):
talking the human through that page is your part. With the MCP server connected, `alerts` says whether the caller is opted
in, how many devices they have, and the last few notifications; `test_alerts`
sends a test once they say it is on; each takes only the project. Opting in is
per member, so one member turning alerts on does not turn them on for anyone
else.

**An agent cannot add a device.** A device exists only once a human allows
notifications in a browser, at `https://my.gagarin.cloud/projects/P/alerts`. On
an iPhone the app must first be added to the Home Screen (Share, then Add to
Home Screen) and opened from there, or the browser will not offer push at all.
If the human has no device yet, hand them that page. Then they hear
when a service has been down for three minutes, when a deploy will not start
(the previous revision keeps serving), and when a container crashes and
restarts, once when it starts and once when it ends, never on repeat. The
console keeps a 30-day feed of these notifications. Four more come from the
metrics, each also once when it starts and once when it resolves: memory at 80%
of its limit or more for 5 minutes (resolves under 75%); CPU at 80% of its
limit or more for 10 minutes (resolves under 70%); a volume 85% full (resolves
under 80%); and 5% or more of requests answered with 5xx over 5 minutes, with
at least 20 requests (resolves under 2%). Tapping one of these opens that
service's graphs. They are part of the same fixed set. There are no rules or
thresholds to choose. Offer alerts after a first deploy that a human cares
about; do not turn them on without asking, because the notifications go to somebody.

The old ntfy alerts are gone: `--server`, `--topic` and `--token` no longer
exist, and sending them is refused with `ntfy_removed`.

## Metrics

Every cluster keeps a metrics store, 30 days deep. For each service, and each
resource (postgres, qdrant, iggy, rabbitmq, valkey), it holds CPU used against
its limit (cores), memory against its limit (bytes), volume disk used against
its size, CPU throttling (the share of periods), and network in and out
(bytes/s); for a service with a public address, also requests/s, the share of
5xx and p95 latency. Windows are `1h`, `24h`, `7d` and `30d`. A figure that was
not measured is `null`: a service that just started, no volume, no address.
Figures appear a minute or two after a service starts.

- `gg metrics PROJECT` is a table of every service now: CPU, memory, disk, and
  req/s, 5xx and p95 for the public ones.
- `gg metrics PROJECT/SVC [--window 1h|24h|7d|30d]` gives current, average, peak
  and limit for each figure over the window.
- In MCP, `metrics` takes `{project, service?, window?}`: project-wide figures
  now, or one service's last/avg/peak/limit per series over a window.
- The console has a **Metrics** tab, `https://my.gagarin.cloud/projects/<id>/metrics`
  (`?service=NAME&window=24h`).

Use it to answer "why is it slow", "is it running out of memory" and "is the
disk filling" from numbers rather than a guess. `gg status` stays the answer to
"is it up". `metrics_unavailable` means the cluster has no metrics store or it
did not answer: retry in a minute.

## Sharing a project

A project has exactly one **owner** — the account that pays for it — plus any
number of editors and viewers.

```
gg members shop                     who can reach it, and as what
gg share shop teammate@example.com  add an editor (the default)
gg share shop them@example.com --role viewer
gg unshare shop them@example.com
```

An **editor** operates the project — deploy, delete individual services, manage
the roster — without paying for it. A **viewer** reads status, logs and the
member list, and nothing else. **Destroying a project is the owner's alone**:
that takes its data and its URL with it, and only the account paying can decide.
Ownership is not on this list because it is the bill, not a role: it is not
granted here, it is offered and accepted — see below.

- `gg share` with no `--role` grants **editor**, which can deploy over whatever
  is running. If the user asked for "read access" or "let them look at the logs",
  pass `--role viewer`.
- Sharing with somebody who has never used Gagarin is allowed — the access waits
  for them and lands the moment they sign in with a GitHub or Google account
  whose verified email is that address. **Nothing is emailed to them**, so tell
  the user to let them know; they get in by running `gg login` and approving it,
  as in "Getting access".
- **Ask before sharing.** Access to a project is the user's to give, not yours to
  infer from a name in the conversation.

## Handing a project over

Sharing gives access away. `gg transfer` gives away the **bill** — who pays for
the project from that moment on.

```
gg share shop them@example.com       first: they must already be a member
gg transfer shop them@example.com    offer it; nothing changes yet
gg transfer shop --withdraw          take the offer back
gg members shop                      shows an offer that is standing
```

It is an offer, never an assignment, and both halves need a human:

1. The **owner** runs `gg transfer` and gets `approval_required` — they click a
   button in their own inbox, signed in to Gagarin, and you run the same command
   again. This is the
   same human gate `gg destroy` uses, for the same reason: a handover cannot be
   undone by the person who started it.
2. The **recipient** gets an email and presses a button. Until they do, nothing
   has changed and `gg members` still shows the old owner. **Tell the user this**
   — a transfer that is "done" from the CLI is a transfer that has not happened.

What happens when they accept: the project keeps its id, services, addresses,
data and history — **nothing restarts**. Usage is billed to the new owner from
that moment, and to the old owner up to it. The **previous owner becomes an
editor**, so they keep operating it and stop paying for it; the new owner can
`gg unshare` them like anyone else.

- **Only the owner can offer**, and only to somebody already on the roster. Share
  first.
- If the recipient already has a project by that name, pass `--as NAME` — names
  are unique within an account, and this is what the project is called in theirs.
- The recipient's account has to be able to carry it: not suspended, has a card
  or a balance, and under their project limit. The refusal comes back to the
  owner with the fix in it — those are things the two of them sort out before
  anybody clicks.
- `gg unshare` on the person an offer was made to **withdraws the offer too** —
  an offer only ever goes to a member, so taking the access away takes the offer
  with it.
- **Never offer a project the user has not explicitly asked you to hand over.**
  This is the one command that ends with them not paying for something they no
  longer own, and no amount of context makes it inferable.

## Diagnosing

Start from the symptom, not from the logs.

| symptom | first suspect | what to run |
|---|---|---|
| a service never becomes ready | the declared port; the app binds elsewhere or on `127.0.0.1` | `gg status`, then redeploy on the port the app really binds |
| `ImagePullBackOff` | the image is not there — a copy that never finished, or a tag that does not exist | `gg history`, then push or copy the image again |
| the container starts and exits | a missing environment variable, or a crash | `gg logs shop/web` |
| killed with no log output | out of memory | `gg status` names the size to move to |
| one service hangs calling another | a missing `gg deps` edge — an undeclared call is dropped, not refused | `gg deps ls shop/api`, or the REACHES column |
| a database driver times out | the same, or the app is not reading `<NAME>_URL` | `gg deps ls`, then `gg resource secrets` to see what it should hold |
| you need to look inside the database itself | it is not on the internet, by design | `gg connect shop/db`, then psql or redis-cli against the printed URL |
| an SMTP connection hangs | ports 25, 465 and 587 are blocked platform-wide | use a provider's HTTPS API; nothing to fix here |
| a custom domain serves no HTTPS | DNS does not point here yet | `gg domain ls`; the record is the user's to create |
| everything shows `◌` and `0/0` | the project is suspended | read the `!` line above the table |
| `docker push` returns 401 in CI | docker was never logged in | `gg registry login` |

**"nothing is listening on port N" is the common one**, and it is almost always
the port rather than the app. Gagarin asks the container every few seconds
whether anything accepts a connection on the port you declared, so a service that
boots perfectly well and listens somewhere else never becomes ready. Many
frameworks also default to `127.0.0.1`, which nothing outside the container can
reach — they need `0.0.0.0`.

**"the previous revision is still serving"** on a redeploy means the old version
is up and answering. The user is not down. Fix the new revision and ship again;
do not tear anything down first.

**Out of memory names its own fix**, in `gg status`:

```
the container ran out of memory and was killed (it exceeded the 1Gi ceiling of
size s); try --size m, which gets 2Gi
```

Redeploy at the size it names. Do not retry unchanged — it will be killed again —
and do not go hunting in the logs first, because a process the kernel killed for
using too much memory usually writes nothing about it. This is the one failure
you can resolve without asking the user anything, so resolve it.

Do not poll in a tight loop, and do not tell the user something is live because a
command exited zero.

## Error codes

gg prints failures as `[code] message`, usually with a `hint:` line under it.
**Branch on the code.** The message is for the human.

**Access and credentials**

| code | what to do |
|---|---|
| `unauthorized` | this machine has no usable credential — run `gg whoami`, then "Getting access". Never ask the user for a token |
| `insufficient_scope` | this credential does not carry that right; a browser session cannot deploy. Deploy from the CLI — the dashboard has no deploy button on purpose |
| `cannot_delegate` | a minted credential tried to mint another. Mint it from the machine a human approved |
| `name_required` | `gg creds create` with no `--name`. Name it after where it will live |
| `invalid_expiry` | `--expires` outside 1–365 days. There is no never; omit it for 90 |
| `name_too_long` | over 120 characters, and it appears in a list. Shorten it |
| `approval_required` | a human must approve a deletion, a released address, a withdrawn dependency, or an ownership offer. The button is in their email, and it asks them to sign in first if they are not. Tell the user, pass on the code, wait, retry the same command. One click covers fifteen minutes, so a sequence of these needs one approval, not several |
| `authorization_pending` | nobody has approved the `gg login` request yet. Relay the link again if needed; run `gg login` again once the user says they approved |
| `expired_token` | the `gg login` request lived fifteen minutes and nobody approved it. Run it again and pass on the new link |
| `access_denied` | the user declined `gg login` on the page. Ask them before running it again |
| `github_account_too_new` | the user's GitHub account is under 30 days old. The `gg login` request is still good: they open the same link, choose Continue with Google, approve, and you run `gg login` again |
| `invalid_email` | the address given to `gg share` or `gg transfer` is not one. Ask the user again; do not guess |

**Projects and roles**

| code | what to do |
|---|---|
| `project_not_found` | no such project, **or** you cannot reach it. `gg projects` lists what you can; `gg init` creates one; otherwise ask for a `gg share` |
| `project_suspended` | the project accepts no writes; reads still work. Out of credit: the user adds some at https://my.gagarin.cloud/billing and it restarts itself. Anything else: only support can lift it — tell the user and stop |
| `project_limit` | destroy one that is no longer needed, or the user writes to support@mail.gagarin.cloud |
| `project_exists` | you already have one by that name. Names need only be unique within your account |
| `invalid_name` | lowercase letters, digits, hyphens; start with a letter; 2–30 characters |
| `insufficient_role` | you are a viewer here. Ask the owner or an editor for edit access; do not retry |
| `owner_only` | only the paying account may do this. Tell the user to run it themselves; nobody can grant it |
| `invalid_role` | roles are `editor` and `viewer`; `owner` is the account that pays |
| `owner_not_a_member` | that address already owns the project; nothing to do |
| `member_not_found` | `gg members <project>` shows who has access |

**Handing a project over**

| code | what to do |
|---|---|
| `not_a_member` | share it first: `gg share P EMAIL`, then offer it |
| `already_owner` | they already own it; nothing to do |
| `name_taken_there` | they have a project by that name. Re-run with `--as NAME` |
| `recipient_suspended` | their account is stopped; they add credit, then you offer again |
| `recipient_cannot_pay` | no card and no balance there; the project would be suspended on arrival. They fix it at https://my.gagarin.cloud/billing |
| `recipient_project_limit` | their account is full; they destroy one, or write to support@mail.gagarin.cloud |
| `no_offer` | nothing is pending. If it was accepted, the project is theirs and only they can offer it back |
| `project_suspended` on a transfer | a project suspended in its own right cannot change hands. Only support can lift that |

**Alerts**

| code | what to do |
|---|---|
| `alerts_off` | `test_alerts` before alerts are on. The human turns them on with the switch at https://my.gagarin.cloud/projects/P/alerts |
| `ntfy_removed` | alerts no longer go to ntfy; `server`, `topic` and `token` are refused. The human turns alerts on in the console |
| `no_devices` | `test_alerts` and the caller has no device. The human allows notifications at https://my.gagarin.cloud/projects/P/alerts (iPhone: add the app to the Home Screen first) |
| `invalid_subscription` | the browser's push subscription was refused (not https, not a known push service, bad keys). The human re-enables notifications in the console |
| `push_unconfigured` | the platform has no push keys yet. Nothing to fix on your side; tell the user |

**Metrics**

| code | what to do |
|---|---|
| `metrics_unavailable` | 503: the cluster has no metrics store, or it did not answer. Retry in a minute; `gg status` still shows what is running |
| `no_such_service` | 404 on `gg metrics P/SVC` or `metrics`: that name is not a service here. `gg status` lists them |

**Services, images and deploys**

| code | what to do |
|---|---|
| `image_required` | `gg push` one first, or use `gg ship` |
| `docker_not_installed` | from gg itself, before any request: there is no `docker` (or, for `gg registry copy`, no `buildx`). Ask your human to install Docker Desktop, OrbStack or colima (Docker Engine on Linux). An image already in the registry needs no docker: `gg deploy` it |
| `docker_not_running` | docker is installed but its daemon did not answer; the message names the socket. Ask your human to start it and run `gg ship` again once `docker info` succeeds |
| `docker_permission_denied` | this user cannot reach the daemon (Linux). Ask your human to add the user to the `docker` group and log in again. Never run gg with `sudo` |
| `image_not_yours` | the image is not in this project's registry space. Build or push into this project, or `gg registry copy` it in |
| `invalid_digest` | pass what `docker push` reported, or leave it out |
| `invalid_port` | set the port the container actually listens on |
| `invalid_timeout` | `timeout_seconds` outside 1–3600. Give 1–3600 or leave it out |
| `service_has_no_timeout` | `timeout_seconds` was given on a service rather than a job. Drop it; a service runs until it is replaced |
| `invalid_ttl` | `ttl_seconds` outside 60–28800. Give 60–28800 or leave it out to keep the current one (28800 for a new job) |
| `service_has_no_ttl` | `ttl_seconds` was given on a service rather than a job. Drop it; a service runs until it is replaced, only a job's finished runs expire |
| `invalid_kind` | `kind` is absent for a service or `job` for a job; nothing else exists |
| `job_has_no_port` / `job_has_no_volume` | drop the field: a job listens on nothing and keeps nothing. Durable data goes in a resource it reaches |
| `not_a_job` | that name is a service; a job needs a name of its own |
| `invalid_schedule` | five cron fields like `"0 3 * * *"`, or `@daily` and the like. Not `@every`, no `CRON_TZ=` — the zone is `--tz`. An empty one is refused too: a schedule cannot be removed, so destroy the job to stop it |
| `invalid_time_zone` | an IANA name like `Europe/Berlin` or `UTC` — or a `--tz` given to a job with no schedule |
| `service_has_no_schedule` | `--schedule`/`--tz` reached a service. A schedule is a job's: `gg run` |
| `job_running` | a one-shot job was given a schedule while its run is going. Wait for it to end (`gg status`), or destroy the job |
| `invalid_volume` | an absolute path inside the container, e.g. `/var/lib/postgresql/data` |
| `volume_immutable` | a volume is set once and never moves or resizes. Keep it, or destroy the service and deploy again — which throws the data away |
| `invalid_size` | sizes are `s`, `m`, `l`; the message names the account's cap |
| `no_such_revision` | `gg history` lists the ones it had |
| `nothing_to_roll_back_to` | deployed only once. Not a bad call, just nothing to do |
| `not_a_service` | that name is a resource or a job — you tried to deploy a service over it, give it an address, or roll back a managed resource whose credentials Gagarin mints, s3 included (an external can be rolled back) |
| `not_a_resource` | that name is a service. `gg status` shows which is which |

**The graph**

| code | what to do |
|---|---|
| `invalid_needs` / `invalid_deps` | a blank name, a service naming itself, or a job named as something to reach — a job listens on nothing. Correct them; `gg deps ls` shows what is declared |
| `no_such_service` | a name in `gg deps add` or `--deps` is neither a service nor a resource here. `gg status` lists them; create it first |
| `service_in_use` | something still declares it needs this. The refusal names what; `gg deps rm` that edge first — which needs its own approval, though the same click covers the destroy that follows |

**Resources**

| code | what to do |
|---|---|
| `no_such_resource` | `gg status <project>` lists what it has |
| `unknown_resource_type` | `postgres`, `qdrant`, `valkey`, `iggy`, `rabbitmq`, `s3` or `external` |
| `wrong_resource_type` | another type already holds that name. Destroy it — which throws its data away — or pick another name |
| `invalid_storage` | 1 to 100 GB |
| `no_extensions` | only a `postgres` takes extensions: drop `--ext` |
| `unknown_extension` | not in the catalogue; the hint lists every name offered. `pgvector` is called `vector`. timescaledb is not offered |
| `extensions_failed` | HTTP 409: postgres refused — usually dropping an extension a column still uses, or one whose own tables still hold the user's rows (pg_cron's jobs, say). The message is postgres's own reason. **Nothing changed**; remove what is in the way, then restate the set |
| `no_storage` | this type has no volume (valkey, s3): drop `--storage` |
| `no_size` | an external or an s3 runs nothing: drop `--size` |
| `invalid_env` | write `API_KEY`, not `OPENAI_API_KEY` — the prefix is the resource's name |
| `already_exists` | restating an external. `gg resource rotate` is how values change |
| `env_required` | an external's values are the user's; pass `--set K=V` for one of them, `--env-file` for all |
| `conflicting_env` | `--env`/`--env-file` replace the bundle and `--set`/`--unset` amend it: use one or the other |
| `no_such_key` | that external does not publish the key named in `--unset`. `gg resource secrets` lists what it does — and the name goes in without the resource's prefix |
| `no_env` | this type mints its own credentials (s3 included), so there is nothing to pass or amend; `gg resource secrets` reads them |
| `object_storage_unavailable` | HTTP 501: this Gagarin has no object storage configured, so no `s3`. Report it to the user |
| `not_a_bucket` | HTTP 409: only an `s3` can be made public. A service gets an address with `gg domain add` |
| `publish_failed` | HTTP 502: **nothing changed** — retry `gg resource public` or `private` |
| `rotate_failed` | **nothing changed** — the old credential still works. Check `gg status` for a resource that is not running, then retry |
| `cannot_rotate` | no credentials recorded to replace; worth reporting as a bug |
| `not_tunnelable` | an external runs nothing, so there is nothing to tunnel to; its values are `gg resource secrets` |
| `tunnel_unavailable` | no running pod on the far end. `gg status` says why, then run `gg connect` again |

**Backups**

| code | what to do |
|---|---|
| `backup_unsupported` | only postgres, qdrant and iggy have backups; an s3 bucket is on durable storage but never copied, and a rabbitmq is not backed up at all (declare its queues from application code so a fresh broker can be rebuilt). If losing the data would matter, keep a copy elsewhere |
| `backup_unconfigured` | this Gagarin runs without a backup bucket. Report it to the user |
| `restore_name_taken` | a restore creates the resource it fills. Give it a name nothing has yet |
| `backup_mismatch` | that key belongs to another project. Never restore across projects |
| `backup_type_mismatch` | that key was written by no type that has backups — check it against `gg resource backups` |
| `no_backups` | the nightly pass takes the first one; `gg resource backup` takes one now |
| `backup_list_failed` / `backup_failed` | the resource must be running — check `gg status`, then retry once |

**Addresses**

| code | what to do |
|---|---|
| `invalid_domain` | a hostname the user owns: no scheme, no port, no path |
| `domain_taken` | another service holds that name. The refusal does not say who |
| `domain_attached` | release the custom names first, or their DNS points at a host that no longer answers |

**The platform itself**

| code | what to do |
|---|---|
| `apply_failed` | desired state saved, cluster update failed. Retry the same command; it is idempotent |
| `cluster_error` / `internal_error` / `eject_failed` | not your call's fault. Report it to the user |
| `logs_unavailable` | no running pod yet. Check `gg status` first |
| `timeout` | retry once; if it persists, tell the user |
| `rate_limited` | wait a minute. Never retry in a tight loop |
| `body_too_large` | large values belong in a resource, not in a deploy call |
| `no_such_route` | you are calling the API directly and got the path wrong. Use `gg`, the only supported client |

## Destroying things

```
gg destroy shop        the project, and everything in it
gg destroy shop/web    one service
gg destroy shop/db     one resource, and its data
```

You do not say which of the last two a name is; gg asks the platform, which
already knows.

**This will be refused the first time, and that is not a bug.** Your credential
can deploy but not delete, so destroying anything — and the other irreversible
acts, `gg domain rm` and `gg deps rm` — needs a human every time the approval
window has lapsed. You get `approval_required`, and Gagarin emails the
account owner. Then:

1. Tell the user what you are about to delete, and that you have asked them to
   approve it by email — the button asks them to sign in to Gagarin first if
   they are not. Pass on the code from the `fix_hint`.
2. Wait for them to say they clicked it. Do not poll in a loop.
3. Run the same command again.

**Ask the user before *requesting* the approval**, not just before retrying — an
approval email for a deletion they never asked for is alarming. Only a project's
owner can destroy the project; an editor gets `owner_only`, and no amount of
approval changes that, because the answer is "ask the person paying for it".

If a deploy went wrong, prefer fixing it with another `gg ship`. Destroying and
recreating a project loses its data and its URL.

## Leaving

```
gg eject shop -o project.yaml
```

Writes the Kubernetes manifests for the whole project — namespace, and per
service its Deployment, Service, Ingress, NetworkPolicy, environment Secret and
volume claim. These are not a description of what Gagarin runs; they are the
objects it runs, so `kubectl apply -f` on any cluster with an ingress controller
reproduces the project.

Owner only, because the file holds every service's environment in the clear. It
is written mode 0600 and you should treat it as a credential.

Three things it deliberately does not contain, all explained in its own header:
the **images**, which are still in Gagarin's registry and have to be pulled and
pushed somewhere the user controls; the **registry pull secret**, which is a
live credential; and the values from any **external resource**, which are
third-party keys somebody else issued, and an **s3 bucket's** keys, which like an
external's work from anywhere — they come out as a `REPLACE-ME` placeholder
naming the resource, and the header lists exactly which variables to fill in. Volume
claims come back empty — data has to be taken out of the running service.

A minted credential — a database password — *is* in the file, and the asymmetry
is the point: that password is only a risk against a database in the same file,
and an export without it does not come up. A third-party key stays live wherever
the file ends up. `gg eject shop --with-secrets -o project.yaml` includes them,
for a migration happening now into a file that gets deleted; say what that means
before running it with the flag.

Offer this without being defensive when somebody asks what happens if Gagarin
goes away. It is a real answer and it is meant to be used.

## Things Gagarin deliberately does not do

Not missing features. Do not attempt them and do not suggest workarounds:

- deploy from a git repository or a git URL
- read deployment configuration from a file in the repo — `--env-file` supplies
  values, and is the only file Gagarin will ever read
- interpolate variables into each other
- pull images from Docker Hub, GHCR or any registry other than Gagarin's at run
  time (`gg registry copy` brings one in first)
- expose Kubernetes, cloud provider or networking primitives
- open the mail ports
- infer a project from the current directory, or from anything else —
  `.gagarin.json` included: you read that, Gagarin never does
