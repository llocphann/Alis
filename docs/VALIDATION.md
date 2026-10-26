# Maintainer validation

The canonical daily maintainer gate is local, clean-clone validation of `dev`:

```bash
bash scripts/validate-maintainer-local.sh
```

## Fish all-in-one validation

For a developer workstation using Fish, `scripts/validate-all.fish` is the single orchestration entrypoint. It reuses the canonical clean-clone validator instead of maintaining a second copy of the regression matrix, then optionally adds environment-dependent and live acceptance checks.

Run the complete non-release REQUIRED LOCAL matrix for the exact checked-out HEAD with:

```fish
fish scripts/validate-all.fish
```

For the broadest workstation run, including the deferred Nix lane when Nix is installed, live shell `version`/`status`/`doctor`/`doctor --perf`, runtime journal scanning, and an interactive release acceptance checklist, use:

```fish
fish scripts/validate-all.fish --full
```

Useful focused forms are:

```fish
fish scripts/validate-all.fish --strict-qml
fish scripts/validate-all.fish --with-nix
fish scripts/validate-all.fish --live
fish scripts/validate-all.fish --interactive
fish scripts/validate-all.fish --full --log /tmp/alis-my-validation.log
```

The Fish wrapper requires a clean working tree because the canonical validator deliberately tests a clean clone of the exact Git HEAD; uncommitted changes would otherwise be outside the tested snapshot. It records the exact SHA, tool/environment information, PASS/FAIL/SKIP for every orchestration stage, embeds the canonical validator output into the same persistent log, and returns nonzero when REQUIRED checks or explicitly requested optional/release checks fail.

`--full` does not pretend that hardware/compositor/release behavior can be proven statically. The interactive portion asks the operator to exercise bar/settings loading, connected popouts, Media, taskbar previews, both sidebars, Waffle/Overview/Search, Dock, settings navigation, fullscreen/focus transitions, multi-monitor/hotplug, fractional scaling, suspend/resume, hardware-dependent battery/TLP/ThinkFan paths, and package acceptance. Items that are not applicable should be recorded as SKIP rather than PASS.

The command creates a temporary clone, records the exact tested SHA, runs the required non-Nix validation matrix, and writes **one canonical diagnostic log**. By default the log is outside the working tree at:

```text
/tmp/alis-maintainer-validation-YYYYMMDD-HHMMSS.log
```

The exact log path is printed at startup and again as `FINAL LOG:` in the terminal summary. Set `ALIS_VALIDATION_LOG=/path/to/file.log` only when a different destination is needed.

That single log is the only artifact a maintainer should need to send for review. The validator may use temporary per-check capture files internally, but they are removed with the temporary validation workspace and are not separate deliverables.

A PASS applies only to the exact SHA printed in that log. If `dev` advances, the new HEAD is unvalidated until this command is run again.

## Single-log contract

The terminal is intentionally concise: one progress line per check plus the final result, SHA, counts, and `FINAL LOG:` path. Detailed successful-test stdout is not repeated into the log unless it is needed for a skip reason. For a failed check, the log includes the command, working directory, exit code, and complete captured failure output between `BEGIN FAILURE` / `END FAILURE` markers.

The log also records host/OS context, important tool versions, the clean-clone git status, QML parser state, deferred Nix state, grouped failure areas, and environment/release-only checks that were not executed. This makes the log self-contained enough for diagnosis without asking the maintainer to paste terminal output or collect side logs.

QML JavaScript files using `.pragma` or `.import` are not passed to `node --check`; they belong to the QML JavaScript dialect and are delegated to the QML project guards. Plain/Node JavaScript continues to use `node --check`.

The validator invokes Make-only contracts with fail-fast Bash shell flags so a failing command inside a multi-command recipe cannot be followed by a later successful command and incorrectly surface as a PASS.

## Validation matrix

### REQUIRED LOCAL

Daily validation is blocking for all of the following:

- clean-clone identity and exact SHA capture;
- host dependency preflight;
- tracked shell/package, Python, JSON, JavaScript, and Fish syntax;
- every tracked `test-*.py` regression;
- every tracked non-Nix `test-*.sh` regression;
- translation catalog audit and source parity;
- IPC parser coverage and generated registry freshness;
- documentation contracts;
- project-specific QML/startup guards;
- runtime payload and generated-state contracts;
- Connected Perimeter cutover, routing, output placement, fallback, registry recovery, settings, compatibility, and runtime-health contracts;
- Equalizer boundary/lifecycle and optional-backend graceful-degradation contracts;
- battery/TLP/ThinkFan helper, UI, timeout, and lifecycle contracts;
- updater/source-target identity and lifecycle contracts;
- Arch metadata/source identity and non-Nix package contracts;
- staged install/uninstall, package teardown, prefix/path relocation, and package-owned lifecycle hooks;
- a final source-tree mutation check.

The validator collects independent failures instead of stopping at the first failing gate when continuing is safe.

### OPTIONAL / ENVIRONMENT DEPENDENT

`qmlformat` parsing is optional in the normal daily command because old or missing Qt tooling must not turn a project-guard result into a false parser result. The summary always reports one of `QML parser: PASS`, `QML parser: FAIL`, or `QML parser: SKIPPED`, including the detected version when available. A parser skip is counted as a skip, not a PASS.

For an environment that has a suitable parser, the stricter form is:

```bash
bash scripts/validate-maintainer-local.sh --strict-qml
```

Strict mode requires `qmlformat >= 6.8`; missing or older parser tooling is a failure in that mode.

### RELEASE-ONLY

These checks remain outside daily static/local-contract validation because they require a real host or publication environment:

- actual Arch package build/install in a packaging environment;
- live Niri/Quickshell desktop acceptance;
- multi-monitor and hotplug behavior;
- suspend/resume behavior;
- fractional-scaling and live focus/fullscreen acceptance;
- live audio/hardware behavior that requires the real desktop session;
- GitHub release publication, Wiki remote access, credentials, and hosted permissions.

They must be completed before release when relevant; a daily local PASS does not claim these acceptance checks passed.

### NIX-DEFERRED

Nix support remains in the repository, but dedicated Nix evaluation/build/module validation is temporarily deferred and non-blocking for the maintainer daily lane. `scripts/test-nix-module-contract.sh`, Nix package assertions, and `.github/workflows/nix.yml` are not evidence for or against the REQUIRED LOCAL result.

This is a validation-policy choice, not removal of Nix support and not a claim that the Nix lane is green.

### REDUNDANT / COMPATIBILITY AGGREGATES

Some standalone aggregates intentionally re-use lower-level contracts so they remain useful when run by themselves. The canonical validator still discovers tracked test files directly. Successful output is summarized rather than copied wholesale into the canonical log, which keeps repeated aggregate output from dominating the artifact while preserving full diagnostics for failures.

### STALE / NEEDS FIX

The 2026-09-16 validation audit removed two stale orchestration hazards from the required daily path:

- the canonical daily validator no longer makes dedicated Nix validation blocking;
- assertions that previously existed only inline in GitHub Actions are represented by repository regression contracts and are exercised locally.

Future stale tests should be fixed or reclassified rather than weakening product/runtime behavior merely to obtain a green aggregate. Waffle is an active product family and must not be treated as a legacy cleanup target.

## CI relationship

Hosted CI is diagnostic. Non-Nix workflows should invoke the same repository validator or the same reusable contracts used by it; they should not maintain a separate hidden set of product/architecture assertions.

For CI or another already-checked-out exact commit, the validator supports:

```bash
bash scripts/validate-maintainer-local.sh --current-repo
```

That mode still validates a clean clone of the current repository HEAD rather than the mutable working tree.
