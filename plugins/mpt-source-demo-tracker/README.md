# mpt-source-demo-tracker

An example [my-pizza-team](../../../my-pizza-team) **Work Source plugin**: a fake,
offline issue tracker whose "server" is one JSON file. It's a teaching example —
everything a real tracker plugin (Jira, Asana, …) does, in ~100 lines of plain
JavaScript so it loads in place from a local path with no build step. See
my-pizza-team `GUIDE.md` "Writing a Work Source plugin" for the full plugin model.

## What it does

| Hook | Behavior |
|------|----------|
| `sync` (every `intervalSeconds`) | Every issue with `"status": "open"` becomes an external WorkDef. MPT mirrors it read-only (id `demo-tracker~<issue id>`) and enqueues one WorkItem per **revision** — the issue's `updatedAt` (or a hash of title/body when it has none). An issue that's no longer open stops being reported, so its mirror is archived. |
| `onComment` | A comment on the mirrored WorkDef's thread (human, teammate, or daemon) is appended to the issue's `comments`. |
| `onItemTerminal` | The run's outcome is written back: `COMPLETE` → `"status": "done"`, `FAILED` → `"failed"`, `CANCELED` → only a note. Each adds a `mpt` comment. A **triage-mode** issue is never closed: it only gets a `triage … ended …` comment. |

Comments it writes don't change the revision, so its own write-back never re-runs an issue.
To re-run one, bump its `updatedAt` (and set it back to `open` if it was closed).

## Triage mode

An issue with `"mode": "triage"` (or every issue, with the `mode: "triage"`
option; an issue's own `mode` wins, so `"mode": "work"` opts one back out) is
reported with `ExternalDef.mode` / `WorkSource.mode` set, and MPT **triages** it
instead of working it (my-pizza-team GUIDE.md "Triage-mode sources"; docs/DESIGN.md
"External sources" — "Triage mode"). A teammate reads the issue and the team's
`triage.md` and posts proposals with `propose_work`; you **Accept / Edit / Reject**
them on the issue's **Triage** tab in MPT. Accepting creates the task (or story,
or schedule) without starting it. The plugin does nothing else for this: the
daemon picks the run's title ("Triage: …"), prompt, and Run (**Triage now**).

Each new revision is a fresh triage, so to answer a teammate's question, edit the
issue's `body` and bump its `updatedAt`. Proposals and decisions stay in MPT —
they aren't written back to the tracker.

## The tracker file

```json
{
  "issues": [
    {
      "id": "DEMO-1",
      "title": "Add GET /todos/:id",
      "body": "What to do (becomes the WorkDef's goal)",
      "acceptanceCriteria": "- optional",
      "status": "open",
      "updatedAt": "2024-06-01T10:00:00Z",
      "mode": "work",
      "comments": []
    }
  ]
}
```

## Configuration

In the team's `config.json`:

```json
"packages": [
  {
    "source": "../../../plugins/mpt-source-demo-tracker",
    "config": {
      "file": "../../tracker/tracker.json",
      "directory": "/path/to/the/project",
      "intervalSeconds": 10
    }
  }
]
```

| Option | Default | Meaning |
|--------|---------|---------|
| `file` | `tracker.json` | The tracker file, relative to the team dir. |
| `directory` | — | Working directory for the issues' WorkItems (relative to the team dir). |
| `intervalSeconds` | `10` | How often to sync. |
| `mode` | `work` | `"triage"` makes every issue triage-only (an issue's own `mode` wins). |
| `urlBase` | `https://tracker.example/browse/` | Prefix of each issue's (fake) link. |
| `id` / `label` | `demo-tracker` / `Demo Tracker` | Source id and UI tab name (not in the form; config.json only). |

## Settings from the UI, preview, on/off

The plugin declares a **`configSchema`** (a small JSON Schema with UI hints — titles,
descriptions, defaults, `mode` as a drop-down) for everything above but `id` / `label`,
so my-pizza-team's **Config → Sources → Demo Tracker** shows a form for it (GUIDE.md
"Setting up a plugin from the UI"):

- **Preview** calls the plugin's **`preview(ctx, draftOptions)`**: the open issues of the
  draft's `file`, mapped exactly as `sync` maps them — read-only, no write-back, nothing
  mirrored. An unreadable file or an empty tracker comes back as a warning.
- **Save** writes the settings into the team's config.json and calls **`init`** again; `init`
  re-reads `ctx.options()` into the settings every hook uses, so a new `file`, `directory`,
  `urlBase` or `mode` applies to the next sync without a restart. (`intervalSeconds` is read
  when the daemon starts its timers; `mode` is a getter on the source, so it reaches new
  revisions.)
- **On/off:** the plugin declares no `toggle`, so MPT gives it the default one,
  `features.demo-tracker`: off = no sync; with mirrors, "Turn off and archive N items".

Or add it with the CLI (from the team dir): `mpt plugins add <path> --config '{"file":"…"}'`.
Plugins load at daemon startup, so restart the daemon after changing the package
or its config (`mpt plugins list` shows whether it loaded, and the error if not).

## Package layout

- `package.json` — `"mpt": { "sources": ["./index.js"] }` is the manifest;
  `"peerDependencies": { "my-pizza-team": "*" }` lets `index.js` import
  `WORK_SOURCE_API_VERSION` from `my-pizza-team/plugin`, which the daemon resolves
  to its own copy (nothing is installed here).
- `index.js` — the default export is a factory `(options, { teamDir }) => WorkSource`.
