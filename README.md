# mpt-demo-team

A demo "team" with a fake project. Used to show how my-pizza-team works and to test agent workflows against known code.

## What's Inside

```
mpt-demo-team/
├── setup-demo.sh           # Run this to set up the demo
├── fixtures/
│   ├── project/            # Demo todo API (TypeScript, Node.js)
│   │   ├── AGENTS.md       # The project's conventions (build/test, style, API) — teammates read it
│   │   ├── src/index.ts    # Simple HTTP todo API — no auth yet
│   │   ├── tests/          # Basic tests
│   │   ├── package.json
│   │   └── tsconfig.json
│   ├── team/               # MPT team directory fixture (flat; see my-pizza-team docs/WORKDEF_UNIFICATION.md)
│   │   ├── config.json            # `packages`: demo-tracker + mpt-personas-demo; `sourcePersonas`
│   │   ├── personas/
│   │   │   └── demo-coder.md       # team persona the in_progress state selects
│   │   ├── workflows/default/
│   │   │   └── workflow.json       # in_progress: { "persona": "demo-coder" }
│   │   ├── stories/               # flat story files (children live in tasks/)
│   │   │   ├── add-user-auth.json      # tasks: [{id,status}]; directory = demo project
│   │   │   └── ui-theme-polish.json    # pending (design-review gate)
│   │   ├── tasks/                 # EVERY unit of work is a WorkDef (authored markdown)
│   │   │   ├── add-user-auth-1/workdef.md     # board task (parent: story add-user-auth)
│   │   │   ├── add-user-auth-2/workdef.md
│   │   │   ├── add-user-auth-3/workdef.md
│   │   │   ├── ui-theme-polish-1/workdef.md
│   │   │   ├── audit-project-dependencies/workdef.md  # Solitary (no parent); persona careful-reviewer
│   │   │   └── nightly-test-run/workdef.md            # Scheduled (parent: schedule); no persona
│   │   └── schedules/             # cron parents (fire their child WorkDefs)
│   │       └── nightly-test-run.json                  # cron 0 2 * * *
│   ├── team-legacy/        # Pre-persona team (context/, triage.md, in_progress.md): ./setup-demo.sh --legacy
│   └── tracker/
│       └── tracker.json    # Seed issues for the demo-tracker plugin (DEMO-1, DEMO-2; DEMO-3 triage-mode)
├── plugins/
│   ├── mpt-source-demo-tracker/   # Example Work Source plugin (plain JS, no build) + its own persona
│   └── mpt-personas-demo/         # Example persona package (personas only: 3 personas, no build)
├── plugins.local.example.json     # Example overlay for your own plugins (see "Trying your own plugins")
├── try-plugin.sh           # Install (git/npm) + doctor a plugin, add it to plugins.local.json, bring the sandbox up
├── run-ui.sh               # Daemon only (no agents); --restart, --clean, --legacy
├── run-e2e.sh              # Full end-to-end run (daemon + leader + worker)
├── .gitignore              # Ignores demo/, plugins.local.json and .plugin-packages/
└── README.md
```

## Quick Start

```bash
cd mpt-demo-team
./setup-demo.sh
```

This copies fixtures into:
- `./demo/project/` — the code agents will work on
- `./demo/team/.my-pizza-team/` — the team directory MPT reads
- `./demo/tracker/tracker.json` — the demo-tracker plugin's fake issue tracker

The entire `demo/` directory is `.gitignored` so you can experiment freely.

Then start MPT:

```bash
# From the team dir (auto-detects .my-pizza-team)
cd demo/team
mpt start

# Or explicit from anywhere:
TEAM_DIR=./demo/team/.my-pizza-team mpt start
```

## The Demo Story

**"Add User Authentication"** — 3 tasks that build on each other:

1. **Create auth module** — `src/auth.ts` with password hashing and JWT-like tokens
2. **Add register/login endpoints** — `POST /register` and `POST /login`
3. **Protect todo routes** — Auth middleware on all `/todos` endpoints

The tasks are designed to be small, self-contained, and testable. They exercise the full MPT workflow: `todo → in_progress → review → done`. The `in_progress` state selects the team persona **Demo coder** (`personas/demo-coder.md`), so every board task's prompt starts with it.

## Personas

How a teammate works is a **persona** (my-pizza-team GUIDE.md "Personas";
docs/DESIGN.md "Personas: One Library, Selected by Reference"): a markdown file
that workflow states, triage, the assistant, Solitary/Scheduled tasks and Work
Sources *select by id*. Project knowledge isn't a persona — it lives in the
project, in `demo/project/AGENTS.md` (formerly the team's
`context/project-conventions.md`; MPT no longer has a context library). The
fixtures use every origin and most ways of selecting one:

| Persona | Origin | Selected by |
|---------|--------|-------------|
| `demo-coder` | team (`fixtures/team/personas/demo-coder.md`) | the `default` workflow's `in_progress` state (`workflow.json` `"persona"`) |
| `mpt-personas-demo/careful-reviewer` | package (`plugins/mpt-personas-demo`) | the Solitary task *Audit project dependencies* (`persona:` in its workdef.md) |
| `mpt-personas-demo/tracker-triager` | package | the demo-tracker's per-source triage persona (config.json `sourcePersonas.demo-tracker.triagePersona`) — DEMO-3 |
| `mpt-source-demo-tracker/tracker-worker` | package (the tracker plugin itself) | the tracker's declared `defaultPersona` — DEMO-1, DEMO-2 |
| `mpt-personas-demo/careful-implementer` | package | nothing by default; `run-e2e.sh` makes it DEMO-1's per-item override (the Persona picker on its page) |
| `builtin:triage` / `builtin:assistant` / `builtin:worker` | built-in | note triage and the assistant (nothing set); `builtin:worker` only stands in for a missing persona |

The Scheduled *Nightly test run* sets no persona, so its prompt has no persona block.

**The persona package.** `plugins/mpt-personas-demo/` is a persona-only plugin
package: `package.json` `"mpt": { "personas": ["personas/*.md"] }`, three
personas, no sources, no build. config.json loads it in place by relative path,
like the tracker. Its personas are **read-only** on Config → Personas, named
`<package.json name>/<file name>`; **Duplicate to edit** copies one into the team
library. `mpt plugins doctor ./plugins/mpt-personas-demo` checks it (✓ per
persona). Copy the folder to start your own team's package.

**Watching it.** Config → **Personas** lists the library (team, built-in and
package badges) and each persona's **Used by**. While a teammate works, a ✦
persona chip on its Team row, Queue row, Watch header and the task's Runs shows
the persona its run recorded at claim (`GET /api/agents` → `persona`, and
`persona` on every WorkItem).

**The legacy layout (migration).** `fixtures/team-legacy/` is a team in the
pre-persona layout: `workflows/default/in_progress.md`, `triage.md`, and a
`context/` library with a persona-tagged entry (`pair-programmer`), an entry
attached to a story and to a Solitary task (`project-conventions`), and an
unattached one (`release-checklist`); its demo-tracker runs in source-wide triage
mode with no triage persona. `./setup-demo.sh --legacy` (or `./run-ui.sh
--legacy`) sets it up, and on its first start the daemon migrates it in place:
personas `default-in-progress`, `triage` and `pair-programmer` (the state and
`triage.persona` point at them); the attached entry inlined into the tasks'
Additional Context; `context/` archived as `context.migrated/` (with a notice on
the home page); and `sourcePersonas.demo-tracker.triagePersona` seeded with
`triage`. A second start changes nothing. `run-e2e.sh` checks all of it first.
(The SQLite `assistant_persona` step can't be shown from fixtures: no `state.db`.)

## Showcasing Pause, Directory Affinity & Standalone Work

The fixtures go beyond the board story to exercise the rest of the model:

**A pending story** — **"Polish the UI Theme"** (`ui-theme-polish`) starts
`"pending": true`, so the daemon hands out none of its tasks until you activate it
(**Activate** on the Board's Pending tab or the story page, or `POST
/api/stories/ui-theme-polish/activate`). It models a design-review gate.

**Directory affinity** — both stories set a `directory` (the demo project path,
filled in by `setup-demo.sh`). Teammates are a flat generalist pool with no
capabilities or work modes; the daemon simply biases work toward the teammate
whose working directory matches. Spawn a teammate homed at the demo project and
it preferentially picks up this work:

```bash
# A generalist teammate homed at the demo project (directory affinity):
pi --ppt-worker            # started with its cwd = demo/project
```

**Standalone WorkDefs** — two jobs that don't live on the board (under
`team/tasks/`):

- **Solitary** — *Audit project dependencies*. A one-shot: open the **Tasks**
  page and hit **Run** to enqueue it.
- **Scheduled** — *Nightly test run* (cron `0 2 * * *`). The daemon enqueues a
  run each night; the **Schedule** page's **Run now** triggers one immediately.

Completed work (from stories or WorkDefs) shows up in the **Inbox** on the home
page for review. See my-pizza-team `docs/FRONTIER_ENGINEER_REFACTOR_PLAN.md` for
the WorkItem/WorkDef model.

## The Demo-Tracker Plugin

`plugins/mpt-source-demo-tracker/` is an example **Work Source plugin** (see its
README and my-pizza-team `GUIDE.md` "Writing a Work Source plugin"): a fake,
offline issue tracker backed by `demo/tracker/tracker.json`. The team's
`config.json` lists it under `packages` by local path — loaded in place, no
install — with `config: { file, directory, intervalSeconds }`. It declares a
`configSchema` and a `preview` hook, so **Config → Sources → Demo Tracker** edits
those settings in a form, previews the open issues a file would yield, and saves
without a restart (only `intervalSeconds` waits for one).

Every 10s it syncs the tracker's **open** issues into MPT, which mirrors each
(read-only) and enqueues one run per revision. The seed has two issues against
the todo API: **DEMO-1** "Add GET /todos/:id" and **DEMO-2** "Validate empty
titles". Write-back goes the other way: comments on an issue's thread are
appended to its `comments`, and a finished run marks it `done` / `failed` (a
canceled run just leaves a note).

**Triage mode.** The third seed issue, **DEMO-3** "Customer request: due dates
and overdue reminders", has `"mode": "triage"`: it's a vague request to *think
about*, not work to do. Instead of working it, a teammate **triages** it — the same
flow as a note's Auto Triage — and proposes tasks, stories, or schedules. Its row on
the Demo Tracker tab wears a triage badge; its page opens on a **Triage** tab with
the issue read-only and each proposal's **Accept / Edit / Reject**. Accepting
creates the work without starting it, and a finished triage leaves the issue open.
To answer a question, edit the issue's `body` and bump its `updatedAt` — the next
revision is triaged again. (`"mode"` on an issue, or the plugin's `mode` option
for all of them; see the plugin's README.)

**Personas.** The plugin ships a persona of its own (`personas/tracker-worker.md`,
listed in its `package.json` beside its source) and declares it as the source's
`defaultPersona`, so DEMO-1 and DEMO-2 are worked with it. The demo team sets a
**per-source** triage persona (`sourcePersonas.demo-tracker.triagePersona` in
config.json; Config → Sources → Demo Tracker) for DEMO-3 — a triage-mode item
*must* have one: without it the issue is mirrored but not run, and Config →
Sources names the fix. A person can also override one item (the Persona picker on
its page; `PUT /api/work-defs/demo-tracker~DEMO-1/persona`), which survives
re-syncs. Resolution: the item's override → the source's per-item suggestion →
the per-source setting → the source's default.

How to watch it:

- **UI:** Work → **Demo Tracker** tab (`/work/source/demo-tracker`): each issue,
  its fake link, revision, and latest run. **Sync now** pulls immediately.
- **CLI:** from `demo/team`, `mpt plugins list` shows whether it's installed and
  loaded (and the error if not). `curl localhost:<port>/api/work-sources` shows the same.
- **Re-sync:** edit `demo/tracker/tracker.json` — add an issue, or bump an
  issue's `updatedAt` to run it again; set its `status` to anything but `open`
  and its mirror is archived. Changes show up within ~10s.
- **Write-back:** comment on an issue in the UI, or let a teammate finish one, then
  look at the tracker file.

Plugins load at daemon startup, so a change to the plugin code, or a hand edit of its
`packages` entry, needs a daemon restart (the tracker file itself doesn't, nor does a
Save on Config → Sources, which re-inits the plugin live).

## Trying your own plugins

The demo team doubles as a **plugin sandbox**: try any plugin package — Work
Sources, personas (`"mpt": { "personas": [...] }`), or both — a git URL (`ssh://git.amazon.com/pkg/MPTSimWorkSources`), an `npm:` spec, or a
local checkout you're writing — against a throwaway team before it goes into a
real one, without committing your personal config, and without losing it (or
re-cloning it) when the demo resets.

**From a git URL (or npm spec)** — the quickest way:

```bash
./try-plugin.sh ssh://git.amazon.com/pkg/MPTSimWorkSources \
  --config '{"taskei":{"workflowStep":"Implementation","dryRun":false,"maxItems":3}}'
```

It runs `./setup-demo.sh` (so the demo team exists), then
`mpt plugins add <spec> [--config …]` against the demo team — clone, `npm install
--omit=peer`, `npm run build` into `demo/team/.my-pizza-team/packages/` — then
`mpt plugins doctor <spec> [--config …]`. On failure it prints the error, undoes
the install (`mpt plugins remove`) and leaves `plugins.local.json` unchanged. On
success it records the spec (as given) in `plugins.local.json`, re-runs setup and
starts `run-ui.sh --restart` (unless `--no-start`). `git:<host>/<path>`,
`https://…` URLs and an `@ref` suffix (branch, tag, commit) work too.

- **The package cache.** Installed packages (`demo/team/.my-pizza-team/packages/`)
  survive `./setup-demo.sh` (and so `run-ui.sh` / `--restart`): setup moves them
  aside to `.plugin-packages/` (gitignored) while it resets `demo/`, then back.
  Re-running `./try-plugin.sh <spec>` for an installed spec only runs the doctor
  (fast); **`--update`** re-fetches and rebuilds it first (`mpt plugins update`).
  **`./setup-demo.sh --fresh`** also clears the cache; a spec still in
  `plugins.local.json` is then reinstalled by the daemon on its next start (or by
  the next `try-plugin.sh`).
- **The contract** (MPT isn't build-system aware): a git plugin must install and
  build with plain npm against your configured registry (`npm config get
  registry`), or ship prebuilt `mpt.sources` entries. A persona-only package needs
  no build at all (MPT never runs npm in one).
- **Personas from a package** show on Config → Personas once the daemon restarts;
  pick them on a workflow state, a task, or a source (Config → Sources: persona /
  triage persona). A triage-mode source that declares no triage persona gets
  `builtin:triage` on its first start — pick a better one there.
- **Prerequisites:** git access to the host (for `ssh://git.amazon.com/…`, your
  ssh key set up for git.amazon.com — `git ls-remote <url>` should work). For
  live syncs of the SIM plugins (MPTSimWorkSources with `--config`, and the
  running daemon): `mcscli` on your PATH and a fresh `mwinit`.
- `./try-plugin.sh --remove <spec>` drops it from `plugins.local.json` and deletes
  its install from the cache.

Your plugins live in **`plugins.local.json`** (gitignored): a JSON array of
entries in the same format as config.json `packages` — a spec string, or
`{ "source": "<path|spec>", "config": { … } }`. Local paths may be absolute or
`~/`; relative ones are relative to this repo. `setup-demo.sh` (so also
`run-ui.sh`) merges it into `demo/team/.my-pizza-team/config.json` on every
setup: paths are made absolute, an entry for the same package as a fixture entry
replaces it (otherwise the demo-tracker stays), `__DEMO_PROJECT__` in a config is
filled in, and bad JSON stops the setup with an error. Entries with only a `"//"`
key are comments. See `plugins.local.example.json` (MPTSimWorkSources with
placeholders) — copy it, or let `try-plugin.sh` write the file for you.

**From a local checkout** (a plugin you're developing): the same script with a
path. It isn't installed — it loads in place — so build it yourself first:

```bash
# 1. Build the plugin (Brazil packages: brazil-build, never plain npm)
(cd ~/ws/MPT/src/MPTSimWorkSources && brazil-build)

# 2. Check it and bring the sandbox up: mpt plugins doctor (+ one live
#    init/sync with --config), record it in plugins.local.json, setup, run-ui
./try-plugin.sh ~/ws/MPT/src/MPTSimWorkSources \
  --config '{"taskei":{"workflowStep":"Implementation","dryRun":false,"maxItems":3}}'

# 3. Browse http://localhost:6789/work — a tab per source. run-ui.sh prints
#    each plugin's load status (✓ / ✗ with the error) and its sources.

# 4. After a rebuild, restart the daemon (re-runs setup, keeps plugins.local.json)
(cd ~/ws/MPT/src/MPTSimWorkSources && brazil-build) && ./run-ui.sh --restart
```

- `./try-plugin.sh <path|spec> [--config '<json>'] [--no-start] [--update]` — stops
  if the install or doctor fails (plugins.local.json unchanged). Without `--config`
  an entry's existing config is kept. `--no-start` sets up without starting the
  daemon; `--update` applies to git/npm specs only.
- `./try-plugin.sh --list` shows the entries; `./try-plugin.sh --remove <path|spec>`
  removes one (then `./run-ui.sh --restart`). `./try-plugin.sh --help` for the rest.
- Relative paths *inside* a config are up to the plugin: the daemon passes the
  team dir (`demo/team/.my-pizza-team`), the doctor a temp dir — so prefer
  absolute ones (e.g. the demo-tracker's `file`).
- `run-e2e.sh` ignores plugins.local.json (it runs setup with
  `MPT_DEMO_NO_LOCAL_PLUGINS=1`), so e2e stays deterministic.

**Setting it up from the UI.** Once a plugin is installed and loaded, you don't
have to edit `--config` JSON by hand: open **Config → Sources**
(`http://localhost:<port>/config/sources`) in the sandbox (my-pizza-team GUIDE.md
"Setting up a plugin from the UI"):

1. Pick the source. A plugin that declares a `configSchema` (MPTSimWorkSources'
   `sim-t` and `Taskei`, and the demo-tracker) gets a form — titles, help text,
   defaults; otherwise a JSON editor.
2. **Preview** shows what a sync would pull with the settings on screen, *unsaved*:
   the items, warnings ("not configured: set resolverGroup", "run mwinit", a bad
   value), and nothing is mirrored, queued or written back. Iterate here with
   `dryRun` still on.
3. **Save** writes the settings into `demo/team/.my-pizza-team/config.json`
   (`packages[].config`) and re-initializes the plugin live — no `--restart`.
4. Its checkbox in the list switches it on/off (stops syncing). Switching off a
   source that has mirrored items offers **Turn off and archive N items** (a
   disconnect: mirrors archived, queued runs canceled); switch it back on to get
   them back.

A UI Save lands in the demo's config.json, which **the next `setup-demo.sh` /
`run-ui.sh --restart` rebuilds** from the fixtures + `plugins.local.json`. To keep
settings you found in the UI, copy the source's block into its `plugins.local.json`
entry (or `./try-plugin.sh <spec> --config '<json>' --no-start`). `--config` on the
command line is still the way to give a plugin its *first* settings, before the
daemon (and the UI) is up; then refine them in the UI.

**UI only vs with agents.** `run-ui.sh` starts no teammates: you see what the
plugin mirrors and enqueues, and can comment / cancel / Sync now, but nothing
runs. To have work done, run `run-e2e.sh`-style agents (or `pi --ppt-worker`)
against the sandbox daemon. Teammates then work in the demo project
(`demo/project`) unless the plugin's config sets a `directory` — set one only
if you mean real work to happen in that checkout. Keep `dryRun` / `maxItems`
small, and remember write-back hooks (comments, done/failed) reach the real
system if your plugin does real write-back.

**Where the data goes.** Items from a real external system (Taskei tasks, SIM
tickets, …) are mirrored only into the gitignored `demo/` (the demo team dir);
nothing lands in this repo, and `setup-demo.sh` / `--restart` wipe it (all but
the installed packages, see "The package cache").

**Graduating to a real team.** Once it behaves here, add it to the real team
the same way, from that team's directory:
`mpt plugins doctor <path|spec> --config '<json>'`, then
`mpt plugins add <path|spec> --config '<json>'` (or edit its config.json `packages`),
and restart that team's daemon. Drop the sandbox-only bits (a `directory` under
`demo/`, tiny `maxItems`), and remove the entry here if you like.

## Resetting

Just run `./setup-demo.sh` again — it nukes the `demo/` dir and copies fresh fixtures
(and re-merges `plugins.local.json`, which lives outside `demo/`). Installed plugin
packages are kept; `./setup-demo.sh --fresh` clears them too.

## Just the UI (no agents)

To browse the seeded board / tasks / schedule without spawning any agents, use
`run-ui.sh`. It sets up the fixtures and starts the daemon from `../my-pizza-team`
source in the foreground — no leader, no worker:

```bash
./run-ui.sh            # set up fixtures + start the daemon (Ctrl+C to stop)
./run-ui.sh --restart  # stop the running daemon, re-run setup, start again
./run-ui.sh --clean    # stop a daemon started by this script
./run-ui.sh --legacy   # the same on the pre-persona layout (watch it migrate)
```

Once the daemon is healthy it prints each plugin package's load status, its
sources and how many personas it ships (from `GET /api/work-sources`): ✓, or ✗
with the error.

Then open <http://localhost:7437/> (Board · Tasks · Schedule). Override the port
with `PORT=8080 ./run-ui.sh`.

Prerequisites: `node` 24+ only (the UI is served prebuilt from `my-pizza-team/ui/dist`).

## E2E Test Run

To run the full end-to-end flow (daemon + leader + worker agent):

```bash
./run-e2e.sh
```

This will:
1. Check the **persona migration**: set up the legacy layout (`setup-demo.sh
   --legacy`), start the daemon on it, and assert each step's result (state file,
   `triage.md` and the persona-tagged entry → personas listed by `GET
   /api/personas`; the triage-mode source's triage persona seeded; attached context
   inlined, `context/` → `context.migrated/`, the notice on `/api/status`,
   `/api/context` → 410); restart it and assert nothing changed
2. Set up the demo fixtures (`setup-demo.sh`) and start the MPT daemon from
   `../my-pizza-team` source
3. Check the demo-tracker plugin: loaded, all three issues mirrored and enqueued, and
   write-back (a thread comment, a canceled run) lands in `demo/tracker/tracker.json`
4. Check **personas**: `GET /api/personas` lists the team, built-in and package
   personas; package personas are read-only (PUT/DELETE 409; duplicate works);
   Used by (the workflow state, the Solitary task, the tracker's triage setting);
   then claim DEMO-1 (after setting its per-item override) and DEMO-2 as a
   throwaway agent and assert each prompt carries its persona and each WorkItem
   recorded it (`via` workdef / source-default); complete both and reopen them in
   the tracker file (the override survives the re-sync)
5. Play a teammate on the triage-mode **DEMO-3** through the agent API (triage
   prompt with the per-source triage persona, recorded on the run; a
   `propose_work`-style analysis, COMPLETE), accept its proposal (a task is
   created, not run; the issue stays open), and re-queue it with Triage now
6. Exercise the Config → Sources routes on the demo-tracker: `GET /api/sources` lists
   it with its `configSchema` and toggle; a **preview** with draft settings (pointing
   at a scratch copy of the tracker with an extra issue, E2E-1) shows E2E-1 without
   mirroring anything, and invalid settings get a 400; a **Save** (`PUT
   /api/sources/demo-tracker/config`) rewrites config.json, re-inits the plugin live,
   and the next sync mirrors E2E-1; switching it off is refused (409) while it has
   mirrors, a **disconnect** switches it off and archives them, and no sync runs while
   it's off; finally the fixture settings are restored, it's switched back on, and
   DEMO-1..3 come back and are re-queued
7. Launch a Pi leader in a tmux session
8. Spawn a worker agent pointed at `demo/project/`, and wait (up to 2 minutes; a
   warning, not a failure) for its **in-flight persona** on `GET /api/agents`
9. Monitor task progress, the tracker issues' statuses and each working
   teammate's persona until you Ctrl+C

Prerequisites: `pi`, `node` 24+, `tmux`, and the Pi extension installed (`mpt setup`).

To clean up running processes:
```bash
./run-e2e.sh --clean
```
