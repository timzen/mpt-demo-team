---
title: Nightly test run
type: Scheduled
directory: __DEMO_PROJECT__
cron: "0 2 * * *"
---
## Goal

Run the todo API's test suite and report the result. If anything fails, capture
the failing output so a human can triage it in the morning.

## Acceptance Criteria

- The test command is run from the project directory.
- A pass/fail summary is posted as a completion comment on this work.
- On failure, the relevant test output is included in the summary.

## Additional Context

This is scheduled work: the daemon enqueues a fresh run every night at 2am
(cron `0 2 * * *`). You can also trigger a run immediately from the Schedule
page with "Run now".
