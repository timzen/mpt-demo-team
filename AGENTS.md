# AGENTS.md

Instructions for AI coding agents working on the mpt-demo-team project.

## Purpose

This project provides a **reproducible demo environment** for testing my-pizza-team (MPT). It contains:

- A fixture-based demo project (simple todo API)
- A fixture-based team directory (story, tasks, workflow, personas)
- A legacy (pre-persona) team fixture that proves MPT's persona migration
- An example Work Source plugin (`plugins/mpt-source-demo-tracker/`) and its seed tracker file
- An example persona package (`plugins/mpt-personas-demo/`)
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
│   │   ├── AGENTS.md     # The project's conventions (was the team's context/project-conventions.md)
│   │   ├── src/index.ts  # The app agents will modify
│   │   ├── tests/        # Existing tests
│   │   ├── package.json
│   │   └── tsconfig.json
│   ├── team/             # MPT team directory contents (persona layout)
│   │   ├── config.json           # packages (tracker + persona package), sourcePersonas
│   │   ├── personas/demo-coder.md  # team persona; the in_progress state selects it
│   │   ├── workflows/default/workflow.json  # in_progress: { "persona": "demo-coder" }
│   │   ├── stories/              # add-user-auth.json, ui-theme-polish.json (pending)
│   │   ├── tasks/<id>/workdef.md # board tasks, Solitary audit (persona:), Scheduled nightly run
│   │   └── schedules/nightly-test-run.json
│   ├── team-legacy/      # Pre-persona team (context/, triage.md, workflows/default/in_progress.md,
│   │                     #   story `context`, `contextRefs`, a triage-mode tracker) — setup-demo.sh --legacy
│   └── tracker/tracker.json  # Seed issues for the demo-tracker plugin (DEMO-3 is triage-mode)
├── plugins/
│   ├── mpt-source-demo-tracker/  # Example Work Source plugin (package.json, index.js, personas/, README)
│   └── mpt-personas-demo/        # Example persona package (package.json, personas/*.md, README)
├── plugins.local.example.json    # Example plugin overlay (plugins.local.json is gitignored)
├── setup-demo.sh         # Run to (re)create demo/ from fixtures (+ merges plugins.local.json;
│                         #   keeps installed plugin packages; --fresh clears them;
│                         #   --legacy uses fixtures/team-legacy)
├── try-plugin.sh         # [git/npm: mpt plugins add] → mpt plugins doctor → plugins.local.json → setup → run-ui.sh
├── run-ui.sh             # Daemon only, no agents (--restart, --clean, --legacy); prints plugin statuses
├── run-e2e.sh            # Full e2e run (ignores plugins.local.json)
├── .gitignore            # Ignores demo/, plugins.local.json and .plugin-packages/
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

### Personas

MPT's only behaviour concept (my-pizza-team docs/DESIGN.md "Personas: One
Library, Selected by Reference"); there is no context library any more —
project knowledge goes in the project (`fixtures/project/AGENTS.md`).

- Team persona `demo-coder` (`fixtures/team/personas/`) ← the `in_progress` state.
- `plugins/mpt-personas-demo/` (persona-only package, loaded in place by
  config.json `packages`): `careful-implementer`, `careful-reviewer` (← the
  Solitary audit task's `persona:`), `tracker-triager` (← config.json
  `sourcePersonas.demo-tracker.triagePersona`). Ids are `<package.json name>/<file>`;
  package personas are read-only (duplicate to edit).
- The tracker ships `tracker-worker` and declares it as `defaultPersona`.
- Keep personas polished and self-contained (frontmatter title/description/tags/kinds;
  `###` headings or lower; no unclosed fences) — they're teaching examples too.
- `fixtures/team-legacy/` must stay in the **old** layout (that's its point):
  don't "fix" it. `run-e2e.sh` asserts exactly what the migration makes of it, so
  change both together.

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
- **Personas:** default `mpt-source-demo-tracker/tracker-worker` (its own package);
  the fixture's per-source triage persona `mpt-personas-demo/tracker-triager` (a
  triage-mode item needs one, or it's mirrored but not run); a per-item override is
  `PUT /api/work-defs/demo-tracker~<id>/persona` (kept in the source's kv, survives re-syncs)
- Watch it: Work → **Demo Tracker** tab, `mpt plugins list` (from `demo/team`),
  `GET /api/work-sources`; edit `demo/tracker/tracker.json` to trigger a re-sync (~10s)
- **Settings UI:** it declares a `configSchema` + `preview`, and `init` re-reads
  `ctx.options()` (idempotent) — so Config → Sources edits, previews and saves it live
- `run-e2e.sh` first checks the persona migration on `fixtures/team-legacy` (files, `GET
  /api/personas`, the notice, 410 on `/api/context`, idempotent on restart); then the persona
  library (team/built-in/package listed, package personas read-only, Used by), DEMO-1 (per-item
  override) and DEMO-2 (source default) prompts + recorded WorkItem persona (claimed by a throwaway
  agent, completed, reopened in the tracker file), DEMO-3's per-source triage persona, and the
  worker's in-flight persona on `GET /api/agents` (warn-only). It also checks the tracker loaded,
  mirrored + enqueued all three issues, that write-back reaches the file, DEMO-3's triage end to end through the API (claim → triage prompt →
  `/proposals` → COMPLETE → accept creates a task that never runs → Triage now), and the
  Config → Sources routes (GET /api/sources schema; preview mirrors nothing; PUT config
  re-inits + next sync reflects it; switch-off 409 → disconnect archives; restore + re-queue)

Keep the plugin plain JavaScript (no build step), small, and well commented — it's
a teaching example. Plugins load at daemon startup, so restart after changing it.
The daemon runs under **Node** (`node daemon/main.ts`): the plugin loader needs
Node's module hooks.

### Trying your own plugins (the sandbox)

`plugins.local.json` (gitignored, at the repo root) is a JSON array of config.json
`packages` entries — a spec string or `{ source, config }`; relative local paths
are relative to the repo, `~/` and absolute work too; `{ "//": "…" }` entries are
comments. `setup-demo.sh` merges it into `demo/team/.my-pizza-team/config.json`
after copying the fixtures (paths made absolute; deduped by package, local
entries winning; the demo-tracker entry kept otherwise) and skips it when
`MPT_DEMO_NO_LOCAL_PLUGINS=1`, which `run-e2e.sh` sets so e2e stays deterministic.
`plugins.local.example.json` shows MPTSimWorkSources with placeholder config.

- Git/npm specs: `./try-plugin.sh ssh://git.amazon.com/pkg/MPTSimWorkSources
  [--config '<json>']` runs setup, `mpt plugins add <spec>` against the demo team
  (clone + `npm install --omit=peer` + `npm run build` into
  `demo/team/.my-pizza-team/packages/`), then `mpt plugins doctor`; on failure it
  `mpt plugins remove`s it and leaves plugins.local.json alone; on success it
  records the spec as-is, re-runs setup, starts `run-ui.sh --restart`. Re-runs for
  an installed spec only doctor it; `--update` runs `mpt plugins update` first.
  Contract: the plugin installs + builds with plain npm, or ships prebuilt entries
  (MPT is not Brazil-aware). Needs git access to the host (ssh key for
  git.amazon.com); live SIM syncs need `mcscli` + a fresh `mwinit`.
- **Package cache:** `setup-demo.sh` moves `demo/team/.my-pizza-team/packages/`
  aside to `.plugin-packages/` (gitignored) while it resets `demo/` and restores
  it, so installs survive resets; `./setup-demo.sh --fresh` clears it. The merge
  keeps entries that aren't installed — the daemon installs missing packages on start.
- Local paths: build the plugin (`brazil-build` for Brazil packages) →
  `./try-plugin.sh <path> --config '<json>'` (runs `mpt plugins doctor` from
  `../my-pizza-team` source and stops on failure, records the entry, runs setup,
  starts `run-ui.sh --restart`; `--no-start`, `--list`, `--remove`) → browse the
  Work tab → after a rebuild, `./run-ui.sh --restart`.
- `run-ui.sh` starts no agents. With agents, teammates work in `demo/project`
  unless the plugin config sets `directory`.
- Real external data is mirrored only into the gitignored `demo/`.
- Graduate a plugin with `mpt plugins doctor` + `mpt plugins add <path|spec> --config …`
  in the real team, then restart its daemon. README "Trying your own plugins" has the details.
- Never commit a `plugins.local.json`, and keep real group names / logins out of
  the example (placeholders only). The scripts write nothing outside this repo.

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
