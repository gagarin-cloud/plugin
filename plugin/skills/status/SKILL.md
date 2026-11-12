---
name: status
description: Show what is actually running in a Gagarin Cloud project — desired vs actual state, addresses, sizes and today's cost. Use when the user asks whether a service is up, what is deployed, what an address is, or what a project costs.
---

Report the state of the user's Gagarin Cloud project — the one they named, if
they named one.

If no project was named, read `.gagarin.json` at the repository root: it is the
note a previous session left of which project this repository is, and its `id`
is the project to use. If there is no such file, run `gg projects` and ask
which one they mean — do not guess, and do not infer a project from the
working directory. Gagarin names nothing after the directory you stand in, and
it does not read that file either; you do.

Then run `gg status <project>`.

Two things about reading the result:

- **`gg status` is the only thing that reads the cluster.** Every other write
  records a demand without watching it come true, so this is the only answer to
  "is it up".
- Every row already carries a sentence written by the engine, so that a terminal
  and a dashboard cannot describe the same row differently. **Relay those
  sentences rather than rewriting them into your own words.** Summarise what
  needs attention; do not re-render the table.

If a service is waiting on DNS or a certificate, `gg status` says which side it
is waiting on — theirs or Gagarin's. Say which.

If the Gagarin MCP tools are connected and `gg` is not installed — or you
cannot run commands where you are — use the `status` tool instead; it reads the
same thing. `projects` lists what there is when no project was named.

For "why is it slow", "is it running out of memory", "is the disk filling":
`gg status` says what is running, not how hard. Run `gg metrics <project>`, or
`gg metrics <project>/<service> --window 24h` for one service over time; the
`metrics` tool is the same. Answer from those numbers.
