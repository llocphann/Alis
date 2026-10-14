# Alis native runtime

Alis uses this Rust workspace as its production backend. Python implementations remain installed as an explicit rollback path, not the default selector.

The workspace builds `alis-inputd`, `alis-mpdd`, `alis-native` and `alis-theme`. The optional Companion state/scheduling backend (`alis-companiond`) is now built and installed separately by [Hadanion](https://github.com/llocphann/Hadanion). A source checkout can also use `native/target/release/` for development validation.

`scripts/native-dispatch` defaults to Rust. Explicit environment overrides have highest priority, then persisted selector state, then packaged binaries. Existing compatibility routes may use their retained Python fallback when strict mode is off. The external Hadanion package owns Companion dispatch and does not depend on this workspace or the generic backend selector.

Use `scripts/native-backend python` for emergency fallback, `scripts/native-backend rust` to return to production, and `scripts/native-backend status` to inspect state. Required migration `050-rust-native-default` clears benchmark-only selector overrides and promotes existing installations once.

Source build/install:

```bash
bash native/scripts/install-runtime.sh --build-only
bash native/scripts/install-runtime.sh --dest /path/to/runtime/native/bin
```

The final pre-cutover qualification at `1897c662cb2fd4123c254ed6b4242f0914dc5744` passed all native parity/build gates, deep MPD snapshot parity, and three alternating live Python/Rust A/B rounds with zero native activation blockers.

## Internal library snapshots

The default MPD `snapshot HOST PORT MUSIC_ROOT` contract retains `folders` for
manual tools and deep compatibility tests. LocalMusic adds a trailing `--lean`
to this command to omit that unused duplicate tree. All tracks, playlists,
artwork, queue, status and ordering are unchanged; folder/genre navigation is
derived from `tracks`. Both Python and Rust support the hint. Rust RPC forwards
it as snapshot `params.includeFolders=false`; omitted or non-boolean values
preserve the full format. Older helpers or daemons can return the full payload
without breaking the frontend, so this is an additive protocol change.
