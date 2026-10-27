# AGENTS.md

Instructions for AI coding agents working on the mpt-demo-team project.

## Purpose

This project provides a **reproducible demo environment** for testing my-pizza-team (MPT). It contains:

- A fixture-based demo project (simple todo API)
- A fixture-based team directory (story, tasks, workflow)
- An example Work Source plugin (`plugins/mpt-source-demo-tracker/`) and its seed tracker file
- A setup script that copies fixtures into .gitignored runtime directories

## Before Starting Work

1. Read `README.md` to understand the demo structure
2. Look at `fixtures/` to understand what gets deployed
3. Run `./setup-demo.sh` if you need a working demo environment

## Project Structure

```
mpt-demo-team/
├── fixtures/
│   ├── project/          # Demo app source (todo API in TypeScript)
│   │   ├── src/index.ts  # The app agents will modify
│   │   ├── tests/        # Existing tests
│   │   ├── package.json
│   │   └── tsconfig.json
│   └── team/             # MPT team directory contents
│       ├── config.json
│       ├── workflows/default/
│       │   ├── workflow.json
│       │   ├── in_progress.md
│       │   └── review.md
│       ├── stories/add-user-auth/
│       │   ├── story.json          # taskOrder lists the tasks in order
│       │   └── tasks/              # dirs are named by task id (identity, not order)
│       │       ├── add-user-auth-1/task.json
│       │       ├── add-user-auth-2/task.json
│       │       └── add-user-auth-3/task.json
│       └── context/
│           └── project-conventions.md
│   └── tracker/tracker.json  # Seed issues for the demo-tracker plugin (DEMO-3 is triage-mode)
├── plugins/
│   └── mpt-source-demo-tracker/  # Example Work Source plugin (package.json, index.js, README)
├── setup-demo.sh         # Run to (re)create demo/ from fixtures
├── .gitignore            # Ignores demo/ runtime directory
└── README.md
```

## Key Concepts

### Workflow

The demo uses MPT's default workflow: `todo → in_progress → review → done`

- **Claim** from `todo` transitions to `in_progress` (agent starts working)
- **Release** from `in_progress` transitions to `review` (lead sees results)
- **Lead** can approve (`review → done`) or send back (`review → in_progress`)
- **Re-claim** from `in_progress` just assigns — no transition (agent picks up where they left off with new context from lead's comments)

### The Demo Story

"Add User Authentication" — 3 tasks building on each other:
1. Create auth module (hashing + tokens)
2. Add register/login endpoints
3. Auth middleware to protect routes

Tasks are sequential within the story — MPT only offers the next unclaimed, non-done task.

### The Demo-Tracker Plugin

`plugins/mpt-source-demo-tracker/` is a fake, offline issue tracker written as a
my-pizza-team Work Source plugin (my-pizza-team GUIDE.md "Writing a Work Source
plugin"). `fixtures/team/config.json` `packages` loads it **in place** by a path
relative to the team dir (`../../../plugins/mpt-source-demo-tracker`), with
`config: { file, directory, intervalSeconds }`; `setup-demo.sh` copies
`fixtures/tracker/` to `demo/tracker/` and fills `__DEMO_PROJECT__` in
`directory` like everywhere else.

- `sync` mirrors the tracker's **open** issues (revision = `updatedAt`), one run per revision
- `onComment` appends to the issue's `comments`; `onItemTerminal` marks it `done` / `failed` (CANCELED: a note)
- **Triage mode:** an issue's `"mode": "triage"` (or the plugin option `mode`) is
  reported as `ExternalDef.mode` / `WorkSource.mode`; MPT triages it (proposals
  accepted/rejected on its Triage tab) instead of working it, and `onItemTerminal`
  never closes a triage-mode issue. Seed issue **DEMO-3** is the example.
- Watch it: Work → **Demo Tracker** tab, `mpt plugins list` (from `demo/team`),
  `GET /api/work-sources`; edit `demo/tracker/tracker.json` to trigger a re-sync (~10s)
- `run-e2e.sh` checks it loaded, mirrored + enqueued all three issues, that write-back reaches
  the file, and DEMO-3's triage end to end through the API (claim → triage prompt →
  `/proposals` → COMPLETE → accept creates a task that never runs → Triage now)

Keep the plugin plain JavaScript (no build step), small, and well commented — it's
a teaching example. Plugins load at daemon startup, so restart after changing it.
The daemon runs under **Node** (`node daemon/main.ts`): the plugin loader needs
Node's module hooks.

## While Working

### Adding New Fixtures

- Keep the demo project simple — it's for testing MPT, not showcasing app architecture
- Tasks should be small, self-contained, and testable
- Each task should produce a verifiable result (tests pass, endpoint works, etc.)

### Modifying the Setup Script

- `setup-demo.sh` must be idempotent (safe to re-run)
- It should always print the full paths needed to run MPT
- The `demo/` directory is ephemeral — never commit its contents

## After Making Changes

1. Run `./setup-demo.sh` to verify it still works
2. Update `README.md` if the fixture structure or usage changes
3. Keep this AGENTS.md in sync with any structural changes
