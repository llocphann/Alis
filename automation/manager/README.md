# Hadalis Automation control

Settings is a frontend to the installed `~/.local/share/hadalis-automation/control.py` JSON endpoint. The installer also delegates old repo-copy control scripts to that backend before they can overwrite migrated state. Configuration stays at `$XDG_CONFIG_HOME/hadalis/automation.json`; durable runtime, recovery copies and bounded events stay privately under `$XDG_STATE_HOME/hadalis-automation`. Migration preserves existing profiles, prompts, continuous-loop semantics and uncertain submissions. Config/state transactions recover atomically after an interrupted write.

The scheduler independently manages each profile's project, conversation, user-message ID, final-response receipt and checkpoint. It uses bounded concurrency (default 4, maximum 8) and fair admission. Waiting for a response/job holds no global owner or queue. Only equal conversation IDs and truly shared resources serialize. Navigation, opening another project and normal Desktop use do not change monitoring. Editing the managed chat itself pauses continuation to preserve its history.

Submission intent is durable before dispatch. Lost acknowledgements reconcile the exact message ID and never resend. An unidentified legacy pending chat remains quarantined while other profiles progress. Completed responses are persisted before counters or continuation. Desktop/network downtime backs off observation, bounded to 300 seconds, without permanently disabling it. Up to three read-only stream reattachments resume existing server streams without a new message. A server-confirmed terminal generation failure archives its receipt and permits a distinct checkpoint/evidence recovery step, bounded to three automatic recoveries. Ambiguous generation/action outcomes are never replayed. Invalid final directives or unsupported diagnosis evidence retain the completed receipt and pause only that profile.

Generic objectives can research, analyze, code through GitHub, dispatch pinned local tests/diagnostics, inspect results, debug, fix and continue. WAIT_RESULT has profile ownership and can use a private local worker receipt while Git publication is down. Continuation receives only allowlisted observations, error codes and provenance; raw machine data stays local. Optional HADALIS_CHECKPOINT preserves phase, summary, next step and evidence IDs. HADALIS_DIAGNOSIS conclusions must cite observed worker evidence IDs. ChatGPT remains the reasoning agent; the backend and worker make deterministic protocol transitions only.

Start, Pause, Resume, Stop and Restart affect one profile. Pending replies remain observable after Stop. Restart reconciles the pending reply first, or requests cancellation of a local job before scheduling a fresh chat. Cancel local job persists a cancellation request; action receipts prevent execution replay. Confirmed Remove archives local recovery metadata and removes only the profile, retaining ChatGPT history. Archive/delete preferences remain pending semantic Desktop support and do not perform chat cleanup.

Backend, worker and the allowlisted privilege broker start under the user default target and have no lifecycle dependency on Quickshell or Desktop. Their systemd units bound process counts, memory and shutdown. Desktop is optional transport; its startup failure does not kill diagnostics/job publication/recovery. Privileged requests have fixed command/service allowlists, reasons and a durable local audit. Authenticate with an OS Polkit agent or sudo cache; Automation has no password field or persistent credential protocol. Risky shell changes require pinned canonical validation, staging and an independent rollback journal/watchdog. See automation/worker/README.md.

Install from the full Git source with `python3 scripts/install-hadalis-automation.py --enable-now`. Restart updated Python services explicitly; they do not reload source automatically. The installer does not synchronize the whole Quickshell deployment. The reset option refuses unresolved submissions/jobs. Status is read-only and shows scheduler and worker-pool health. Bounded diagnostics/export remains private; inspect logs before sharing. Regression tests use isolated config/state and fake transport. `HADALIS_TEST_NATIVE_LIVE=1 python3 scripts/test-hadalis-native-live.py` performs opt-in real Desktop concurrency/restart acceptance with harmless objectives and private evidence.

### GitHub token

Settings accepts an optional per-profile token for local Git operations. It is
stored by `secret-tool` in the system Secret Service keyring, without a plaintext
fallback. Install `libsecret` if that tool is missing and unlock the user keyring.
Input uses private stdin; Git receives it only through a repository-scoped
credential helper pipe. Configuration, state, Activity, prompts and results
contain no token. Duplication does not copy credentials. Clear removes the
keyring entry. ChatGPT's GitHub connector keeps its own authentication.
