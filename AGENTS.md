# AGENTS.md

Instructions for AI coding agents working on the mpt-demo-team project.

## Purpose

This project provides a **reproducible demo environment** for testing my-pizza-team (MPT). It contains:

- A fixture-based demo project (simple todo API)
- A fixture-based team directory (story, tasks, workflow)
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
│       └── notes/
│           └── project-conventions.md
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
