# THEME-PERF-06 — Production image seed cache

The Rust `alis-theme` backend now caches only the expensive **image extraction** outputs:
the original (pre-inversion) seed color and the auto-detected image scheme. It
does **not** cache computed palettes, terminals, SCSS, or generated integration
templates. Those still reflect each dark/light, invert, smart, soften,
color-strength, and terminal setting on every request.

## Correctness and invalidation

- Key: SHA-256 of **full image contents**, the bitmap sampling size
  (`--size`), and an explicit extraction/scheme algorithm version.
- In-place image replacements, including same size and restored modification
  time, produce a new key. An image modified during decode is **not cached**.
- Cache hits are double-checked against image bytes before reuse. A replaced
  or corrupted entry falls back to normal image generation without changing
  colors.
- Entries are validated before use; cache errors do not cause a theme-generation
  failure. Entries are written via unique temporary files plus atomic rename.
- Only `v1-*.json` entries in Alis' seed-cache directory are eligible for
  pruning. Oldest entries are removed after inserts to keep **at most 64**
  entries in normal single-writer operation.
- Cache files contain the image digest, seed and scheme, but **not source image
  paths**. The legacy `--cache color.txt` still emits the seed exactly as
  before, independently of this performance cache.

Cache path: `${XDG_CACHE_HOME:-$HOME/.cache}/alis/theme-seeds/`

Disable temporarily for diagnosis or comparison:

    ALIS_THEME_SEED_CACHE=0 scripts/native-dispatch theme --path IMAGE ...

This opt-out affects only the production seed cache. The Python fallback stays
correct but does not use this Rust-specific persistent cache. Changing the
generator algorithm in future **must** bump `CACHE_VERSION` in
`native/alis-theme/src/seed_cache.rs`.

## Verification

Direct integration test (works without an installed Quickshell):

    cargo build --release --manifest-path native/Cargo.toml -p alis-theme
    python3 scripts/test-theme-seed-cache.py native/target/release/alis-theme

The test creates synthetic BMP files and private XDG directories to cover:
cold/warm hits, byte-for-byte output parity under mode/variant changes, legacy
seed file compatibility, source byte/size invalidation, malformed cache
recovery, concurrent first writers, and the bounded-entry policy.

All-in-one owner diagnostics include this integration test and an isolated
cold/warm/no-cache performance comparison:

    bash scripts/collect-auto-theme-diagnostics.sh

The suite is non-destructive to installed theme state. On the owner's setup,
this command will rebuild the `native/target/release/alis-theme` executable
selected by the backend. Neither command restarts Quickshell. Runtime
wallpaper-to-presented-frame improvements require separate live traces; the
previous 75–77 ms potential saving is **not** a guaranteed observed speed-up.
