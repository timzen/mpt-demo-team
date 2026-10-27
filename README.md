# mpt-demo-team

A demo "team" with a fake project. Used to show how my-pizza-team works and to test agent workflows against known code.

## What's Inside

```
mpt-demo-team/
├── setup-demo.sh           # Run this to set up the demo
├── fixtures/
│   ├── project/            # Demo todo API (TypeScript, Node.js)
│   │   ├── src/index.ts    # Simple HTTP todo API — no auth yet
│   │   ├── tests/          # Basic tests
│   │   ├── package.json
│   │   └── tsconfig.json
│   ├── team/               # MPT team directory fixture (flat; see my-pizza-team docs/WORKDEF_UNIFICATION.md)
│   │   ├── config.json            # `packages` loads the demo-tracker plugin
│   │   ├── workflows/default/
│   │   │   ├── workflow.json
│   │   │   └── in_progress.md      # state persona for the one agent state
│   │   ├── stories/               # flat story files (children live in tasks/)
│   │   │   ├── add-user-auth.json      # tasks: [{id,status}]; directory = demo project
│   │   │   └── ui-theme-polish.json    # pending (design-review gate)
│   │   ├── tasks/                 # EVERY unit of work is a WorkDef (authored markdown)
│   │   │   ├── add-user-auth-1/workdef.md     # board task (parent: story add-user-auth)
│   │   │   ├── add-user-auth-2/workdef.md
│   │   │   ├── add-user-auth-3/workdef.md
│   │   │   ├── ui-theme-polish-1/workdef.md
│   │   │   ├── audit-project-dependencies/workdef.md  # Solitary (no parent)
│   │   │   └── nightly-test-run/workdef.md            # Scheduled (parent: schedule)
│   │   ├── schedules/             # cron parents (fire their child WorkDefs)
│   │   │   └── nightly-test-run.json                  # cron 0 2 * * *
│   │   └── context/
│   │       └── project-conventions.md
│   └── tracker/
│       └── tracker.json    # Seed issues for the demo-tracker plugin (DEMO-1, DEMO-2; DEMO-3 triage-mode)
├── plugins/
│   └── mpt-source-demo-tracker/   # Example Work Source plugin (plain JS, no build)
├── plugins.local.example.json     # Example overlay for your own plugins (see "Trying your own plugins")
├── try-plugin.sh           # Doctor a plugin, add it to plugins.local.json, bring the sandbox up
├── run-ui.sh               # Daemon only (no agents); --restart, --clean
├── run-e2e.sh              # Full end-to-end run (daemon + leader + worker)
├── .gitignore              # Ignores demo/ runtime dir and plugins.local.json
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

The tasks are designed to be small, self-contained, and testable. They exercise the full MPT workflow: `todo → in_progress → review → done`.

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
install — with `config: { file, directory, intervalSeconds }`.

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

Plugins load at daemon startup, so a change to the plugin code or its `packages`
entry needs a daemon restart (the tracker file itself doesn't).

## Trying your own plugins

The demo team doubles as a **plugin sandbox**: try any Work Source plugin package
(e.g. `~/ws/MPT/src/MPTSimWorkSources`, or one you're writing) against a
throwaway team before it goes into a real one — without committing your personal
config, and without losing it when the demo resets.

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

**The workflow:**

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

- `./try-plugin.sh <path|spec> [--config '<json>'] [--no-start]` — stops if the
  doctor fails (plugins.local.json unchanged). Without `--config` an entry's
  existing config is kept. `--no-start` sets up without starting the daemon.
- `./try-plugin.sh --list` shows the entries; `./try-plugin.sh --remove <path|spec>`
  removes one (then `./run-ui.sh --restart`). `./try-plugin.sh --help` for the rest.
- Relative paths *inside* a config are up to the plugin: the daemon passes the
  team dir (`demo/team/.my-pizza-team`), the doctor a temp dir — so prefer
  absolute ones (e.g. the demo-tracker's `file`).
- `run-e2e.sh` ignores plugins.local.json (it runs setup with
  `MPT_DEMO_NO_LOCAL_PLUGINS=1`), so e2e stays deterministic.

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
nothing lands in this repo, and `setup-demo.sh` / `--restart` wipe it.

**Graduating to a real team.** Once it behaves here, add it to the real team
the same way, from that team's directory:
`mpt plugins doctor <path> --config '<json>'`, then
`mpt plugins add <path> --config '<json>'` (or edit its config.json `packages`),
and restart that team's daemon. Drop the sandbox-only bits (a `directory` under
`demo/`, tiny `maxItems`), and remove the entry here if you like.

## Resetting

Just run `./setup-demo.sh` again — it nukes the `demo/` dir and copies fresh fixtures
(and re-merges `plugins.local.json`, which lives outside `demo/`).

## Just the UI (no agents)

To browse the seeded board / tasks / schedule without spawning any agents, use
`run-ui.sh`. It sets up the fixtures and starts the daemon from `../my-pizza-team`
source in the foreground — no leader, no worker:

```bash
./run-ui.sh            # set up fixtures + start the daemon (Ctrl+C to stop)
./run-ui.sh --restart  # stop the running daemon, re-run setup, start again
./run-ui.sh --clean    # stop a daemon started by this script
```

Once the daemon is healthy it prints each plugin package's load status and its
sources (from `GET /api/work-sources`): ✓, or ✗ with the error.

Then open <http://localhost:7437/> (Board · Tasks · Schedule). Override the port
with `PORT=8080 ./run-ui.sh`.

Prerequisites: `node` 24+ only (the UI is served prebuilt from `my-pizza-team/ui/dist`).

## E2E Test Run

To run the full end-to-end flow (daemon + leader + worker agent):

```bash
./run-e2e.sh
```

This will:
1. Set up demo fixtures (runs `setup-demo.sh`)
2. Start the MPT daemon from `../my-pizza-team` source
3. Check the demo-tracker plugin: loaded, all three issues mirrored and enqueued, and
   write-back (a thread comment, a canceled run) lands in `demo/tracker/tracker.json`;
   then play a teammate on the triage-mode **DEMO-3** through the agent API (triage
   prompt, a `propose_work`-style analysis, COMPLETE), accept its proposal (a task is
   created, not run; the issue stays open), and re-queue it with Triage now
4. Launch a Pi leader in a tmux session
5. Spawn a worker agent pointed at `demo/project/`
6. Monitor task progress (and the tracker issues' statuses) until you Ctrl+C

Prerequisites: `pi`, `node` 24+, `tmux`, and the Pi extension installed (`mpt setup`).

To clean up running processes:
```bash
./run-e2e.sh --clean
```
