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
│   └── team/               # MPT team directory fixture
│       ├── config.json
│       ├── workflows/default/
│       │   ├── workflow.json
│       │   ├── in_progress.md
│       │   ├── needs_input.md
│       │   └── review.md
│       ├── stories/add-user-auth/
│       │   ├── story.json
│       │   └── tasks/
│       │       ├── 01-auth-module/task.json
│       │       ├── 02-login-endpoint/task.json
│       │       └── 03-protected-routes/task.json
│       └── notes/
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

## Resetting

Just run `./setup-demo.sh` again — it nukes the `demo/` dir and copies fresh fixtures.

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

Prerequisites: `pi`, `deno`, `tmux`, and the `pi-pizza-team` extension installed.

To clean up running processes:
```bash
./run-e2e.sh --clean
```
