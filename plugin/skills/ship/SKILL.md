---
name: ship
description: Take the current repository to production on Gagarin Cloud end to end — Dockerising if needed, creating the project, provisioning databases, wiring dependencies, building and shipping the image and giving it an address. Use when the user asks to deploy, host, ship or put an application on the internet with Gagarin.
---

You take the repository in front of you to a working HTTPS URL on Gagarin Cloud.

Read the `gagarin` skill of this plugin before anything else. It is the
authority on every command, flag and error code here; read it rather than
guessing. What follows is only the order of work and the mistakes that matter.
If your host offers subagents, run everything after "Before anything" in one:
it is a long procedure, and the main conversation only needs its report.

The user may have named a target — `project/service:port`. If they did not,
work out a sensible one from the repository and **confirm it with the user
before creating anything**. `.gagarin.json` at the repository root, if it
exists, names the project a previous session used and is the default when no
target names one; still confirm.

## Before anything

Two things are faster to catch here than three steps in:

- `gg` is on the PATH. If it is not, stop and tell the user to run this
  plugin's `setup` skill (`/gagarin:setup` in Claude Code). The MCP tools
  cannot substitute: they deliberately cannot build or push an image, and that
  is most of this procedure. The same applies if you cannot run commands where
  you are (ChatGPT on the web, for instance): say that building happens with
  `gg ship` on the machine that holds the source, and that from here you can
  deploy an image already in the registry, wire dependencies, add an address
  and read status over the MCP tools — and stop.
- `docker` is running (`docker info`). `gg build` and `gg push` shell out to
  it. If it is not, ask the user to start or install it and stop there.

Then `gg whoami`. If it reports no credentials, stop and tell them to run
`gg login`; relay the link and code exactly as printed and never handle a
secret yourself.

`git` is not required. If the directory is not a repository, or `git` is
missing, say once that `.gagarin.json` will not be committed and carry on. If
it is a repository with uncommitted changes, tell the user the image will be
tagged from the clock rather than the commit, and let them commit first if they
want the hash — do not commit for them.

Then read `.gagarin.json`, if there is one, and `gg projects`, before assuming
a project exists or that you may write to it. If the note names a project
`gg projects` does not list, the API is right — fix the file and say so. A
`viewer` role means every deploy will be refused.

If the project already exists and the Gagarin MCP tools are connected, call
`memory_briefing` for it before reading any code, with a `focus` that says what
you are about to do ("deploy the web service"): a previous session may already
have found the port, the Dockerfile quirk and the variables the app needs.
Without the MCP tools, skip this — memory is unavailable there, and nothing
else waits on it.

## The order

1. **Understand the repo.** What does it run, what port does it listen on, what
   does it need? A Dockerfile that already exists is the answer; if there is
   none, write one and say you did.
2. **Agree the names.** Everything is named for its project — `shop` is a
   project, `shop/web` a service inside it. Nothing is inferred from the
   directory. Confirm `project/service:port` with the user before creating
   anything.
3. **`gg init <project>`** if it does not exist yet. Either way, once the
   project is settled, write `.gagarin.json` — `{ "project": { "id": "…",
   "name": "…" } }`, with the id `gg init` printed or the one `gg projects`
   shows — and commit it if this is a git repository (if it is not, say so;
   do not `git init` on your own). Identity only: no ports, no services, no env.
   Nothing reads it; you still name the project in every command.
4. **Provision what it needs** — `gg resource add`. If a resource type exists,
   use it rather than running your own container.
5. **Wire it** — `gg deps add <service> <resource>` opens the route *and* hands
   over the credentials. It is one call, not a call plus a deploy.
6. **`gg ship <project>/<service>:<port>`** — build, push and deploy fused.
7. **`gg domain add`** — a service is private until it has an address.
8. **`gg status <project>`** until it is actually up.

## The five mistakes to not make

- **A zero exit code is not success.** Every write is asynchronous: a command
  that exits zero recorded a demand, it did not watch it come true. `gg status`
  reads the cluster and is the only thing that can answer "is it up". Poll it.
  Never report a deploy as working on the strength of `gg deploy` returning.
- **Never invent a flag.** A refused command names the shape it should have had;
  read the refusal. Error codes are stable — act on the code, not the prose.
- **A deploy replaces the environment and nothing else.** Restate every variable
  every time. Dependencies, the domain, the volume and the size all survive a
  deploy that forgets to mention them; env does not.
- **No secret goes in a deploy env.** A Gagarin database's credentials arrive
  with `gg deps add`; a third-party key (Stripe, OpenAI, SMTP, a webhook secret)
  becomes an `external` resource, written to a file, never passed with `--env`.
  If the application's `.env` holds secrets, move them into externals and deploy
  the rest. Say which ones you moved, by name only. If you cannot tell whether a
  variable is secret, treat it as one.
- **A private service is default-denied.** Until the *caller* declares
  `gg deps add`, its calls are dropped — which hangs rather than failing fast.
  If something times out reaching something else, check the graph first.
- **You cannot destroy anything.** Deleting a project, service or resource needs
  the account holder's approval by email, every time. If the path forward needs
  a deletion, stop and say so. Do not pretend it succeeded, and do not work
  around it.

## Finishing

Report the address, what is running on it, and what it is connected to. If
anything is still converging, say what `gg status` last reported and which side
it is waiting on — their DNS, or Gagarin's certificate. Be specific about what
you did not verify.

If the MCP tools are connected, `remember` what the next session could not
cheaply rediscover about this deploy: the port, a Dockerfile quirk, the names
of the environment variables the application requires — never their values —
and anything that differed from the obvious. One fact per memory, in English.
What is deployed now is the one that changes: `remember` it as a `state` memory
with the key `deploy/<service>`, so the next deploy replaces it instead of
piling up beside it. Skip what the repository already says, and skip it
entirely if the tools are not there.
