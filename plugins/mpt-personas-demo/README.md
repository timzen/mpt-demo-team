# mpt-personas-demo

An example [my-pizza-team](../../../my-pizza-team) **persona package**: three
personas, no Work Sources, no code, no build. It's the smallest thing that
shares personas between teams — copy the folder to start your own. See
my-pizza-team `GUIDE.md` "Distributing a persona package" and docs/DESIGN.md
"Persona packages".

## What's in it

| Persona id | For | Used in the demo team |
|------------|-----|-----------------------|
| `mpt-personas-demo/careful-implementer` | workers — small, test-first changes; reads AGENTS.md first | `run-e2e.sh` sets it as DEMO-1's per-item override |
| `mpt-personas-demo/careful-reviewer` | workers — reviews/audits without editing; findings ranked by severity | the Solitary task *Audit project dependencies* |
| `mpt-personas-demo/tracker-triager` | triage — turns tracker tickets into concrete proposals | the demo-tracker's per-source triage persona (DEMO-3) |

An id is `<package.json name>/<file name without .md>`. They're **read-only** in
MPT (Config → Personas shows the package's name as their badge); **Duplicate to
edit** makes a team copy you can change (it doesn't follow later updates here).

## Layout

```
mpt-personas-demo/
├── package.json        # "name" (the id namespace) + "mpt": { "personas": ["personas/*.md"] }
└── personas/
    ├── careful-implementer.md
    ├── careful-reviewer.md
    └── tracker-triager.md
```

Each file is ordinary persona markdown — frontmatter `title`, `description`
(shown in pickers), `tags`, optional `kinds` (which pickers list it first:
`worker`, `triage`, `assistant`) — then the instructions injected into the
prompt. Use `###` headings or lower (they're nested under the prompt's own
sections), and close every code fence (an unclosed one is refused).

## Using it

The demo team's `config.json` loads it in place:

```json
"packages": [ { "source": "../../../plugins/mpt-personas-demo" } ]
```

Elsewhere: `mpt plugins doctor <path>` (✓ per persona), then `mpt plugins add
<path|git URL|npm:spec>` from the team dir and restart the daemon. Personas load
at startup; running work keeps the persona it started with.
