---
name: ci
description: Wire a repository's CI pipeline to deploy to Gagarin Cloud on push — mint a scoped deploy credential, store it as a secret, and write the workflow. Use when the user asks to set up continuous deployment, automate deploys, or deploy from GitHub Actions or another CI system to Gagarin.
---

You wire this repository's CI to deploy to Gagarin Cloud on push.

Read the `gagarin` skill of this plugin before anything else: its **"Setting up
CI"** section is the recipe. What follows is the order of work and the rules
you must not break. If your host offers subagents, run the rest of this in one:
it is a long procedure, and the main conversation only needs its report.

Everything here runs on the machine that holds the repository. If you cannot
run commands where you are (ChatGPT on the web, for instance), hand the user
the recipe instead — the `gg creds create` line and the workflow — and say
which secret to set where. Do not try to do it over the MCP tools: there is no
route from them to the forge's secret store, and `create_credential` would put
the secret in the transcript.

## The order

1. **`gg whoami`** — you need a working credential to mint one from. If there is
   none, stop and tell the user to run this plugin's `setup` skill
   (`/gagarin:setup` in Claude Code).
2. **Find out what CI they use.** Look for `.github/workflows/`, `.gitlab-ci.yml`,
   `.buildkite/`, `cloudbuild.yaml`. Ask if it is ambiguous. Do not assume GitHub.
   `git remote get-url origin` says where the repository lives.
3. **Check the forge CLI.** On GitHub that is `gh auth status`; on GitLab,
   `glab auth status`. If it is missing or not signed in, say so before minting
   anything: ask the user to install it and run `gh auth login` / `glab auth
   login` themselves, or to set the secret by hand (see below). Do not sign in
   for them.
4. **Confirm the project and service names** and which branch should deploy.
   Read `.gagarin.json` at the repository root first — the note of which
   project this is, if a deploy left one — then `gg status` or `gg projects`
   rather than guessing. If the two disagree, the API is right. Do not write
   the note here if it is absent: that is the deploy's job, and there may be
   no project yet.
5. **Mint a credential**, named for where it will live:
   `gg creds create --name "github actions: <owner>/<repo>"`.
6. **Put it straight into the secret store** — see the rule below.
7. **Write the workflow.** Install gg, `gg registry login`, build and push
   tagged with the commit, deploy, then `gg status`.
8. **Tell them what to check** on the first run — and, once they have pushed,
   watch it with the forge CLI (the skill's "Watch the first run").

## Rules that are not negotiable

- **Never run `gg login` in CI, and never copy this machine's credential into
  it.** A pipeline gets one of its own.
- **The minted secret must never reach the transcript, a file, or your output.**
  `gg creds create` prints it to stdout alone on its line, everything else to
  stderr, precisely so it can be piped without touching disk:

  ```sh
  gh secret set GAGARIN_TOKEN --body "$(gg creds create --name "github actions: acme/web" 2>/dev/null)"
  ```

  On GitLab, the same shape:

  ```sh
  glab variable set GAGARIN_TOKEN --masked --value "$(gg creds create --name "gitlab ci: acme/web" 2>/dev/null)"
  ```

  Run it as one command. Do not capture it into a shell variable you later echo,
  do not print it "to confirm", and do not write it into a file — not even a
  temporary one. It is shown once; Gagarin keeps only a hash. If the user needs
  it again they revoke and mint another.
- **No signed-in forge CLI means you do not mint it.** There is no route from
  here to the secret store that skips your output. Hand the user the
  `gg creds create --name "…"` command to run in their own terminal and say
  where in the CI settings to paste it.
- **`gg registry login` is not optional** before any `gg build --push`,
  `gg push` or `gg registry copy`. Docker has no idea what a Gagarin credential
  is until it runs, and the failure without it is a `401` out of `docker push`.
- **Tag with the commit, explicitly.** `${{ github.sha }}` is what makes a
  deploy reproducible and a rollback explicable. `gg build` with no tag uses
  the short hash only when the checkout is clean and falls back to the clock
  otherwise, and a pipeline that writes a file before building is not clean —
  so never leave the tag to it in CI.
- **`gg status` at the end is a report, not a gate.** Do not write a polling
  loop in CI. If they want a gate, gate on their own health check against the
  service's address.

## What the credential can and cannot do

Say this to the user explicitly, because it is the reason this is safe: what you
minted **can deploy but cannot destroy** — no flag turns that on — it **expires**
(90 days by default, 365 maximum, never "never"), and it **cannot mint another**.
Tell them the expiry date and that rotating means minting the new one, updating
the secret, then `gg creds revoke <id>`.

## Finishing

Report which secret you set, where, what the workflow does on which branch, and
when the credential expires. Do not trigger a deploy to test it unless the user
asks — that is their push to make. If they push while you are here and the
forge CLI is signed in, watch the run to the end and report how it finished,
with the failing step's log if it failed, then `gg status`.
