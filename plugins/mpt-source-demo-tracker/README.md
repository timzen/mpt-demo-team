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
| `onItemTerminal` | The run's outcome is written back: `COMPLETE` → `"status": "done"`, `FAILED` → `"failed"`, `CANCELED` → only a note. Each adds a `mpt` comment. |

Comments it writes don't change the revision, so its own write-back never re-runs an issue.
To re-run one, bump its `updatedAt` (and set it back to `open` if it was closed).

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
| `urlBase` | `https://tracker.example/browse/` | Prefix of each issue's (fake) link. |
| `id` / `label` | `demo-tracker` / `Demo Tracker` | Source id and UI tab name. |

Or add it with the CLI (from the team dir): `mpt plugins add <path> --config '{"file":"…"}'`.
Plugins load at daemon startup, so restart the daemon after changing the package
or its config (`mpt plugins list` shows whether it loaded, and the error if not).

## Package layout

- `package.json` — `"mpt": { "sources": ["./index.js"] }` is the manifest;
  `"peerDependencies": { "my-pizza-team": "*" }` lets `index.js` import
  `WORK_SOURCE_API_VERSION` from `my-pizza-team/plugin`, which the daemon resolves
  to its own copy (nothing is installed here).
- `index.js` — the default export is a factory `(options, { teamDir }) => WorkSource`.
