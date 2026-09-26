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
│   └── team/               # MPT team directory fixture (flat; see my-pizza-team docs/WORKDEF_UNIFICATION.md)
│       ├── config.json
│       ├── workflows/default/
│       │   ├── workflow.json
│       │   └── in_progress.md      # state persona for the one agent state
│       ├── stories/               # flat story files (children live in tasks/)
│       │   ├── add-user-auth.json      # tasks: [{id,status}]; directory = demo project
│       │   └── ui-theme-polish.json    # paused (design-review gate)
│       ├── tasks/                 # EVERY unit of work is a WorkDef (authored markdown)
│       │   ├── add-user-auth-1/workdef.md     # board task (parent: story add-user-auth)
│       │   ├── add-user-auth-2/workdef.md
│       │   ├── add-user-auth-3/workdef.md
│       │   ├── ui-theme-polish-1/workdef.md
│       │   ├── audit-project-dependencies/workdef.md  # Solitary (no parent)
│       │   └── nightly-test-run/workdef.md            # Scheduled (parent: schedule)
│       ├── schedules/             # cron parents (fire their child WorkDefs)
│       │   └── nightly-test-run.json                  # cron 0 2 * * *
│       └── context/
│           └── project-conventions.md
├── .gitignore              # Ignores demo/ runtime dir
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

**A paused story** — **"Polish the UI Theme"** (`ui-theme-polish`) starts
`"paused": true`, so the daemon never enqueues its tasks until you un-pause it
(in the UI, or `PUT /api/stories/ui-theme-polish` with `{ "paused": false }`).
It models a design-review gate.

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

## Resetting

Just run `./setup-demo.sh` again — it nukes the `demo/` dir and copies fresh fixtures.

## Just the UI (no agents)

To browse the seeded board / tasks / schedule without spawning any agents, use
`run-ui.sh`. It sets up the fixtures and starts the daemon from `../my-pizza-team`
source in the foreground — no leader, no worker:

```bash
./run-ui.sh          # set up fixtures + start the daemon (Ctrl+C to stop)
./run-ui.sh --clean  # stop a daemon started by this script
```

Then open <http://localhost:7437/> (Board · Tasks · Schedule). Override the port
with `PORT=8080 ./run-ui.sh`.

Prerequisites: `deno` only (the UI is served prebuilt from `my-pizza-team/ui/dist`).

## E2E Test Run

To run the full end-to-end flow (daemon + leader + worker agent):

```bash
./run-e2e.sh
```

This will:
1. Set up demo fixtures (runs `setup-demo.sh`)
2. Start the MPT daemon from `../my-pizza-team` source
3. Launch a Pi leader in a tmux session
4. Spawn a worker agent pointed at `demo/project/`
5. Monitor task progress until you Ctrl+C

Prerequisites: `pi`, `deno`, `tmux`, and the Pi extension installed (`mpt setup`).

To clean up running processes:
```bash
./run-e2e.sh --clean
```
