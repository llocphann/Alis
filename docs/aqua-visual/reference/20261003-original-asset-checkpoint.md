# Aqua Visual First — original reference asset integrity checkpoint (2026-10-03)

Repository `llocphann/Hadalis`, branch `dev`; managed profile `profile-1e0042aca8e24db2`. Pre-write observed HEAD `f292351e2450aa07d97a9b1353367d4fb4e77593`. Read and followed unchanged `AGENTS.md`, `to-do/README.md` and `automation/worker/README.md`. The most recent prior visual checkpoint is `docs/aqua-visual/runs/20261002T190454Z-b04003/checkpoint.md`. The production `modules/abyss/companion/AbyssCompanion.qml` still has `border.width: 0` (verified blob `714ac71485b67fa242cde62f6296962f56f9b3f5`); do not repeat prior baseline/A/B jobs.

## Source identity discovery

Four named *actual Git-tracked* original files now exist in `assets/`; connector blob IDs in the exact requested order:

| Actual source asset | Connector-verified Git blob SHA |
| --- | --- |
| `assets/Water Droplet Companion.png` | `d232af73adeb2e9d4673ced04269f73a5d84a06d` |
| `assets/Water Droplet Companion Expression.png` | `f11033572cd43634be1c5a6451f5d172989c17a8` |
| `assets/Water Droplet Companion Animation.png` | `dbeabf0c00b58f5ef1e32a5f86016fbd1e71881a` |
| `assets/Water Droplet Companion Animation Plus.png` | `01d76718c365fe675359b3bfc9e5b303bbacaff6` |

The manifest `docs/aqua-visual/reference/manifest.json` exists (blob `ae8411dfec3bf35d616ffc6b347517671c6bdf31`) but currently declares `01_aqua_blueprint.png`, `02_aqua_expressions.png`, `03_aqua_animation.png`, `04_aqua_animation_plus.png` with original file sizes/hash values, whereas those four declared relative files are not present inside `docs/aqua-visual/reference/`. **Do not modify any of the four original assets** or assume the manifest authenticates the actual assets.

## Distinct bounded verification and diagnosis

- Added read-only `scripts/test-aqua-original-reference-assets.py`; profile-owned job `JOB-AQUA-REF-INTEGRITY-P1E0042-20261003-50` at source `483ed202186069c4aa0f02f8296da298f202db18`: receipt `:0` **exit1** at Unix `1790970451`; stdout empty, stderr 572 bytes private, no timeout. This result alone does not identify a failure cause.
- Added fixed-output `scripts/aqua-reference-assets-bounded-diagnostic.py`, which classifies only each source asset as M=match, B=byte mismatch, H=SHA mismatch, P=invalid PNG or X=missing without publishing image bytes. Profile-owned `JOB-AQUA-REF-DIAG-P1E0042-20261003-51:0` source `07bafcb0d88d3e57d468eab91b5870f56e68e2f8`, **exit0** at Unix `1790970541`, stdout 19 bytes, SHA-256 `7def0c7bdaae52302ccce34771a0ec1a9e075d375c12cf19fbc53cc8c0ad8584`, stderr0/no timeout. Deterministic enumeration of all 625 four-character classifier combinations, independently validated with SHA-256 `abc` test vector, matches **only** the classifier output `AQUA_REF_DIAG=BBBB\n`: all four actual source assets have *byte lengths different from current manifest entries*. Actual lengths and SHA-256 hashes are **not yet collected**.
- The GitHub connector's base64 fetch returned no binary content for these large original assets; its raw blob method returned UnicodeDecodeError for PNG bytes. No actual reference pixels were opened in this turn. **VISUAL_REVIEW_BLOCKED; no similarity/visual acceptance claim**. The previously reviewed, independently redacted [borderless real-Bar left/right Aqua sheet](../runs/20261002T190454Z-b04003/curated-real-bar-left-right.png) remains a candidate output, NOT a reference replacement.
- Earlier canonical validation remains unclassified; no new successful canonical follow-up receipt has been verified. Requested legacy classifier job `JOB-AQUA-CANONICAL-DIAG-P1E0042-20261003-49` remains NOT_FOUND in pending/results on last audit and must not be adopted or called pending.

## Next safe action

1. Fresh GitHub probe, fetch current `dev`, read `AGENTS.md` and worker contract; reconcile any concurrent writes or queued job receipts before dispatch.
2. Design one SHA-pinned **read-only** local source-inventory job that produces a bounded, explicitly safe metadata report with the **actual** four source SHA-256 digests, lengths and PNG dimensions, or source-verified downsized preview images for this chat through a source-owned, reviewed publication path. No raw local-machine logs/screenshots or original-asset mutations.
3. Correct the reference manifest only after identifying the exact original assets and verifying hashes. Then OPEN actual blueprint/expression/animation boards, compare the relevant Aqua renderer pixels/frame sequences against those exact references, and choose one evidence-led next visual change. Preserve existing valid A/B baselines and the default-off and native input safety invariants. Maintain visual-first order; no VISUAL PASS without direct reference comparison and owner acceptance.

No new local execution is pending from this checkpoint: `...50` and `...51` both have terminal receipts. No production-geometry or animation edit was made in this turn.


## 2026-10-03 rotation carry-forward

The detailed, current visual-first rotation handoff is `../20261003-visual-rotation-checkpoint.md`. This earlier reference-identity audit remains immutable historical evidence: all four actual `assets/` images exist, but manifest SHA-256/size identity is **not** verified; do not interpret its legacy relative filenames as missing source assets. Read the newer document for visual runs, receipt reconciliation and NEXT_CHAT_BOOTSTRAP.
