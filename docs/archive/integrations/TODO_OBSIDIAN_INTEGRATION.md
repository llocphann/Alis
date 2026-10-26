> Historical snapshot archived on 2026-10-10 from Alis `8b2ed6f0a1fccddade206f0060ed19d19337a5da`. This document does not assign active work or prove that pending acceptance is complete. Use [the current categorized tasks](../../../to-do/README.md).

> Obsidian implementation now belongs to optional [Alis-Intergration](https://github.com/llocphann/Alis-Intergration); this is the former in-core design.

# Todo ↔ Obsidian Integration

Status: **implemented on `dev`; Internal remains the default backend**

Research baseline: 2026-09-22
Runtime contract updated: 2026-09-22

This document defines the safe integration boundary between Alis' existing
Todo UI and an Obsidian Markdown task source. It is intentionally conservative:
the default internal backend must keep its current behavior, Obsidian files must
never be rewritten wholesale, and Tasks-plugin semantics must never be silently
downgraded.

## 1. Goals

1. Keep `TodoWidget` as the shared UI used by Sidebar Right and Dashboard.
2. Let users select either the existing Alis store or an Obsidian note as
   the canonical Todo source.
3. Keep Obsidian Markdown editable from either application and reflect changes
   in Alis without restarting Quickshell.
4. Preserve ordinary Markdown around the managed tasks byte-for-byte.
5. Preserve Obsidian Tasks semantics for recurrence, custom statuses,
   completion dates and on-completion actions when that plugin is available.
6. Work while Obsidian is closed for reading and for safe/basic mutations.
7. Never launch Obsidian merely because Alis is polling or probing
   capabilities.
8. Fail closed on stale task references, ambiguous vaults, malformed managed
   sections or concurrent edits.

## 2. Non-goals for V1

- Parsing every task in an entire vault.
- Reimplementing the Obsidian Tasks query language.
- Reimplementing recurrence or custom-status transition logic.
- Managing arbitrary Markdown outside the Alis-owned task region.
- Requiring a companion Obsidian plugin.
- Depending on Advanced URI for task mutation.
- Depending on the CLI as the only way to read the task note.
- Automatically opening/focusing another vault in the background.
- Persisting synthetic UUIDs into the user's Markdown.

## 3. Current Alis contract

The current runtime has one singleton, `services/Todo.qml`.

Current canonical source:

```
~/.local/state/user/todo.json
```

Current human-editable mirror:

```
~/.local/state/user/todo.txt
```

The public UI contract currently consumed by `TodoWidget.qml` is:

```qml
Todo.list
Todo.ready
Todo.addTask(text)
Todo.markDone(index)
Todo.markUnfinished(index)
Todo.deleteItem(index)
```

`DashTodo.qml` embeds the same `TodoWidget`; therefore the integration belongs
behind `Todo.qml`, not in Dashboard-specific code.

The current `todo.txt` parser is intentionally simple. It trims lines, accepts
plain text as tasks and serializes the complete file back to `- [ ] ...`
lines. That behavior is valid only for the internal mirror and MUST NOT be used
against an Obsidian note.

## 4. Backend ownership

`Todo.qml` remains the facade. Backend selection is additive:

```
TodoWidget / DashTodo
        |
        v
   services/Todo.qml
        |
        +-- internal backend
        |     todo.json (canonical)
        |     todo.txt  (mirror)
        |
        +-- obsidian backend
              configured Markdown note (canonical)
```

The existing todo.json remains the dormant internal store while the Obsidian
backend is active. It is not reused as an Obsidian cache and is not overwritten
by Obsidian synchronization.

The default is `internal`. Existing installations therefore change no behavior
until the user explicitly configures and activates the Obsidian backend.

There must never be two writable canonical stores at the same time. Backend
switching changes which store is active; it does not repurpose or destroy the
inactive store.

## 5. Config schema

The implementation adds a top-level `todo` object to `Config.qml` and
`defaults/config.json`.

```json
{
  "todo": {
    "backend": "internal",
    "obsidian": {
      "vaultPath": "",
      "notePath": "Alis/Todo.md",
      "scope": "managed-section",
      "preferTasksPlugin": true,
      "allowBasicOfflineMutation": true
    }
  }
}
```

Schema:

```qml
property JsonObject todo: JsonObject {
    property string backend: "internal"
    property JsonObject obsidian: JsonObject {
        property string vaultPath: ""
        property string notePath: "Alis/Todo.md"
        property string scope: "managed-section"
        property bool preferTasksPlugin: true
        property bool allowBasicOfflineMutation: true
    }
}
```

Do not persist derived capability state such as CLI availability, whether
Obsidian is running, Tasks-plugin version or the active vault. Those are runtime
facts.

This is an append-only config addition. No config migration script is required
because the fallback remains `internal`.

## 6. Managed Markdown boundary

V1 manages only the region between exact markers:

```md
<!-- alis:todo:start -->
- [ ] First task
- [/] In progress task
<!-- alis:todo:end -->
```

Rules:

- At most one managed region is allowed.
- Both markers must exist before ordinary synchronization begins.
- A missing or duplicate marker is an error, not permission to rewrite the
  document.
- Text before the start marker and after the end marker is immutable to Alis.
- The marker lines themselves are immutable.
- A setup/migration operation may create the region after explicit user action.
- The parser ignores task-looking text inside fenced code blocks.
- Newline convention (LF/CRLF) and final-newline state are preserved.
- UTF-8 BOM, if present, is preserved.
- Alis never normalizes unrelated whitespace.

A dedicated note is recommended, but not required.

## 7. Task recognition

Match the same structural task shape used by Obsidian Tasks:

```text
indentation + list marker + whitespace + [status] + remainder
```

Supported list markers:

```
-  *  +  1.  1)
```

The parser must retain, not discard:

- raw line
- indentation, including blockquote/callout `>` prefixes
- list marker
- status character
- remainder after the checkbox
- source note path
- 1-based source line
- hash of the exact raw source line
- newline convention

V1 does not attempt to strip every Tasks-plugin metadata field out of the
description. Unless a Tasks-aware enrichment result is available, `content`
is the checkbox remainder exactly as represented in Markdown (trimmed only at
the checkbox boundary). This prevents a partial metadata parser from silently
changing what the user wrote.

The task model exposed by the facade becomes a superset of the old model:

```js
{
    content: "Fix Sidebar",
    done: false,

    id: "ephemeral-reference",
    statusChar: "/",
    statusType: "IN_PROGRESS",

    sourcePath: "Alis/Todo.md",
    sourceLine: 17,
    rawLine: "- [/] Fix Sidebar",
    rawHash: "...",

    indent: "",
    listMarker: "-"
}
```

`content` and `done` remain for UI compatibility.

The ID is an ephemeral optimistic-concurrency reference, not a persistent task
identity. A suitable V1 identity is derived from source path + line + exact-line
hash. If the file changes and the reference becomes stale, the mutation aborts
and the UI reloads.

## 8. Status semantics

Do not infer `done` as `statusChar !== " "`.

Core Obsidian Tasks meanings include:

- space → TODO
- `/` → IN_PROGRESS
- `x` / `X` → DONE
- `-` → CANCELLED

Custom statuses may map any configured character to TODO, DONE, IN_PROGRESS,
ON_HOLD, CANCELLED or NON_TASK.

When Tasks settings are available, read the plugin's status configuration and
derive `statusType` from it. Unknown symbols are treated conservatively as
TODO, matching Tasks' fallback behavior.

The current two-tab UI remains:

- Unfinished: everything whose status type is not DONE
- Done: status type DONE

CANCELLED is not silently treated as DONE. A later UI refinement may expose
status-specific filters without changing the backend contract.

## 9. Helper boundary

Do not grow `Todo.qml` into a Markdown/CLI implementation.

Add a one-shot Python helper, proposed path:

```
scripts/todo/obsidian_todo.py
```

Python is already a Alis runtime dependency and is used by multiple current
services.

The helper communicates only JSON on stdout. Diagnostics go to stderr.

Proposed commands:

```
obsidian_todo.py scan
obsidian_todo.py capabilities
obsidian_todo.py add --text ...
obsidian_todo.py toggle --id ...
obsidian_todo.py delete --id ...
obsidian_todo.py initialize-section
obsidian_todo.py migrate-preview --internal-json ...
obsidian_todo.py migrate-apply ...
```

Common input may be supplied as arguments for short scalar values and a JSON
request file/stdin for structured data. Never place full note contents in an
Obsidian CLI `content=` argument.

Every mutating response is followed by a fresh scan. The scan result, not CLI
stdout, is authoritative confirmation.

## 10. Read path

The canonical read path for the Obsidian backend is the filesystem, not the
Obsidian CLI.

```
FileView watches configured note + parent directory
        |
        +-- debounce
        |
        v
obsidian_todo.py scan
        |
        +-- validate path containment
        +-- validate managed markers
        +-- parse exact task lines
        +-- preserve raw references
        |
        v
Todo.list
```

Reasons:

- it works with Obsidian closed;
- it does not launch/focus Obsidian;
- it avoids CLI stdout timing/race behavior;
- it gives Alis the exact raw lines needed for optimistic concurrency.

`FileView` is suitable for the watcher. Quickshell currently watches both the
file and its parent directory and re-adds the file watch after replacement, so
atomic rename/write does not permanently detach synchronization.

## 11. Basic filesystem mutation

Basic tasks may be mutated without Obsidian running, but "basic" is a proven
capability, not a guess.

A basic task is one for which Alis can safely perform a structural checkbox
operation without emulating Tasks-plugin behavior. In particular:

- if `preferTasksPlugin=false`, ordinary space/x checkbox transitions may use
  the filesystem path;
- if last-known Tasks settings say the plugin manages the task (including a
  non-empty Global Filter that the line contains, or an empty Global Filter
  that makes all checkbox tasks eligible), toggle is rich and requires the
  Tasks-aware path;
- if `preferTasksPlugin=true` and Tasks capability/settings are unknown,
  offline toggle fails closed instead of assuming plain checkbox semantics;
- explicit delete remains a line-deletion operation guarded by the same CAS
  checks; it is not presented as a Tasks completion transition.

The helper must:

1. Open the configured note.
2. Revalidate that the physical note is inside the configured vault.
3. Locate exactly one managed region.
4. Locate the task by expected line and raw hash.
5. Abort on mismatch; never search-and-replace a merely similar string.
6. Replace/delete only the exact task line.
7. Preserve all other bytes and newline conventions.
8. Write a sibling temporary file, fsync it, then atomically replace the note.
9. Rescan and verify the requested state.

If a task contains rich Tasks metadata or uses a custom status whose transition
cannot be proven safe, basic mutation is unavailable.

## 12. Tasks-aware mutation

Do not reimplement Obsidian Tasks recurrence/status logic.

When the Tasks plugin is enabled, its public API v1 exposes:

```js
plugin.apiV1.executeToggleTaskDoneCommand(rawLine, path)
```

That operation can transform one source line into:

- zero lines for on-completion delete;
- one line for a normal transition;
- two lines for recurring-task completion.

Therefore every patch primitive MUST support a 1 → 0/1/2 line replacement.

Preferred rich mutation:

```
user clicks task action
        |
        v
verify Obsidian is already running
        |
        v
read-only CLI probe: active vault physical path
        |
        +-- mismatch --> no rich mutation; offer Open in Obsidian
        |
        v
serialized `obsidian eval`
        |
        +-- verify FileSystemAdapter.getBasePath()
        +-- resolve exact TFile
        +-- load Tasks plugin
        +-- calculate transformed Markdown with apiV1
        +-- Vault.process(file, callback)
              |
              +-- revalidate raw line/hash inside callback
              +-- replace exact 1 line with 0/1/2 lines
        |
        v
ignore mutation stdout as acknowledgement
        |
        v
filesystem rescan + verify
```

`Vault.process()` is the required Obsidian-side writer because Obsidian
documents it as the atomic read-modify-write primitive that prevents a file
from changing between the read and write phases.

Inside eval, physical-vault verification must use the public desktop
`FileSystemAdapter.getBasePath()` API and fail if it does not resolve to the
configured vault path.

## 13. CLI safety rules

The official CLI has useful capabilities but is not a transactional RPC layer.
V1 therefore applies these restrictions:

1. Never call the CLI as a background "is Obsidian running?" probe. Official
   behavior is to launch Obsidian on the first command if it is not running.
2. Detect a running app without invoking the CLI first.
3. Never use a target-vault CLI invocation merely to test availability; targeting
   a closed second vault can open a new Obsidian window.
4. For rich mutation, require the currently active CLI vault to resolve to the
   configured physical vault path. Preserve the raw
   `FileSystemAdapter.getBasePath()` value from that probe and bind the
   following mutating eval to that exact value. This permits symlink aliases
   without weakening the guard against an active-vault switch.
5. Serialize all Alis CLI calls. Current CLI versions have reported stdout
   cross-talk when eval calls overlap.
6. Use a helper-side lock in addition to the QML operation queue.
7. Treat mutation stdout/exit code as transport information only. A reported
   CLI issue can lose stdout after awaited vault mutations.
8. Confirm success by rescanning the file.
9. Put strict timeouts around every CLI subprocess.
10. Never pass full Markdown through CLI `content=`; current reports include
    multi-byte UTF-8 corruption around IPC chunk boundaries.

These rules deliberately sacrifice some multi-vault convenience for data
safety. V2 may relax them only after the relevant CLI behavior is demonstrably
stable.

## 14. Tasks plugin settings

When the active vault is verified and Tasks is enabled, use a read-only
`obsidian eval` to obtain settings via the plugin's public `loadData()`
method. Do not read a hardcoded
`.obsidian/plugins/obsidian-tasks-plugin/data.json` path.

`loadData()` can contain only persisted user values, so the helper must fill
missing fields with the Tasks defaults that the integration explicitly
supports and reject/ignore unknown schema shapes conservatively. Do not reach
into private runtime modules merely to obtain defaults.

Useful settings include:

- `globalFilter`
- `taskFormat`
- custom status definitions
- done/cancelled date behavior
- recurrence placement behavior

Global Filter is particularly important. If Tasks is configured to recognize
only tasks containing (for example) `#task`, Alis-created tasks must include
that filter when Tasks-aware creation is available. Alis must not invent a
second manually configured copy of the filter.

If plugin settings cannot be read, creation remains a plain Markdown task and
the UI must not claim Tasks-aware behavior.

V1 does not claim to reproduce Tasks' interactive Create/Edit modal. In
particular, Alis Add Task does not synthesize optional created-date or other
modal-only metadata. When a known non-empty Global Filter is required, Alis
may prepend that exact filter so the new checkbox is recognized by Tasks.
Subsequent completion/status transitions use the Tasks API when available.

## 15. Capability state

Runtime capability should be explicit and observable:

```js
{
    backend: "obsidian",
    noteReadable: true,
    noteWritable: true,

    obsidianInstalled: true,
    obsidianRunning: false,
    cliRegistered: true,
    cliResponsive: false,

    activeVaultMatches: false,

    tasksPluginInstalled: true,
    tasksPluginEnabled: false,
    tasksApiAvailable: false,

    richMutationAvailable: false,
    lastError: ""
}
```

Suggested high-level states:

```
internal
obsidian-ready-offline
obsidian-ready-basic
obsidian-ready-tasks
obsidian-needs-focus
obsidian-conflict
obsidian-invalid-config
obsidian-unavailable
```

Do not block reading merely because rich mutation is unavailable.

V1 deliberately does **not** persist a capability/settings cache. Tasks settings
are trusted only when obtained from the currently running, physically verified
vault. When Obsidian or Tasks capability is unavailable, rich classification
fails closed instead of authorizing a write from stale metadata.

A future diagnostic-only cache may store non-secret metadata, but it must never
contain canonical task content, prove that Obsidian is currently running, or
increase mutation capability.

## 16. Todo.qml facade evolution

Add non-breaking state:

```qml
readonly property string backend
property bool busy
property string errorMessage
property var capabilities
property string sourceLabel
```

Add ID-based operations:

```qml
function toggleTask(taskId)
function deleteTask(taskId)
function openSource(taskId)
function reload()
```

Keep the current index APIs as compatibility wrappers during migration:

```qml
markDone(index)
markUnfinished(index)
deleteItem(index)
```

The wrappers resolve the current item to its ephemeral ID and delegate. New UI
code should use IDs directly because line numbers and array indices can change
after recurrence expansion or external edits.

Only one mutation may be in flight. Additional UI actions queue or are disabled
until the authoritative rescan completes.

## 17. UI behavior

### Todo widget

The normal task list remains visually familiar.

Add lightweight backend feedback only when useful:

- source label / Obsidian indicator;
- busy state during mutation;
- non-destructive warning when rich mutation needs Obsidian;
- retry/reload on conflict.

The edit button changes from opening `Directories.todoTxtPath` to
`Todo.openSource(...)`.

For the Obsidian backend, open the note with the official URI form using its
absolute path:

```
obsidian://open?path=<percent-encoded-absolute-path>
```

This action is explicitly user-triggered, so focusing/opening Obsidian is
acceptable here.

### Settings

Put Todo integration in Settings → Services → Data. Reuse the existing
`FileDialog` / `FolderDialog` + `SettingsNativeDialogGuard` patterns.

Required controls:

- Backend: Alis / Obsidian
- Vault folder
- Note path inside vault
- Prefer Obsidian Tasks semantics
- Allow safe/basic mutation while Obsidian is closed
- Connection/capability diagnostics
- Open note
- Reload
- Migration/setup action

The backend selector must not activate `obsidian` until the note configuration
and migration/setup transaction succeeds.

## 18. Setup and migration

Switching canonical stores is a transaction, not a toggle.

The implemented V1 setup offers two ownership-safe paths:

- **Use Obsidian note**: activate the verified note as-is and preserve the
  Internal store dormant and unchanged.
- **Preview import → Import & activate**: available only when the managed target
  section is empty. Preview reports added/duplicate/conflicting counts, then the
  import is backed up, copied and verified before activation.

Automatic merge into a non-empty managed section is intentionally deferred.
V1 fails closed instead of guessing how to reconcile two canonical histories;
the user can review/edit the note explicitly and then activate it as-is.

Before applying a migration:

1. scan both sources;
2. compute a preview;
3. show added/duplicate/conflicting counts;
4. back up the target note once;
5. revalidate source hashes immediately before write;
6. freeze Alis-side mutations of the internal store while the copy is in flight;
7. apply the managed-section patch atomically;
8. rescan;
9. only then set `todo.backend = "obsidian"`. If migration fails, times out,
   or cannot start, release the freeze and keep Internal canonical.

Never delete or overwrite `todo.json` during migration. It remains the
inactive internal store and therefore a clean rollback target. V1 keeps
Obsidian runtime capability state in memory only.

Returning to `internal` is also explicit; it reactivates the preserved
internal store. It must not silently import the current Obsidian state unless
the user selects that operation.

## 19. Conflict behavior

A conflict is expected, not exceptional, when two editors can modify one file.

On any stale raw hash, changed marker boundary or unexpected line count:

- abort the mutation;
- do not retry against guessed content;
- rescan;
- keep the user's external edit;
- expose a short conflict state to the UI.

For add operations, the insertion point is the end of the managed region and
the region hash is checked immediately before write.

No last-writer-wins behavior is allowed for Obsidian notes.

## 20. Security and path validation

All helper operations must:

- canonicalize `vaultPath` with `realpath`;
- reject an empty/root vault path;
- normalize `notePath` as a vault-relative path;
- reject absolute `notePath` values;
- reject `..` traversal;
- resolve symlinks and verify the final note remains under the configured vault;
- never execute note contents as shell;
- invoke subprocesses with argv arrays, never shell interpolation;
- percent-encode URI values.

## 21. Flatpak

Do not implement the old socket-symlink workaround as normal behavior.

Current Flathub packaging has moved past the earlier CLI/socket issue, and the
integration should first use the officially registered Linux CLI at
`~/.local/bin/obsidian` when available.

Flatpak-specific handling belongs in diagnostics only. Alis should not mutate
Flatpak runtime directories or create compatibility socket links automatically.

The URI handler remains the preferred explicit "Open in Obsidian" path and is
compatible with desktop-file registration.

## 22. Test matrix

Parser fixtures must cover at least:

1. empty managed section;
2. LF;
3. CRLF;
4. UTF-8 BOM;
5. no final newline;
6. prose before/after region;
7. headings in document;
8. fenced code containing fake checkboxes;
9. nested list indentation;
10. blockquote/callout indentation;
11. `-`, `*`, `+`, numbered `1.`, numbered `1)` markers;
12. TODO `[ ]`;
13. DONE `[x]` and `[X]`;
14. IN_PROGRESS `[/]`;
15. CANCELLED `[-]`;
16. unknown/custom status;
17. duplicate task text on different lines;
18. marker-looking text inside fenced code is ignored;
19. duplicate markers -> fail closed;
20. missing marker -> fail closed;
21. stale raw hash -> conflict;
22. external edit during mutation -> conflict;
23. add at managed-region end only;
24. delete one line;
25. Tasks transform 1 → 2 lines for recurrence;
26. Tasks transform 1 → 0 lines for on-completion delete;
27. Global Filter task creation;
28. Tasks plugin unavailable;
29. Obsidian closed;
30. Tasks settings unknown while `preferTasksPlugin=true` -> offline toggle denied;
31. last-known Global Filter says task is Tasks-managed -> offline toggle denied;
32. active vault mismatch;
33. wrong physical vault inside eval;
34. CLI timeout;
35. CLI empty stdout after successful mutation;
36. two attempted concurrent mutations;
37. note symlink escaping vault -> reject;
38. Dashboard and Sidebar see the same refreshed list;
39. no persisted capability cache exists in V1, so stale cache data cannot
    authorize mutation;
40. `backend=internal` regression: existing Todo behavior remains unchanged.

Tests should use temporary directories and fixture Markdown. Unit tests must not
require a real personal vault.

## 23. Implementation sequence

The sequence below was used to keep the integration reviewable. The runtime now
contains each layer; later hardening commits tightened Tasks status semantics,
Flatpak detection, migration staging, source persistence, and wrong-vault
guards without changing the default Internal ownership.

Keep commits small and independently reviewable.

### Commit A — contract tests and parser helper

- add `scripts/todo/obsidian_todo.py`;
- implement scan/parse only;
- add parser/path-safety fixtures;
- no runtime wiring.

### Commit B — config and Settings shell

- add `todo` schema/defaults;
- add Services → Data controls;
- backend still defaults to internal;
- no automatic migration.

### Commit C — Todo facade refactor

- separate current internal persistence behind internal methods;
- add ID-based facade API and operation state;
- keep current index API wrappers;
- add regression tests proving internal behavior is unchanged.

### Commit D — read-only Obsidian backend

- dynamic note watcher;
- helper scan process;
- managed-region validation;
- edit/open-source URI;
- capability diagnostics;
- no rich writes yet.

### Commit E — safe offline mutations

- optimistic raw-line/region hash checks;
- atomic basic add/toggle/delete;
- conflict handling;
- rescan verification.

### Commit F — Tasks-aware CLI bridge

- non-launching running-app gate;
- active physical vault verification;
- serialized CLI lock;
- read-only Tasks settings discovery;
- `apiV1.executeToggleTaskDoneCommand()`;
- `Vault.process()`;
- post-mutation filesystem verification.

### Commit G — setup/migration transaction

- preview;
- backup;
- export/merge choices;
- activate backend only after verified success.

### Commit H — UI refinement and full regression pass

- capability/warning states;
- status-aware display behavior;
- Dashboard/Sidebar integration tests;
- runtime log audit;
- docs update.

No commit should combine the internal Todo refactor with first-time Obsidian
mutation logic.

## 24. Upstream contracts used

Primary contracts researched for this design:

- Obsidian CLI: app-running requirement, Linux CLI registration, vault/file
  targeting, tasks/task commands and eval.
  https://help.obsidian.md/cli
- Obsidian URI: absolute `path=` opening and URI encoding.
  https://help.obsidian.md/uri
- Obsidian Vault API: prefer `Vault.process()` for background read-modify-write.
  https://docs.obsidian.md/Plugins/Vault
- Obsidian Plugin API: `Plugin.loadData()` is public.
  https://docs.obsidian.md/Reference/TypeScript%20API/Plugin/loadData
- Obsidian desktop adapter: `FileSystemAdapter.getBasePath()` is public.
  https://docs.obsidian.md/Reference/TypeScript%20API/FileSystemAdapter/getBasePath
- Obsidian Tasks API/source: `apiV1.executeToggleTaskDoneCommand()`, status
  registry behavior, Global Filter behavior and recurrence/on-completion
  transforms.
  https://github.com/obsidian-tasks-group/obsidian-tasks

The CLI is treated as an optional accelerator/semantic bridge, not as the
canonical data store or a reliable mutation acknowledgement channel.

## 25. Acceptance criteria

The integration is ready to ship only when all of the following are true:

- Existing users who never enable Obsidian observe no Todo behavior change.
- Activating Obsidian never overwrites the dormant internal `todo.json`.
- Editing the managed Markdown region in Obsidian updates both Sidebar and
  Dashboard.
- Alis never modifies bytes outside the managed region.
- A concurrent external edit cannot be silently overwritten.
- Recurring/custom Tasks transitions use Tasks semantics when available.
- Rich tasks are never silently downgraded when Tasks semantics are unavailable.
- Background sync never launches or focuses Obsidian.
- Explicit Open/Edit can launch/focus Obsidian.
- Wrong-vault mutations fail closed.
- Every mutation is verified by a fresh filesystem scan.
- The full parser/mutation regression matrix passes.
