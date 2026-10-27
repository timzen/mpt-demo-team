// mpt-source-demo-tracker — a fake, offline issue tracker as an MPT Work Source plugin.
//
// A teaching example: everything a real tracker plugin (Jira, Asana, …) does,
// against a JSON file instead of an API, in plain JavaScript so it loads in place
// from a local path with no build step. See my-pizza-team GUIDE.md "Writing a
// Work Source plugin" and the `WorkSource` / `SourceContext` types.
//
// The "tracker" is one JSON file:
//
//   { "issues": [ { "id": "DEMO-1", "title": "…", "body": "…", "status": "open",
//                   "updatedAt": "2024-06-01T10:00:00Z", "comments": [] } ] }
//
//   - sync:           every *open* issue becomes an ExternalDef. MPT mirrors it
//                     (read-only) and runs it once per revision. An issue that is
//                     no longer open stops being reported, so MPT archives its mirror.
//   - onComment:      a comment on the issue's MPT thread is appended to `comments`.
//   - onItemTerminal: a finished run writes the outcome back — COMPLETE marks the
//                     issue "done", FAILED marks it "failed", CANCELED just leaves a note.

import * as fs from "node:fs";
import * as path from "node:path";
import { createHash } from "node:crypto";
// Resolved by the daemon to *its own* copy of the host API (a peer dependency:
// never installed here), so this is always the running app's value.
import { WORK_SOURCE_API_VERSION } from "my-pizza-team/plugin";

/** @typedef {{ id: string, title: string, body?: string, acceptanceCriteria?: string, status: string, updatedAt?: string, comments?: { at: string, author: string, body: string }[] }} Issue */

/**
 * The default export is a factory: called once at daemon startup with this
 * package's `config` from the team's config.json `packages` entry (read-only).
 * @type {import("my-pizza-team/plugin").PluginFactory}
 */
export default function demoTracker(options, { teamDir }) {
  // Settings, with defaults. Paths are relative to the team directory.
  const file = path.resolve(teamDir, String(options.file ?? "tracker.json"));
  const directory = options.directory ? path.resolve(teamDir, String(options.directory)) : undefined;
  const everySeconds = Number(options.intervalSeconds ?? 10);
  const urlBase = String(options.urlBase ?? "https://tracker.example/browse/");

  /** @returns {{ issues: Issue[] }} */
  function readTracker() {
    // A missing or broken file is an error: MPT logs it, backs off, and retries
    // (the "external system" is down); it never archives everything.
    const data = JSON.parse(fs.readFileSync(file, "utf8"));
    if (!Array.isArray(data.issues)) throw new Error(`${file}: expected { "issues": [...] }`);
    return data;
  }

  /** Read-modify-write one issue. Synchronous, so two write-backs never interleave. */
  function updateIssue(issueId, change, ctx) {
    try {
      const data = readTracker();
      const issue = data.issues.find((i) => i.id === issueId);
      if (!issue) return ctx.log(`write-back: no issue ${issueId} in ${file}`);
      change(issue);
      fs.writeFileSync(file, JSON.stringify(data, null, 2) + "\n");
    } catch (e) {
      // Write-back is fire-and-forget: log, never throw into the daemon.
      ctx.log(`write-back to ${issueId} failed: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  function addComment(issue, author, body) {
    (issue.comments ??= []).push({ at: new Date().toISOString(), author, body });
  }

  /** @type {import("my-pizza-team/plugin").WorkSource} */
  const source = {
    id: String(options.id ?? "demo-tracker"), // lowercase + dashes; prefixes the mirrored WorkDef ids
    label: String(options.label ?? "Demo Tracker"), // the UI tab's name, and "Open in Demo Tracker"
    apiVersion: WORK_SOURCE_API_VERSION,
    syncEveryMs: () => everySeconds * 1000,

    init(ctx) {
      ctx.log(`reading issues from ${file} every ${everySeconds}s`);
    },

    // Every open issue, as it reads *now*. MPT diffs this against its mirrors.
    async sync() {
      return readTracker().issues
        .filter((issue) => issue.status === "open")
        .map((issue) => ({
          externalId: issue.id,
          // The revision decides "is this a new version to run?". It covers what
          // the work *is* (title, body, updatedAt) and not the comments we append
          // ourselves, so our own write-back never re-triggers a run.
          revision: issue.updatedAt ?? hash([issue.title, issue.body, issue.acceptanceCriteria]),
          title: issue.title,
          goal: issue.body ?? issue.title,
          acceptanceCriteria: issue.acceptanceCriteria,
          directory,
          url: urlBase + encodeURIComponent(issue.id),
        }));
    },

    // A mirrored def's parent id is the issue's externalId.
    onComment(def, comment, ctx) {
      updateIssue(def.parent?.id, (issue) => addComment(issue, comment.from, comment.body), ctx);
    },

    onItemTerminal(def, item, ctx) {
      updateIssue(def.parent?.id, (issue) => {
        if (item.state === "COMPLETE") issue.status = "done";
        else if (item.state === "FAILED") issue.status = "failed";
        addComment(issue, "mpt", `run ${item.id} ended ${item.state}`);
      }, ctx);
    },
  };
  return source;
}

/** A short content hash, for issues without an updatedAt. */
function hash(parts) {
  return createHash("sha256").update(JSON.stringify(parts)).digest("hex").slice(0, 16);
}
