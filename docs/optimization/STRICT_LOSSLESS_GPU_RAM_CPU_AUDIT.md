# Strict-lossless GPU / RAM / CPU optimization audit

Audit baseline: `dev` at `1155e37093781a27e64a9caa100a52ac1ab60d15`.

Scope: find remaining optimization opportunities that are either strict-lossless or can be held to a measured visual deviation below 1%. This is research only. It does not authorize runtime changes by itself.

**Canonical status:** this is the sole active optimization research ledger. See [the optimization index](README.md). Superseded handoffs and dated implementation journals live under [`docs/archive/optimization/`](../archive/optimization/); do not append new research to them.

Rules:

- Do not claim whole-Hadalis CPU/GPU/RAM/FPS percentages without before/after measurement.
- Preserve runtime behavior, read/dependency order, lifecycle, input/focus, output ownership and fallbacks.
- A visual-change candidate must have a deterministic or owner-session A/B oracle and stay below 1% normalized visual error before promotion.
- Prefer lifecycle/allocation/render-pass removal over changing animation timing or fidelity.
- `Gain GPU` / `Gain RAM` below are qualitative unless an exact structural metric is shown.
- Lexical occurrence counts are evidence of code shape, not proof of runtime cost.

## Verified retired findings (current dev)

This is an **overlay on historical research**, not a claim that the following entire rounds are obsolete. Findings retain their original text and IDs for auditability. Only rows backed by a current source check and implementation commit are marked `RETIRED / IMPLEMENTED`.

| Finding | Current status | Verified evidence | Boundary |
| --- | --- | --- | --- |
| R16.1 / promotion #30 — LocalMusic dead `folderCollections` | **RETIRED / IMPLEMENTED** | `9376fa34f`; current `services/LocalMusic.qml` contains no `folderCollections` | R16.2 MPD `folders` transport remains **OPEN / compatibility-gated** |
| R43.2 / promotion #117 — OrbitalWeather per-quadrant table | **RETIRED / IMPLEMENTED** | `63ea47423`; `hourAngles` now shares transient tables; parity test is in-tree | R43.1 liquid Canvas per-node preparation remains **OPEN / oracle-gated** |

Earlier `NO ACTION`, `ALREADY OPTIMIZED`, `MEASURE FIRST`, `SUPERSEDED`, and `NOT PROMOTED` labels are **not** automatically marked newly retired. A low-value but still-existing code path is not the same as a completed implementation.

## Audit table

| File | Issue | Risk | Gain GPU | Gain RAM | Visual risk |
|-|-|-|-|-|-|
| `modules/screenCorners/ScreenEdgeField.qml` + `ScreenEdgeField.frag` | **IMPLEMENTED / REFERENCE BASELINE.** Healthy Screen Edge path already removed MultiEffect, ShaderEffectSource capture and blur-pyramid intermediates. Adaptive four-tile rasterization covers only the proven non-transparent perimeter. | Low for current implementation; live compositor acceptance remains separate. | **High structural reduction already landed.** Documented raster footprint is <9.7% of output at 1920x1080 and <4.9% at 3840x2160 for the default geometry; this is not a whole-GPU speedup %. | Medium structural reduction from removal of capture/blur intermediates and fallback binding compaction. | Intended global normalized MAE <=1%; owner-session A/B still required for live visual acceptance. |
| `modules/altSwitcher/AltSwitcher.qml` | **CANDIDATE — GPU/render passes.** Current `dev` contains 3 `MultiEffect` occurrences, 1 `ShaderEffectSource`, 4 `layer.enabled` sites and 2 `layer.effect` sites. The skew path uses a blurred layer plus an offscreen masked image layer with MSAA. Research replacing the mask/capture path with analytic geometry or a cheaper single-pass mask, while keeping the exact skew silhouette and current high-load fallbacks. | Medium. Mask AA, blur appearance, focus/navigation and rapid-switch lifecycle must remain identical. | Medium–High while the skew switcher is visible; zero expected idle gain when closed. | Low–Medium from fewer offscreen layer/mask surfaces. | Target 0% for mask-only replacement; otherwise <1% with raster A/B. |
| `modules/wallpaperSelector/WallpaperSkewView.qml` | **CANDIDATE — GPU + transient texture RAM.** Current `dev` contains 3 `MultiEffect`, 2 `ShaderEffectSource`, 3 `layer.enabled` sites. The front skew image keeps `layer.enabled: true`; the flipped back face allocates another masked effect only while flipped; a separate shadow MultiEffect is also present. Investigate analytic parallelogram clipping/masking and current-item/visible-range layer materialization. | Medium–High. Must preserve skew AA, flip face, video-preview behavior, delete UI, shadow and rapid navigation. | **High local potential** while the wallpaper selector is open, especially with multiple delegates. | Medium potential from avoiding per-delegate offscreen layer/mask textures. | Target <1%; requires front/back raster comparison including animation frames. |
| `modules/waffle/lock/WaffleLockSurfaceSafe.qml` | **CANDIDATE — lock-screen rendering.** Current `dev` contains 4 `MultiEffect`, 1 `ShaderEffectSource` and 9 Loaders. Full-screen wallpaper blur and avatar masking deserve separate measurement. For static wallpaper, investigate a frozen/cached blur path; keep GIF/video wallpaper dynamic. Avatar mask may be replaceable with a cheaper clip/analytic path. | Medium. Lock reliability and authentication UI take priority over savings; dynamic wallpapers must not freeze. | Medium while locked if the background blur is currently recomputed/materialized more often than needed. | Low–Medium from avoiding persistent mask/capture intermediates. | Target 0% for avatar clipping; <1% for any blur-path substitution. |
| `modules/overview/Overview.qml` | **MEASURE FIRST — conditional full-scene effect.** Current `dev` has one conditional `layer.enabled` + `ShellDesaturationEffect`; its three primary Loaders are already lifecycle-gated. Profile the desaturation path before changing it. Do not disturb the lazy-loader work that is already present. | Medium–High because the effect applies to a composed scene and Overview has input/transition ownership. | Low–Medium only when desaturation is enabled; otherwise none. | Low–Medium if a full-size layer buffer can be avoided. | Target 0%; no candidate should be promoted without capture parity. |
| `modules/abyss/AbyssWaveController.qml` | **MEASURE FIRST — CPU-to-texture update path.** The controller already sleeps when `mode === "SLEEPING"`, uses 128/256 samples, lowers idle disturbance cadence to 100 ms and updates one 1-pixel-high texture. Active mode still advances at 16/33 ms and repaints Canvas samples. Profile JS/Canvas cost before considering a native/image-buffer path. | High. The wave solver, spectrum response, settling and fresh-texture timing are visible behavior. | Low/uncertain; moving work can trade CPU for GPU rather than reduce total GPU. | Negligible–Low. | 0% preferred. Do not alter sample count/cadence unless a <1% perceptual oracle is added. |
| `modules/abyss/AbyssPerimeter.qml` | **LOW-PRIORITY / CURRENTLY CLEAN RENDER GRAPH.** Current `dev` has no MultiEffect, ShaderEffectSource, layer effect or persistent Loader in this file; only bounded interaction timers were found. Continue allocation/read-order research rather than adding another visual renderer. | Low for research; high if reactive topology is changed. | Low expected from renderer changes because the major composition is already centralized. | Low–Medium possible only through proven temporary-array/binding removal. | 0%; avoid visual-path churn. |
| `modules/dashboard/DashboardLayout.js` | **CANDIDATE — CPU/allocation, existing research lineage.** Existing optimization notes identify a guarded X-axis subset and responsive-overlap work. Re-run against current `dev`, preserve malformed-state behavior, candidate ordering/ties and read order, then promote only with oracle parity. | Medium. Geometry ordering and malformed layouts are contract-sensitive. | None directly. | Low from fewer temporary candidate arrays/objects if the guarded subset still exists. | 0%; layout coordinates must remain identical for the strict-lossless path. |
| `modules/dashboard/DashboardCanvas.qml` | **MEASURE FIRST — interactive CPU/binding pressure.** Current file has no MultiEffect/ShaderEffectSource/layer effect and no timers; it has one Loader, one Repeater and several Behaviors. Focus on drag/resize binding churn and object allocation rather than GPU effects. | Medium. Pointer geometry, draft commit/cancel and collision constraints are sensitive. | Low. | Low. | 0%; interaction geometry must be identical. |
| `services/GameMode.qml` | **CANDIDATE — CPU wakeups, not GPU.** Niri window changes already trigger event-driven fullscreen checks, but a recurring fallback timer also runs while auto-detect is active. Research watchdog semantics: reset the fallback only after a trustworthy event-driven check while preserving the maximum detection bound when events are missed. | Medium. The fallback exists for correctness; removing it outright is unsafe. | None. | None. | 0% visual; behavioral latency must remain within the current bound. |
| `services/TimerService.qml` | **CANDIDATE — CPU wakeups, subscription-gated refresh.** Stopwatch refresh runs every 33 ms whenever the stopwatch is running, independent of whether a visible consumer currently needs frame-rate updates. Research deriving elapsed time from the stored start timestamp and using a consumer/visibility lease for presentation refresh without changing persisted time semantics. | Medium–High. Hidden consumers, IPC and exact stopwatch behavior must be audited first. | None. | Negligible. | 0% visual for visible consumers; no timing/semantic drift allowed. |
| `services/Audio.qml` | **LOW PRIORITY / ALREADY BOUNDED.** Two 16 ms dispatch timers are one-shot queue coalescers; the 16 ms repeating ramp timer runs only during protected volume ramps. Do not merge or slow these without evidence because they encode device/protection behavior. | Medium for tiny expected gain. | None. | Negligible. | 0%; audio behavior is functional, not cosmetic. |
| `services/MemoryPressureService.qml` | **NO ACTION / ALREADY OPTIMIZED.** Checks are every 5 minutes, use `FileView` on `/proc/self/maps`, disable file watching and avoid spawning shell+grep. This is already a low-overhead design. | High downside / negligible upside. | None. | Negligible. | 0%. |
| `services/Network.qml` | **LOW PRIORITY / MOSTLY EVENT DRIVEN.** Uses `nmcli monitor`, a 200 ms debounce and bounded restart/rescan timers instead of constant short-interval polling. Keep unless profiling shows subscriber churn or process-spawn cost. | Medium. Connectivity state correctness is more important than micro-savings. | None. | Negligible. | 0%. |
| `modules/common/widgets/FadeLoader.qml` | **NO ACTION / GOOD LIFECYCLE BASELINE.** Loader is active only while shown or animating out, and visibility follows opacity. Preserve this pattern and compare other heavy Loaders against it. | Low. | Indirect only. | Low–Medium savings already realized by unloading hidden content. | 0%. |


| `modules/common/widgets/GlassBackground.qml` + `AngelBackground.qml` + `RicelinSurface.qml` + `ZzzGlassWash.qml` | **HIGH-CONFIDENCE CANDIDATE — bound wallpaper-glass rendering to the visible surface.** These helpers position a screen-sized wallpaper behind a usually much smaller panel, then enable a `MultiEffect` layer on that screen-sized item and mask/clip the result back to the panel. `GlassBackground.qml` explicitly notes that hiding the layer releases roughly 16 MiB per instance. Research a padded, screen-aligned local capture/sourceRect whose bounds are only the panel plus exact blur reach. Keep the original decoded wallpaper cache and sampling transform. | Medium. Crop coordinates, PreserveAspectCrop mapping, fractional scale and corner masks must be exact. | **High local/persistent potential** for visible glass panels because the offscreen blur area can fall from screen area to panel+padding area. | **High local potential** from smaller FBO/effect intermediates; decoded source cache may remain shared. | 0% is plausible for a sourceRect/crop-only path if blur padding and sampling coordinates are exact; otherwise require <1% raster A/B. |
| `modules/bar/BarContent.qml` + `modules/dock/Dock.qml` | **HIGH-CONFIDENCE CANDIDATE — full-screen wallpaper layer used to paint only a thin Bar/Dock slice.** Both Aurora/Angel fallback paths create an Image sized to the whole output, then enable `MultiEffect` blur while the parent clips to Bar/Dock geometry. Research capture-before-blur: retain the same screen-aligned wallpaper transform but materialize only the visible strip/body plus `blurMax` support. Native-blur paths stay unchanged. | Medium. All four Dock edges, Bar top/bottom ownership, PreserveAspectCrop and blur-edge support must be exact. | **High local potential** on non-native-blur Aurora/Angel paths; structural work scales with cropped area rather than full output. | **High local potential**: a full-screen RGBA8 layer is ~7.9 MiB at 1920×1080 and ~31.6 MiB at 3840×2160 before effect intermediates; the candidate should allocate only strip/body+padding textures. These are texture-size calculations, not measured RSS savings. | Target 0%; exact crop oracle should compare every visible pixel including 64 px blur reach. |
| `modules/common/perimeter/ConnectedSurfaceIrisFrame.qml` | **HIGH-CONFIDENCE CANDIDATE — connected shadow has a 4-stage render chain.** Current path renders a second `ConnectedSurfaceIrisField` as a shadow mask, captures it with `ShaderEffectSource`, blurs via `MultiEffect`, then captures the blurred result again with another `ShaderEffectSource` to enforce owner-side clipping. First investigate eliminating only the second capture with an exact clipped presentation item; separately evaluate an analytic SDF shadow integrated with the field as a <1% visual candidate. | Medium for capture elimination; Medium–High for analytic shadow. Owner-side scissoring, tangent weld rules and fractional scale are locked contracts. | Medium–High while connected popups/OSD/toasts/clipboard/edge surfaces are visible; savings multiply because this frame is reused by multiple surface families. | Medium from removing one or more transient shadow textures. | 0% target for second-capture removal; analytic replacement requires <1% global/edge-band A/B and existing shadow contract parity. |
| `services/ResourceUsage.qml` + `modules/common/widgets/ResourceUsageMonitor.qml` | **HIGH-CONFIDENCE CANDIDATE — metric-demand gating.** Lifecycle is already good for history/network, but every active lease still initializes/polls GPU and starts `diskPollTimer` regardless of whether the consumer displays GPU/disk. Default process-backed GPU cadence is 6 s (15 s in Low Power) and disk launches `df -B1 /` every 30 s. Add independent GPU/temperature/disk demand bits, prime each metric when demand appears, and preserve existing defaults for callers until all consumers are annotated. | Low–Medium. Must preserve immediate freshness when a metric becomes visible and existing retry/startup semantics. | None directly; may reduce dGPU/process activity and system power rather than rendering work. | Negligible direct RAM. | 0%. |
| `modules/background/Backdrop.qml` + `modules/waffle/backdrop/WaffleBackdrop.qml` | **MEASURE FIRST — full-screen blur is inherently full-screen, but animated branches remain expensive.** Static Aurora already decodes/renders at half resolution in the ii backdrop; GIF/video blur is gated by animation/effects/battery state and frozen-video frames release the decoder. Do not duplicate the Bar/Dock crop strategy here because the visible result is the whole output. Profile animated blur and transition overlap before proposing further visual compromise. | High for small expected gain unless profiling identifies a dominant branch. | Potentially high only during animated blurred wallpapers; otherwise current gating is already strong. | Medium transient during crossfade/animated blur. | 0% preferred; any temporal/downsample change requires <1% visual metric plus motion acceptance. |
| `modules/lock/LockSurface.qml` | **MEASURE FIRST — many small effect layers plus one full-screen safe blur.** Current file contains one safe `MultiEffect` wallpaper blur and numerous conditional DropShadow layers on lock-screen text/icons. The focus retry timer is bounded by attempts and is not an idle-loop target. Profile effect-node/FBO residency while locked before considering group-shadow consolidation. | High because lock readability/authentication reliability outrank micro-savings. | Medium only while locked if many individual shadow layers are simultaneously materialized. | Low–Medium. | Target 0%; do not change legibility or focus timing. |


| `services/AntiFlashbangSampler.qml` + `services/Brightness.qml` | **HIGH-CONFIDENCE FEATURE-ENABLED CPU/process candidate.** Anti-Flashbang is disabled by default, but when enabled each output samples at 500 ms by default by spawning `timeout -> bash -> grim -> magick`; event-triggered requests can add samples around window/workspace changes. Research a native streaming PPM mean-luminance helper or direct native capture/reducer that removes shell/ImageMagick process churn while preserving the current brightness policy and failure/backoff semantics. | Medium–High. This is a safety/comfort feature: sample meaning, timeout, fallback-to-1 after failures and policy thresholds must not drift. | None directly. | Low direct RAM; meaningful transient process/allocation reduction while enabled. | 0% visual-policy target. Any luminance numerical difference must be bounded tightly enough that threshold/multiplier decisions remain identical across an oracle corpus. |
| `services/WindowPreviewService.qml` | **MEASURE FIRST — bounded warm decoded preview cache.** The service intentionally retains up to 12 decoded 768×512 images, documented in-source as ~18 MiB of CPU pixel data, so Overview/hover previews open without decode latency. This is bounded rather than a leak. Research pressure-aware eviction only if RSS evidence shows value; keep disk snapshots and recapture policy unchanged. | Medium. Eviction can trade RAM for first-presentation latency even if pixels remain identical. | None. | Up to the bounded warm-cache footprint can be reclaimed under pressure; no baseline saving should be claimed unless the cache policy changes. | 0% pixels, but UX latency risk means this is not strict behavioral parity. |
| `services/RecorderStatus.qml` | **NO ACTION / BOUNDED FALLBACK.** External `wf-recorder` discovery uses `pgrep` every 15 s (30 s Low Power) only when not recording and no fast UI demand; visible recorder UI owns a separate 1 s demand poll and action-triggered checks are bounded. Existing regression explicitly protects this split. | High downside for tiny idle saving unless an equally reliable event source replaces external-recorder discovery. | None. | Negligible. | 0%. |
| `services/MprisController.qml` | **NO NEW CANDIDATE FROM THIS PASS.** The previously identified unconditional PipeWire enrichment debt has already been adapted: `pw-dump` is now scheduled from audio-stream/player-relevant events rather than an unconditional construction-time call. MPD bridge probing remains a separate compatibility path for ALSA/direct MPD. | Medium. Media discovery compatibility is broad. | None. | Negligible. | 0%. |


| `services/Notifications.qml` | **HIGH-CONFIDENCE CPU/allocation candidate — fuse derived-history rebuilds.** Every list mutation currently filters the full list for popups, scans the full list for latest-per-app timestamps, scans the full list again to build groups, then scans the popup subset again for popup groups. A single ordered pass can build popupList, latest timestamps and both group maps while preserving first-icon ownership, notification ordering, critical flags and the existing quirk that popup-group time is derived from the latest notification for that app across the full history. | Low–Medium if read/order parity is oracle-tested; notification objects/actions/timers are untouched. | None. | Low transient allocation reduction; persistent history size unchanged. | 0%. |
| `modules/common/widgets/Favicon.qml` | **HIGH-CONFIDENCE CPU/process candidate — eliminate cached-hit shell spawn and coalesce duplicate misses.** Every component instance starts `/usr/bin/bash` on completion even when the favicon file already exists; uncached instances can race for the same domain and launch duplicate curl work. Research a shared resolver/in-flight map: try the local cached URL without a child process, perform one direct curl/fetch per missing domain, then fan out the resulting URL to all waiters. | Low–Medium. Must preserve failed-download semantics, file identity, user agent and retry behavior; malformed/corrupt cache handling needs an explicit contract. | Negligible. | Low direct RAM; avoids transient child-process memory. | 0%. |
| `modules/mediaControls/EqualizerPanel.qml` + `modules/sidebarRight/CompactSidebarRightContent.qml` | **HIGH-CONFIDENCE hidden-work candidate — presentation-gate the CAVA lease.** The compact sidebar keeps its base Controls section loaded permanently; when the Media subsection exists, its Equalizer uses `active: root.panelVisible` even while a different sidebar section is presented. The Canvas 33 ms animation clock becomes effectively hidden with its ancestor, but the explicit Equalizer/CAVA subscription can remain held for the whole time the sidebar is open. Research a presentation lease that retains CAVA through the controls crossfade/prewarm boundary and releases it once Controls/Media cannot contribute visible pixels. | Medium. Returning directly to Controls must not expose analyzer startup/stale-spectrum latency; crossfade timing and other CAVA consumers must remain unchanged. | Low–Medium indirect reduction when this is the last CAVA consumer. | Low. | 0% target; release only outside the visible/crossfade interval. |


| `modules/wallpaperSelector/WallpaperSkewView.qml` | **HIGH-CONFIDENCE transient CPU/process candidate — uncached color analysis.** In addition to the GPU mask candidate above, current `dev` automatically walks every non-video item after color-cache load, component completion, count changes and folder changes; uncached images are processed in batches of 20 by one Bash script that invokes ImageMagick `convert` once per image. This work happens even with default `sortMode: "date"` and no color filter selected. Research a single native/batched analyzer with parity to the current 1×1 HSL result; separately evaluate demand-driven analysis only if color-filter first-use latency is explicitly accepted. | Medium. Hue/saturation bucket output, failure handling, queue ordering and cache publication must remain stable. Cache identity is currently filename-only and collides across folders; do not optimize around that bug without defining migration/path identity. | None. | Low direct RAM; lower transient child-process memory. | 0% for native-equivalent analysis; deferred first-use analysis changes interaction latency and is not strict behavioral parity. |


| `scripts/inir` | **HIGH-CONFIDENCE startup latency/process candidate — repair the pre-QML environment cache and ABI fast path.** `_get_systemd_user_env()` mutates cache variables but both consumers capture it with command substitution, so the function runs in a subshell and its cache state does not reach the parent. `apply_qt_runtime_env()` can therefore invoke bounded `systemctl --user show-environment`, then background `ensure_systemd_graphical_env` invokes it again while QML starts. Separately, `check_qs_abi()` runs `qs --version` before consulting the mtime-keyed successful ABI cache. Populate/read environment cache in the parent shell, parse the snapshot once, and move the exact successful ABI cache check ahead of `qs --version` while retaining a full probe when binary/library identity changes. | Low–Medium. Session env recovery and ABI mismatch protection are startup-critical; fallback paths must remain byte/condition equivalent. | None. | Negligible steady RAM; lower transient process memory. | 0%; no UI behavior change. |
| `shell.qml` + `services/ThinkFanService.qml` | **HIGH-CONFIDENCE default-startup process candidate — demand-gate ThinkFan ownership.** `shell.qml` force-materializes `ThinkFanService` every session, while the shipped default is `powerProfiles.fanControl.enabled=false`. The singleton immediately runs `/usr/libexec/inir-thinkfan --status` on completion. Keep session-long ownership when profile fan control is enabled, react when it becomes enabled later, and let Settings/System Monitor materialize/refresh the service on demand otherwise. | Low–Medium. Must preserve profile-follow immediately after enable and existing managed/direct-control detection. | None. | Negligible direct RAM; avoids helper/process fan-out on default sessions. | 0%. |
| `services/Battery.qml` + `services/TlpService.qml` | **HIGH-CONFIDENCE default-startup process candidate — separate normal battery telemetry from charge-care capability.** Battery unconditionally binds many `TlpService.*` properties, which materializes `TlpService`; its completion unconditionally runs `/usr/libexec/inir-battery-charge-limit --status` even though shipped `battery.chargeLimit.enable=false`. Demand-load/prime the charge-limit adapter when charge care is enabled or the Battery/TLP Settings surface needs capability details; keep ordinary UPower battery state independent. | Medium. Settings must get authoritative capability/status immediately on first presentation, and enabled policies must reconcile on boot before any write. | None. | Negligible direct RAM; avoids helper/process fan-out on default sessions. | 0%. |
| `services/Audio.qml` + `modules/common/widgets/SoundPicker.qml` | **HIGH-CONFIDENCE settings-only startup candidate — lazy sound-theme catalog.** Audio correctly refreshes microphone state on materialization, but also always runs `sh -> ls | sed | sort` to populate `themeSounds`. Repository search shows the catalog is consumed by `SoundPicker` only, and SoundPicker is used by Settings pages. Add idempotent `ensureThemeSoundsLoaded()`; refresh on audio-theme changes only after the catalog has been demanded. | Low. Preserve first Settings presentation and post-theme-change contents/order exactly. | None. | Negligible direct RAM; removes one startup shell pipeline. | 0%. |
| `modules/common/Appearance.qml` | **HIGH-CONFIDENCE settings/explicit-backend startup candidate — demand-gate Niri blur capability probe.** Appearance runs `niri --version` whenever Niri is active. Yet `blurBackendFor()` explicitly makes `auto` fidelity-first and never selects compositor blur; `nativeBlurSupported` is otherwise used by explicit compositor selection and Effects Settings visibility. Probe only when any effective blur backend requests `compositor`, or when an Effects Settings surface asks for capability; reactively prime when config changes. | Low–Medium. Explicit compositor config present at boot must not briefly fall back to wallpaper/off due to an unresolved capability. | None. | Negligible. | 0%. |
| `modules/common/widgets/MediaArtworkResolver.qml` | **HIGH-CONFIDENCE process dedupe candidate — share in-flight artwork resolution by cache key.** Six call sites can materialize independent resolvers for the same current media. Each instance independently launches cache-existence checks, local MIME checks/copies, file-stability checks, data-URI writers or curl download/retry workers against the same deterministic cache path. Atomic publish prevents corruption but does not prevent duplicated work. Research a shared resolver keyed by normalized metadata/cache identity that owns one in-flight operation and publishes readiness to all consumers. | Medium. Preserve display-source cache-busting, local-file stability checks, retries, MIME rejection and old-art retention during metadata transitions. | None directly. | Low–Medium transient reduction from fewer concurrent helper processes and duplicated buffers. | 0%. |
| `modules/common/widgets/CliphistImage.qml` | **HIGH-CONFIDENCE transient process dedupe candidate — one decode owner per clipboard entry.** Visibility gating prevents mass decode, and atomic temp-file publication prevents corruption, but multiple clipboard/search surfaces can still see the same uncached image simultaneously and each launch a Bash + `cliphist decode` pipeline before the shared output exists. A shared per-entry in-flight lease can let one owner decode while all waiters publish the same completed path. | Low–Medium. Entry identity, failure behavior and session-cache cleanup must remain unchanged; do not make invisible rows eager. | None. | Low transient reduction. | 0%. |
| `services/ThemeService.qml` + `services/MaterialThemeLoader.qml` + `services/IconThemeService.qml` + `services/FontSyncService.qml` | **MEASURE FIRST — separate shell-internal theme readiness from external desktop synchronization.** At Config-ready, shell calls ThemeService and IconThemeService. ThemeService can queue `applycolor.sh` plus the default-enabled Vesktop palette generation; IconThemeService restores the saved theme via `gsettings set` then runs native desktop icon sync; FontSync later reconciles GTK/KDE fonts. Shell palette/icon identity should stay immediate, but external app synchronization could be coalesced/deferred until after first frame if startup traces show contention. | Medium–High. External applications may observe synchronization timing, so this is not strict behavioral parity unless the deferred boundary is proven unobservable for session startup. | None. | Low transient. | Shell visual target 0%; external-app timing requires separate acceptance. |
| `modules/common/Directories.qml` + `services/SystemInfo.qml` | **MEASURE FIRST — split critical bootstrap directories from transient cleanup and lazy GECOS display-name lookup.** Directories already consolidated fourteen child processes into one ordered Bash bootstrap, but that command still removes feature temp trees during first-frame formation. SystemInfo seeds username from `$USER` yet immediately runs `getent passwd` to resolve displayName. Measure before changing: defer only cleanup that no startup-visible feature requires, and resolve displayName on first profile/lock/settings demand while retaining NSS correctness. | Medium. Early avatar/profile consumers and stale-cache cleanup contracts must be enumerated first. | None. | Low. | 0%. |


| `services/MprisController.qml` | **HIGH-CONFIDENCE session-growth cleanup — prune expired player-grace keys during existing lifecycle updates.** `_playerGrace` stores `dbusName -> timestamp`; behavioral grace expires after 2 s, but stale keys are never deleted. Every metadata-valid update clones the entire map with `Object.assign`, so many unique browser/mpv instance names slowly increase retained JS data and clone cost. When updating/rebuilding existing player state, retain only unexpired/current entries; do not add a polling timer. | Low. The only observable contract is the existing 2 s grace; pruning entries older than that cannot extend or shorten a valid grace window if the comparison uses the same timestamp boundary. | None. | Low but truly cumulative session RAM/JS-object reduction. | 0%. |
| `modules/abyss/looks/AbyssField.frag` + `AbyssField.qml` | **MEASURE/PROVE FIRST — guaranteed-transparent interior rejection before wave/SDF work.** Every presented full-screen Abyss field currently evaluates `waveProfile()`, water interaction and an SDF union with up to 40 rounded-rect records before the existing `d > 24` transparent exit. A conservative per-edge maximum inward-reach bound, expanded by connection smoothing, shadow/glow, current `crestPeak`, contact/ripple displacement and AA safety, could reject center fragments before wave texture reads and record SDF evaluation. | High until the geometric bound is formally conservative. Large utility/dialog surfaces can legitimately extend far into the workspace; derivative rules and corner joins must remain valid. | **Potentially high** on large outputs because rejected center pixels avoid wave texture sampling and dozens of SDF/fuse operations. | Negligible. | Exact 0% target for all accepted pixels; any false rejection is unacceptable. |
| `services/deferred/LatexRenderer.qml` | **MEASURE FIRST — intentional unbounded session cache, not a simple leak.** Every successful unique expression remains in `processedHashes`, `processedExpressions` and `renderedImagePaths`. The expression/path maps are actively consumed by `MessageTextBlock` to replace rendered LaTeX and replay duplicate completion, so they cannot simply be dropped after render. Consider count/byte-bounded LRU only if long AI sessions show meaningful JS/RSS growth; eviction trades RAM for MicroTeX re-render work. | Medium. Evicted expressions can incur re-render latency/process cost and must not break existing rendered messages. | None. | Potentially medium only in unusually LaTeX-heavy long sessions. | Pixels can remain 0%; latency/resource behavior changes. |
| `modules/background/widgets/CustomImageWidget.qml` | **MEASURE FIRST — paused video pipeline residency.** Transition-stale media slots are already cleared, and playback stops when hidden/power-suspended, but the active video slot keeps its `MediaPlayer` Loader active and source attached while merely paused. Benchmark PSS/GPU decoder residency versus resume latency before considering delayed unload/recreate on WidgetPowerManager suspension. | Medium–High for UX latency; unloading can change resume frame/timing even if eventual pixels are identical. | Low–Medium possible decoder/GPU residency reduction while suspended. | Medium possible multimedia-buffer reduction. | Not strict behavioral parity unless an exact preserved-frame/resume contract is proven. |
| `modules/settings/BarConfig.qml` | **MEASURE FIRST — section-level Settings residency.** Classic Bar page sections are all instantiated and switched with `visible`; host-level Settings residency is already bounded elsewhere. If page-open allocation profiling justifies it, use a short-residency/lazy section wrapper for inactive Appearance/Spectrum/Behavior/Modules content rather than redesigning the whole Settings host. | Medium. Section switch latency, focus/search navigation and config binding initialization are user-visible. | Low local potential. | Low–Medium while Bar Settings is open. | 0% visual result, but interaction latency must be accepted. |
| `services/PowerProfilePersistence.qml` | **MEASURE FIRST — ownership probe timing, not probe removal.** The shell keeps this service startup-resident; Config readiness immediately launches a shell that checks `systemctl is-active/is-enabled tlp-pd.service` before deciding whether persisted shell-owned power profile may be restored. The ownership check is correctness-critical. Measure moving only reconciliation after first frame; reject if delayed restore changes thermal/power/user-visible profile behavior. | High relative to expected saving. | None. | Negligible. | UI 0%, but power-profile timing is observable system behavior. |
| `scripts/capture-windows.sh` + `services/WindowPreviewService.qml` | **MEASURE FIRST — preview capture concurrency 2 vs 1.** Capture helper defaults to bounded two-way concurrency (override 1–4) and atomically publishes each result. Serial capture may reduce compositor/clipboard contention but increases total refresh time; current implementation already has timeout, stale-file, clipboard restoration and bounded warm-cache safeguards. Benchmark rather than assume. | Medium. First-preview/Overview freshness latency changes even if final images are identical. | Potentially lower transient compositor pressure. | Low transient. | Final pixels 0%; latency tradeoff. |


| `services/GameMode.qml` | **HIGH-CONFIDENCE correctness/startup-process candidate — make Niri animation reconciliation Config-ready-safe and separately owned from reactive GameMode state.** GameMode is effectively startup-resident through Appearance. Its 200 ms init schedules a 900 ms Niri reconciliation without checking `Config.ready`; before config loads, `controlNiriAnimations` falls back to `true`, so a slow boot can mutate/reload Niri even if the user's final config disables that behavior. Keep fullscreen/manual state resident, but arm animation reconciliation only once Config is authoritative; if Config is not ready when the timer would fire, queue exactly one reconciliation for the ready transition. | Low–Medium for the Config-ready fix; higher for any later no-op reload suppression. Must preserve crash-recovery reconciliation and manual/auto GameMode semantics. | None. | Negligible. | 0%. |
| `shell.qml` + `services/Weather.qml` + `services/ShellUpdates.qml` | **NO IMMEDIATE OPTIMIZATION — tier comments do not equal singleton materialization, but expensive work is already internally delayed.** Critical Bar bindings can instantiate Weather/ShellUpdates before shell's Tier 3/4 assignments. Weather nevertheless delays initial network work 3 s; ShellUpdates delays repo work 5 s and performs only update-resume state restoration at ~1 s. Treat future tiers as explicit expensive-work ownership, but do not add Loader indirection merely to delay singleton state. | Medium if timing is changed. | None. | Negligible. | 0%. |
| `services/MprisController.qml` | **MEASURE FIRST — direct-ALSA MPD compatibility probe remains eager.** Standard MPRIS state is needed early, and `pw-dump` is already event-gated, but `Component.onCompleted` still launches a Bash probe for `mpd-mpris` + `pgrep mpd` so an MPD session that bypasses PipeWire can become visible automatically. Moving only this probe after first frame could reduce startup fan-out, but can delay an already-playing MPD indicator. | Medium; direct-ALSA MPD discovery timing is user-visible. | None. | Negligible. | 0% pixels; presentation timing tradeoff. |
| `services/YtMusic.qml` | **NO ACTION — feature is already correctly self-gated despite early singleton references.** MprisController references YtMusic, but YtMusic's completion path calls `_initialize()` only when `sidebar.ytmusic.enable` is true; dependency probes, orphan-mpv cleanup, browser detection, data loads and OAuth checks remain dormant otherwise. | — | None. | None beyond resident declarative state. | 0%. |


| `services/Wallpapers.qml` | **HIGH-CONFIDENCE dead-cache removal — stop rebuilding the unused `wallpapers` list.** The service already exposes `folderModel` directly to every live selector/settings consumer. Repository-wide search finds no reader of `Wallpapers.wallpapers`; inside the service it is only cleared and repopulated in 64-item batches from `folderModel`. Remove `wallpapers`, `_wallpaperCacheIndex`, `_wallpaperCacheBuilder`, `_wallpaperCacheBatchesSincePublish`, `rebuildWallpapersCache()`, `appendWallpapersCacheBatch()`, the zero-delay cache timer and the `onCountChanged` rebuild hook. | Low. Preserve the public `folderModel`/directory/search/history contract; verify no external documented IPC/SDK surface promises `Wallpapers.wallpapers`. | None. | Low–Medium on large wallpaper folders by avoiding duplicate path strings, repeated array copies and batch timer churn. | 0%. |
| `services/AppSearch.qml` | **HIGH-CONFIDENCE CPU/allocation candidate — revision-keyed memo for `lookupDesktopEntry(appId)`.** Taskbar, dock, media, icon, ScreenTime and desktop-item surfaces repeatedly resolve stable app IDs. Direct misses currently fall through aggressive normalization and token-overlap loops over `_desktopIdStemMap`/`_startupClassMap` every call. Cache both hits and misses by exact input for the current `_cacheRevision`; invalidate atomically whenever DesktopEntries rebuild. | Low. The memo must key on input plus current revision and never survive a DesktopEntries rebuild; malformed/empty inputs remain uncached or preserve current null semantics. | None. | Low–Medium JS allocation/CPU reduction on repeated unknown/Electron/AppImage IDs. | 0%. |
| `services/Wallpapers.qml` + `FolderListModelWithHistory.qml` | **MEASURE FIRST — lazy wallpaper catalog residency.** `Wallpapers` is startup-resident through theme/background state, and its `FolderListModelWithHistory` immediately points at `~/Pictures/Wallpapers` (or configured directory), even though ordinary desktop rendering only needs the configured current path. Random-wallpaper actions and selector/settings pages need the catalog. Measure directory metadata/RSS cost with 100/1k/10k entries before deciding whether catalog ownership should activate only on selector/settings/random/auto-wallpaper demand. | Medium. Random shortcut currently has immediate access to `folderModel.count`; lazy loading introduces first-use latency unless a separate on-demand picker is used. Directory history/search semantics must survive activation/deactivation. | None directly. | Potentially medium with very large libraries. | 0% final pixels; first-use latency is the acceptance risk. |
| `services/GlobalActions.qml` + `scripts/setup/_scan.sh` | **LOW-PRIORITY / MEASURE FIRST — setup recipe scan.** Tier 3 always runs one Bash scanner; today the shipped directory has only one non-private recipe, so the scanner starts Bash plus one AWK process and reads at most 60 lines of that script. It also enables reactive rescans on folder mutation. This is real process fan-out but currently too small to justify complicating IPC/search availability. | Low technically, but setup actions are part of the globalActions catalog/IPC after Tier 3. | None. | Negligible. | 0%. |
| `services/RecorderStatus.qml` | **MEASURE FIRST — global external-recorder discovery cadence.** The service already does the right thing for visible controls: keyed fast-demand leases and bounded quick checks. When idle with no UI demand it still runs a global status probe every 15 s (30 s in low-power mode) to discover externally launched recorders. Replacing or further delaying this changes discovery latency; only revisit if process-wakeup traces show measurable cost. | Medium because external recorder detection latency is observable. | None. | Negligible. | 0%. |
| `services/AwwwBackend.qml` | **NO IMMEDIATE OPTIMIZATION — capability probe is required by the default backend contract.** Static wallpapers default to awww when both optional client/daemon binaries are available; the service must discover availability before deciding whether the external renderer or internal fallback owns the visible wallpaper. One startup Bash capability probe is therefore legitimate until an equivalent in-process executable lookup is available without PATH semantic loss. | — | None. | Negligible. | 0%. |


| `services/WallpaperListener.qml` | **HIGH-CONFIDENCE reactive CPU/allocation candidate — narrow the global Config safety net to the one list it exists to protect.** `Config.configChanged` has no path and fires after every `setNestedValue(s)`. WallpaperListener already has direct bindings for multi-monitor enable/global path and a dedicated `onWallpapersByMonitorRefChanged`; the broad listener exists only as a fallback for nested/list propagation. On every unrelated setting edit it currently restarts an 80 ms timer, reconstructs the per-screen map and serializes both old/new maps before concluding nothing changed. Track a serialized `wallpapersByMonitor` safety key and schedule the fallback refresh only when that key changes; keep all direct triggers and screen hotplug behavior. | Low. The safety fingerprint must be updated on initial/direct refresh and must still catch list replacement/reload cases that fail to emit the QML property change. | None. | Low CPU/allocation reduction during settings-heavy sessions; scales with output count and config edit rate. | 0%. |
| `services/ThemeService.qml` | **HIGH-CONFIDENCE reactive wakeup candidate — drive live-theme debounce from `liveRegenSignature`, not every Config change.** The 260 ms handler ultimately returns immediately when `liveRegenSignature === _lastLiveRegenSignature`. That signature already includes every config/wallpaper input capable of changing the regeneration result. Replace the global `Config.onConfigChanged -> liveRegenerateDebounce.restart()` trigger with the signature's own change signal, retaining Config-ready priming and explicit theme/apply paths. | Low. Keep startup signature priming, `setTheme()`'s explicit delayed auto regeneration, family-change semantics and cooldown behavior unchanged. | None directly. | Low timer/JSON/config churn reduction while editing unrelated settings. | 0%. |
| `services/MprisController.qml` | **HIGH-CONFIDENCE reactive CPU candidate — rebuild player filtering only when its two config inputs change.** The global Config listener currently calls both `_updateMpvCache()` and debounced `_rebuildPlayerList()` after every setting edit. Config affects `isRealPlayer()` only through `media.filterDuplicatePlayers` and `sidebar.ytmusic.enable`; `_updateMpvCache()` depends on live MPRIS membership, not Config. Use a small derived filter signature/change handler for those two values and leave player/YtMusic lifecycle signals as the cache/rebuild owners. | Low. Verify filter-toggle and YtMusic enable/disable produce the same membership/order and empty-list grace behavior. | None. | Low CPU/allocation reduction; avoids repeated MPRIS scans during unrelated settings changes. | 0%. |
| `services/ThinkFanService.qml` | **HIGH-CONFIDENCE opt-in process/wakeup candidate — replace global Config profile-follow events with derived fan-intent changes.** When profile fan control is enabled, every unrelated Config change calls `_handleProfileFollowEvent()`; stale status can trigger a helper refresh, while fresh status schedules an apply check. The actual config intent is fully represented by `profileFanControlEnabled` and `configuredActiveFanLevel`, with PowerProfiles already owning profile changes. Trigger profile-follow only from those derived values plus PowerProfiles. | Low–Medium. Preserve enable/disable behavior, active-profile level edits, post-startup arming and stale-status refresh before privileged writes. Existing tests that assert a generic `onConfigChanged` must be rewritten around the narrower contract. | None. | Low normally; meaningful process/wakeup reduction only for users with profile fan control enabled. | 0%. |
| `services/TlpService.qml` | **HIGH-CONFIDENCE opt-in reactive candidate — reconcile charge policy from `enabled`/`effectiveRequestedLimit` changes instead of every Config write.** The current global listener calls `apply()` after every Config mutation. `apply()` has strong no-op guards, so unrelated writes usually do not spawn `pkexec`, but they still schedule reconciliation. The desired charge policy is represented by the two Config-derived properties; hardware/status changes already flow through detector/apply completion. | Low. Preserve Config-ready detection, supported/discrete normalization and disable-owned-policy cleanup. | None. | Low CPU/event-loop reduction; avoids unnecessary apply comparisons on unrelated setting edits. | 0%. |
| `modules/background/Background.qml` | **NO CURRENT CHANGE — revision invalidations are live, not dead.** Full-file verification shows `_zoneRevision` is consumed by `_computeZoneOccupants()`, and `_imageRouteRevision` is consumed by the dynamic image-converter `Connections.target`. Search snippets initially obscured those reads. Do not remove either counter without a replacement dependency contract. | — | None. | None. | 0%. |


| `modules/bar/Workspaces.qml` | **HIGH-CONFIDENCE multi-output CPU candidate — skip workspace config/occupancy refresh when the workspace config snapshot is unchanged.** Every Workspaces instance listens to global `Config.configChanged`; `syncWorkspaceConfig()` then calls `updateWorkspaceOccupied()`, whose debounced worker builds a Set from every Niri window and derives occupied state for each shown workspace. Unrelated settings changes therefore cause O(outputs × windows) work. Keep the broad reliability signal if desired, but compare a signature/snapshot of only `bar.workspaces` fields before assigning properties or scheduling occupancy work. | Low. Relevant workspace config changes must still refresh immediately; Niri/Hyprland workspace/window signals remain the authoritative occupancy triggers. | None. | Low–Medium CPU/allocation reduction during settings edits, larger with more outputs/windows. | 0%. |
| `services/Ai.qml` | **NO IMMEDIATE MODEL-REBUILD BUG — global Config listener already has a semantic signature guard.** `_syncExtraModels()` serializes AI policy/extraModels/provider membership and returns before destroying/recreating AiModels when unchanged. A narrower Config trigger could save signature allocations when Ai is resident, but model churn is already prevented. | — | None. | Low possible allocation cleanup only. | 0%. |
| `services/TimerService.qml` | **NO IMMEDIATE OPTIMIZATION — broad Pomodoro sync is intentionally cheap.** Every Config change copies four validated integers into service properties. No process, file I/O, model rebuild or list scan follows solely from that sync. Keep the simple reliable listener unless profiling identifies it. | — | None. | Negligible. | 0%. |
| `shell.qml` deferred-feature Config listener | **NO IMMEDIATE OPTIMIZATION — broad checks are idempotent feature admission, not repeated heavy work.** On Config changes shell re-evaluates ScreenTime/Weather/CavaTheme/CalendarSync/FontSync eligibility; assignments are one-way singleton materialization and expensive service work retains its own lifecycle. Narrow only if a runtime trace shows this bookkeeping itself matters. | — | None. | Negligible. | 0%. |

| `modules/common/widgets/CliphistImage.qml` + `Favicon.qml` + `modules/settings/QuickWallpaperItem.qml` + `NotificationAppIcon.qml` + taskbar preview images | **HIGH-CONFIDENCE CANDIDATE — replace simple non-inverted rounded-mask FBOs with scene-graph clipping.** These leaf/image paths still enable an `OpacityMask` whose mask is only a same-bounds rounded rectangle/circle. The repository already treats `Quickshell.Widgets.ClippingRectangle` as the preferred no-mask-FBO primitive for equivalent media/thumbnail clipping. Start only with masks that have no inversion, transformed mask, blur contribution outside the clip, or topology-dependent shape. | Low–Medium. Edge antialiasing, subpixel/fractional-scale coverage, animated radius and ready/error transitions need raster parity; do not bulk-convert complex masks. | Medium aggregate on list/grid/preview surfaces; structurally removes one offscreen mask/effect layer per visible converted instance. | Low–Medium transient/persistent texture reduction depending on delegate count and lifetime. | Target 0%; if edge raster differs, require <1% global normalized error plus explicit edge-band/max-channel checks before promotion. |
| `modules/sidebarLeft/SidebarLeftContent.qml` and other lifecycle-gated full-surface rounded clips | **SECOND-PHASE CANDIDATE — extend the same scene-graph clipping proof to large content surfaces.** The left Sidebar SwipeView currently keeps a same-bounds rounded `OpacityMask` only while the panel is visible. If the leaf oracle proves `ClippingRectangle` parity, test the full-sidebar case separately; one avoided full-panel FBO is structurally larger than an icon mask. Do not remove child masks merely because a parent also clips until every alternate host is proven. | Medium. SwipeView transitions, current/adjacent Loader ownership, animated radius, pointer clipping and alternate embedding paths are behavior contracts. | Medium–High local potential while such a panel is open; zero idle gain when its current lifecycle gate is closed. | Medium local texture potential from removing a panel-sized offscreen layer. | Target 0%; require open/close, swipe-transition, fractional-scale and rounded-edge raster/input parity. |

| `services/NiriService.qml` | **HIGH-CONFIDENCE CPU/allocation candidate — reuse the already-sorted workspace projection on activation/urgency events.** `handleWorkspaceActivated()` and `handleWorkspaceUrgencyChanged()` rebuild `root.workspaces`, then call `Object.values(updatedWorkspaces).sort((a,b) => a.idx-b.idx)` even though those event types do not change workspace membership or `idx`. Build the same updated workspace objects/map, then project them through the existing `allWorkspaces` order; fold focused-index discovery into that pass. Keep full sort only for authoritative `WorkspacesChanged`/topology events. | Low–Medium. Must preserve stable equal-`idx` tie order, per-record object identity choices, malformed/missing workspace behavior, property-notify timing and current-output quirks. | None directly. | Low transient allocation reduction; persistent state unchanged. CPU gain scales with workspace-switch frequency and workspace count by removing an O(W log W) sort plus a temporary `Object.values` array on activation/urgency. | 0%. |

| `services/NiriService.qml` + AltSwitcher consumers | **ORACLE-REQUIRED CPU/allocation candidate — suppress provably no-op MRU republish on duplicate focus events.** `handleWindowFocusChanged()` always constructs and assigns a fresh `mruWindowIds` array for every non-null focus event. When the focused id is already first and has no duplicate later in the array, the value produced by the current filter+unshift algorithm is element-for-element identical, yet the fresh `var` assignment can notify `onMruWindowIdsChanged` consumers and trigger AltSwitcher snapshot rebuild work. Guard only this canonical no-op case; keep all window/workspace focus normalization and duplicate cleanup unchanged. | Medium until notification parity is proven. The value is identical, but current consumers can observe the change signal itself; repeated same-id focus events must not be an intentional refresh channel. | None. | Low transient allocation reduction plus avoided AltSwitcher rebuild allocation/CPU on duplicate focus events; persistent RAM unchanged. | 0%. |

| `services/CalendarSync.qml` + `modules/dashboard/DashAgenda.qml` + Waffle notification-center Calendar | **HIGH-CONFIDENCE CPU/allocation candidate — finish migration from per-day external-event scans to the existing batch bucket helper.** Current `CalendarSync._getEventBucketsForDates()` already preserves per-day inclusion semantics and is used by several 14/30-day consumers, but DashAgenda still calls `getEventsForDate()` once for each of 14 days and Waffle upcoming events does the same for 3 days. Build the identical ordered date list once, call the existing batch helper once, then keep all later filtering/cloning/sorting/caps unchanged. | Low. Must preserve RFC5545 exclusive-DTEND behavior, repeated appearance of multi-day all-day events in every matching day bucket, today/past filtering and output order. | None. | Low transient allocation reduction; persistent RAM unchanged. CPU gain removes repeated full external-event list scans/date parsing from these view rebuilds. | 0%. |
| `modules/sidebarRight/calendar/CalendarWidget.qml` + `modules/waffle/notificationCenter/CalendarWidget.qml` + `services/Events.qml` / `CalendarSync.qml` | **HIGH-CONFIDENCE local CPU candidate — build one bounded visible-date metadata snapshot instead of scanning both event lists twice per day cell.** Classic Sidebar materializes 42 cells; each count/color pair performs 2 local-list scans and 2 external-list scans. Waffle's shared CalendarView materializes 10 weeks × 7 days = 70 delegates, with the same query shape, so one full invalidation can drive up to 140 local and 140 external full-list scans before rendering dots/counts. Build exact local/external buckets once for the visible dates, then derive count/color metadata with O(1) cell lookup. | Low–Medium. Preserve local notified/all-day semantics, external multi-day inclusion, unique source-color encounter order, previous/current/next-month dates and the existing event/month invalidation boundary. | None. | Low bounded metadata RAM in exchange for large transient allocation/date-object reduction; persistent event storage unchanged. | 0%. |
| `scripts/scan-widgets.sh` | **HIGH-CONFIDENCE strict-lossless process candidate — remove three avoidable child processes per custom-widget manifest.** The scanner is already one bounded shell owner, but its loop executes external `dirname`, `basename` and `cat` for every `widget.json`. The glob shape makes directory/id extraction expressible with Bash parameter expansion, and Bash's `$(<file)` reads the manifest without spawning `cat`. Preserve the same unreadable-file `continue`, trailing-newline command-substitution behavior and JSON text. | Low. Oracle unusual paths, unreadable manifests and exact output bytes before changing the script. | None. | Low transient process-memory reduction. CPU/process gain is exactly up to 3 fewer child processes per discovered manifest while retaining the single scanner process. | 0%. |

| `services/LocalMusic.qml` | **RETIRED / IMPLEMENTED at `9376fa34f` (R16.1).** Current QML no longer declares or assigns `folderCollections`; keep this historical finding, but remove it from the pending implementation queue. The distinct backend/Python `folders` transport/schema candidate R16.2 is **still active**. **Historical R16.1 claim (not the current runtime state):** stop retaining dead `folderCollections` state in QML. At the original baseline, snapshot application stored `payload.tracks`, `payload.playlists` and `payload.folders`, but the live Songs browser derives folder navigation directly from `LocalMusic.libraryTracks`; current repository search finds no consumer of `LocalMusic.folderCollections`. Remove the property and assignment only, leaving native/Python snapshot shape unchanged. | Low. Re-run a dev-wide reference search and LocalMusic navigation/selection/playback oracle immediately before implementation. | None. | Medium potential for large libraries because the parsed `payload.folders` subtree duplicates track metadata by folder and can become collectible after snapshot application instead of being retained. Exact RSS needs measurement. | 0%. |
| `native/inir-mpdd/src/main.rs` + `scripts/local_music_mpd.py` | **COMPATIBILITY-GATED higher-value follow-up — stop constructing/serializing the duplicate `folders` snapshot field only if the stable MPD snapshot contract is intentionally revised or a lean mode is added.** Rust currently clones track objects into folder buckets; Python emits the equivalent second representation. The shell does not need it after the QML dead-retention cleanup, but current deep benchmark contracts explicitly include `folders` among stable snapshot fields. | Medium–High contract risk. Do not silently remove from only one backend or break native/Python parity/manual callers. | None. | Potentially medium transport/transient RAM reduction for large libraries; also removes folder grouping/cloning/serialization CPU. No credit until compatibility is resolved. | 0%. |

| `services/MinimizedWindows.qml` | **HIGH-CONFIDENCE CPU/allocation candidate — replace workspace filter+sort selection with stable one-pass extrema/nearest selection.** `stashWorkspaceForOutput()` filters eligible workspaces, sorts descending by `idx`, then returns element 0. `restoreWorkspace()` filters one output, sorts ascending, then either finds exact `idx` or reduces to the nearest. Both sorts are unnecessary if the one-pass selector reproduces current stable-sort tie behavior explicitly. | Low. Tie behavior is the proof boundary: descending stash selection keeps the first source-order workspace among equal max `idx`; restore exact-`idx` keeps first source-order duplicate; nearest fallback must prefer lower `idx` on equal distance because the current ascending stable sort presents it first. | None. | Low transient allocation reduction plus O(W log W) -> O(W) CPU on minimize/restore fallback paths; persistent RAM unchanged. | 0%. |
| `services/MinimizedWindows.qml` + `modules/waffle/bar/tasks/TaskAppButton.qml` | **HIGH-CONFIDENCE micro-candidate — count minimized windows without allocating a filtered ID array.** `countMinimizedForApp()` currently calls `getMinimizedForApp(appId).length`, allocating a temporary array. Waffle binds this count once per task-app delegate. Use a direct counter loop with the exact same case-insensitive substring predicate; keep `getMinimizedForApp()` for callers that actually need IDs. | Very low. Preserve null/error behavior for malformed app records and exact substring semantics. | None. | Low transient allocation/CPU reduction proportional to visible task-app delegates × minimized-state invalidations. | 0%. |
| `services/TrayService.qml` | **HIGH-CONFIDENCE CPU/allocation candidate — promote the archived one-pass tray partition into the canonical ledger.** The service independently filters `SystemTray.items.values` three times for Fcitx, pinned-user-list and unpinned-user-list outputs, repeating Fcitx normalization and linear pin membership tests. One ordered pass plus a membership Set can produce the same three arrays. | Low. Preserve source order, passive filtering asymmetry, raw-id equality, duplicate pin semantics and final invertPins composition. | None. | Low transient allocation/CPU reduction on tray source/status/pin invalidation; persistent RAM essentially unchanged. | 0%. |
| `modules/bar/SysTray.qml` | **HIGH-CONFIDENCE separate Material-tray candidate — collapse three local SystemTray scans into one private partition snapshot.** Material does not simply consume `TrayService` outputs: it uses `bar.tray` config and has a Spotify exception that keeps passive Spotify visible. It currently performs its own Fcitx filter plus pinned/unpinned filters over the same source list. Build one local partition preserving the Material-specific pin namespace and Spotify rule rather than incorrectly reusing the generic/Waffle result. | Low–Medium. The Spotify passive exception, Fcitx ownership, bar-specific pin list, invertPins and overflow-close behavior are hard contracts. | None. | Low transient allocation/CPU reduction on every Material tray invalidation; avoids repeated lowercase/classification work. | 0%. |

| `services/Network.qml` | **HIGH-CONFIDENCE process candidate — remove shell/head/awk wrappers from connected-network detail refresh while preserving current row-order semantics.** Network is already event-driven via `nmcli monitor` + 200 ms debounce, but active-link detail refresh still runs `sh -c "nmcli ... | head -1"` for connection name and `sh -c "nmcli ... | awk ..."` for Wi-Fi signal. Run the same two `nmcli` queries directly and move the trivial text selection into QML. | Low–Medium. Name must remain first active-connection line. Signal parser must reproduce the current awk+SplitParser semantics: every row beginning `*` is emitted in source order and the **last emitted active row wins** if more than one appears. Preserve failure/stale-clear behavior and do not alter the monitor cadence. | None. | Low transient process-memory reduction; up to **4 intermediary child processes removed per connected-Wi-Fi detail refresh** (two shells + `head` + `awk`) while the two required nmcli queries remain. | 0%. |

| `services/AppSearch.qml` + all `resolveWindowIdentity()` consumers | **HIGH-CONFIDENCE CPU/allocation candidate — invalidate compiled identity rules on the narrow config signal instead of serializing the entire rule list for every window lookup.** `_parseIdentityRules()` currently computes `JSON.stringify(Config.options.windows.appIdentityRules)` on every call, even cache hits. `resolveWindowIdentity()` is invoked inside Taskbar, Dock, Bar preview, both AltSwitchers and Waffle Task View collection passes. Keep the compiled rule array resident and rebuild on initial use/Config-ready plus `appIdentityRulesChanged`. | Low–Medium. Must preserve first-match ordering, malformed-rule skip behavior, nested JsonObject replacement/reload handling and lazy desktop-entry resolution. | None. | Low transient allocation + CPU reduction multiplied by window count × number of consumers; persistent RAM unchanged except the already-retained compiled rules. | 0%. |
| `modules/bar/BarTaskbar.qml` | **HIGH-CONFIDENCE CPU candidate — precompute first-occurrence pinned rank once per rebuild.** In separate-pinned mode the running-app sort comparator performs `pinnedApps.findIndex(...)` for both operands on every comparison, then publication performs another `pinnedApps.some(...)` per running group. Build one lowercase rank Map that preserves the **first** case-insensitive occurrence, use it for comparator rank and membership, and keep the current alphabetical fallback for unpinned apps. | Low. Duplicate/case-variant pins are the key oracle: naïve Map overwrite would retain the last rank and change order. | None. | Low CPU/allocation reduction; removes repeated O(P) scans from O(R log R) comparisons and final O(R·P) membership checks. | 0%. |
| `services/TaskbarApps.qml` | **STRICT-LOSSLESS companion cleanup — remove the dead `_identityRulesRevision` read/counter after AppSearch owns rule invalidation.** The revision is incremented on `appIdentityRulesChanged` and read into a local inside imperative `computeApps()`, but the value is never consumed; the same handler already restarts the refresh timer. | Very low. Keep the actual refresh restart and AppSearch invalidation intact. | None. | Negligible standalone; removes dead state/read and avoids presenting it as a required dependency token. | 0%. |

| `services/GameMode.qml` + fullscreen consumers | **HIGH-CONFIDENCE CPU candidate — derive fullscreen state once per Niri snapshot and answer per-output queries from a cached snapshot.** Current `hasAnyFullscreenWindow`, `hasVisibleFullscreenWindow` and `hasFullscreenOnOutput()` independently rescan `NiriService.windows`, and `hasFullscreenOnOutput()` is consumed by many simultaneously resident Bar/ScreenEdge/Background/Sidebar/Abyss/WidgetPowerManager paths. Build one derived `{any, visible, activeOutputs}` snapshot from the same windows/workspaces/output semantics and make reads O(1). | Low–Medium. Preserve the current distinction where “any fullscreen” may use the single-output fallback even when workspace metadata is temporarily missing, while visible/per-output queries require a resolved active workspace. | None. | Low transient allocation + potentially meaningful CPU reduction on window/workspace/layout publications: O(C·N) repeated scans -> one O(N) derivation + O(1) consumer reads. | 0%. |
| `services/DesktopItems.qml` + `modules/background/Background.qml` | **HIGH-CONFIDENCE RAM/allocation candidate — publish one read-only cloned item-list snapshot per items revision instead of cloning the complete item set once per output.** `DesktopItems.listItems()` clones every item into a fresh array; Background calls it from each output's desktop-item model and then filters by output. With M outputs and I items, one revision can allocate roughly M·I cloned records before filtering. Maintain a shared presentation snapshot rebuilt only when `items` changes and let Background perform only the per-output filter. | Low–Medium. Must preserve item order, invalid-record hiding, stale-output/focused-output fallback and the defensive-copy contract for callers that still require mutable results. | None. | Low–Medium transient RAM/allocation reduction on multi-output desktops; persistent RAM adds one bounded shared read snapshot but removes repeated per-output clones. | 0%. |

| `services/NiriService.qml` | **HIGH-CONFIDENCE CPU/allocation candidate — maintain a private layout-sorted window view and stop re-running `sortWindowsByLayout(windows)` inside every `sortToplevels()` call.** Public `windows` is already layout-sorted on normal window publication and output-geometry changes, but workspace topology changes can alter sort keys without reassigning `windows`; that is why a naïve direct iteration is not strict-lossless. Refresh a private sorted view on every actual sort-key source change and keep public signal counts unchanged. | Low–Medium. Must preserve `windowsChanged` / `windowOrderChanged` counts, workspace idx/output topology effects and output geometry order. | None. | Low transient allocation + CPU reduction: removes one repeated map→sort→map preparation per compositor toplevel sort pass. | 0%. |
| `modules/common/widgets/SettingsSearchRegistry.qml` | **HIGH-CONFIDENCE CPU/allocation candidate — pre-normalize immutable search fields at registration.** `registerOption()` already snapshots label/description/page/section/keywords, but every keystroke lowercases/join-normalizes all of them again for every live entry. Store private normalized fields beside the existing raw fields once per registration and keep scoring/order unchanged. | Low. Registry lifecycle/re-registration and translated text-at-registration semantics must remain identical. | None. | Low transient allocation + CPU reduction proportional to registry size × keystrokes. | 0%. |
| `modules/common/widgets/SettingsSearchRegistry.qml` | **HIGH-CONFIDENCE CPU/allocation candidate — generate highlight markup only after score/sort/top-50 selection.** Current search creates highlighted label/description strings for every match before sorting, then discards everything after the first 50. Highlight markup does not influence score or ordering, so retain raw text + matched terms through ranking and call the same highlighter only for the selected top 50. | Low. Preserve exact matched-term order, overlap markup, scores, tie order and every returned field. | None. | Low–Medium transient string/allocation reduction for broad queries with >50 matches. | 0%. |
| `modules/settings/ThemesConfig.qml` | **HIGH-CONFIDENCE process candidate — collapse saved-theme polling fan-out to one Bash + one jq per poll.** While the custom-theme editor is expanded, the 2 s poll starts one Bash and then one external `basename` plus one `jq` per saved JSON file. Derive basename with shell parameter expansion and invoke one jq over the ordered file list while preserving one compact output object per input file. | Low–Medium. Preserve glob order, invalid-file warning/skip behavior, filenames with spaces/dots and same model reset/publication timing. | None. | Low transient RAM/CPU process reduction. Per poll, process count changes from roughly `1 + 2T` to `2` for T saved themes. | 0%. |

| `services/WorldClock.qml` | **HIGH-CONFIDENCE lifecycle/RAM candidate — lazy-materialize the full timezone picker catalog only when a picker needs it.** Runtime clock rendering needs only configured timezones/offsets/entries, but WorldClock eagerly builds the complete IANA timezone list plus a second `{label,tz,icon}` combo model whenever the singleton materializes. Current consumers of the full catalog are picker/editor surfaces only. | Low–Medium. Picker must still have the complete model on its first visible frame; preserve Intl fallback, labels and selected-timezone behavior. | None. | Low–Medium persistent/transient RAM reduction for sessions that display World Clock without opening timezone editors; avoids full catalog label construction. | 0%. |
| `modules/sidebarLeft/LocalMusicView.qml` | **HIGH-CONFIDENCE CPU candidate — prepare exact lowercase search haystacks once per active search session.** Current `filteredTracks` lowercases title/artist/album/folder and concatenates a haystack for every track on every query edit. Build `[{track, searchText}]` lazily when query becomes non-empty, reuse while `libraryTracks` identity is unchanged, invalidate on library change and release when query clears. | Low. Preserve exact String/null fallback, spacing, substring semantics, result identity/order and immediate updates on library rescans. | None. | Low bounded transient RAM while search is active in exchange for materially lower per-keystroke CPU/string allocation on large libraries. | 0%. |
| `services/NiriService.qml` + classic/Waffle Background | **HIGH-CONFIDENCE CPU candidate — centralize active-workspace occupancy instead of recomputing it per output/family.** Classic and Waffle backgrounds independently materialize `Object.values(workspaces)`, find the active workspace for an output, then scan all Niri windows for occupancy. Derive `activeWorkspaceIdByOutput` and `occupiedWorkspaceIds` once from authoritative Niri snapshots and expose a reactive O(1) helper/map. | Low–Medium. Preserve non-Niri/unknown-output/no-active-workspace false behavior and exact invalidation on window/workspace topology changes. | None. | Low transient allocation + CPU reduction: repeated O(M·(W+N)) background scans become shared O(W+N) derivation plus O(1) per-output reads. | 0%. |
| `modules/background/Background.qml` | **HIGH-CONFIDENCE Hyprland CPU/allocation candidate — replace `relevantWindows.filter(...).sort(...)` plus later `some()` with one summary pass.** The sorted array is only used for min workspace id, max workspace id and current-workspace occupancy. Derive `{first,last,hasCurrent}` directly in one scan while preserving the existing falsy-id fallback semantics. | Low. Workspace id 0 is currently permitted by the filter but then treated as falsy by `|| 1/10`; preserve that quirk rather than “fixing” it here. | None. | Low transient allocation + CPU reduction: remove one filtered array, O(N log N) sort and later O(N) occupancy scan per relevant update/output. | 0%. |
| `modules/background/Background.qml` + `modules/screenCorners/ScreenCorners.qml` | **HIGH-CONFIDENCE secondary Hyprland candidate — replace nested fullscreen `filter().filter()[0]` allocations with one `find/some` pass.** Both paths only ask whether this monitor's active workspace contains a fullscreen Wayland window. | Low. Preserve loose monitor-name equality, active-workspace requirement, Wayland-only fullscreen detection and false/undefined behavior when data is absent. | None. | Low transient allocation/CPU reduction on Hyprland workspace/toplevel updates. | 0%. |

| `services/AppSearch.qml` | **HIGH-CONFIDENCE CPU/allocation candidate — memoize final `lookupDesktopEntry(appId)` hit/miss per DesktopEntries epoch.** The helper already has reverse maps, but every call restarts heuristic lookup, normalization candidates, suffix stripping and potentially token-overlap scans. Many Taskbar/Dock/AltSwitcher/settings/media paths ask for the same ids repeatedly. Cache exact-input `DesktopEntry|null`, distinguish cached miss, and invalidate immediately on DesktopEntries change. | Low–Medium. Immediate invalidation must occur before the existing 500 ms reverse-map rebuild so a newly installed/removed desktop entry is observable with today's timing. | None. | Low transient allocation + potentially meaningful CPU reduction for repeated misses/unusual Electron/AppImage ids. Small bounded memo RAM. | 0%. |
| `services/MprisController.qml` | **HIGH-CONFIDENCE CPU/allocation candidate — memoize the final MPRIS-specific `_desktopEntryForHint()` result after AppSearch fallback.** Direct AppSearch misses currently fall into a full DesktopEntries fuzzy scan/tokenization path, and the same cleaned hint can be resolved repeatedly by player/stream display-name/icon helpers. Cache final `DesktopEntry|null` by exact cleaned hint and invalidate immediately on DesktopEntries changes. | Low–Medium. Preserve every score/tie/threshold rule and direct-AppSearch precedence. | None. | Low transient allocation + CPU reduction, especially for repeated hints that miss AppSearch and enter the catalog-wide fallback. | 0%. |
| `services/Notifications.qml` + `modules/dock/DockAppButton.qml` | **HIGH-CONFIDENCE CPU candidate — derive normalized notification-badge lookup once per popup-group rebuild.** Each Dock button currently normalizes caller ids, then scans all popup groups and normalizes every group app name. Build a private normalized key→{first-rank,count} index alongside `_cachedPopupGroupsByAppName`, preserving the current “first group in object order matching any caller id wins” semantics. | Low. Do not sum collisions or let caller-identifier order replace current popup-group order. | None. | Low CPU/allocation reduction scaling from roughly D×G normalized group scans to small per-button key lookups after each group snapshot rebuild. | 0%. |

| `services/Notifications.qml` | **HIGH-CONFIDENCE CPU candidate — reuse notification objects already owned by timeout/read callers instead of re-looking them up by ID.** `timeoutNotification()` does one `findIndex` then calls `cancelTimeout(id)`, which scans again; `timeoutAll()` already iterates `popupList` objects but calls the ID helper for each; `markReadForApp()` already has each matching object but triggers another list scan. Add a private object-based timer cancel helper and keep the public ID helper for external callers. | Very low. Preserve timer stop/destroy/null, timeout signal count/order, popup mutation phase ordering and final `triggerListChange()`. | None. | Low transient allocation/CPU reduction; removes P×N lookup work from timeout-all/read-heavy histories. | 0%. |
| `services/Weather.qml` | **HIGH-CONFIDENCE process candidate — execute primary wttr.in curl directly instead of through Bash.** The primary request constructs one URL and runs `bash -c "curl ..."`; no shell feature is required, while fallback/AQI paths already use direct curl argv. | Very low. Preserve URL construction, query encoding, request-generation ownership, retry/failover counters and empty/error parsing. | None. | Low transient RAM/CPU; exactly one fewer Bash process per primary weather request/retry. | 0%. |
| `services/ScreenTime.qml` | **HIGH-CONFIDENCE startup process candidate — use the already-owned `todayFileView` for the startup day read instead of `bash -c 'test -f && cat || echo'`.** The service already persists today's file through FileView. Route startup `Loaded` / `FileNotFound` into the existing `_finishStartupRead()` contract while retaining all other failure behavior. | Low–Medium. FileView error/timing parity, reentrancy and startup-before-first-write assumptions must be covered. Do not replace the batched history range reader. | None. | Low transient process-memory/CPU; removes one Bash plus cat/test pipeline on ScreenTime initialization. | 0%. |
| `modules/regionSelector/RegionSelection.qml` | **HIGH-CONFIDENCE process/quoting candidate — remove avoidable outer `bash -c` layers for recording and content-region detection.** Recorder start can exec `record.sh --region <region> [--sound]` directly; content-region detection can invoke `bash find-regions-venv.sh --image ...` as interpreter+script argv, retaining one required Bash for the wrapper but removing the extra command-string parser. | Low. Preserve exact region/image argv, wrapper startup failure, RecorderStatus quick-check timing and current detached-process behavior. Do not touch screenshot/copy/OCR/search/edit branches that use real shell composition. | None. | Low transient process/CPU reduction on explicit region actions; removes one shell from recorder start and one extra `-c` shell layer from region detection. | 0%. |
| MPRIS position-refresh producers across Bar / media controls / Sidebar / Lock / Waffle / VolumeMixer | **MEASURE THEN ADAPT — share one demand-leased position ticker per player identity instead of independent surface timers.** Current source still has ten `positionChanged()` occurrences: nine producer-style timers plus LyricsService listener. Producers request 500 ms, 1 s or configured ~3 s cadences and can target the same `MprisPlayer`. A per-player lease owner can run at the minimum requested interval while any consumer is active. | Medium–High timing risk. Raw `positionChanged()` signal phase/count is observable and `triggeredOnStart` semantics matter. Requires trace/oracle before promotion to strict-lossless. | None directly. | Potentially meaningful wakeup/CPU reduction when multiple media surfaces for the same player coexist; RAM negligible. | Expected pixels 0%; event timing changes unless explicitly normalized. |

| Cloudflare WARP quick toggles (common/Waffle + Classic + Android) | **HIGH-CONFIDENCE process candidate — execute `warp-cli status` directly instead of `/bin/sh -c`.** All three implementations use a fixed executable path and no shell syntax, yet every 5 s status refresh while the relevant surface is open forks an intermediate shell. | Very low. Preserve status parsing, availability/daemon/toggled state, panel-open gating and action-triggered refresh timing. | None. | Low transient RAM/CPU; one fewer shell process per status refresh per live toggle instance. | 0%. |
| `services/Hyprsunset.qml` | **HIGH-CONFIDENCE low-frequency process candidate — execute `hyprctl hyprsunset temperature` directly.** The probe uses Bash only for argv tokenization; timeout, stdout, state publication and pending-toggle control already live in QML. | Very low. Preserve PATH/spawn-failure, 5 s timeout, empty/error/6500 parsing and pending action state. | None. | Low transient RAM/CPU; one fewer Bash process per Hyprsunset state probe. | 0%. |
| `services/ResourceUsage.qml` | **HIGH-CONFIDENCE companion candidate — remove Bash from recurring NVIDIA/Intel process-backed GPU samples.** NVIDIA can run `nvidia-smi` directly and select the first non-empty row in QML; Intel can run `/usr/bin/timeout 1 intel_gpu_top -J -s 500` directly. Preserve stderr suppression, first-GPU ownership, timeout and existing parser semantics. | Low–Medium. Multi-GPU first-row behavior and malformed/timeout/error cases are the key oracle. | None. | Low transient process-memory/CPU; one shell removed per expensive GPU sample that remains after metric-demand gating. | 0%. |
| `modules/settings/InterfaceConfig.qml` | **HIGH-CONFIDENCE process candidate — collapse Settings World Clock preview from one Bash + N external `date` children to one Bash.** Current 20 s visible-section refresh invokes `date` once per configured timezone. Sibling WorldClock implementations already pass timezones as argv and use Bash builtin `printf '%(...)T'`. Preserve cadence, namespace and `timezone|time|offset` protocol. | Low–Medium. Valid IANA zones are straightforward; malformed shell-significant timezone strings require an explicit safe-argv contract decision rather than preserving accidental shell parsing. | None. | Low transient RAM/CPU; removes N external processes per preview refresh for N configured zones. | 0%. |
| `modules/sidebarLeft/widgets/WorldClockWidget.qml` | **HIGH-POTENTIAL / ORACLE-GATED — separate sparse timezone metadata refresh from in-process display ticking.** The visible sidebar clock currently starts one Bash every 30 s, or every second when seconds are enabled, to obtain time/offset/date/day-of-year/hour data. Reuse sparse offset metadata and advance display time locally; align minute-only updates to boundaries. | Medium–High temporal/locale risk until deterministic old-vs-new oracle exists. DST, quarter-hour zones, midnight/year rollover, clock jumps and locale formatting must match. | None. | Potentially meaningful process/wakeup reduction while the sidebar clock is visible; seconds mode can eliminate nearly one shell spawn per second. | Expected pixels 0%; time-format/event semantics must be proven. |

| Direct media-art `Image` / `StyledImage` paths in media presets, Waffle Action Center/Widgets/Lock and VolumeMixer | **HIGH-CONFIDENCE RAM/GPU candidate within the <1% visual budget — bound decode size to conservative presentation resolution instead of decoding arbitrary original cover dimensions.** Hadalis already uses a 2× presentation-size `sourceSize` policy in `MediaCrossSlideImage.qml`, but several direct cover-art paths still have no sourceSize and use `cache:false`. Start with small foreground slots (48/96/104/108 px) at a 2× or DPR-proven bound; separately tune card-sized blurred sources with enough oversampling to preserve blur/filtering. | Medium. This is not exact pixel-lossless by assumption: source downscaling can change filtering/blur slightly. Require <1% global/edge-detail error at 1.0/1.25/1.5/2.0 DPR plus visual sharpness review. | Low–Medium GPU/texture residency reduction when large covers are shown on several surfaces; may also reduce upload/decode pressure. | Potentially medium steady image RAM for large source artwork; illustrative 2000×2000 RGBA is ~16 MB versus ~0.18 MB for a 216×216 2× decode target, before backend-specific overhead. | <1% measured visual budget; reject or raise decode target if exceeded. |

| `services/Wallpapers.qml` | **HIGH-CONFIDENCE JS allocation candidate — mutate private thumbnail pending/known maps in place instead of cloning the complete map on every insert/delete.** Current `_singleThumbPending` and `_knownThumbnailOutputs` are private imperative sets; repository-wide search finds no binding, change handler or external consumer of their property identity. Enqueue/drain/remember/forget currently copy all keys with `Object.assign`. Preserve membership answers and queue order while mutating the private objects directly. | Very low. Final proof is that no `...Changed` signal is used as a wakeup and repeated/distinct key behavior is identical. | None. | Low–Medium transient JS allocation/GC reduction when browsing large wallpaper sets; avoids quadratic-ish cumulative key copying while filling/draining private sets. | 0%. |
| `scripts/thumbnails/thumbgen.py` + `services/Wallpapers.qml` + `ThumbnailImage.qml` | **HIGH-CONFIDENCE protocol candidate — publish per-file READY/FAILED from the batch generator so delegates can skip post-batch `test -f` child processes.** Generation is already centralized, but each `ThumbnailImage` may still spawn its own existence check. Extend machine progress so Python reports whether the expected output actually exists after each result; only READY enters the shared known-thumbnail set. | Low–Medium. Current `PROGRESS ... FILE` token is not a success signal; fresh-cache and failure can both return false. Preserve retry/fallback behavior and do not mark failed outputs known. | None. | Low transient process-memory/CPU; can remove one per-delegate `test -f` process after successful/fresh batch work across large galleries. | 0%. |
| `services/Wallpapers.qml` | **HIGH-CONFIDENCE tiny session-RAM cleanup — clear `_ffPending[videoPath]` after successful first-frame cache publication.** Success already stores `videoFirstFrames[videoPath]`, so the stale pending key no longer influences behavior because success cache wins first. Failure-side deletion is intentionally excluded because it would change current no-retry-for-session behavior. | Very low for success path. Do not alter failure semantics without a separate correctness/backoff decision. | None. | Low cumulative JS map reduction for sessions visiting many distinct video wallpapers. | 0%. |
| `services/Wallhaven.qml` | **HIGH-CONFIDENCE JS allocation candidate — mutate private bounded tag caches/order lists in place.** The 64/256-entry suggestion/count/tag caches currently clone the whole cache object and key-order array on every insertion/update/eviction. Repository search shows the structures are private and read imperatively. Preserve exact first-occurrence removal, append-newest ordering, TTL and eviction semantics. | Very low. Verify no property-change signal consumer and exact LRU order for same-key refresh/past-limit eviction. | None. | Low–Medium transient JS allocation/GC reduction during tag enrichment; avoids O(K) copies per insert and O(K²) cumulative filling work at K up to 256. | 0%. |
| `modules/background/Background.qml` | **HIGH-CONFIDENCE low-priority companion — mutate the private 64-entry wallpaper-size LRU in place.** `cacheWallpaperSize()` clones cache + key list for every successful `magick identify`; repository search finds no external/binding consumer of their identities. | Very low. Preserve lookup answers and exact LRU ordering/eviction. | None. | Low transient JS allocation reduction; smaller leverage than Wallhaven because writes are sparse and limit is 64. | 0%. |
| `services/CompositorService.qml` + `services/NiriService.qml` | **MEASURE / PROVE FIRST — focus-only enriched-toplevel refresh.** Niri `onActiveWindowChanged` currently schedules the same full `sortToplevels()` matching path as structural window-order changes. A pure focus change should only flip `activated` in the already matched ordered array, but Quickshell may also emit `ToplevelManager.valuesChanged` on focus transitions. Instrument trigger coalescing first; only add a focus-only fast path when no structural full sort is pending. | Medium due undocumented external signal behavior. Never let the fast path supersede a pending structural sort or membership/title/app/workspace change. | None. | Potential low–medium CPU/allocation reduction on frequent focus switching if active-window events commonly arrive without foreign-toplevel structural changes. | 0% visual; event/update timing must remain equivalent. |

| `services/AppCatalog.qml` | **HIGH-CONFIDENCE CPU/allocation candidate — pre-normalize immutable catalog search metadata once when the JSON catalog loads.** Current `filteredCatalog` lowercases name/description and every tag for every catalog entry on every search-query edit. Store private normalized name/description/tag text alongside the loaded records (or in a parallel search index), then keep the exact current substring predicate and original result objects/order. | Low. Preserve null/default behavior, category-first filtering, tag semantics and exact original object identity returned to delegates. | None. | Low–Medium transient string/allocation and CPU reduction proportional to catalog size × keystrokes. | 0%. |
| `services/AppCatalog.qml` + `modules/sidebarLeft/SoftwareView.qml` | **HIGH-CONFIDENCE reactive CPU candidate — remove the dummy `installedPackages` dependency from `filteredCatalog`.** The binding reads `const _installed = root.installedPackages` but never uses it to include/exclude/order apps. Install status is independently bound per `AppCard` through `AppCatalog.isInstalled(app.id)`, which reads the authoritative map. Installed-status refresh therefore does not need to rebuild the whole filtered model/Repeater. | Low–Medium. Prove QML dependency capture through `isInstalled()` updates every badge/action without a model reset; preserve list identity/order and empty-state behavior. | None. | Low CPU/allocation and delegate churn reduction after package-status refresh/install/remove checks. | 0%. |

| `modules/waffle/startMenu/AllAppsContent.qml` | **HIGH-CONFIDENCE interactive CPU/allocation candidate — split alphabetically sorted app snapshot from per-keystroke filtering/grouping.** Current `groupedApps` starts from `DesktopEntries.applications.values`, filters, then sorts all matches by name on every `filterText` edit; `flatApps` then flattens the groups again solely for Enter-to-activate. Maintain one sorted visible-app base projection per DesktopEntries revision, filter that ordered snapshot per query, group without re-sorting, and let `flatApps` reuse the filtered array. | Low. Preserve immediate DesktopEntries update timing, noDisplay filtering, exact localeCompare order/stability, section lettering and original DesktopEntry object identity. Do not silently switch to AppSearch.list unless its 500 ms rebuild debounce is explicitly accepted. | None. | Low–Medium transient array/sort/string CPU reduction on interactive filtering; removes O(A log A) sort from every keystroke and one flatten pass. | 0%. |
| Material + Waffle Autostart settings (`AutostartConfig.qml`, `WAutostartPage.qml`) | **HIGH-CONFIDENCE CPU candidate — replace filter+sort comparator status scans with one stable enabled/disabled partition.** Both pages start from already alphabetically sorted `AppSearch.list`, filter by name/genericName, then sort again by `Autostart.isAppOn()` first and name second. `isAppOn()` scans managed entries and, on miss, external spawn lines; the comparator can call it repeatedly O(A log A) times. In one pass, test each filtered app once and append to enabled/disabled arrays; concatenate them to preserve enabled-first + alphabetical-within-group order. | Low. Depends on AppSearch's documented/name-sorted list; verify duplicate equal-name stability and all external-spawn matching semantics. | None. | Low–Medium CPU reduction in Settings search/rebuilds; changes repeated status scans + sort into one status evaluation per app and O(A) stable partition. | 0%. |

| `services/Autostart.qml` + both Autostart settings pages | **HIGH-CONFIDENCE CPU candidate — derive exact managed/external app membership indexes when parsed state changes, making `isAppEnabled()`, `isAppExternal()`, `isAppOn()` and `appEntrySource()` O(1).** Current helpers rescan managed entries and external spawn lines for every app-row/status query. Build exact-semantics indexes from `entries` and `externalLines`, preserving first managed duplicate ownership, enabled-only external lines and current gtk-launch/raw-executable normalization. | Low–Medium. Duplicate managed ids, case sensitivity and external token normalization are strict contracts; indexes must rebuild after every entries/externalLines mutation, not only file reload. | None. | Low–Medium CPU reduction across Material/Waffle Autostart filtering and per-row bindings; small bounded index RAM proportional to startup directives. | 0%. |
| `modules/settings/DockConfig.qml` | **HIGH-CONFIDENCE interactive CPU/allocation candidate — prepare the Add Applications search projection when AppSearch/pinned state changes instead of rebuilding haystacks + alphabetic sort on every query edit.** Current `filteredAddApps()` rebuilds a lowercase pinned Set, joins/lowercases name+genericName+comment+id for every app, then sorts the result for every search binding evaluation. Build a private unpinned prepared list once per AppSearch/pinned revision with original app reference + lowercase haystack, sorted with the exact current comparator; query edits then only filter it. | Low. Preserve fallback name/id ordering, pinned-id case folding, original app identity, and immediate updates when pins/AppSearch change. | None. | Low–Medium transient string/array/sort CPU reduction while searching the add-app dialog. | 0%. |

| `services/ShellLayoutController.qml` | **HIGH-CONFIDENCE CPU/allocation candidate — keep public descriptor copies but stop JSON deep-cloning static descriptors inside private controller paths.** `_descriptors` is a readonly literal, yet `currentState()`, `legalSlots()`, `validatePlacement()`, `setProperty()` and `resetSurface()` reach it through `descriptor()`, which serializes/parses a fresh copy even though those paths only read descriptor fields. Add a private first-match descriptor reference helper for internal read-only use; retain `descriptor()` / `surfacesForFamily()` fresh-copy semantics and the fresh `legalSlots()` array returned to callers. | Very low. Public mutation isolation, unknown-surface behavior, family filtering/order and fresh returned arrays/objects must remain identical. | None. | Low transient JS allocation/GC reduction; no persistent-state reduction claimed. | 0%. |
| `services/DesktopWidgetLayout.qml` | **HIGH-CONFIDENCE CPU/allocation candidate — prepare read-side output/screen indexes at their revision boundaries.** Every `enabled()` call currently rebuilds configured + connected monitor arrays in `outputAllowed()`, then linearly scans `records` through `widgetOverride()`; `effectiveEnabled()` additionally deep-normalizes/clones all records merely to recover saved output names. Keep mutation-time `_normalizedRecords()`, but derive first-record-by-output, ordered unique saved-output names and configured/connected membership once per relevant Config/screens revision for the read path. | Low–Medium. Duplicate-output first-match semantics, trimmed record output names, untrimmed configured names, stale/disconnected fallback behavior, hotplug reactivity and original override-object identity are strict contracts. | None. | Low transient array/deep-clone reduction, with a tiny bounded retained index proportional to outputs. | 0%. |
| `services/DateTime.qml` | **HIGH-CONFIDENCE CPU micro-candidate — decouple date-only locale formatting from second/minute clock precision.** `shortDate`, `date` and `collapsedCalendarFormat` all bind directly to `clock.date`; when second precision is enabled or the screen is locked, the shared clock advances every second even though these three strings normally change only when the calendar day/format/locale changes. Guard those three conversions behind an exact day/format/locale key while leaving `time`, `timeDisplay` and minute-based uptime refresh untouched. | Low–Medium. Must preserve midnight rollover, manual wall-clock/date jumps, timezone/locale changes and live date-format config changes at the same observable tick. | None. | Negligible persistent RAM; low recurring CPU/string-allocation reduction, larger only while the shared clock is at 1 Hz. | 0%. |

| `services/ShellUpdates.qml` + `setup` | **HIGH-CONFIDENCE update-time process candidate — keep the current 2 s progress cadence but stop spawning `cat` for every status read.** While an update is active, `updateProgressPoller` launches `updateProgressReader` every 2000 ms; that Process is only `cat update-status`. The watchdog owns a second one-shot `cat` reader. The service already owns a blocking `FileView` for the same status file. Reuse a FileView reload/text path and a shared parser while retaining the 2 s timer and 120 s watchdog. Do **not** replace this first with pure `watchChanges`: `setup` writes markers with shell redirection (`printf > file`), so a watcher may observe the truncate/write intermediate state. | Low. Preserve exact progress/failure parsing, two-second presentation cadence, watchdog extension/stuck detection, shell-restart resume and missing-file behavior. Keep the boot-staleness Bash probe because it also compares mtime with boot epoch. | None. | Low transient process-memory/CPU reduction during updates; removes one child process every 2 s plus watchdog `cat` reads. | 0%. |
| `modules/waffle/taskview/WaffleTaskViewContent.qml` | **HIGH-CONFIDENCE interactive CPU/allocation candidate — group windows by workspace once per cache refresh and retain a private per-slot projection.** `refreshCache()` currently filters the complete `NiriService.windows` array once for every visible workspace, then sorts each subset. `previewCounts` independently filters the full flattened cache once per workspace on drag updates, and keyboard helpers filter the flat cache again per navigation call. Build a workspace-id→slot map, distribute windows in one pass, keep each slot's exact existing column sort, and publish both the existing flat cache and an internal per-slot view/count snapshot. | Low–Medium. Preserve current-output exclusion, missing-position fallback to column 0, stable equal-column order, flat result order/fields, drag exclusion/+1 target semantics and fresh-array behavior where callers may mutate results. | None. | Low–Medium transient array/CPU reduction while Task View is open; changes repeated O(W×N) scans into O(W+N) grouping plus the same per-workspace sorts. | 0%. |
| `services/NiriService.qml` + published-window ID consumers | **HIGH-CONFIDENCE CPU candidate — derive a first-match window-id index from the published `windows` snapshot.** Several consumers repeatedly call `NiriService.windows.find(w => w.id === id)`; Waffle `TaskAppButton` does that inside a loop over an app's toplevels, and `MinimizedWindows` performs ID finds in restore/visibility paths. Maintain a small id→window lookup whenever public `windows` changes, preserving Array.find's **first duplicate wins** behavior, and let only consumers of the published snapshot use it. | Low–Medium. Duplicate/missing IDs and exact object identity are contracts. NiriService handlers that intentionally operate on `_pendingWindows` / the freshest unpublished list must keep their current scans or own a separate proven index. | None. | Tiny bounded Map/object RAM cost in exchange for lower repeated lookup CPU; no RAM-saving claim. | 0%. |
| `services/AquaMind.qml` | **HIGH-CONFIDENCE micro-candidate — select the next eligible proactive reminder in one stable pass instead of materializing and sorting all reminder rows every minute.** `offerAutomatic()` calls `reminderRows()`, which copies journal schedule rows, appends bounded Todo/calendar rows, sorts the whole array by start minute, then immediately `find()`s the first unreminded item in the ±10-minute window. For the automatic path only, scan sources in today's existing source order and retain the earliest eligible item; on equal start minute keep the first encountered row to match stable-sort + find semantics. Keep `reminderRows()` itself for any direct callers/tests. | Low. Source ordering, invalid-time rejection, Todo/calendar bounds, reminder-key construction, stable equal-time tie behavior and the existing Obsidian context-refresh-before-reminder ordering must remain exact. | None. | Low transient JS allocation/CPU reduction on the one-minute proactive cadence; intentionally low priority. | 0%. |
| `modules/abyss/companion/OctoTentacles.qml` + `WaterDropletBody.qml` + `AquaPresence.qml` | **MEASURE FIRST — new companion render/state-machine paths are not source-only optimization candidates yet.** Octo now owns one liquid ShaderEffect per tentacle. Aqua's floor reflection is already a bounded 76×82 `ShaderEffectSource`, only live while visible, grounded and detailed effects are enabled. Presence timers inspected in this pass are bounded one-shot deadlines, not recurring idle polls. Profile GPU/frame cost and capture current Aqua/Octo A/B fixtures before changing shader fidelity, tentacle count, reflection behavior or state timing. | High if optimized by assumption. These are highly visible character/motion contracts and were concurrently changed in the current dev sequence. | Unknown until measured. | Low/unknown. | No promoted visual substitution; any later renderer candidate needs a deterministic <1% A/B oracle. |

| `services/TaskbarApps.qml` | **HIGH-CONFIDENCE CPU/allocation candidate — compile ignored-app regexes only when the ignored pattern list changes.** `computeApps()` runs behind a 16 ms coalescing timer and is retriggered by compositor/toplevel/AppSearch/config events, yet every run rebuilds the fixed system-pattern array, copies user patterns and constructs every `RegExp` again. Keep the compiled list resident and rebuild it on initial demand plus the existing `ignoredAppRegexesChanged`/config-replacement boundary. | Low. Preserve `_stringArray()` normalization, user-before-system pattern order, case-insensitive flags and the current `_compileRegexes()` behavior that logs/skips invalid regexes. Config reload/object replacement must not leave stale patterns. | None. | Low transient JS allocation/CPU reduction multiplied by every Waffle taskbar rebuild; persistent RAM is the same small compiled array already alive during each computation. | 0%. |
| `modules/overview/OverviewNiriWidget.qml` + `modules/overview/Overview.qml` + `services/NiriService.qml` | **HIGH-CONFIDENCE CPU/allocation candidate — remove redundant per-output workspace sorts from Overview.** Every current assignment to `NiriService.allWorkspaces` already publishes the array sorted ascending by `idx`. JavaScript `filter()` preserves source order, but OverviewNiriWidget and both classic Overview Left/Right key paths filter that array by output and sort it by the same comparator again. Remove only those second sorts and retain the filter/find/index logic unchanged. | Very low. The source-order invariant must be regression-covered at every `allWorkspaces` publication site, including equal-`idx` stable ordering, activation and urgency updates. | None. | Low transient array/sort CPU reduction: O(W log W) follow-up sorts become O(W) filters on Overview recomputation/navigation. | 0%. |
| `modules/background/Background.qml` + clock/widget diagnostic paths | **HIGH-CONFIDENCE normal-session CPU/allocation candidate — make desktop-clock diagnostic serialization demand-driven instead of continuously reactive.** Background says the clock diagnostics are bounded/inert, but production wiring observes `ClockWidget.debugPaletteReport` and `editControlsGeometryReport` unconditionally. That keeps nested `JSON.stringify`, `JSON.parse(clockSurface.surfaceReport)`, contrast calculations, CookieClock diagnostic serialization and an extra edit-control geometry solve live during ordinary clock/style/position changes. Preserve the documented `background clockDebugState` IPC response by building the same payload on demand when that function is called rather than maintaining serialized strings continuously. | Low–Medium. `clockDebugState` is documented even when `INIR_REGION_DEBUG` is not set; only mutating debug functions are env-gated. Preserve exact payload fields, disabled-state behavior, unloaded-clock behavior and any last-known snapshot semantics. | None. | Low–Medium transient JS/string allocation and avoidable geometry/diagnostic CPU reduction in normal sessions, especially during desktop-clock dragging/style changes. | 0%. |
| `modules/abyss/bar/AbyssBar.qml` + `modules/abyss/looks/AbyssLayout.js` | **HIGH-CONFIDENCE micro-candidate — compare normalized module IDs element-by-element instead of JSON-serializing both arrays.** `syncModuleIds()` currently computes enabled placement IDs and calls `JSON.stringify(next) !== JSON.stringify(moduleIds)` on every placements publication. `AbyssLayout.normalize()` already canonicalizes every accepted placement ID with `String(...)`, so length + ordered strict string comparison is equivalent before deciding whether to republish `moduleIds`. | Very low. Preserve enabled-only filtering, placement order, duplicate rejection performed by normalize, and no-op publication suppression. The proof depends on normalized string IDs; do not apply the helper to unnormalized editor drafts elsewhere. | None. | Low transient string/allocation/CPU reduction across per-edge/output AbyssBar placement updates; most useful during editor/layout churn. | 0%. |

| Hotspot quick-toggle family — common/Waffle + Classic + Android | **HIGH-CONFIDENCE process/wakeup candidate — move hotspot status/actions into one shared state owner with surface-demand leasing.** Waffle can instantiate one common `HotspotToggle` as the Action Center button model and a second one inside `HotspotControl`; each instance owns its own 5 s `nmcli connection show --active` poll while the same Action Center is open. Classic/Android variants duplicate the same transport again for their own sidebar surfaces. Centralize status/start/stop processes and expose one reactive hotspot state; keep presentation/notifications local. | Low–Medium. Preserve the exact external-change freshness bound, initial/open refresh, action completion refresh, start delete-then-create transaction, stop semantics, config-derived SSID/password and failure notifications. Demand must be reference-counted so one closing surface cannot stop another live consumer. | None. | Low recurring CPU/transient RAM plus child-process reduction whenever multiple hotspot controls coexist; Waffle button+menu is a source-proven duplicate owner. | 0%. |
| `modules/abyss/content/AbyssClipboardContent.qml` + `services/deferred/Cliphist.qml` | **HIGH-CONFIDENCE interactive CPU/allocation candidate — prepare exact clipboard row metadata on source revision, not on every search keystroke.** The current `rows` binding maps all pins and up to 400 history entries into new row objects, reparses previews and lowercases every preview before filtering whenever `search.text` changes. Cache source metadata keyed by `Cliphist.pinned` / `Cliphist.entries`; query changes should only lowercase the query, filter prepared keys, and publish fresh matched row records if fresh model identity is required. | Low–Medium. Preserve pins-before-history order, `pinPreview()`, the exact raw history preview after the first tab, case-insensitive substring semantics, image-entry values and all pin/unpin/delete/copy behavior. Do not substitute `Cliphist.filterEntries()` because its cleanup/display semantics differ. | Small bounded prepared-row cache while the Abyss clipboard surface is resident. | Low–Medium CPU/allocation reduction during typing; turns per-keystroke source normalization from O(P+H) string/object construction into source-revision work plus O(P+H) comparisons. | 0%. |
| `modules/sidebar/SidebarHost.qml` | **HIGH-CONFIDENCE failure/cold-load wakeup candidate — gate the 16 ms presentation frame ticker on readiness signals instead of polling Loader/geometry readiness.** `presentationTimer` repeats every 16 ms after a presentation request, while `tryPresent()` simply returns if the Loader is not Ready or geometry is zero. A slow cold load therefore polls readiness every frame, and Loader.Error/never-valid geometry can leave the ticker running indefinitely. Stop the ticker while prerequisites are false; re-arm from Loader status/geometry changes, then preserve the existing one warm / two cold 16 ms ready-frame settle before showing. | Medium. QML signal ordering and the compositor's required closed-frame contract are sensitive. Preserve cold/warm frame counts, resume remap, editor presentation, close cancellation, loader recovery and exact first-visible timing once prerequisites become valid. | None. | Low normal cold-open CPU/wakeup reduction; high failure-path protection by eliminating a possible ~62.5 Hz unbounded readiness poll. | 0%; presentation timing after readiness must remain identical. |
| `modules/common/widgets/NotificationGroup.qml` | **HIGH-CONFIDENCE micro-candidate — do not reverse an entire notification group when collapsed UI displays only the newest two.** Current collapsed model evaluates `notifications.slice().reverse().slice(0, 2)`. Use only the final two source elements and reverse that tiny slice; keep the expanded full reverse unchanged. | Very low. Preserve newest-first ordering, fresh-array behavior, 0/1/2-item cases and opacity of the second collapsed item when the group has more than two notifications. | None. | Low transient CPU/allocation reduction for large app notification groups while collapsed: O(N) copy+reverse becomes O(1) bounded copy/reverse. | 0%. |

| `services/HyprlandData.qml` | **HIGH-CONFIDENCE process candidate — route Hyprland raw events to the minimum snapshot refresh set instead of calling `updateAll()` for every event.** Today every raw event can request `hyprctl clients -j`, `monitors -j`, `layers -j`, `workspaces -j` and `activeworkspace -j` together. The socket event contract already separates window/workspace/monitor/layer/input classes. Keep `updateAll()` for startup, config reload, monitor topology and unknown events; route known window events to clients, layer events to layers, workspace/focus events to workspace+monitor state, and ignore input-only events for this service. | Medium. Exact event→snapshot ownership must be trace-tested against the Hyprland versions Hadalis supports. Unknown names must fall back to `updateAll()`; do not trust a closed enum. Preserve the current queued-refresh behavior when a domain process is already running. | None. | Potentially high transient CPU/process reduction on Hyprland: common window/title/focus/layer events can drop from up to five `hyprctl` child processes to the one or two snapshots they can actually invalidate. | 0%. |
| `services/HyprlandData.qml` + Bar workspace/active-window consumers | **HIGH-CONFIDENCE CPU/allocation candidate — derive largest-window-by-workspace during the existing clients publication pass.** `biggestWindowForWorkspace()` currently allocates a filtered array and reduces the full workspace subset every call. Bar Workspaces can call it once per workspace while ActiveWindow calls it independently. Build a private workspace-id→largest-window index while `windowList` is parsed, reusing the same pass that already builds `windowByAddress`; `addresses` can be pushed in that loop too instead of a second `map`. | Low–Medium. Preserve loose numeric/string workspace-id compatibility, **first strictly-largest wins**, and the current quirk where an all-zero-area workspace returns `null` because the reducer starts at null/area 0 and uses `>`, not `>=`. Preserve exact published window object identity. | Small private index; no extra cloned window records. | Low–Medium CPU/allocation reduction on window snapshot changes and Bar workspace recomputation; removes repeated O(N) filter arrays and area scans per workspace. | 0%. |
| `services/deferred/HyprlandXkb.qml` | **HIGH-CONFIDENCE process/lookup candidate — read and index XKB `base.lst` once per file revision instead of spawning `cat` for every uncached layout description.** Current layout changes clear the visible code, spawn `cat /usr/share/X11/xkb/rules/base.lst`, split the entire file and `find` the first matching layout/variant line. Use a read-only watched `FileView`, build description→code in source order, and answer later layout changes O(1). | Low–Medium. Preserve exact first-match ordering, the current variant code concatenation, empty/missing-file behavior, cache invalidation when the rules file changes on disk, and immediate clearing of the previous layout code while a new description is unresolved. | Small map for the XKB rules file. | Low transient CPU/process reduction and faster layout switching after initialization; eliminates one `cat` child process plus a full-file split/search for each first-seen layout description. | 0%. |
| `services/InternalTodoBackend.qml` | **HIGH-CONFIDENCE transport candidate pending a focused FileView fixture — use a dedicated read-only `FileView` for externally edited `todo.txt` instead of spawning `cat` after every debounced file change.** The existing warning is specifically about reusing the writer FileView after `setText()`; Quickshell documents `watchChanges + reload()` as the normal read path. Keep the writer FileView for writes/watch invalidation, add a second reader that never calls `setText`, reload it after the existing 300 ms debounce, and parse only after `loaded`. | Medium until fixture-proven. Preserve startup lock, self-write no-op behavior, 300 ms debounce, fresh-disk semantics, file-not-found/error behavior, list equality, and JSON write ordering. Atomic rename/write watcher behavior needs an explicit oracle before implementation. | One small FileView object; no retained duplicate task model required. | Low recurring process/RSS reduction for users who externally edit/auto-save the text mirror; removes one `cat` child process per debounced external change. | 0%. |

| `services/deferred/LauncherSearch.qml` | **HIGH-CONFIDENCE process candidate — remove math scheduling side effects from the reactive `results` binding.** Every non-empty non-Clipboard/non-Emoji result rebuild currently executes `mathTimer.restart()`. The binding also depends on `mathResult`, so a `qalc` response can re-evaluate `results` and schedule the same expression again. Move scheduling to the debounced-query invalidation boundary (plus live math-prefix changes) while leaving result composition unchanged. | Low. Preserve arbitrary qalc expressions, including expressions that do not start with a digit; preserve the configured non-app delay, prefix stripping, process cancellation/restart semantics and result ordering. Do not infer “not math” from app-looking text unless UI semantics are changed separately. | None. | Low–Medium transient CPU/process reduction in launcher search; removes self-rescheduling and unrelated reactive rebuild-triggered qalc launches. | 0%. |
| `services/YtMusic.qml` + `modules/common/Config.qml` | **HIGH-CONFIDENCE write/churn candidate — skip the five-second resume persistence transaction when the exact resume snapshot has not changed.** `_resumeSaveTimer` runs whenever a video ID is loaded, including indefinitely while paused, and `_persistResume()` always calls `Config.setNestedValues()`. Config does not equality-dedupe: every call records reload mutations, restarts the write timer, bumps global revision and emits `configChanged`. Track a local dirty revision across the nine resume fields and let the existing 5 s checkpoint clear it after persistence. | Low–Medium. Preserve the current five-second maximum checkpoint cadence while playback position advances, immediate explicit persist calls, destruction flush, track/playlist metadata, pause/play state and crash-resume payload. Do not globally change Config mutation semantics. | One bool/revision counter; negligible. | Medium local reduction during paused/unchanged loaded tracks: avoids up to one full Config mutation/write schedule every 5 s, plus downstream global Config listeners. | 0%. |
| `services/deferred/Emojis.qml` | **HIGH-CONFIDENCE per-keystroke CPU candidate — extend the existing prepared-entry cache with the lowercase key used by sloppy/Levenshtein mode.** Normal fuzzy mode already prepares `Fuzzy.prepare(entry)` once per list revision. Sloppy mode still calls `entry.toLowerCase()` for up to the first 100 entries on every query. Store `lower` beside `name`/entry and reuse it in both limited top-K and unlimited sloppy branches. | Very low. Preserve the first-100 bound, score threshold, binary insertion tie behavior, full-sort behavior when limit ≤ 0, source object/string identity and list-revision invalidation. | Tiny bounded extra string cache for emoji entries. | Low but repeated CPU/allocation reduction on every sloppy emoji query keystroke. | 0%. |
| `modules/bar/UtilButtons.qml` | **HIGH-CONFIDENCE micro-candidate — derive the active utility order once and reuse it for count/index/placement.** The file has at most 11 utility IDs, but every visible Loader computes row/column through `utilityIndex(id)`, which filters the full ordered list and re-runs `utilityActive()`; `visibleUtilityCount` performs the same filter independently. Publish one reactive `activeUtilityOrder = utilityOrder.filter(utilityActive)`, use its length and `indexOf()`, and keep Loader activation semantics unchanged. | Very low. Preserve configured order normalization, dynamic Privacy/Audio/Niri availability dependencies, inactive-loader behavior and `Math.max(0, index)` fallback. | One small derived array replacing repeated temporary arrays. | Low allocation/CPU reduction on bar utility-state/config changes; mainly removes repeated dependency evaluation and filter arrays. | 0%. |

| `modules/sidebarLeft/LocalMusicView.qml` + `services/LocalMusic.qml` | **HIGH-CONFIDENCE interactive CPU/allocation candidate — prepare immutable-per-library track metadata once instead of rebuilding search/folder keys across the complete MPD library on every query or selection change.** Current search lowercases and concatenates title + artist + album + folder for every track on every keystroke; folder browsing and selected-track resolution separately renormalize folder/key strings while rescanning the same library. Build a projection keyed to `libraryTracks` replacement containing the original track reference, exact `trackKey`, normalized folder and lowercase search haystack; query/folder/selection changes then reuse those fields. | Low–Medium. Preserve empty-query source-list behavior, JS lowercase semantics, root/nested folder normalization, original track identity/order, URI-before-path key precedence, child-folder grouping/order and immediate invalidation on every library replacement/rescan. | Low bounded metadata proportional to library size; replaces repeated temporary lowercase/concatenated strings. | Medium local CPU/allocation reduction for large music libraries during search, folder navigation and selection. | 0%. |
| `services/LocalMusic.qml` + local-lyrics Python/Rust producers | **HIGH-CONFIDENCE hot-path CPU candidate — replace the synchronized sidecar-lyrics linear active-line scan with an upper-bound binary search.** Both current producers sort timed LRC rows ascending before publishing, while `localLyricsActiveIndex` scans from row 0 until playback position on every reactive position update. Find the last timestamp `<= position` in O(log N), preserving last-equal-timestamp ownership. | Very low. Preserve unsynced/empty = -1, before-first = -1, duplicate equal timestamps -> last duplicate, exact timestamp, backwards/forwards seeks and original row/index identity. The optimization relies on the existing producer contract that synced rows are numeric and sorted. | None. | Low–Medium repeated CPU reduction while synchronized local lyrics are displayed; largest benefit for long lyric files / frequent MPRIS position updates. | 0%. |
| `services/WidgetPowerManager.qml` + `modules/background/widgets/AbstractBackgroundWidget.qml` | **HIGH-CONFIDENCE duplicate-work candidate — compute per-output widget pause state once per widget instead of twice.** Every `AbstractBackgroundWidget` currently binds `powerActive` through `widgetsActiveForOutput()` and `powerReduced` through `reducedModeForOutput()`; both call the same `shouldPauseForOutput()`, whose window-presence branch rebuilds active-workspace state and scans Niri windows. Because the public results are exact complements, derive `powerReduced: !powerActive` while keeping the authoritative service call for `powerActive`. | Very low. Verify every trigger: output eligibility, edit mode, manual GameMode, fullscreen, windows-present policy, Niri/non-Niri and multi-output workspaces. Preserve all existing animation/effect bindings and exact complement semantics. | None. | Low–Medium aggregate CPU/allocation reduction across multiple resident desktop widgets; removes one duplicate output-policy/workspace/window evaluation per widget invalidation. | 0%. |
| `services/deferred/Cliphist.qml` | **HIGH-CONFIDENCE per-keystroke CPU candidate — add the lowercase sloppy-search key to the existing revision-keyed prepared clipboard entry cache.** Normal fuzzy search already prepares entries once per `entries` revision and the classic filter path already has its own prepared display keys, but sloppy/Levenshtein mode still calls `entry.toLowerCase()` for up to the first 100 history rows on every query. Cache the exact lowercase raw-entry string alongside the existing fuzzy-prepared record and reuse it in both limited top-K and unlimited sloppy branches. | Very low. Preserve the first-100/maxEntries bound, score threshold, equal-score insertion order, limit semantics, exact raw entry identity and cache invalidation on every `entries` replacement. | Tiny bounded extra lowercase-string cache. | Low but repeated CPU/allocation reduction for sloppy clipboard search; same proven class as Emoji #98. | 0%. |

| `services/deferred/AnimeService.qml` + `modules/sidebarLeft/animeSchedule/AnimeScheduleView.qml` | **HIGH-CONFIDENCE network/parse candidate — coalesce only exact same-day schedule requests that are already in flight.** The singleton schedules `fetchSchedule("today")` from its own `Component.onCompleted`, while the view calls the same request from its `Component.onCompleted`; before the first response fills the 10-minute per-day cache, both can POST the same 50-item AniList query and independently normalize the same payload. Track in-flight state by resolved target day so a second request for that exact day reuses the pending work. Keep requests for different days independent to preserve today's per-day freshness/ordering semantics. The same cleanup can remove the dead `dayNum` and unused legacy `query` string currently constructed before `scheduleQuery`. | Low. Do not globally coalesce different weekdays or pre-mark their caches valid: that would change freshness and response ordering. Preserve error/loading semantics, NSFW request variable, target-day resolution and exact normalized list/object order. | Tiny bounded in-flight-day state. | Low–Medium startup/network/JSON-normalization reduction when the Anime view instantiates; also suppresses repeated same-day clicks while a request is pending. | 0% final visual output; loading/signal cadence must be oracle-tested. |
| `services/deferred/NewsService.qml` + `scripts/test-news-service-contract.sh` | **HIGH-CONFIDENCE strict CPU/allocation candidate — reject stale successful XHRs before RSS parsing, not after it.** A 200 response currently runs the full regex-based `_parseRss(xhr.responseText)` and only then checks `generation !== _requestGeneration`. Stale results are already forbidden from mutating cache/timestamps/articles, so the parse has no observable product effect. Move the generation guard ahead of `_parseRss`; update the contract test to require stale rejection before parsing while still proving no stale cache mutation. | Very low. Preserve current status/error behavior for the active generation, last-request-wins semantics, cache writes and exact parser output for non-stale responses. Pay attention to stale 200 vs active non-200 races. | None. | Low–Medium transient CPU/allocation reduction during rapid board/feed changes or duplicate surface fetches; completely removes regex/date/object construction for stale 200 bodies. | 0%. |
| `modules/sidebarLeft/anime/BooruImage.qml` + `BooruResponse.qml` + `modules/common/Directories.qml` | **HIGH-CONFIDENCE process-fan-out candidate — give manual preview downloads one shared directory-readiness owner instead of running external `mkdir -p` inside every image delegate.** Manual providers (`danbooru`, `waifu.im`, `t.alcy.cc`) instantiate one `BooruImage` per response image; every delegate starts Bash whose first child is `mkdir -p previewDownloadPath`, then performs the existing cache-file test and optional curl. `Directories` already owns an ordered cleanup/recreate bootstrap for `booruPreviews`, but that bootstrap is asynchronous, so simply deleting delegate mkdir calls would create a startup race. Expose/reuse one explicit directory-ready gate (session- or response-scoped), then let all delegates retain the exact `[ -f cache ] || curl` behavior after readiness. | Low–Medium. Immediate-sidebar-open during bootstrap, failed directory creation, multiple historical responses, duplicate filenames and provider switches must be tested. Do not replace manual local-file rendering with direct remote Image URLs, and do not introduce a serial download queue in the first patch because that would change arrival timing. | One tiny readiness flag/process owner; no new image cache. | Low–Medium child-process reduction on manual-provider result pages: N per-thumbnail mkdir children collapse to one readiness operation while cache/download semantics stay unchanged. | 0% pixels; thumbnail arrival timing must remain acceptably equivalent. |

| `modules/ii/overlay/OverlayTaskbar.qml` | **HIGH-CONFIDENCE transient GPU/texture-RAM candidate — bound the Angel taskbar wallpaper blur to the visible taskbar instead of materializing a full-output effect layer.** The retained taskbar is only content-sized, but `taskbarBlurWallpaper` is sized and decoded to `Quickshell.screens[0]`, then gets a `MultiEffect` blur before the parent clips/masks it back to the taskbar. Reuse the existing screen-aligned PreserveAspectCrop transform and materialize only taskbar bounds plus the exact 64 px blur support. | Low–Medium. Preserve the current `screen[0]` sampling contract, screen-relative x/y alignment, rounded mask, content-width changes and the full open→fade-out lifetime owned by `presentationActive`. | **High local potential while Overlay is visible in Angel mode; zero expected idle gain once the retained taskbar has faded out.** | **High local transient potential.** A full-screen RGBA8 layer is ~7.9 MiB at 1920×1080 and ~31.6 MiB at 3840×2160 before effect intermediates; the strict candidate should allocate only taskbar+blur-padding surfaces. These are texture-size calculations, not measured RSS savings. | Target 0%; exact crop A/B must include every taskbar edge through the 64 px blur reach, fractional scale and wallpaper crop alignment. |
| `modules/waffle/altSwitcher/WaffleAltSwitcher.qml` + `WaffleAltSwitcherContent.qml` | **HIGH-CONFIDENCE transient render-pass candidate — collapse the Waffle skew preset per-slice mask capture into one analytic parallelogram mask/pass.** Every instantiated skew delegate enables a content layer while `cardVisible`, then applies `MultiEffect` masking whose mask is another `ShaderEffectSource`/layer containing a white `Shape`. The same delegate already owns the exact parallelogram equation for `containmentMask`, so mask geometry is not unknown. Keep preview capture, ListView geometry and the Canvas shadow unchanged in the first experiment; replace only the duplicated content+mask offscreen chain. | Medium. AA edge coverage, 4×/1× layer-sample behavior, current expanded-slice animation, preview arrival, focus/navigation and rapid close must remain identical. | **Medium–High local potential while the skew switcher is visible**, multiplied by visible/cached slice delegates; zero expected gain for other presets or while closed. | Low–Medium transient texture reduction from removing one or more per-delegate offscreen mask/content surfaces. | Target 0% for an exact mask-only collapse; otherwise require <1% global error plus a stricter alpha/edge-band comparison on the slanted edges. |

| `services/ai/AiProviderCatalog.qml` + `modules/settings/AiConfig.qml` | **HIGH-CONFIDENCE catalog-publication CPU/allocation candidate — publish with append-once storage and build one provider→models index instead of repeatedly copying/filtering the full model catalog.** `_publishModels()` currently grows `merged` through repeated `merged = merged.concat(bucket)` copies, sorts it, then each Material provider card calls `modelsFor(providerId)`, which filters the entire sorted catalog again. Current presets contain 11 providers. Fill one array with `push`, keep the exact existing sort comparator, build a stable private `Map` of provider buckets from that sorted result, and have `modelsFor()` return a fresh `slice()` of the bucket. Mutate the private Map before the single existing `models` publication so `modelsChanged` remains the authoritative UI invalidation. | Low. Preserve `Object.keys(_catalogByProvider)` pre-sort input order, stable equal-key sort behavior, exact model object identity, strict `providerId ===` membership semantics, fresh-array return behavior from `modelsFor()`, and current `modelsChanged`/`catalogUpdated` cadence. | Small O(M) resident reference index across the discovered model catalog. | Medium transient CPU/allocation reduction on catalog load/refresh and when the provider settings grid is live; removes repeated concat copies plus up to one full M-model filter per visible provider card. | 0%. |
| `modules/sidebarRight/events/EventsWidget.qml` + `modules/background/widgets/calendar/CalendarUpcomingWidget.qml` | **HIGH-CONFIDENCE calendar CPU/allocation candidate — parse each merged event timestamp once before sorting instead of constructing two `Date` objects per comparator call.** Both 30-day merged-list builders clone local/external events and then sort with `new Date(a.dateTime || a.startDate) - new Date(b.dateTime || b.startDate)`. Prepare a private event→millisecond key while appending; reuse the already-created external `evtTime` where available; sort by numeric keys with the same stable source order for equal/invalid keys. | Low. Preserve the current local/external inclusion rules, all-day past-event exception, object clone shapes, equal-time stability, invalid-date comparator behavior (`NaN` acts as an equal comparison), full EventsWidget ordering, CalendarUpcoming `slice(0,maxEvents)`, and day-header grouping. | Tiny transient timestamp Map/parallel keys during rebuild; no persistent cache required. | Low–Medium CPU/allocation reduction on event/calendar refreshes, growing with the number of 30-day merged events; Date parsing falls from comparator-multiplied O(N log N) construction to O(N) preparation while the sort itself remains unchanged. | 0%. |

| `modules/bar/BarTaskbar.qml` + `BarTaskbarButton.qml`; `modules/dock/DockApps.qml` + `DockAppButton.qml`; Waffle `WaffleTaskViewContent.qml` + `WindowThumbnail.qml` | **HIGH-CONFIDENCE compositor CPU candidate — per-owner published-focus hoist instead of one full `NiriService.windows.find(is_focused)` per delegate.** Bar and Dock buttons each recompute the identical `windows.find(...) ?? activeWindow` expression, while every Waffle task-view window thumbnail independently finds the focused id. Compute the exact current expression once in each existing owner and pass the object/id into its delegates; do not change `NiriService` authority or signal ordering. | Low. Preserve exact published-window-first/fallback semantics, null behavior, object identity, title/app-id matching, focus-only updates and each owner's current lifetime. Waffle must keep its current focus highlight even when cached task-view membership is not refreshed on focus-only updates. | One object/int binding per owner; removes equivalent bindings from every delegate. | **Medium local CPU potential on Niri window publications/focus churn**, scaling with visible taskbar/dock app delegates and Task View window count: O((B+D+T)×N) focused-window scans become O((owners)×N) plus O(1) delegate reads. | 0%. |
| `modules/bar/Workspaces.qml` | **HIGH-CONFIDENCE multi-output CPU/allocation candidate — build one workspace representative/occupancy summary per published Niri window snapshot.** In workspace mode every rendered workspace button filters all `NiriService.windows` to choose `first focused else first`; the occupancy worker separately scans the same list into a Set, and column mode performs another active-workspace filter. Build one source-order-preserving summary `{representativeByWorkspace, occupiedIds}` in one pass; use O(1) representative lookup per button and reuse `occupiedIds`. Keep the column-mode array filter separate in the first patch to avoid retaining per-workspace arrays. | Low. Representative selection must preserve Array.filter + Array.find semantics: first focused window wins, otherwise first source-order window; duplicate/malformed workspace ids, empty workspaces, showAppIcons off/on, per-monitor slot mapping and focus changes must remain exact. | Small O(workspaces) resident maps/Sets per Workspaces instance; no per-window bucket arrays required. | **Low–Medium CPU/allocation reduction per window snapshot, larger with many workspaces/outputs.** Removes W full-window filter allocations for workspace icon delegates and lets the existing occupancy refresh reuse the same membership summary. | 0%. |

| `modules/wallpaperLauncher/WallpaperLauncherList.qml` + `WallpaperLibrary.qml` | **HIGH-CONFIDENCE interactive CPU/allocation candidate — Wallpaper Launcher prepared relative-path search keys.** Every non-empty query currently filters the full selected wallpaper list and runs `relativePath.toLowerCase()` for every entry on every keystroke, although `WallpaperLibrary` publishes a stable sorted snapshot until the next scan/mode switch. Prepare the exact lowercase relative-path key once per published entry snapshot, then filter by those keys while returning the original entry objects in the same order. | Very low. Preserve `trim().toLowerCase()` query normalization, empty-query identity (`return entries`), fresh filtered-array behavior, original entry object identity/order, Static/Animated mode switches, scan refreshes and current-path index/preview timing. | Small bounded O(total relative-path characters) search-key RAM while prepared; can be lazy/session-scoped if desired. | **Medium local CPU/allocation reduction while typing in large wallpaper libraries**; per-keystroke lowercase work falls from O(N path text) to O(N) substring checks. | 0%. |
| `modules/cheatsheet/CheatsheetKeybinds.qml` + `NiriKeybinds.qml` / `HyprlandKeybinds.qml` | **HIGH-CONFIDENCE interactive CPU/allocation candidate — Cheatsheet lazy prepared search fields.** `allKeybinds` already clones the compositor snapshot once, but every search keystroke lowercases `key`, every modifier, `comment` and `category` again for every row. Lazily prepare separate lowercase fields on the first non-empty search for the current `allKeybinds` snapshot and reuse them across subsequent keystrokes; return the existing cloned keybind objects rather than wrapper objects. | Very low. Do not concatenate fields into one haystack because that can create cross-field false matches. Preserve optional-field behavior, per-modifier `some()` semantics, first-search malformed-data behavior, fresh filtered-array identity, result order and Niri/Hyprland reload invalidation. Clear/rebuild the prepared cache when `allKeybinds` changes; it may be dropped again when search becomes empty. | Temporary O(keybind text) lowercase cache only during an active search session if cleared on exit. | **Low–Medium interactive CPU/allocation reduction**, scaling with keybind count/modifier count and query length; stable strings are normalized once per search session instead of once per keystroke. | 0%. |
| `services/Ai.qml` + `modules/sidebarLeft/aiChat/AiModelSelector.qml` | **HIGH-CONFIDENCE interactive/catalog CPU candidate — AI recommendation pre-score + query-independent recommendation set.** `recommendedModelIds()` currently calls `_profileScore()` twice per sort comparison, rebuilding/lowercasing model labels repeatedly; the selector then calls the complete recommendation pipeline from inside its `entries` binding, so changing only search text can re-filter/sort recommendations even though recommendation inputs did not change. Decorate each allowed runnable model with its score once before the same stable descending sort, and expose a recommendation Set/property that invalidates only with the exact runnable-model/model-field readiness inputs, not `filter` text. Non-recommended catalog modes should not compute the set at all if it is not otherwise needed. | Low. Preserve `_profileAllows` rules, exact numeric score/coercion, input-order tie stability, minimum-limit behavior, model-id identity, credential/policy/provider readiness invalidation and default-model selection. Do not cache complete selector entries because `ready`, `hasKey` and provider status have independent reactive lifetimes. | Small O(R) transient decorated score records during recommendation rebuild; optional Set of at most the requested recommendation count. | **Medium local CPU reduction for large discovered catalogs and repeated model-search typing**, especially under the default Recommended filter; scoring work changes from comparator-multiplied calls to once per candidate and recommendation sorting leaves the text-query hot path. | 0%. |

| `modules/bar/weather/LiquidOrbitalField.qml` | **HIGH-CONFIDENCE Canvas-fallback CPU candidate — Liquid Orbital Canvas per-frame node preparation.** The animated Canvas fallback calls `liquidSample()` for 120 contour samples, up to one active glow sample, one sample per hour pod, and 4×19 moving-streak samples. With 8 hours that is up to 205 `liquidSample()` calls/frame; each currently loops all 8 nodes and recomputes each node\'s fixed-for-that-frame angle ellipse frame and breathing radius. Prepare `{angle, frame, radius, active}` once per node at the start of the paint and pass that transient array through every sample path, while keeping the sample-angle ellipse frame calculation unchanged. | Low–Medium. This is fallback-renderer math, so compare exact generated coordinates/raster across animated/frozen times, node counts, active indexes, geometry changes and shader compile handoff. Preserve arithmetic order inside signed-arc/profile/thickness calculations and do not alter the compiled ShaderEffect path. | Tiny O(node count) transient frame-local array; no persistent cache or QML NOTIFY state. | **Medium–High CPU reduction on the Canvas fallback path only**, especially Software/Null graphics backends: repeated node frame/radius preparation falls from roughly O(samples×nodes) to O(nodes) per paint while the actual liquid sample math remains. Compiled GPU shader path is unchanged. | 0%. |
| `modules/bar/weather/OrbitalWeather.qml` + `modules/dashboard/DashWeather.qml` | **RETIRED / IMPLEMENTED at `63ea47423` (R43.2).** Current `hourAngles` shares a local per-quadrant `tables` map while preserving the direct liquid mode and uncached public fallback. This proposal is no longer pending; retain the historical proof/measurement boundary. **Historical R43.2 claim (not the current runtime state):** OrbitalWeather per-quadrant arc-length table reuse. At the original baseline, the non-liquid Dashboard orbit mapped each hourly label to an equal-arc position by rebuilding the same 72-sample cumulative ellipse-length table independently for every hour. Within one `hourAngles` evaluation, `orbitRadiusX/Y` and each quadrant\'s start/end angles are identical; only the target fraction differs. Build the exact existing table at most once per used quadrant and resolve every hour from that transient table with the same target/search/interpolation math. Keep liquid mode\'s direct parametric angle path unchanged. | Low. Preserve `hourFromLabel()` parsing, quadrant/fraction mapping, 72-sample arithmetic, linear interpolation, invalid-label fallback and exact hour ordering. Do not exploit ellipse symmetry or change `orbitAngleForHour()` fallback semantics unless separately proven. | At most four short transient cumulative-length arrays during one binding evaluation; no retained cache required. | **Low–Medium CPU reduction during Material Dashboard weather geometry/resizes**: an 8-hour model avoids rebuilding a 72-sample table eight times and instead builds only the quadrants actually used. Weather popup liquid mode is unaffected. | 0%. |

| `modules/common/widgets/shapes/ShapeCanvas.qml` + `shapes/morph.js` + `shapes/cubic.js` | **HIGH-CONFIDENCE animation CPU/allocation candidate — ShapeCanvas allocation-free morph streaming.** Every Canvas paint calls `Morph.asCubics(progress)`. For M matched segments that routine allocates a result array, one interpolated `Cubic` per segment, two 8-slot arrays per interpolated segment (`Array.from(...).map(...)`), then an additional 8-slot array + closing `Cubic` so the final endpoint exactly equals the first anchor. ShapeCanvas repaints not only while `progress` animates but also for color/stroke changes, so the same geometry allocation can recur on color-only frames at stable progress. Extend the existing mutable interpolation path with a closed streaming iterator that reuses one `MutableCubic`, captures the first anchor, and overrides only the final endpoint exactly as `asCubics()` does today; stream directly into the Canvas path instead of materializing the cubic array. | Low–Medium. The final-segment closure rule is pixel-critical and the current `forEachCubic()` alone is **not** equivalent. Preserve interpolation arithmetic, segment order/count, progress overshoot, first/last anchor identity, fit-to-canvas transforms, stroke width compensation and all animation timing. | One reusable 8-number mutable cubic per ShapeCanvas instance instead of per-paint result/cubic/point arrays. | **Medium transient allocation + local CPU reduction** across shared Material Shape animations and color repaints; no change to MaterialShapes matching topology or pixels. | 0%. |
| `modules/common/perimeter/ConnectedSurfaceIrisField.qml` + `ConnectedSurfaceIrisFrame.qml` | **HIGH-CONFIDENCE connected-surface CPU/allocation candidate — Connected iRiS shared shape-uniform packet.** A production frame owns two `ConnectedSurfaceIrisField` instances: the visible plate and the SDF shadow mask. Both consume the same five-shape snapshot and the same `smoothing: root.fuse`, yet each independently derives 20 shape vectors, 5 radius blocks, 5 fuse blocks and 10 join blocks (40 shape-derived `vector4d` values) plus the same id map and helper lookups. Prepare that immutable shape/smoothing packet once per snapshot and let both fields bind their named shader uniforms to the same prepared values; keep viewport/screen/tint/rim/edge field-local. | Low–Medium. Preserve capacity-20 zero fill, shape order, duplicate-id last-write map behavior, scalar coercion/fallbacks, non-array join wrapping, missing join names, exact update timing and every named ShaderEffect uniform value. Packet replacement must invalidate both fields in the same QML turn. Do not touch `IrisField.frag(.qsb)` or shadow-pass topology. | One shared O(capacity) prepared packet replaces two identical CPU-side preparations; each ShaderEffect still owns its uniform bindings/GPU uploads. | **Low–Medium CPU/allocation reduction during connected-popup geometry animation**, with zero claimed GPU-pass reduction. Distinct from Round 2.2 shadow-pass elimination research. | 0%. |

| `modules/settings/SettingsPageRegistry.qml` + `SettingsPageRegistryData.qml` + static Settings search consumers | **HIGH-CONFIDENCE interactive CPU/allocation candidate — Settings static prepared family-routed search index.** `SettingsPageRegistryData.searchIndex()` already caches the translation-expanded raw static index, but every non-empty Settings query calls wrapper `SettingsPageRegistry.searchIndex()`, which re-filters legacy slots, runs `FamilyPolicy.settingsRoute()` for every entry, clones redirected entries, then each consumer lowercases `label`, `description`, `pageName`, `section` and `keywords.join(" ")` again. Prepare the routed static snapshot plus private normalized fields once per exact family/translation epoch; query edits then only run the existing term/scoring predicates. | Low. Invalidate on Translation index rebuild and every `panelFamily` change; preserve hidden-legacy filtering, Abyss page-name/route substitutions, raw object fields, consumer-specific `isPageApplicable`/allowed filtering, score/order/tie behavior and immediate family-switch observability. Do not fold dynamic control entries into this cache; candidates #43/#44 already own that separate lifecycle. | Bounded O(static search text) normalized strings and routed entry references for one active family epoch. | **Low–Medium interactive CPU/allocation reduction across standalone Settings, SettingsOverlay and SettingsFocus**: eliminates per-keystroke full-index route/filter/map/clones and repeated static metadata normalization. | 0%. |

| `scripts/images/least_busy_region.py` + desktop-widget auto-placement callers | **HIGH-CONFIDENCE image-analysis CPU/memory candidate — least_busy_region processed-grayscale reuse.** In normal and largest-region modes the script decodes the wallpaper as grayscale, rescales/crops it for the region search, then later `get_region_brightness()` decodes and rescales/crops the same grayscale image again for the chosen region. Keep the current color decode for dominant-color clustering, but retain the exact already-processed grayscale array from the search pass and run the existing clamp/slice + `np.mean/std` brightness calculation on that array. | Low. Preserve `cv2.IMREAD_GRAYSCALE`, Lanczos resize dimensions, center-crop arithmetic, coordinate clamping, `np.mean/std` rounding and all JSON fields. Keep `--color-only` on its current independent read path and do not derive grayscale from the color decode, which could change codec/conversion pixels. Treat in-place wallpaper-file mutation during one invocation as outside the parity claim unless explicitly fixture-tested. | One already-existing scaled grayscale array lives slightly longer within the same process; eliminates a second decoded/resized grayscale image allocation. | **Medium local CPU/memory-bandwidth reduction per normal/largest image-analysis invocation**: removes one full grayscale decode + scale/crop pass while leaving search, color clustering and output unchanged. Benefits both generic desktop widgets and Waffle clock callers. | 0%. |
| `modules/waffle/background/WaffleBackgroundClock.qml` + `services/DesktopWidgetLayout.qml` | **HIGH-CONFIDENCE process/fan-out candidate — Waffle clock records-change process narrowing.** Every `DesktopWidgetLayout.recordsChanged` currently calls `refreshPlacementIfNeeded()` on every per-output Waffle clock. In auto-placement mode this launches the OpenCV least/busiest-region subprocess even when the changed record belongs to another widget or another output. The only per-output record fields the clock reads are `enable`, `placementStrategy`, `x` and `y`: `onClockEnabledChanged` and `onPlacementStrategyChanged` already refresh auto-placement, while `x/y` matter only in free mode and are handled by `syncFreePositionFromConfig()`. Remove the unconditional direct image-analysis refresh from `onRecordsChanged`; keep free-position sync and let the exact derived-property/geometry/wallpaper handlers own real placement invalidation. | Low–Medium. QML binding/signal ordering must be fixture-tested so same-record `enable`/`placementStrategy` edits still trigger exactly one eventual analysis; preserve free-mode x/y sync, initial Config-ready behavior, wallpaper/size-triggered analysis, force-center gating and multi-output independence. | None. | **Potentially high transient process/CPU reduction while editing desktop-widget layout**, especially multi-output: unrelated output/widget record writes stop launching one Python/OpenCV analysis per resident auto-placed Waffle clock. | 0%. |

| `scripts/images/least_busy_region.py` | **HIGH-CONFIDENCE image-analysis CPU candidate — least_busy_region padded-integral hot loop.** Both least/busiest and largest-region scans immediately drop OpenCV integral images\' zero border with `[1:,1:]`, then call a Python `region_sum()` twice per candidate window; that helper branches on `x1 > 0` / `y1 > 0` to reconstruct the missing border. Keep the native `(h+1)×(w+1)` integral arrays and compute each inclusive rectangle from the same four operands in the same subtract/subtract/add order: `I[y2+1,x2+1] - I[y2+1,x1] - I[y1,x2+1] + I[y1,x1]`. This removes per-window boundary branches without changing candidate order or variance math; in largest-region mode also hoist constant `region_w*region_h` outside the inner scan. | Very low. Preserve exact candidate ranges, out-of-bounds `continue`, row-major first-match/tie semantics, float64 integral depth and arithmetic order. Oracle exact sum/squared-sum/variance and chosen coordinates including x/y=0, padding-adjusted tiny images, least/busiest and largest-region binary-search steps. | None in practice: the current sliced integral views already keep the full OpenCV base arrays alive. | **Medium local Python CPU reduction inside the sliding-window search**, especially large screens/small stride: removes two helper calls and up to six boundary tests per candidate window, plus a loop-invariant multiply in largest-region scans. | 0%. |
| `modules/settings/CustomThemeEditor.qml` | **HIGH-CONFIDENCE interactive CPU candidate — CustomTheme quick-adjustment prepared HSL baseline.** Saturation/brightness/temperature sliders debounce at 50 ms. `captureOriginalColors()` already freezes one deep-cloned baseline for the whole adjustment session, but every debounce tick repeats `Object.keys`, `m3`/hex validation, `Qt.color()` parsing and HSL extraction for every baseline color before applying only new slider factors. When the baseline is first captured, prepare the same ordered valid-color rows as `{key,h,s,l,a}` once; each later tick only performs factor math + `Qt.hsla(...).toString()` and builds the same update object. Reset the prepared rows exactly whenever `originalColors` is reset today. | Very low–Low. Preserve `Object.keys` enumeration order, current `m3` + `startsWith("#")` eligibility, Qt color parsing semantics (including malformed/edge color strings), hue wrapping, clamping, alpha, update insertion order, 50 ms debounce and today\'s intentionally frozen baseline semantics if unrelated theme values change mid-session. | Tiny O(valid m3 colors) numeric metadata for the active quick-adjustment session, alongside the baseline object already retained. | **Low–Medium interactive CPU reduction during slider drags**: removes repeated key filtering/color parsing/HSL extraction at up to the existing 20 Hz debounce cadence. Theme application/config publication cost remains unchanged. | 0%. |

| `modules/settings/AdvancedConfig.qml` + Waffle `WThemesPage.qml` + `scripts/colors/apply-targets.sh` / `modules/90-cava.sh` | **HIGH-CONFIDENCE process/pipeline candidate — Cava Settings target-specific apply.** Both Settings families debounce Cava-specific option changes and then launch `switchwall.sh --noswitch`, regenerating the wallpaper palette and waking the general external-theme pipeline even though repository-wide search shows `appearance.cava.*` is consumed by the Cava target only. Route those debounced changes to `apply-targets.sh cava` (or the same target module) against the existing generated palette; retain a full-regeneration fallback only when required palette artifacts are absent. The enable/disable toggle still executes the Cava target so its managed block is added/stripped exactly as today. | Low–Medium. Preserve 500 ms coalescing, Config write order, first-run/missing-palette recovery, managed-block strip/add behavior, cover-source extraction, exact external Cava config, and internal visualizer reactivity. Do not skip target execution merely because `enableCava=false`: disabling must remove an existing managed block. | None beyond existing target process; eliminates unrelated palette/external-target work. | **Medium–High transient CPU/process/I/O reduction for Cava Settings changes**: replaces a whole wallpaper color regeneration + possible all-target apply wave with one Cava-target apply once artifacts exist. | 0%. |
| `services/DateTime.qml` + direct date/calendar consumers across Lock/Bar/VerticalBar/Widgets/Calendar surfaces | **HIGH-CONFIDENCE recurring CPU/reactivity candidate — DateTime stable calendar/minute snapshot fan-out.** The shared `SystemClock` intentionally runs at 1 Hz when second precision is enabled or while locked, but many consumers read raw `DateTime.clock.date` only to format a calendar date, derive a today key/name, or feed month/day calendar state. Those bindings reevaluate every second even though their semantic input changes only at the next minute/day. Publish stable day-level and, where needed, minute-level snapshots from the same SystemClock and migrate only consumers whose current format/logic omits seconds. Candidate #79 remains the service-internal three-string optimization; this extends the same boundary to external consumers and calendar inputs. | Low–Medium. Preserve midnight rollover, manual wall-clock jumps, timezone changes, live locale/Translation changes, lock/unlock precision transitions, exact formatted strings, date identity/fields needed by CalendarView, and all true minute/second consumers. `Notifications` quiet-hours and second-hand/rotation logic stay on raw clock/minute/second signals. | One/two tiny Date snapshots or scalar epoch records in the singleton. | **Low–Medium recurring CPU/string/reactive reduction, potentially larger while locked/multi-output** because lock/date/calendar surfaces stop inheriting 1 Hz invalidation solely from raw clock-date identity. | 0%. |

| `modules/common/Config.qml` | **HIGH-POTENTIAL CPU/temporary-allocation candidate — repeated deep JSON clone of in-flight mutation overlays.** During `_reloadInFlight` and/or `_writeInFlight`, each `setNestedValue(s)` clones *all previously pending overlay entries* through `JSON.stringify`/`JSON.parse`, then assigns one new path. For a burst of K distinct large mutable payload edits in one flight, cumulative previous-overlay traversal can grow quadratically with K; repeated same-key edits can redundantly clone the prior large value. Consider a private sparse last-write-wins overlay representation with equivalent JSON normalization/snapshot semantics, publishing/replaying at the original ownership boundaries. | **Medium / oracle-required** because last-value references, prior-value cloning, special/non-JSON values, QML `var` NOTIFY, insertion/replay order, style migration and overlapping reload/write/save completion can be observable. Do not simply mutate the current overlay in place and claim parity. Need real QV4 asynchronous race tests. | Bounded live overlay storage; possible lower transient JSON-copy allocation, most relevant under overlapping file I/O. | Potential reduction in config-mutation latency during bursts; **not** a claimed startup/steady-state whole-shell win. | 0% functional state drift, no runtime change authorized. |
| `modules/sidebarRight/notepad/NotepadWidget.qml` | **HIGH-CONFIDENCE allocation-shape candidate — per-edit whole-document word-list allocation.** `wordCount` currently uses `textArea.text.trim()` to test non-empty and again calls `.trim().split(/\s+/).length`, generating a word array and repeated string processing for every change to the editor's `text`. For long notes, the split result scales with word count. Investigate one exact ECMAScript-whitespace streaming count and optionally an explicit visibility/presentation demand boundary after confirming QML binding activity. | Low–Medium. Preserve immediate displayed count, empty/whitespace-only notes, JS Unicode `\s` and `trim` semantics, text changes/programmatic loads, compact/full presentation and QML public `wordCount` behavior. `Notepad` cross-surface tab synchronization and 800 ms autosave must remain untouched. | Remove O(words) temporary split array per evaluated text change; still requires O(text) scan unless a stronger proof-backed incremental model is used. | Potentially lower typing GC/CPU for large notes only; benchmark JS scanning cost before claiming CPU improvement. | 0% exact count/UI timing drift. |

| `modules/common/Config.qml` + `services/CustomWidgets.qml` | **HIGH-CONFIDENCE STRUCTURAL ALLOCATION CANDIDATE; behavior/NOTIFY parity still unproved — batch custom-widget default seeding repeatedly deep-copies the expanding custom config tree.** `CustomWidgets._seedMissingConfig()` builds a potentially large `updates` object of missing keys and calls `Config.setNestedValues(updates)` once. That function loops keys and calls `_applyNestedKey`; each `background.widgets.custom.*` key currently executes `JSON.parse(JSON.stringify(customWidgetData))`, publishes one new QML `customWidgetData`, and then `_cloneObject(data)` for `_customSnapshotForInject`. For K new keys, each prior value can be copied during subsequent keys, so cumulative traversed prior tree may grow quadratically in K for similar-size values. This occurs even with no FileView read/write in flight, unlike R51.1's separate in-flight overlay copies. | Medium–High: repeated fresh-object identity, *intermediate* `customWidgetDataChanged` delivery, string coercion, custom snapshot/inject ordering, concurrent external edits, and saved JSON/fallback are all observable. Do not silently coalesce per-key NOTIFY or alias live mutable trees. Prove real QV4 step-by-step parity or retain current publication semantics. | Potentially lower transient JS allocations under batch missing-default seeding, proportional to total custom-widget config shape. Not proof of persistent RSS reduction. | Highest expected savings during many-widget install/reload/default creation; inspect clone counts/bytes and time before claiming CPU speedup. | 0% behavior/data drift. |
| `modules/common/functions/audioRouting.js` + `services/Audio.qml` | **HIGH-CONFIDENCE GRAPH-ALGORITHM CANDIDATE / CONTRACT-GATED.** During EasyEffects sink routing, `resolveSink()` computes directed reachability by scanning every PipeWire link repeatedly for up to `nodes.length` passes. For a reverse-ordered chain of N known nodes and E links, this can require O(N×E) edge observations. A guarded adjacency traversal can approach O(N+E) on fully observed graph snapshots, but **an unconditional BFS is NOT strict-lossless**: when links mention absent node IDs, the original pass cap may stop before full transitive closure while BFS would continue and select a different sink. Validate every traversable link endpoint against the current nodes snapshot; use the original traversal for incomplete/malformed graphs. Preserve all output selection/driver/configured-name/observable read ordering. | Medium–High, strict parity for missing nodes and side-effecting getters unproven. Pure-JS graph-only differential prototype: 20,000 deterministic graphs, 13,587 eligible, 6,413 fallback, 0 reachability mismatches; this is **not** production QV4 or complete `resolveSink` parity. Profile actual PipeWire topology before implementing. | Additional adjacency storage per resolution; could trade temporary allocations against repeated link scans. No measured RSS improvement. | Potentially faster EasyEffects topology re-resolution on complex graphs; normal small graphs may regress due to guard/index setup. | 0% routing/OSD behavior drift. |
| `services/ScreenTime.qml` + `modules/sidebarRight/screenTime/ScreenTimeWidget.qml` + `modules/waffle/actionCenter/screenTime/ScreenTimePage.qml` | **HIGH-CONFIDENCE INTERACTIVE CPU/TEMP-ALLOCATION CANDIDATE — reuse one historical range snapshot per UI refresh instead of recomputing it for each projection.** `getCachedDays(days)` remerges today's data with cached history by building fresh app objects and 24-element hourly arrays; each UI's `_refreshData()` calls it once for `_displayData`, then `getAppList(days)` recomputes the same merged range and an open hour drilldown's `getHourBreakdown(hour,days)` recomputes it again. Additionally `rangeReadProc` already constructs a merged `rangeLoaded(days,data)` payload before both UIs ignore `data` and recompute on receipt. For selected historical range + open drilldown, this is three merge traversals per owner refresh, plus one at range publication, not recurring work when ScreenTime is disabled. | **Medium, QV4/observer parity gate.** Derive `appList`/`hourBreakdown` from the fresh `_displayData` snapshot within one refresh without changing the service's public `getCachedDays/getAppList/getHourBreakdown` fresh returns, QML property change order, sort tie order, cache miss/loading behavior, or day-rollover/range generation. Do not memoize globally just by `days` as today mutates. | Fewer copied per-app records and 24-slot arrays during historical range refresh; no proven persistent RSS reduction. | May reduce CPU/GC of historical Activity views; not a default idle-shell or full-app performance claim. | 0% numerical/UI update drift; instrument real QV4 and owner sessions. |
| `services/ResourceUsage.qml` + history graph consumers | **MEASURE FIRST / QML NOTIFY-GATED:** Five history update methods each publish a newly spread-copied array, then call `.shift()` on the just-published QML `list<real>` when over `historyLength`. This entails repeated O(H) copying and a distinct intermediate published length H+1 under a full ring. An exact bounded-copy projection may reduce temporary churn, but merging append/truncate into one assignment can change intermediate property reads, `valuesChanged`, list identity and chart repaint timing. | Medium–High; current append-then-shift behavior, unusual `historyLength` values, QML list wrapper semantics and synchronous readers require a native QV4 oracle. | Potential transient allocation reductions per active history sample; no measured persistent RAM gain. | Potential CPU/GC gain under long history and short polling interval; requires profiler. | 0% history/graph/NOTIFY drift. |
| `services/CalendarSync.qml` `_getEventBucketsForDates` + active calendar owners | **HIGH-CONFIDENCE SOURCE-LEVEL CPU COMPARISON CANDIDATE — index target local-day timestamps once for timed external events.** The existing batch helper still performs one `eventTime === targetTimes[i]` comparison per requested day for each non-all-day event; for E timed events and D visible dates this is E×D comparisons (plus date parsing). A private `Map<localMidnightMs, orderedIndices[]>` makes most valid timed events a direct lookup while leaving all-day, multi-day, exclusive DTEND and result append order unchanged. **Exclude NaN target/event timestamps** because JS `Map` considers NaN equal to NaN, whereas original `===` does not. Preserve duplicate dates by storing all ordered target indices. | Medium/QV4 strict-lossless gate. Compare every emitted per-date array by identity/order, dynamic QML event reads, legacy/malformed dates, TZ/DST and all-day handling; do not change `getEventsForDate` or existing calendar invalidation cadence. Isolated JS differential: 16,000 generated cases, zero membership/order/identity mismatches; **not** native acceptance. | Additional temporary D-sized Map/index arrays per batch; no proven persistent memory benefit. | Potential reduced comparisons when feeds are large and 14–30 date windows request all events; on tiny feeds Map setup could cost more. Prototype loop-count sample: 10,516,348 baseline timed comparisons vs 503,958 indexed timed lookups (not runtime time/CPU %). | 0% calendar membership, display order or identity drift. |
## Promotion order

1. **Bounded wallpaper-glass capture** — `GlassBackground` family plus Bar/Dock non-native-blur paths. This attacks screen-sized offscreen layers that are often displayed only through small panel geometry.
2. **Pre-QML environment/ABI fast path** — repair the broken parent-shell environment cache and let unchanged ABI identity skip `qs --version`; highest-confidence startup latency candidate.
3. **ConnectedSurfaceIrisFrame shadow capture elimination** — first remove only the redundant post-blur capture if exact clipping parity can be proven; keep analytic-shadow replacement as a separate <1% candidate.
4. **ResourceUsage metric-demand gating** — add GPU/temperature/disk demand leases so persistent CPU/RAM-only consumers do not launch unrelated probes/processes.
5. **Default-off capability demand gating** — ThinkFan, battery charge-limit/TLP, Audio sound catalog and Niri native-blur capability should not spawn startup probes until their feature/settings demand exists.
6. **Anti-Flashbang native sampler** — high CPU/process reduction when the opt-in feature is enabled; preserve luminance/policy decisions exactly.
7. **Notification derived-state single pass** — strict-lossless CPU/allocation reduction for long histories without truncating or changing persisted history.
8. **Media artwork shared in-flight resolver** — coalesce identical cache checks/download/copy/stability work across simultaneously visible media surfaces.
9. **Favicon shared resolver/in-flight coalescing** — remove cached-hit Bash spawns and duplicate cache-miss downloads.
10. **Clipboard image decode in-flight coalescing** — keep visibility-lazy behavior but avoid duplicate decode processes for the same entry.
11. **Compact Sidebar Equalizer presentation lease** — release hidden CAVA ownership without changing visible analyzer frames.
12. **WallpaperSkew color-analysis process consolidation** — eliminate one ImageMagick process per uncached image while preserving exact color buckets.
13. **WallpaperSkewView masked delegate layers** — strong transient GPU/RAM candidate while the selector is open.
14. **AltSwitcher skew mask/blur path** — strong interactive GPU candidate with bounded lifetime.
15. **Waffle lock static-wallpaper blur + avatar mask specialization** — potentially valuable because lock screens can remain visible for long periods.
16. **DashboardLayout guarded allocation/CPU work** — strict-lossless if current-dev oracle parity is re-established.
17. **GameMode fallback watchdog research** — small CPU/wakeup candidate with no visual change.
18. **Wallpapers dead catalog-cache removal** — remove the unused duplicated path list/batch rebuild while preserving the public FolderListModel.
19. **GameMode Config-ready-safe Niri reconciliation** — preserve startup-resident GameMode state but prevent pre-config mutation/reload based on fallback defaults.
20. **AppSearch revision-keyed desktop-entry lookup memo** — avoid repeated O(n)-style fallback scans for stable unknown/Electron/AppImage IDs.
21. **Domain-specific Config invalidation narrowing** — WallpaperListener, ThemeService and MPRIS are the cleanest first cuts; ThinkFan/TLP follow with feature-specific regression updates.
22. **Workspace config snapshot guard** — prevent every unrelated Config write from scheduling per-output O(windows) occupancy reconstruction.
23. **MPRIS expired grace pruning** — low-risk cumulative session cleanup; fold pruning into existing lifecycle updates with no timer.
24. **TimerService consumer-gated stopwatch presentation refresh** — only after all consumers are enumerated.
25. **Niri workspace ordered-projection reuse** — remove redundant all-workspace re-sorts from activation/urgency events while preserving record identity and equal-index ordering.
26. **Niri MRU no-op publish suppression** — only after proving duplicate same-id focus events do not intentionally use `mruWindowIdsChanged` as a refresh signal.
27. **Calendar remaining-view batch migration** — reuse the existing `_getEventBucketsForDates()` helper for DashAgenda/Waffle upcoming paths with exact multi-day all-day parity.
28. **Calendar visible-date metadata snapshot** — collapse the 42/70-cell repeated local/external list scans only after count/color/invalidation parity is oracle-covered.
29. **Custom-widget scanner shell builtins** — remove per-manifest `dirname`/`basename`/`cat` child processes after byte/output oracle coverage.
30. **[RETIRED / IMPLEMENTED: `9376fa34f`] LocalMusic dead `folderCollections` retention** — removed from QML; keep historical slot for stable numbering. R16.2 transport/schema optimization remains a separate active candidate.
31. **LocalMusic lean snapshot mode / schema revision** — only if stable `folders` compatibility is explicitly preserved or versioned.
32. **MinimizedWindows stable one-pass workspace selection** — remove two sort-based selectors after tie-breaking oracle coverage.
33. **TrayService one-pass partition** — migrate the revalidated archived tray classifier into current canonical work.
34. **Material SysTray one-pass partition** — independently preserve `bar.tray` + Spotify semantics; do not alias it blindly to the Waffle/generic service result.
35. **Minimized app-count allocation removal** — low-risk micro follow-up after the larger MinimizedWindows selector proof.
36. **Network direct-argv detail refresh** — remove shell/head/awk wrappers only after row-order and failure-state parser parity is covered.
37. **AppSearch identity-rule signal invalidation** — remove per-window JSON serialization after config-reload/replacement parity is proven.
38. **BarTaskbar first-occurrence pinned-rank Map** — eliminate comparator-time pinned-list scans while preserving duplicate/case ordering.
39. **TaskbarApps dead identity revision cleanup** — fold into #37; do not treat as an independent performance project.
40. **GameMode fullscreen derived snapshot** — collapse repeated per-consumer Niri fullscreen scans while preserving any/visible/output fallback distinctions.
41. **DesktopItems shared presentation snapshot** — stop cloning the entire item set once per output on every items revision.
42. **Niri private layout-sorted window view** — remove redundant sort preparation from `sortToplevels()` without changing public window notification behavior.
43. **Settings search normalized registration fields** — eliminate repeated lowercase/join normalization on every keystroke.
44. **Settings search post-top-50 highlighting** — avoid generating discarded highlight markup.
45. **Saved-theme catalog process batching** — reduce `1 + 2T` child processes per visible-editor poll to one Bash + one jq.
46. **WorldClock lazy timezone catalog** — avoid full IANA picker-model allocation unless an editor/picker is actually opened.
47. **LocalMusic active-search haystack cache** — trade bounded search-session RAM for lower per-keystroke normalization/allocation.
48. **Niri active-workspace occupancy snapshot** — share output occupancy across classic/Waffle Background instead of rescanning windows/workspaces per output.
49. **Hyprland Background one-pass workspace summary** — replace filter+sort+some with one scan while preserving id-0 fallback behavior.
50. **Hyprland active-fullscreen find/some** — secondary allocation cleanup for Background/ScreenCorners.
51. **AppSearch DesktopEntry hit/miss memo** — cache exact lookup results per DesktopEntries epoch with immediate invalidation.
52. **MPRIS desktop-entry hint memo** — cache the expensive post-AppSearch fuzzy resolver by cleaned hint.
53. **Notification badge normalized-group index** — move app-name normalization/group scanning to the popup-group rebuild boundary.
54. **Notification object-reference timer cancellation** — remove redundant ID scans inside callers that already own the notification object.
55. **Weather primary direct curl argv** — remove one Bash process from every wttr.in primary request/retry.
56. **ScreenTime startup FileView read** — retire the one-shot test/cat shell while keeping range-history batching unchanged.
57. **Region Selector direct argv cleanup** — remove avoidable outer shells only from recorder/content-region branches.
58. **MPRIS per-player demand-leased position ticker** — MEASURE/ADAPT only until signal timing/freshness contract is defined.
59. **WARP direct status argv** — remove one shell from every open-surface status refresh across all three implementations.
60. **Hyprsunset direct probe argv** — low-risk companion cleanup for explicit/deferred state probes.
61. **ResourceUsage direct GPU argv** — remove Bash from NVIDIA/Intel samples while retaining metric-demand gating as the larger owner.
62. **Settings World Clock one-Bash preview** — eliminate one external `date` process per configured timezone on every 20 s preview refresh.
63. **Sidebar World Clock split metadata/display cadence** — oracle-gated, higher leverage when seconds are enabled.
64. **Media artwork conservative decode bounds** — start with repeated small foreground slots, then card-sized blur sources under a <1% raster/resource oracle.
65. **Wallpaper private thumbnail-map in-place mutation** — remove whole-map copies from pending/known sets after notification-observer proof.
66. **Thumbnail batch READY/FAILED protocol** — let successful batch outputs seed the shared known set and eliminate delegate `test -f` fan-out.
67. **Video first-frame successful-pending cleanup** — delete stale success-side `_ffPending` keys only; leave failure retry policy unchanged.
68. **Wallhaven bounded-cache in-place mutation** — remove O(K) cache/order cloning for private 64/256-entry caches.
69. **Background wallpaper-size cache in-place mutation** — same safe class, lower leverage.
70. **Niri focus-only enriched refresh** — MEASURE/PROVE FIRST; instrument Niri + foreign-toplevel triggers before any fast path.
71. **AppCatalog normalized search index** — move name/description/tag lowercase work from every keystroke to catalog-load time.
72. **AppCatalog install-status model isolation** — stop package-status refreshes from rebuilding an unchanged filtered app model.
73. **Waffle All Apps sorted-base projection** — sort DesktopEntries only on source revision, then filter/group without per-keystroke resort/flatten.
74. **Autostart stable enabled/disabled partition** — evaluate `isAppOn()` once per filtered app and preserve AppSearch alphabetical order instead of comparator-time rescans.
75. **Autostart managed/external membership indexes** — move exact startup-line matching to entries/externalLines rebuild boundaries so row/status lookups are O(1).
76. **Dock Add Applications prepared search projection** — precompute unpinned search haystacks/order outside the keystroke path.

77. **ShellLayoutController internal descriptor references** — retain public fresh-copy isolation but eliminate JSON serialize/parse from internal read-only state/validation paths.
78. **DesktopWidgetLayout revision-scoped read indexes** — stop rebuilding monitor arrays, linear output scans and deep normalized records across repeated widget/output enable checks.
79. **DateTime day-key formatting guard** — keep 1 Hz time where requested while avoiding three date-only locale conversions on unchanged calendar days.

80. **ShellUpdates FileView status reads** — retain the exact 2 s progress cadence and watchdog semantics while removing repeated `cat` child processes.
81. **Waffle Task View one-pass workspace projection** — group windows once per refresh and reuse per-slot arrays/counts for drag/navigation.
82. **Niri published-window ID index** — O(1) first-match lookups for consumers of the committed `windows` snapshot; never substitute it for pending-window logic.
83. **Aqua proactive reminder one-pass selection** — low-priority stable minimum selection that avoids minute-cadence array construction/sort.

84. **TaskbarApps ignored-regex signal cache** — stop recompiling unchanged user/system regexes on every Waffle taskbar computation while preserving invalid-pattern skip/log behavior.
85. **Overview redundant workspace-sort removal** — rely on the verified sorted `NiriService.allWorkspaces` publication invariant and keep output filtering/order exact.
86. **Desktop-clock diagnostics on-demand serialization** — keep `clockDebugState` byte/field semantics but stop continuously maintaining diagnostic JSON/geometry during normal rendering.
87. **AbyssBar module-ID direct equality** — replace dual JSON serialization with ordered string-array equality after Layout normalization.

88. **Shared Hotspot state/process owner** — coalesce duplicate 5 s status polls and start/stop transport across common/Waffle/Classic/Android controls while preserving per-surface demand and five-second external-state freshness.
89. **Abyss Clipboard source-revision search preparation** — parse/lowercase pin/history previews only when clipboard sources change, not on every query character.
90. **Sidebar presentation readiness-gated frame ticker** — stop 16 ms polling while Loader/geometry prerequisites are unavailable and preserve the existing one/two-frame settle only after readiness.
91. **NotificationGroup collapsed latest-two projection** — slice the final two source notifications before reversing instead of reversing the whole group.

92. **Hyprland event-scoped snapshot refresh** — replace unconditional five-process `updateAll()` fan-out with domain-specific refreshes for known raw events plus a safe unknown/config/topology fallback.
93. **Hyprland largest-window workspace index** — build first-strict-maximum workspace ownership during client publication and reuse it from Bar consumers.
94. **Hyprland XKB watched rules index** — parse `base.lst` once per file revision and remove per-layout `cat` + full-file scans.
95. **Internal Todo dedicated FileView reader** — after a focused stale-buffer/watch fixture, replace external-edit `cat` transport without touching the writer FileView contract.

96. **Launcher math scheduling outside results binding** — one qalc schedule per relevant debounced query invalidation, never as a side effect of result recomputation/mathResult publication.
97. **YtMusic resume dirty checkpoint** — retain the 5 s crash-resume checkpoint while suppressing unchanged Config mutations/writes and their global revision fan-out.
98. **Emoji sloppy-search lowercase preparation** — reuse per-list-revision lowercase keys instead of lowercasing up to 100 entries per query.
99. **Bar utility active-order projection** — compute the ordered active utility list once and reuse it for count/index/layout placement.

100. **LocalMusic prepared library metadata** — move per-track lowercase search haystacks, normalized folder paths and stable keys to the `libraryTracks` revision boundary.
101. **LocalMusic timed-lyrics binary lookup** — exploit the producer-guaranteed sorted LRC timeline to replace reactive O(N) active-line scans with exact upper-bound O(log N) lookup.
102. **Background widget power-state complement reuse** — call the per-output pause computation once per widget and derive reduced state as the exact inverse.
103. **Cliphist sloppy-search lowercase preparation** — reuse source-revision lowercase raw-entry keys instead of normalizing up to 100 clipboard rows per query.

104. **Anime schedule same-day in-flight coalescing** — suppress duplicate AniList schedule POST/normalization only when the exact resolved weekday is already pending; keep cross-day freshness independent.
105. **News stale-response pre-parse guard** — move generation rejection ahead of RSS regex parsing so stale 200 bodies do zero parse/allocation work.
106. **Booru manual-preview shared directory readiness** — replace per-thumbnail `mkdir -p` children with one race-safe readiness owner while retaining cache-test/curl/local-file semantics.
107. **Overlay taskbar bounded Angel blur** — crop the screen-aligned Angel wallpaper/effect source to the taskbar plus exact blur support instead of allocating a full-output layer for a small retained taskbar.
108. **Waffle skew Alt Switcher single-pass parallelogram mask** — keep the existing skew geometry/preview/shadow contracts while eliminating the per-delegate content-layer + captured mask chain.
109. **AI catalog append-once publication + provider index** — eliminate repeated concat copies and per-provider full-catalog filters while preserving the single `models` publication boundary and fresh `modelsFor()` arrays.
110. **Merged-calendar prepared sort timestamps** — parse local/external event timestamps once per 30-day list rebuild and sort by the prepared numeric keys instead of reparsing dates inside every comparator call.
111. **Per-owner Niri focused-window hoist** — compute the exact existing published-focus expression once in BarTaskbar, DockApps and Waffle Task View owners instead of rescanning the full window snapshot in every delegate.
112. **Workspaces one-pass representative/occupancy summary** — preserve first-focused/first-window semantics while replacing per-workspace full-list filters and the separate occupancy membership scan with one published-snapshot summary.
113. **Wallpaper Launcher prepared relative-path search keys** — normalize each published wallpaper relative path once per library snapshot instead of once per entry per keystroke.
114. **Cheatsheet lazy prepared search fields** — keep separate lowercase key/modifier/comment/category fields only for the active search session and reuse them across query edits.
115. **AI recommendation pre-score + query-independent recommendation set** — score allowed runnable models once per recommendation rebuild and remove the recommendation sort from model-search text edits.
116. **Liquid Orbital Canvas per-frame node preparation** — prepare each hour node's angle ellipse frame and breathing radius once per Canvas paint, then reuse them across contour, glow, pod and moving-streak samples.
117. **[RETIRED / IMPLEMENTED: `63ea47423`] OrbitalWeather per-quadrant arc-length table reuse** — already uses local tables in `hourAngles`; keep historical slot for stable numbering.
118. **ShapeCanvas allocation-free morph streaming** — stream interpolated cubic segments through one reusable mutable cubic while retaining the exact final-anchor closure rule.
119. **Connected iRiS shared shape-uniform packet** — prepare the common shape/smoothing uniform vectors once per snapshot and share them between visible and shadow-mask iRiS fields.
120. **Settings static prepared family-routed search index** — cache the family-routed static Settings search snapshot and its normalized text fields per translation/family epoch instead of rebuilding them on every query edit.
121. **least_busy_region processed-grayscale reuse** — reuse the exact scaled/cropped grayscale search image for final brightness statistics instead of decoding/resizing it a second time in the same invocation.
122. **Waffle clock records-change process narrowing** — stop global desktop-widget record writes from directly launching Waffle clock image analysis; rely on the clock's actual enable/strategy/geometry/wallpaper invalidations.
123. **least_busy_region padded-integral hot loop** — retain OpenCV's zero border so every sliding-window sum uses the same four integral operands without Python boundary branches; hoist largest-region area from the inner loop.
124. **CustomTheme quick-adjustment prepared HSL baseline** — parse/filter the frozen custom-theme baseline once per adjustment session and reuse ordered HSL metadata across 50 ms slider ticks.
125. **Cava Settings target-specific apply** — apply only the Cava theming target for `appearance.cava.*` edits once palette artifacts exist, instead of regenerating the wallpaper palette and waking unrelated external targets.
126. **DateTime stable calendar/minute snapshot fan-out** — keep the shared clock precision but stop date-only/minute-only external consumers from inheriting 1 Hz invalidation.
127. **Config in-flight overlay clone churn** — optimize only after exact asynchronous save/reload/NOTIFY and JSON-normalization parity; do not weaken existing race protection.
128. **Notepad live word-count allocation** — remove per-edit word-array materialization with exact whitespace/count semantics and no delayed visible stats.
129. **Custom-widget configuration batch deep-copy churn** — first prove per-key custom data NOTIFY/identity, async persistence, source-order and injection parity; then reduce repeated previous-tree cloning without changing external behavior.
130. **EasyEffects graph-reachability guarded adjacency** — measure active topology first; only use the faster traversal for endpoint-complete graph snapshots and retain exact bounded-scan fallback.
131. **ScreenTime historical snapshot projection reuse** — keep every public fresh-return contract; avoid repeated merged range clone work within one Activity refresh, preserving dataChanged/rangeLoaded behavior.
132. **ResourceUsage history copy/append/shift sequence** — profile first and prove native QV4 list mutation/NOTIFY/graph repaint parity before any single-assign or ring-buffer change.
133. **CalendarSync timed-event date-key bucket index** — profile event/date distribution first; preserve NaN, duplicate-date, per-event order, all-day RFC5545 boundaries and QV4 source reactive reads.
134. **MPRIS player/stream name-score normalized-node reuse** — measure mixer/player binding frequency first; preserve each `_streamMatchScore()` identity/total, resolver ordering, QV4 coercion/getter behavior and every selected stream/label/icon before moving repeated normalization outside the inner player-hint loop.
135. **GlobalActions query-token hoist** — split each nonempty action-search query once per `fuzzyQuery` call instead of once per action; preserve every scoring branch, tie order, action identity, empty-query alias and reactive result lifecycle; measure UI latency before implementation.
136. **Events fully-settled reminder Date-parse guard** — evaluate a narrow skip only for records with both notification flags strictly `true`, retaining every unsettled record, recurrence insertion and notification/persistence signal order; native object-coercion/read-order oracle required.
137. **Notepad tab-ID Set normalization** — keep `_normalizeTabs()` behavior and allocation order, replace only the growing seen-ID array membership tests with an invocation-local `Set` of the same canonical strings; measure realistic load and duplicate-ID repair costs before implementation.
138. **Overview window-record ID index** — share a first-wins, snapshot-local safe-positive-int `Map` for `OverviewNiriWidget` delegates instead of repeating `NiriOverviewModel.findWindowRecord()` linear searches; preserve record object identity, malformed-ID fallback and ScriptModel/rebind order; measure active Overview/TaskView window counts first.
139. **SearchWidget shared prefix normalization** — hoist `StringUtils.cleanOnePrefix(debouncedSearchText, [seven live search prefixes])` from every `SearchItem` delegate binding to one owner-scoped reactive string per query/prefix revision; preserve first-prefix order, all custom/overlapping/empty prefixes, exact delegate query values and QML NOTIFY timing; benchmark visible-row fan-out before implementation.

## Explicit non-candidates from this pass

- Do not reopen Screen Edge renderer optimization until live acceptance/measurement provides a new bottleneck; the current path is already aggressively reduced.
- Do not rewrite `AbyssPerimeter.qml` rendering just because it is large; the current file does not show the MultiEffect/capture pattern targeted by this audit.
- Do not optimize `MemoryPressureService.qml` polling: five-minute direct `FileView` reads are already bounded and cheaper than the previous process-spawn pattern.
- Do not merge Audio timers merely to reduce timer count; they are short-lived functional coalescers/ramp control, not idle polling.
- Do not infer cost from Timer/Loader counts alone. Runtime residency, repaint invalidation and source dirtiness must be measured.

## Required evidence before implementation

For every promoted candidate, record:

1. exact parent `dev` SHA;
2. source file/blob SHA;
3. current behavior/lifecycle contract;
4. focused oracle or deterministic regression covering malformed/edge states where applicable;
5. before/after process CPU, RSS and GPU evidence when the candidate claims resource improvement;
6. visual A/B evidence for any visual-path substitution, with normalized global error below 1%;
7. canonical `bash scripts/validate-maintainer-local.sh` result for the exact committed candidate SHA;
8. owner-session compositor validation separately when the change depends on live Niri/Quickshell behavior.

This document is a prioritized research map, not a claim that every candidate will produce a measurable whole-application improvement.

## Research continuation — 2026-10-07

Baseline for this continuation: `7308011b38035c9c3c5f5374bbbea874e6ef1d3b`.

### R2.1 — Bounded wallpaper-glass capture

Source evidence:

- `modules/common/widgets/GlassBackground.qml` blob `0df61709dc3ab6f1667196ca66a1c85c188dd960` uses an Image with `width: root.screenWidth`, `height: root.screenHeight`, then enables a `MultiEffect` layer while the component itself is panel-sized and masked.
- `AngelBackground.qml`, `RicelinSurface.qml` and `ZzzGlassWash.qml` repeat the same screen-aligned wallpaper pattern.
- `BarContent.qml` blob `3afa7aa5e27c069ceed6c3db71d34f1e7ef445d1` and `Dock.qml` blob `a42cff209c3f9239ad0818987af7f50a00e1f645` each create a full-output wallpaper Image and attach a blur `MultiEffect`, while parent geometry clips the visible result to a narrow Bar/Dock body.

Research direction:

1. keep one normal decoded/cached wallpaper source;
2. preserve the exact screen-space PreserveAspectCrop transform;
3. capture/materialize only `visibleSurfaceBounds + exactBlurReach`;
4. blur that bounded texture;
5. crop/mask to the existing body exactly.

The strict-lossless oracle must compare the old/new result for all screen edges, arbitrary panel coordinates, fractional scale, multiple source aspect ratios and blur disabled/enabled. No implementation should rely on a guessed fixed 64 px padding when the effective kernel or scale changes.

### R2.2 — Connected iRiS shadow pass reduction

`modules/common/perimeter/ConnectedSurfaceIrisFrame.qml` blob `e703046f2a527ad30afc1a83ccd71f5e5a78cba7` currently contains:

```text
ConnectedSurfaceIrisField (shadowMaskField)
  -> ShaderEffectSource (shadowTextureSource)
  -> MultiEffect blur (blurredShadow)
  -> ShaderEffectSource crop (isolatedShadow)
  -> visible ConnectedSurfaceIrisField
```

The first promotion candidate is intentionally narrow: prove that `isolatedShadow` can be replaced by exact rectangular clipping/presentation without changing blur sampling or owner-side cutoffs. That would remove one capture texture/pass while leaving the accepted mask field and MultiEffect blur untouched.

A second, separate candidate may adapt the Screen Edge analytic-shadow technique to the iRiS SDF and remove the mask/capture/blur chain entirely. That is not strict-lossless by assumption; it requires a <=1% raster budget plus edge-band and maximum-channel-delta checks.

### R2.3 — ResourceUsage metric leases

`services/ResourceUsage.qml` blob `1d8e8693c230ee7450072366557b6070d433af58` already demand-gates history arrays and network parsing. The remaining lease is coarse:

- first consumer initializes GPU source detection and hybrid-GPU detection even if it needs only CPU/RAM;
- while the service is alive, `diskPollTimer` runs every 30 s and launches `/usr/bin/df -B1 /`;
- process-backed GPU usage may launch `nvidia-smi` or `intel_gpu_top` every 6 s by default (15 s minimum in Low Power);
- `ResourceUsageMonitor.qml` currently exposes only `histories` and `network` demand bits.

Strict-lossless direction: extend the lease with independent `gpu`, `temperature` and `disk` demand. Consumers that display those metrics opt in; when a demand transitions 0 -> 1, prime that metric immediately so the UI never shows a stale value. Existing callers can default to current behavior until every built-in consumer is annotated and contract-tested.

This is especially relevant to persistent Bar/VerticalBar consumers: their monitor already sets `network: false` and `histories: false`, but the service still performs disk polling and GPU work even when the corresponding indicators are disabled.

### R2.4 — Findings deliberately not promoted

- `MemoryPressureService.qml`: already uses a five-minute direct `FileView` read with no watch and no shell process.
- `KeyboardIndicators.qml`: primary state is event-driven through the native input-lock monitor; the recurring LED discovery timer is fallback-only while evdev is unavailable.
- `Battery.qml`: cycle-count refresh is only every 15 minutes.
- `Audio.qml`: 16 ms timers are short-lived queue/ramp control, not idle periodic polling.
- `Backdrop.qml`: static Aurora already uses half-resolution source/effect textures and frozen-video paths release decoders; further work needs measurement rather than generic timer/effect deletion.

## Research continuation — round 3

Baseline: `dev` at `7f6a735269980d0f40ff12fbb4f5799b2e180d11`.

### R3.1 — Anti-Flashbang process-chain removal

Current source identity:

- `services/AntiFlashbangSampler.qml`: `eecb90a0aedd07a4376772883d2b46010fa3a533`;
- `services/Brightness.qml`: `2a67e59a2aaca66e915f9d4bd3ab9ca06cb95e80`;
- default config keeps `light.antiFlashbang.enable=false`, `sampleInterval=500`, `sampleScale=0.10`.

The current sampler invokes, per active output and periodic sample:

```text
timeout
  -> /bin/bash -o pipefail
       -> grim -o OUTPUT -s SCALE -t ppm -
       -> magick ppm:- -colorspace Gray -format '%[fx:mean*100]' info:
```

This is intentionally not classified as a default-idle Hadalis cost because the feature ships disabled. Once enabled, however, it is a high-frequency process pipeline and therefore a high-confidence optimization target.

Strict-lossless research path:

1. keep output selection, scale, timeout, generation, pending/debounce and failure backoff unchanged;
2. replace only the shell/ImageMagick reduction portion with a small native streaming PPM reducer, or a direct native capture path if the existing compositor API can provide identical sampled pixels;
3. build a corpus oracle containing generated RGB frames, gradients, near-threshold frames, real `grim` captures and malformed/truncated PPM;
4. compare native mean against the current ImageMagick result and then run both through `antiFlashbangPolicy.js`;
5. require identical policy branch/multiplier results at every threshold-boundary case before calling it strict-lossless.

Do not optimize by merely increasing `sampleInterval` or reducing `sampleScale`; those are behavior/quality changes and belong to a separate user-controlled tradeoff, not this strict-lossless program.

### R3.2 — Warm preview cache is bounded, not a leak

`services/WindowPreviewService.qml` at `2bfca7368179e3f6cbaff32ac0375daa49ab8a38` explicitly caps decoded warm previews at 12 images of 768×512 and documents approximately 18 MiB of CPU pixel residency. It also destroys entries as the LRU-style order exceeds that limit.

Conclusion: do not classify this as an unbounded RAM bug. A pressure-aware eviction hook could reclaim RAM while keeping disk snapshots, but it changes first-open decode latency and therefore is only a conditional RAM/latency tradeoff. Measure RSS and presentation latency before promotion.

### R3.3 — Existing process-polling work that should not be rediscovered

- `RecorderStatus.qml` at `7e221f7168f42c5348f4b07fe7ae8a0827c6a946` already separates slow 15 s/30 s external-recorder discovery from 1 s UI-demand polling and bounded action checks.
- `MprisController.qml` at `3a8184f9308f0816ea395ea26f182bb5a3fbcf15` no longer performs unconditional construction-time `pw-dump`; stream metadata refresh is triggered by relevant audio/player state. This matches the earlier optimization research and should not be promoted again.
- `TlpRuntimeCapabilities`, `PowerProfilePersistence` and `ThinkFanService` use sparse safety cadences and/or feature/runtime demand. Historical startup notes must be checked before any new promotion so removed/evolved startup debt is not counted twice.

### R3.4 — Cache sweep conclusion

The cache sweep did not find a new high-confidence unbounded core RAM cache:

- AltSwitcher/Waffle icon caches are capped at 100 entries.
- Window preview warm decode is capped at 12 entries.
- Settings page retention is capped.
- Wallhaven tag/suggestion caches have explicit limits.
- Background wallpaper-size metadata cache is capped.
- Anime schedule cache has a small finite day-key space.
- AppSearch caches are proportional to the installed DesktopEntry set and intentionally avoid repeated fuzzy-preparation work.

`NewsService` keeps feed responses by feed URL for the lifetime of the deferred singleton, but its practical key space is tied to a small fixed topic/mode set. It is lower priority than the render-pass and process-spawn candidates above unless RSS evidence shows otherwise.

## Research continuation — round 4

Baseline: `dev` at `b9821ec8f3959b075e8c7a0a60d902baa8c472c0`.

### R4.1 — Notification derived-state fusion

Current source: `services/Notifications.qml` at `a05c6744c123d8ed96ee19c8d04cccdbcdeeae0e`.

The current `_updateGroups()` pipeline performs:

```text
list.filter(popup)                 ~ N
list.forEach(latest-per-app)       ~ N
_groupsForListOptimized(list)      ~ N
_groupsForListOptimized(popupList) ~ P
sort full app names                ~ G log G
sort popup app names               ~ Pg log Pg
```

where `N` is retained history length and `P` is the popup subset. The repository has no configured notification-history count/age cap, so this path scales with long-session history.

A strict-lossless replacement can traverse `root.list` once and construct:

- `popupList` in original list order;
- `latestTimeForApp`;
- full groups, preserving the first encountered `appIcon`, notification order and critical flag;
- popup groups, preserving the first popup notification's icon and popup order.

After the pass, set both full and popup group `time` from the completed **full-history** `latestTimeForApp`, because that is what the current two-stage implementation does even for popup groups. Then sort the same group-key sets with the same comparator.

Required oracle: randomized histories including duplicate app names, equal timestamps, mixed popup state, critical urgency, empty names and mutation sequences. Compare public `popupList`, `latestTimeForApp`, group object fields, notification reference identity and app-name ordering.

This candidate deliberately does **not** cap history or alter persistence; those would change user-visible/history semantics.

### R4.2 — Favicon cached-hit and duplicate-miss process churn

Current source: `modules/common/widgets/Favicon.qml` at `3d7e24e97236e53a174c977736d75e5ed850871d`.

Every component completion starts:

```text
bash -c '[ -f CACHE ] || curl ...'
```

Therefore a cache hit still creates a shell process. Multiple simultaneously materialized delegates for the same uncached domain have no shared in-flight owner and can race into duplicate shell/curl work.

Research path:

1. centralize per-domain state: `unknown / loading / ready / failed`;
2. let cached files resolve without a process spawn;
3. permit only one download owner for a domain;
4. preserve `curl -f --remove-on-error` semantics or an equivalent direct fetch failure contract;
5. publish the same cache URL to all waiting Favicon instances;
6. retain bounded/explicit retry behavior for failures and define corrupt-cache behavior rather than silently changing it.

Measure cold-cache and warm-cache child-process counts across Search, AI source chips and other multi-item surfaces. The primary claim should be process-count/CPU reduction, not GPU improvement.

### R4.3 — Compact Sidebar hidden Equalizer ownership

Current source:

- `modules/mediaControls/EqualizerPanel.qml`: `2be0c2479bd26bc259077a3a2f07e32ba0b1782a`;
- `modules/sidebarRight/CompactSidebarRightContent.qml`: `da5520299f6562a484b31fe8c3a449ab54abab73`;
- `modules/common/widgets/CavaProcess.qml`: `c8c5e5ea82181d2a28c8af4839920305edad6610`.

The compact sidebar keeps the Controls section loaded unconditionally:

```qml
active: sectionItem.isBase
    || sectionItem.isCurrent
    || Math.abs(root.activeSection - sectionItem.index) <= 1
```

Inside Controls, the Media subsection materializes an `EqualizerPanel` with:

```qml
active: root.panelVisible
```

The Equalizer's CAVA wrapper holds a shared service lease whenever `active` is true. Its Canvas clock is `running: root.active && analyzerCanvas.visible`; ancestor visibility can suppress paint, but it does not release the explicit CAVA lease.

A candidate should therefore target **subscription ownership**, not delete the 33 ms visual clock. That clock intentionally drives the electric-wire `Date.now()` motion while the analyzer is visible.

Strict-lossless boundary: keep the subscription through any period in which Controls can contribute pixels during the section crossfade. If direct navigation can jump from a distant section to Controls, prove that pre-acquisition still supplies the same first visible spectrum frame; otherwise classify the release as a tiny presentation-latency tradeoff rather than strict-lossless.

### R4.4 — Existing optimizations confirmed, not re-promoted

- `AppSearch.qml` already has a limited-result top-N path that avoids allocating/sorting the full score-record set, and lazy prepared-name/icon arrays are revision-cached.
- `MprisController.qml` already moved `pw-dump` behind relevant stream state, matching earlier research.
- Niri window updates already use pending/published batching for presentation churn. The remaining GameMode live-state idea is already tracked in this audit and must preserve the batching contract rather than bypass it globally.
- Notification timer/object destruction on explicit discard is already correct; the new target is repeated derived-state traversal, not orphan cleanup.

## Research continuation — round 5

Baseline: `dev` at `481f9f44cef96e21178b741eb27c743fba4c4cd2`.

### R5.1 — WallpaperSkew color-analysis process consolidation

Current source: `modules/wallpaperSelector/WallpaperSkewView.qml` at `5357519b2dfb96cf2fa7bc52cb239df11d30b974`.

The current color path is still present on current `dev`:

- `_analyzeUncachedColors()` is called after cache load/failure, component completion, count changes and folder changes;
- default mode remains `sortMode: "date"` and `colorFilter: -1`, so uncached color work is not demand-gated by actual color sorting/filtering;
- each batch contains at most 20 images;
- one Bash process is created for the batch, but that script invokes `convert` once for every image:

```text
for each uncached image:
    convert IMAGE -resize 1x1! -colorspace HSL
        -format '%[fx:hue*360] %[fx:saturation] %[fx:lightness]' info:
```

For a folder with `N` uncached non-video images, the current design therefore performs approximately `ceil(N/20)` Bash launches plus `N` ImageMagick child executions.

The preferred strict-lossless direction is **process consolidation**, not simply delaying work:

1. create one helper invocation per batch (or one long-lived bounded request) that reads all batch images itself;
2. emit the same `name<TAB>hue saturation lightness` logical records;
3. preserve sequential result association, per-image failure isolation and current bucket rules;
4. compare against ImageMagick over representative JPEG/PNG/WebP/GIF/static-frame inputs and threshold-boundary HSL values;
5. retain asynchronous batching so UI navigation is not blocked.

A native implementation can be considered only if decoder/color-space behavior is qualified against the current ImageMagick reference. Merely replacing HSL math with an approximate formula is not sufficient for a strict-lossless claim.

### R5.2 — Cache identity prerequisite

The color database is currently addressed by bare `fileName` rather than normalized full path. Two different folders containing the same filename can therefore reuse one color record.

This is a correctness constraint for any optimization:

- a new analyzer must not make the filename collision harder to migrate;
- a path-aware or content-aware key should be evaluated as a separate correctness change;
- performance measurements must distinguish analysis avoided by a valid cache hit from analysis incorrectly skipped because of a filename collision.

The optimization table does not count correcting this identity bug as a resource gain.

### R5.3 — High-frequency timer sweep

A targeted 16/33 ms timer sweep did not justify additional generic timer consolidation:

- `AbyssWaveController` already sleeps when the simulation settles;
- `Audio` 16 ms timers are bounded queue/ramp control;
- `EqualizerPanel` uses its 33 ms clock for intentional continuously animated electric-wire geometry via `Date.now()`; deleting the clock would change pixels;
- common slider/search/background timers found in this pass are interaction/debounce/safety timers rather than unconditional idle animation loops.

Therefore timer count alone remains a rejected optimization heuristic. The higher-value action is to release the owning presentation/service lease when a surface cannot contribute visible pixels.

## Research continuation — round 6

Baseline: `dev` at `5cfb6cc9cc6cb1a4b782362b3137343e4fa8d83e`.

### R6.1 — Pre-QML environment cache is not actually shared

Current source: `scripts/inir` at `5cf6ca0ef112cf0f98ee28f23cc618cbb34d5018`.

The launcher declares:

```bash
_cached_systemd_env=""
_cached_systemd_env_fetched=false

_get_systemd_user_env() {
    if [[ "$_cached_systemd_env_fetched" == true ]]; then
        printf '%s' "$_cached_systemd_env"
        return 0
    fi
    _cached_systemd_env_fetched=true
    _cached_systemd_env="$(timeout 3s systemctl --user show-environment 2>/dev/null)" || true
    printf '%s' "$_cached_systemd_env"
}
```

but both main consumers use command substitution:

```bash
_qs_sys_env="$(_get_systemd_user_env)"
sys_env="$(_get_systemd_user_env)"
```

Bash executes command substitution in a subshell. Therefore `_cached_systemd_env_fetched=true` and the snapshot assignment do not persist to the parent shell. On both the normal path and session-boot path, `apply_qt_runtime_env()` can perform the first bounded `systemctl --user show-environment`; the subsequently backgrounded `ensure_systemd_graphical_env &` inherits the parent state in which the cache is still unfetched and can perform the second call while Quickshell is starting.

Strict-lossless research direction:

1. add a parent-shell population function that mutates the two cache variables without command substitution;
2. let consumers read `$_cached_systemd_env` directly after population;
3. parse the multiline snapshot once into presence/value helpers rather than repeatedly spawning `grep | head | cut` and `grep -q`;
4. preserve all existing fallback socket/environment detection and the 3 s fail-open deadline;
5. add a shell contract test with a fake `systemctl` that counts calls and proves both consumers observe the same snapshot.

This is a structural correctness fix to the intended cache contract as well as a startup optimization.

### R6.2 — ABI cache lookup occurs after an avoidable process

The same launcher calls `qs --version` at the beginning of `check_qs_abi()`, then computes the mtime-keyed `v2:<qs_mtime>:<qt_mtime>` cache and returns immediately when that cache matches.

On an unchanged successful installation, the expensive `strings` scan is correctly skipped, but the `qs --version` process has already been launched.

A safe fast path can compute exact binary/library identity first, compare the successful cache, and return before `qs --version` only when both identities match the previously validated pair. Any changed/missing identity falls through to the current full mismatch checks. The cache must remain **success-only**; never cache or bypass a prior mismatch.

### R6.3 — Default-off feature probes are still startup-owned

Verified current source identities:

- `shell.qml`: `aae76205a819e9b098f6a4be7fb6d56e14ff4900`;
- `ThinkFanService.qml`: `943082413a143df3e642ee3d60587093dda1ec02`;
- `Battery.qml`: `e276ddc01dcbe01977e1f285ed2c7dc46e5928d2`;
- `TlpService.qml`: `4e0ef4fba76eb00df7ddc54941e205029dde07ec`;
- `Audio.qml`: `03e2286f1e4035113ba33523c196aca27904cdcc`;
- `SoundPicker.qml`: `c9f041163d1572230dee136e48efc735bc01a65c`;
- `Appearance.qml`: `55480307855a511518206c8dbea5e5eb20d76c33`.

The four ownership splits are independent:

**ThinkFan**
- shell has `property var _thinkFanService: ThinkFanService`;
- default `powerProfiles.fanControl.enabled=false`;
- `ThinkFanService.Component.onCompleted: root.refresh()`;
- detector command is `/usr/libexec/inir-thinkfan --status`.

**Battery charge care**
- default `battery.chargeLimit.enable=false`;
- ordinary Battery singleton binds `TlpService.available/supported/.../statusReason` unconditionally;
- `TlpService.Component.onCompleted` calls `_detect()`;
- detector command is `/usr/libexec/inir-battery-charge-limit --status`.

**Audio theme sound catalog**
- Audio's microphone state refresh is legitimate startup work;
- the same completion handler also starts `themeSoundsProc`;
- that process is `/bin/sh -c 'ls ... | sed ... | sort -u'`;
- repository search finds `Audio.themeSounds` consumed only by `SoundPicker`, whose call sites are Settings surfaces.

**Niri native blur capability**
- Appearance unconditionally runs `niri --version` on Niri;
- default `performance.blurBackend="auto"`;
- `blurBackendFor()` explicitly returns wallpaper/off for `auto`, never compositor blur;
- `nativeBlurSupported` is otherwise a capability input for explicit compositor blur and Settings visibility.

These should be tested as four small demand gates rather than one large lifecycle rewrite.

### R6.4 — Media artwork work is atomic but not coalesced

Current `MediaArtworkResolver.qml`: `801d6422216b4b5f8e1ed31111b27010b963006e`.

The resolver is instantiated by at least six repository call sites, including the shared media artwork widget, Bar media, PlayerBase/PlayerControl, YT Music card and CavaTheme.

For one deterministic cache identity, every resolver instance owns its own:

- `/usr/bin/test -s` cache check;
- local `file` MIME check;
- local copy-to-cache pipeline;
- file-size stability checker with two `stat` calls and a 200 ms sleep;
- base64 decode writer;
- remote curl/MIME-validation pipeline;
- retry timer.

The cache file publication is atomic, so concurrent writers should converge safely, but duplicate operations still occur before one wins. A shared resolver should own the in-flight state while each visual consumer retains its own presentation generation/display-source state. This distinction avoids coupling UI transitions to another surface's lifecycle.

Required oracle should cover: remote success/failure/retry, simultaneous identical consumers, source switch during in-flight download, local file initially incomplete then stable, non-image local source, data URI, consumer destruction, and old-art retention.

### R6.5 — Clipboard decode has the same atomic-without-dedupe pattern

Current `CliphistImage.qml`: `d210fa7c52aba17fddec09909cc464fe034ffa03`.

The component correctly waits for visibility before decoding and uses a process-unique temporary file followed by atomic `mv`. Its own comment explicitly notes that multiple clipboard surfaces can render the same entry concurrently.

For an uncached entry, simultaneous Clipboard/Search/Waffle presentation can therefore launch more than one:

```text
bash
  -> cliphist decode ENTRY
  -> temporary file
  -> atomic mv to shared session cache
```

The optimization is not to make decoding earlier. Keep the current visibility gate, but centralize `entryNumber -> loading/ready/failed` ownership so one visible consumer triggers the decode and other visible consumers await the result.

### R6.6 — Theme/icon synchronization remains measurement-gated

Current source confirms the older startup concern still exists:

- shell invokes `ThemeService.applyCurrentTheme()` and `IconThemeService.ensureInitialized()` as soon as Config is ready;
- auto theme queues external `applycolor.sh` after 600 ms and default-enabled Vesktop generation;
- saved icon theme restoration starts `gsettings set` and then native desktop-icon synchronization;
- FontSyncService separately reconciles desktop fonts later.

This can create startup process waves, but moving them changes **when external applications** observe the persisted theme. Do not classify deferral as strict-lossless until a startup trace shows material contention and acceptance defines the external synchronization boundary. Shell-internal color/icon identity must remain available immediately.

### R6.7 — Bootstrap cleanup / identity lookup stay measure-first

`Directories.qml` at `0fb9ae0b8ce77bb5b280c3aef16c9b3d22d73f27` already made the important improvement: many independent cleanup/create processes became one ordered Bash invocation. Do not split it back into process fan-out.

`SystemInfo.qml` at `d62d67334070ac34070d113d6316d4d0152327e5` seeds `username` from `$USER` but still schedules `getent passwd USER` immediately for the GECOS display name. Both this lookup and transient feature-directory cleanup are lower priority unless a startup trace attributes measurable delay/I/O to them.

### R6.8 — Current ranking implication

This round changes the audit emphasis: before implementing more low-frequency QML micro-optimizations, obtain a startup trace around the pre-QML launcher and default-off probes. The environment-cache defect has a bounded **seconds-scale worst case**, whereas many later candidates save only a handful of short child processes. That makes it the highest-value CPU/startup candidate found after the rendering work.

## Research continuation — round 7

Baseline: `dev` at `22b0a5fc4039c4f8baee3feb4f3ae781da035cd2`.

### R7.1 — MPRIS grace state has real stale-key growth

Current `services/MprisController.qml`: `3a8184f9308f0816ea395ea26f182bb5a3fbcf15`.

The grace contract is only:

```qml
const graceTime = _playerGrace[name]
return graceTime && (Date.now() - graceTime) < 2000
```

but each valid metadata update does:

```qml
let nextGrace = Object.assign({}, _playerGrace)
nextGrace[name] = Date.now()
_playerGrace = nextGrace
```

No source path deletes expired names. Long-running browser sessions, transient mpv instances and other players with unique D-Bus instance names therefore leave behaviorally dead entries behind. Those entries cost both retained JS memory and clone time on every later grace update.

Strict-lossless direction:

1. during an existing rebuild/grace update, construct the next map from entries whose timestamp is still inside the same 2 s window and/or whose current player is still relevant;
2. update the current player timestamp as today;
3. do not introduce a cleanup timer;
4. add a deterministic clock-based test that compares `_isInGracePeriod` before/after for boundary timestamps and proves stale keys disappear.

This is lower absolute value than startup/render candidates, but unlike speculative cache trimming it has no useful stale-data hit to preserve.

### R7.2 — LaTeX session cache is semantically active

Current sources:

- `services/deferred/LatexRenderer.qml`: `7447b36177da576b25aba5018560ccfaad519d00`;
- `modules/sidebarLeft/aiChat/MessageTextBlock.qml`: `e877c5c8e90a9a0ab06ead0c8bf687141d4721ba`.

A first static read suggested three unbounded structures might duplicate data. Cross-reference disproves a simple deletion:

- `processedHashes` deduplicates in-flight/completed requests;
- `renderedImagePaths[hash]` is read when applying the generated Markdown image;
- `processedExpressions[hash]` is read on `renderFinished` to replace the original expression and is also needed for duplicate completion handling.

Therefore these structures are an intentional session cache, not dead retention. The SVG output directory is reset on shell startup by `Directories`, so growth does not persist across sessions.

Only promote an LRU/count-byte bound after measuring a long LaTeX-heavy chat. The oracle must include already-rendered visible messages, revisiting an old expression after eviction, simultaneous duplicate requests and render failure/retry. The expected tradeoff is lower RAM versus additional MicroTeX process work.

### R7.3 — CustomImageWidget suspension keeps the current video pipeline

Current `CustomImageWidget.qml`: `cc9e05d2775713489a58146d38c4044adedd8267`.

The existing lifecycle is already careful:

- folder rotation stops when `!powerActive` or invisible;
- stale transition slot clears `sourcePath` after the transition;
- GIF playback is gated by visibility/power/animation policy;
- a MediaPlayer is only constructed for slots that actually own a video.

For the **current** video slot, however:

```qml
Loader {
    active: slot.isVideo && slot.sourcePath.length > 0
    sourceComponent: MediaPlayer { source: ... }
}
```

remains active during power suspension. `syncVideoPlayback()` pauses the player once a frame exists rather than clearing the source or destroying the loader.

This may intentionally preserve decoder state and instant resume. Before changing it, record PSS/RSS, render-node/decoder threads and resume-to-first-frame for:

- visible playing video;
- power-suspended for 5 s / 60 s;
- hidden desktop/widget;
- resume after each duration.

A delayed teardown (for example only after sustained suspension) is a RAM/latency policy candidate, not currently a strict-lossless optimization.

### R7.4 — Abyss full-screen fragment early rejection needs a proof, but potential is large

Current sources:

- `AbyssField.frag`: `98719594e2752d5938a02540d47aab0523ebd5d0`;
- `AbyssField.qml`: `e90297e341430c8745b53cc7ade05410092bb819`;
- `AbyssWaveController.qml`: `43f066c05d75d49adff40fdd45343515c69eec97`.

Current shader order:

```text
waveProfile(p)
  -> potentially up to 4 waveAt paths
waterInteraction(p)
field(p)
  -> workspace-hole SDF
  -> up to 40 record() roundedBox/fuse evaluations
dFdx/dFdy/fwidth
if d > 24 -> transparent
material/wallpaper/specular/shadow work
```

The Wave controller already computes `crestPeak`; however `AbyssField.qml` currently passes only wave texture width/active state/effects in `waveMaterial`, not crest height. Surface records carry exact rectangles but there is no precomputed per-edge maximum inward reach uniform.

A safe experiment can compute on the CPU/QML side, whenever records/insets/wave/contact state change:

```text
topReach, rightReach, bottomReach, leftReach
    = maximum inward extent of all active edge-attached records
    + connection/smooth-union radius
    + maximum active wave crest
    + bounded water-contact/ripple displacement
    + 24 px existing shadow/glow exit band
    + AA/refraction safety
```

Then a fragment whose distance from **every** physical edge exceeds the matching conservative reach is guaranteed to remain transparent and may exit before wave sampling/SDF union. This must be proven against corner joins, center/large utility surfaces, editor previews, max-size popups and water interactions. If any content class is not edge-bounded, disable the fast reject for that frame instead of guessing.

Because the ShaderEffect covers the full output, a correct reject could save work over a large fraction of 1440p/4K pixels. No resource percentage is claimed until GPU/frame-time measurement.

### R7.5 — Classic Bar Settings is a local residency opportunity only

Current `BarConfig.qml`: `13857cee12d5d1616476cc0e86fce7b714160df9`.

The page uses an `activeSection` selector, but the large `SettingsCardSection` trees are instantiated normally and only hidden with `visible`. This is distinct from `SettingsPageHost`, which is already bounded and should not be redesigned.

Measure QML object count/RSS/page-open time first. If material, a section loader should:

- instantiate the selected section synchronously enough that search/task navigation remains responsive;
- optionally keep the previous section for a short bounded residency window;
- preserve every config binding and `SettingsTaskNavigator` target;
- unload all section content when the host unloads the page.

This is lower priority because cost exists only while that Settings page is resident.

### R7.6 — PowerProfilePersistence cannot simply be delayed under strict-lossless rules

Current `PowerProfilePersistence.qml`: `b014a90512ad93e94a4e43ffb38aa121f64c309d`.

It probes TLP-PD ownership immediately at Config readiness, because applying a persisted profile before knowing ownership could fight `tlp-pd`. Conversely, deferring the entire probe delays shell-owned profile restoration when `tlp-pd` is absent.

Therefore the process is not equivalent to the default-off ThinkFan/TLP-charge probes from round 6. Moving it after first frame is a timing/power-policy change. Keep this as measurement-only unless the ownership answer can be obtained through a cheaper equivalent event/state source without changing restore timing.

### R7.7 — Window preview concurrency remains an A/B benchmark, not a static conclusion

Current capture helper `1375bd607bb522dca1218ddc581e638829ed25e5` defaults:

```bash
max_concurrent="${INIR_WINDOW_PREVIEW_CAPTURE_CONCURRENCY:-2}"
[[ ! "$max_concurrent" =~ ^[1-4]$ ]] && max_concurrent=2
```

The lifecycle regression explicitly requires bounded two-way default concurrency. Serializing to one capture may smooth compositor/clipboard pressure, but necessarily lengthens a multi-window refresh if individual captures are independent.

Benchmark concurrency 1 and 2 with identical window sets and collect:

- total batch time;
- first-preview publication latency;
- compositor/GPU spikes;
- clipboard restoration duration;
- failed/closed-window behavior.

Do not change the default on static reasoning alone.

## Research continuation — round 8

Baseline: `dev` at `01a898d046e4e33c99f4e1d1e1268d4d27cf9e62`.

### R8.1 — Service residency and expensive-work residency are separate contracts

Current `shell.qml` still documents Tier 3/Tier 4 service assignment, but QML dependencies can materialize a singleton earlier:

- `Appearance` references GameMode, so GameMode cannot be considered truly delayed until the Tier 3 assignment.
- Classic/Abyss bar components can reference `Weather` and `ShellUpdates` before shell assigns `_weatherService`/`_shellUpdatesService`.
- this is not itself a bug: reactive state may legitimately be needed before the expensive background task.

The useful contract is therefore:

```text
singleton may exist early
heavy maintenance/network/process work has a separate idempotent owner/arm point
```

Do not wrap ubiquitous state singletons in fragile Loaders only to satisfy tier comments. Instead, when a service still has expensive eager work, expose an explicit `startDeferredWork()`/lease only for that work and make shell tiering own the call.

### R8.2 — Weather is early-resident but its heavy work is already delayed

Current `Weather.qml`: `53ef5db3a161e6df18a29b1e6a7c6192d2e35a79`.

Shipped Bar weather is enabled, so Weather can be instantiated by first-frame Bar bindings before `_ensureDeferredFeatureServices()`. The service itself, however, does not immediately resolve IP/GPS/location or fetch weather. It owns a 3000 ms `startupDelayTimer` and only begins location/weather work when enabled, Config-ready and not already initialized.

This already keeps the network/process burst away from first-frame formation. Replacing it merely because the singleton appears before Tier 3 would add complexity without a demonstrated saving.

### R8.3 — ShellUpdates is early-resident, but separates resume-state and remote work

Current `ShellUpdates.qml`: `51e7eff2300e169ee0021673757dc9f4f79556d9`.

The update indicator can materialize this singleton before Tier 4. Current work naturally splits into:

- ~1 s: restore an in-progress update marker so a shell restart during `setup update` can recover the progress indicator;
- ~5 s: load/resolve repository and perform the normal shell-update check;
- configured periodic checks later.

The 1 s resume path is correctness/continuity work, not generic background maintenance. The remote/repo path is already delayed beyond first frame. No source-only reason currently justifies moving either path.

### R8.4 — GameMode has a real Config-readiness race

Current `GameMode.qml`: `692f3e200b7c46835f44f152c88f231e2d0bd2b5`.

Initialization starts a 200 ms init timer; on Niri that starts a further 900 ms `startupNiriSyncTimer`. The reconciliation has no `Config.ready` prerequisite. Meanwhile:

```qml
readonly property bool controlNiriAnimations:
    Config.options?.gameMode?.disableNiriAnimations ?? true
```

so a sufficiently slow Config load can execute Niri mutation under fallback `true`, even when the user's eventual value is false.

Safe direction:

1. keep state-file loading/fullscreen observation early;
2. add a one-shot startup Niri reconciliation request;
3. if Config is not ready, mark pending and do not mutate;
4. on Config ready, consume pending exactly once and evaluate final `controlNiriAnimations`;
5. if disabled, finish without a process;
6. if enabled, retain current reconciliation semantics.

### R8.5 — Do not skip Niri reload solely because file text already matches

Current `setNiriAnimations()` applies `sed -i` and then runs `niri msg action reload-config`.

A compositor can remain alive while the shell restarts. The file can already hold the desired value while Niri runtime state is stale because an earlier external edit was never reloaded or a reload failed. Therefore “file unchanged” does not prove “runtime reconciled.”

Only suppress reload if authoritative runtime animation state becomes queryable or another startup owner guarantees a reload from the same snapshot.

### R8.6 — MPRIS optional enrichment has one remaining eager probe

Current `MprisController.qml`: `3a8184f9308f0816ea395ea26f182bb5a3fbcf15`.

`pw-dump` is no longer unconditional, but completion still starts `_mpdMprisProbeProc`, which runs Bash to test `mpd-mpris` and `pgrep -x mpd`. This supports direct-ALSA MPD, where PipeWire cannot trigger discovery.

First-frame deferral is plausible but changes when an already-running MPD player becomes visible, so retain as A/B research rather than strict-lossless promotion.

### R8.7 — YtMusic dependency probes are already correctly gated

Current `YtMusic.qml`: `063ef1bd591d222d9a60b240dec218c1c4171213`.

Despite direct singleton references from MprisController, YtMusic only calls `_initialize()` when `sidebar.ytmusic.enable` is true. Its orphaned-mpv cleanup, dependency probes, browser detection, data load and OAuth/session restoration therefore remain dormant when the feature is disabled.

This is the desired state-vs-expensive-work pattern and should be preserved.

## Research continuation — round 9

Baseline: `dev` at `05f7e7f75416545f16ab67eca6ec017c5dc1bc43`.

### R9.1 — Wallpapers builds a dead duplicate catalog on every folder count change

Current `services/Wallpapers.qml`: `162dc98dcb742d7dec918a1da01659ef64265330`.

The service exposes the live `FolderListModelWithHistory` directly:

```qml
property alias directory: folderModel.folder
property alias folderModel: folderModel
readonly property bool folderModelReady: ...
```

and all repository consumers use `Wallpapers.folderModel`, `folderModelReady`, `effectiveDirectory`, `searchQuery` or direct helper methods.

Separately, the service owns:

```qml
property list<string> wallpapers: []
property int _wallpaperCacheIndex: 0
property var _wallpaperCacheBuilder: []
property int _wallpaperCacheBatchesSincePublish: 0
```

plus `rebuildWallpapersCache()`, `appendWallpapersCacheBatch()` and a zero-delay `wallpaperCacheTimer`. `folderModel.onCountChanged` always starts this batch copy.

Repository-wide search finds **no read of `Wallpapers.wallpapers`**. Inside the file, the property is only cleared and assigned from `builder.slice()`.

That makes this a strict-lossless source cleanup for current repo behavior:

1. remove the unused path-list property and its builder/index counters;
2. remove both rebuild functions and the zero-delay batch timer;
3. remove only the `onCountChanged: root.rebuildWallpapersCache()` side effect;
4. keep the actual `FolderListModelWithHistory` and all navigation/search/history behavior untouched.

For a directory with N items, this avoids copying every file path into a second JS/QML list and avoids repeated partial `slice()` publications every four 64-item batches.

### R9.2 — The wallpaper directory model itself is a separate, larger residency question

Current model implementation: `modules/common/models/FolderListModelWithHistory.qml` at `2aeb3e712dbf3f3ad9e7c0d67a1250b7373fa0ca`.

`Wallpapers.defaultFolder` resolves to `Directories.wallpapersPath`, which defaults to `~/Pictures/Wallpapers`. The `FolderListModelWithHistory` is constructed as soon as Wallpapers is resident and immediately points at that directory.

Yet startup-critical wallpaper rendering does not need the directory catalog. It needs current configured paths, per-monitor mapping and video-first-frame helpers. The catalog is consumed by:

- Wallpaper Selector/Coverflow;
- Quick/Background Settings wallpaper grids;
- random-from-current-folder actions;
- auto-wallpaper cycling.

This suggests a larger memory/I/O opportunity: separate “current wallpaper state/apply helpers” from “directory catalog ownership.”

Do **not** promote this from static reading alone. A lazy model changes the first random/selector interaction unless an on-demand catalog can be primed fast enough. Benchmark at least 100, 1,000 and 10,000 files and record:

- shell startup CPU/I/O;
- RSS before selector open;
- first selector-open latency;
- random shortcut latency;
- folder-history/search behavior after close/reopen.

If the directory model is material, prefer a demand lease such as `selector/settings/random/autoWallpaper` rather than keeping it permanently alive solely for `randomFromCurrentFolder()`.

### R9.3 — AppSearch has a safe memo boundary around expensive fallback identity matching

Current `services/AppSearch.qml`: `74ea3c9e92860af62f10850c89118d79b7837543`.

At startup `_rebuildCache()` builds three reverse maps:

- StartupWMClass -> DesktopEntry;
- executable basename -> DesktopEntry;
- desktop-id stem -> DesktopEntry.

The maps are required early because Taskbar/Dock/IconThemeService/MPRIS and other visible surfaces call `lookupDesktopEntry(appId)`.

For simple IDs, Quickshell heuristic lookup or direct map lookup is cheap. For an unknown/scoped/Electron/AppImage ID, the function can continue through:

- scoped/path segment normalization;
- suffix stripping;
- token extraction;
- `Object.entries(_desktopIdStemMap)` scan with per-key tokenization;
- `Object.entries(_startupClassMap)` scan with per-key tokenization.

The same stable app IDs are resolved repeatedly by taskbar buttons, previews, dock buttons, media-node icon matching and other bindings. There is currently no result memo.

Strict-lossless direction:

```text
lookupMemoRevision
lookupMemo: exact input string -> DesktopEntry | explicit MISS sentinel
```

At the start of `lookupDesktopEntry`:

1. empty input preserves current null result;
2. if memo revision equals `_cacheRevision` and the exact input is present, return cached hit/miss;
3. otherwise execute the current lookup byte-for-byte;
4. cache the final result;
5. when `_rebuildCache()` increments `_cacheRevision`, clear or logically invalidate the memo.

Caching misses is important: strange app IDs are precisely the path that pays the two fallback map scans.

Add a focused contract covering: normal heuristic hit, StartupWMClass hit, exec hit, scoped Electron normalization, token-overlap fallback, cached miss, and invalidation after a synthetic DesktopEntries revision.

### R9.4 — Do not lazy-build the whole AppSearch catalog yet

The full `_rebuildCache()` also sorts DesktopEntries and builds `_cachedList`/`_cachedNameLowers`. Only launcher/settings/all-apps surfaces need the alphabetical list, while taskbar identity needs the reverse maps.

Splitting those ownership domains could save startup sort/allocation work, but the current list also participates in reactive `list` semantics and several Settings pages. This is plausible but lower-confidence than lookup memoization.

Measure desktop-entry counts and `_rebuildCache()` duration before introducing a second lazy list lifecycle. The existing fuzzy prepared-name/icon indices are already lazy and should remain so.

### R9.5 — GlobalActions setup scan is real but currently tiny

Current sources:

- `services/GlobalActions.qml`: `30c88a1edf2c6f70a2f6471631585e9b8fc566bd`;
- `scripts/setup/_scan.sh`: `a8047db9398e1df52e91d94d6114f522bb3b8b23`.

Tier 3 unconditionally calls `refreshSetupActions()`, which starts one Bash process. The scanner then starts one AWK per non-private setup recipe and reads only the first 60 lines for `@meta` headers.

At this baseline, `scripts/setup/` contains only one public recipe (`spotify.sh`). Therefore this wave is currently one Bash + one AWK, not a large startup fan-out.

Keep reactive folder rescanning and immediate post-Tier-3 action availability unless a future recipe count grows enough for measurement to justify a different metadata format.

### R9.6 — RecorderStatus is already demand-tiered where it matters

Current `services/RecorderStatus.qml`: `7e221f7168f42c5348f4b07fe7ae8a0827c6a946`.

The service has already avoided the bad design of one-second global polling:

- visible recorder controls acquire keyed fast-status demand;
- start/stop actions use a bounded 350 ms quick-check loop;
- active recording uses a 1 s tick for elapsed time and stop detection;
- idle/no-demand mode polls every 15 s, or 30 s in low-power mode.

Only the last path remains unconditional once the service is resident, because it discovers externally launched `wf-recorder` instances.

Turning it off would change external-recorder detection semantics. Treat it as a runtime wakeup measurement target, not a source-only optimization.

### R9.7 — Awww startup capability detection is part of the default wallpaper renderer decision

Current `services/AwwwBackend.qml`: `fb5fc38ebe2735a1d97201990e555c40a2c82779`.

The backend is intentionally enabled by default and static wallpaper ownership depends on:

```qml
readonly property bool available: clientAvailable && daemonAvailable
readonly property bool active: enabled && available
```

The startup probe checks explicit standard paths and then PATH fallback for both `awww` and `awww-daemon`. When available, it triggers sync; when unavailable, Background/Waffle fall back to the internal renderer.

Thus this process cannot simply be demand-gated behind Settings or wallpaper selection: it determines the initial visible rendering engine. Only replace it if Quickshell/native code can perform an equivalent executable lookup without losing non-standard PATH support.

## Research continuation — round 10

Baseline: `dev` at `4c1932c0616ea8a4b91a188270c21d0072649228`.

### R10.1 — Config's global invalidation signal has no path information

Current `modules/common/Config.qml`: `3543ed88ddfa5408b1191b76e2c13499caaf67f7`.

Both mutation APIs end by bumping one global revision and emitting the same zero-argument signal:

```qml
function setNestedValue(nestedKey, value) {
    ...
    root._bumpRevision()
    root.configChanged()
}

function setNestedValues(updates) {
    ...
    if (paths.length > 0) {
        ...
        root._bumpRevision()
        root.configChanged()
    }
}
```

This is a valid compatibility mechanism for nested JsonAdapter values, but listeners must treat it as a broad invalidation, not evidence that their own domain changed.

The audit should prefer this pattern:

```text
Config.revision keeps derived values reactive
derived domain signature/property expresses actual intent
onDerivedValueChanged owns domain work
global configChanged remains only where no narrower reliable signal exists
```

No Config API redesign is required for the first optimization pass.

### R10.2 — WallpaperListener's safety net can preserve its purpose without rebuilding on every setting edit

Current `services/WallpaperListener.qml`: `ff0253becd4b3f5b2df24c65d003fb0236304e9a`.

The per-monitor map changes only from:

- `background.multiMonitor.enable`;
- `background.wallpapersByMonitor`;
- `background.wallpaperPath`;
- connected screen changes.

Those already have direct reactive handlers. The additional broad listener is explicitly documented as a safety net for `wallpapersByMonitor` list propagation.

Current unrelated-config path:

```text
Config.configChanged
 -> restart 80 ms timer
 -> create result object for every screen
 -> JSON.stringify(result)
 -> JSON.stringify(effectivePerMonitor)
 -> usually return unchanged
```

Strict-lossless narrowing:

1. keep a canonical `_wallpapersByMonitorSafetyKey` reflecting the last list snapshot incorporated by `refresh()`;
2. on global Config change, stringify only the current `background.wallpapersByMonitor` value;
3. restart the safety debounce only when that key differs;
4. keep direct `onWallpapersByMonitorRefChanged`, global path/mode handlers and `Quickshell.onScreensChanged` intact;
5. focused test: mutate unrelated setting -> no fallback refresh; replace monitor list -> refresh; simulate a missed list property notify but emit `configChanged` -> fallback still refreshes.

`globalAnimationEnabled` and `globalFillMode` are also currently declared in WallpaperListener but have no repository readers and are not used by `refresh()`. They are dead aliases at this baseline and can be removed separately after a QML import/smoke check; the saving is negligible.

### R10.3 — ThemeService already contains the exact signature needed to eliminate broad wakeups

Current `services/ThemeService.qml`: `b73e3ae8060d41fb15d39221ad78111668d8be7c`.

`liveRegenSignature` serializes the actual regeneration inputs: theme, panel family, Waffle wallpaper ownership, palette type, theming wallpaper, external-target toggles, terminal adjustments, soften-colors and auto dark/light behavior.

Yet every Config change currently does:

```qml
function onConfigChanged() {
    liveRegenerateDebounce.restart()
}
```

260 ms later `_tryLiveRegenerateFromConfig()` begins with:

```qml
if (!Config.ready) return
if (root.liveRegenSignature === root._lastLiveRegenSignature) return
```

Therefore unrelated Config mutations already have an explicit semantic no-op proof. Triggering the same debounce from `onLiveRegenSignatureChanged` removes only the redundant timer/wakeup path.

Preserve:

- Config-ready signature priming;
- `currentTheme` explicit apply behavior;
- `setAutoRegenTimer`;
- family-aware regeneration;
- `Wallpapers._applyInProgress` duplicate suppression;
- cooldown/coalescing.

### R10.4 — MPRIS filtering depends on two Config values, not the entire configuration

Current `services/MprisController.qml`: `3a8184f9308f0816ea395ea26f182bb5a3fbcf15`.

Global Config handler:

```qml
function onConfigChanged() {
    root._updateMpvCache()
    root._rebuildPlayerList()
}
```

Source-wide Config references inside this service show player-list membership depends on:

- `Config.options.media.filterDuplicatePlayers`;
- `Config.options.sidebar.ytmusic.enable`.

The other Config reference, `osd.mediaEnabled`, controls action OSD emission and does not require player-list rebuild.

`_updateMpvCache()` scans live `Mpris.players.values` only; it has no Config input.

A strict replacement is a derived filter signature, for example:

```text
filterDuplicatePlayers + "|" + ytmusicEnabled
```

whose change schedules `_rebuildPlayerList()`. Existing MPRIS player lifecycle and YtMusic connections continue to own mpv cache refreshes and metadata-driven rebuilds.

Oracle: same membership/order/trackedPlayer before and after toggling either relevant option, including the 1.8 s empty-list grace; unrelated Config writes must not invoke the rebuild path.

### R10.5 — ThinkFan's broad Config listener can become a real helper spawn when the opt-in feature is enabled

Current `services/ThinkFanService.qml`: `943082413a143df3e642ee3d60587093dda1ec02`.

The global handler sends every Config edit through `_handleProfileFollowEvent()`. When profile fan control is enabled:

- status newer than 30 s -> schedule configured active-level reconciliation;
- status older than 30 s -> immediately `refresh()`, starting `inir-thinkfan --status`.

The periodic status timer is intentionally sparse (5 min) when profile-follow is enabled but ThinkFan is not actively managed, so unrelated Settings edits can become the event that forces a stale-status process.

The actual desired fan intent is already exposed as reactive properties:

```qml
profileFanControlEnabled
activePowerProfileKey
configuredActiveFanLevel
```

PowerProfiles already has its own `onProfileChanged`.

Promotable direction:

- `onProfileFanControlEnabledChanged -> _handleProfileFollowEvent()`;
- `onConfiguredActiveFanLevelChanged -> _handleProfileFollowEvent()`;
- retain `PowerProfiles.onProfileChanged`;
- remove generic Config follow event.

Do not trigger inactive-profile level edits immediately; current runtime only needs the active profile level, and a later power-profile change re-evaluates it.

### R10.6 — TLP charge reconciliation has the same broad-listener smell but stronger no-op guards

Current `services/TlpService.qml`: `4e0ef4fba76eb00df7ddc54941e205029dde07ec`.

Every Config change schedules `root.apply()`. Unlike ThinkFan, `apply()` first checks the already-detected hardware/ownership state and usually returns without spawning anything. Therefore this is primarily event-loop/CPU churn, not a routine process-spawn bug.

Config intent is represented by:

- `enabled`;
- `requestedLimit` / normalized `effectiveRequestedLimit`.

Hardware capability/current ownership are detector-owned state.

Use derived-property changes to request `apply()`, while preserving:

- initial Config-ready detection;
- detector completion reconciliation;
- allowed/discrete limit normalization;
- disabling a policy still owned by Hadalis.

This optimization becomes more valuable after Round 6 demand-gates TlpService itself, because the service can then remain completely absent for default charge-care-off sessions.

### R10.7 — Background revision counters were rechecked and are not dead

Current `modules/background/Background.qml`: `29bd40236ba9579077d361fb1012d4f994ef4a3a`.

A repository search snippet initially exposed only the declaration/increment of `_zoneRevision`, which looked removable. Full-file verification found the reads:

- `_zoneRevision` is explicitly consumed inside `_computeZoneOccupants()`;
- `_imageRouteRevision` is explicitly consumed while resolving the dynamic image-converter `Connections.target`.

Both are deliberate dependency bridges around imperative helper functions. Do not remove them under the current strict-lossless audit.

A later optimization could narrow `_zoneRevision` to widget-layout-related changes, but that requires a domain signature or path-aware Config event and is lower confidence than the service-level cuts above.

## Research continuation — round 11

Baseline: `dev` at `2b66fce9e5b58b801757b581b7029f3f309fb043`.

### R11.1 — Workspaces turns an unrelated Config write into per-output window scanning

Current `modules/bar/Workspaces.qml`: `f7c51bb42b984ba8d3da078652a36ca75bd2db71`.

Every instance owns:

```qml
Connections {
    target: Config
    function onConfigChanged(): void {
        syncWorkspaceConfigTimer.restart()
    }
}
```

The zero-delay timer runs `syncWorkspaceConfig()`, which copies the `bar.workspaces` settings and unconditionally calls:

```qml
root.updateWorkspaceOccupied()
```

That starts a 50 ms debounce whose Niri path does:

```text
iterate NiriService.windows
 -> build Set(workspace_id)
 -> derive occupied state for every shown workspace
```

The shared Workspaces component is instantiated by Classic horizontal/vertical bars and Abyss bar modules, so the cost scales with the number of presented output bars.

Nothing about a change such as theme color, audio setting, notification preference or unrelated widget option changes workspace occupancy.

Strict-lossless direction:

1. compute a canonical snapshot from the fields copied by `syncWorkspaceConfig()`:
   `showAppIcons`, `alwaysShowNumbers`, `useNerdFont`, `monochromeIcons`, `numberMap`, `perMonitor`, `scrollBehavior`, `dynamicCount`, `shown`, `wrapAround`, `scrollSteps`, `invertScroll`;
2. if the snapshot equals the last applied snapshot, return before assignments and before `updateWorkspaceOccupied()`;
3. preserve Config-ready initial sync;
4. preserve Niri/Hyprland workspace/window/focus signals as the normal occupancy owners;
5. if `syncGlobalWorkspaceConfig=false`, do not use unrelated Config changes as an occupancy clock.

Focused regression should count `doUpdateWorkspaceOccupied()` calls across two synthetic outputs: unrelated Config change -> zero new occupancy work; relevant workspace setting -> one per instance after debounce; Niri window/workspace change -> unchanged behavior.

### R11.2 — AI model synchronization already protects the expensive part

Current `services/Ai.qml`: `91496b093b137b77bed6ffbd9bfffeba201684e3`.

Ai still receives every Config change, but `_syncExtraModels()` builds:

```text
policy | JSON(extraModels) | JSON(sorted live provider IDs)
```

and returns when that signature matches `_extraModelsSignature`.

The destructive part — destroying old extra `AiModel` objects, recreating them and rebuilding `modelList` — therefore does not happen for unrelated Config changes.

A later micro-optimization could move the call behind derived `policy/extraModels` changes and let `AiProviderCatalog.onCatalogUpdated` remain the provider owner. That would only save temporary arrays/Set/sort/JSON serialization while Ai is resident, so it ranks below Workspaces and Round 10 services.

### R11.3 — TimerService's broad Config sync is cheap enough to leave alone

Current `services/TimerService.qml`: `00f1733dc6f9b0ef822557dfb8524800af104ff2`.

The global listener calls `_syncPomodoroConfig()`, which validates and assigns four integer values:

- focus duration;
- break duration;
- long-break duration;
- cycles before long break.

It does not launch a process, persist state, rebuild a model or start a timer merely because those assignments occur.

Replacing this with more signal machinery would optimize a handful of arithmetic/property assignments and increase lifecycle complexity. Keep it as a deliberate non-candidate unless profiling contradicts the static assessment.

### R11.4 — Shell's broad deferred-feature check is admission control, not repeated service work

Current `shell.qml`: `aae76205a819e9b098f6a4be7fb6d56e14ff4900`.

On every Config change, shell calls:

```text
_ensureScreenTimeService()
_ensureDeferredFeatureServices()
_ensureLateFeatureServices()
```

Those functions check a small set of booleans/panel membership and assign singleton references only when a feature should exist. Once assigned, the same assignment does not recreate a singleton; the services retain their own work gating.

This broad check also allows an option enabled at runtime to materialize its service without requiring shell restart. It is therefore a good example where narrowing the listener is unnecessary unless actual traces attribute cost to it.



## Research continuation — round 12

Baseline: `dev` at `6230f4ba74a6218515f3f26743f9e830cfa19253`.

This round reconciled the newest canonical cross-repo handoff before promoting
anything. The Settings World Clock process fan-out and Clipboard decode
in-flight ownership are already documented there, so they are not counted as
new findings here.

Current source identities at this baseline:

- `modules/common/widgets/CliphistImage.qml`: `85f316c00c9dfebd6f792d779cb21c6a3e6ba6d2`;
- `modules/common/widgets/Favicon.qml`: `3d7e24e97236e53a174c977736d75e5ed850871d`;
- `modules/settings/QuickWallpaperItem.qml`: `6c9485c0344dc6e9c64c4ff45f24b689eb0bb3df`;
- `modules/common/widgets/NotificationAppIcon.qml`: `b7af10d8c4d9395ed3c4930d1ed86bf025590cbb`;
- `modules/bar/BarTaskbarWindowPreview.qml`: `6ef94fe54845b57f4562620226c519f94ebdee86`;
- `modules/waffle/bar/tasks/WindowPreview.qml`: `3dd610cf20f402ca0bc1f76a9162dd2e41c8573a`;
- `modules/sidebarLeft/SidebarLeftContent.qml`: `06c8e5aa355b97d14d606f7d152123d29a8b36ab`;
- `scripts/test-performance-lifecycle.sh`: `dcbbc9b28ce2258589df2daee5d1d7daa4c439c6`.

### R12.1 — Simple rounded-mask FBO sweep has an in-tree scene-graph precedent

Several current leaf/image components still use the same render shape:

```text
image/content item
  -> layer.enabled
  -> OpacityMask
       -> same-bounds Rectangle with only radius
```

Examples include Clipboard thumbnails, favicons, classic/Waffle taskbar window
previews, quick-wallpaper thumbnails and notification app images. Their masks
are not arbitrary alpha geometry; they are ordinary rounded rectangles or
circles.

Hadalis already has a stronger local precedent than a generic Qt performance
recommendation. `scripts/test-performance-lifecycle.sh` explicitly requires
`MediaCrossSlideImage` and InnerTune thumbnails to use
`Quickshell.Widgets.ClippingRectangle`, and rejects restoring an
`OpacityMask`/permanent rounded-mask FBO on those paths. That makes a bounded
conversion sweep worth testing rather than treating every remaining rounded
mask as unavoidable.

Strict-lossless first phase:

1. select only a non-inverted, same-bounds rounded rectangle/circle mask;
2. keep image source, decode size, cache policy, async behavior, visibility,
   opacity and lifecycle unchanged;
3. replace only the offscreen mask/effect ownership with the existing
   scene-graph clipping primitive;
4. preserve the exact effective radius, including any radius animation;
5. do not include masks that combine blur, transformed coordinates, inverse
   holes, unions, connected-surface topology, ripple-only clipping or any shape
   whose contribution extends outside the clip.

Structural claim only: each proven conversion can remove one mask/effect
layer/FBO for that visible instance. The aggregate value is larger in list/grid
surfaces such as quick-wallpaper and notification delegates than in a single
small avatar. This is not a whole-GPU or whole-RAM percentage.

Required raster/lifecycle oracle:

- transparent-edge and opaque images;
- radius 0, small rounded radius and full/circular radius;
- odd/even item sizes;
- integer and subpixel placement;
- DPR/fractional-scale cases representative of 1.0, 1.25, 1.5 and 2.0;
- ready -> error/fallback and source replacement;
- the animated-radius notification path;
- QuickWallpaper effects enabled/disabled;
- classic and Waffle taskbar preview arrival/removal;
- Clipboard blur overlay and hidden/reused delegate transitions;
- global normalized image error plus an edge-band/max-channel comparison so a
  tiny antialiasing regression cannot be hidden by a large transparent frame.

Target strict-lossless result is exact visible parity. If Qt's two clipping
paths rasterize edge antialiasing differently, the candidate must be reclassified
as a measured visual substitution and remain below the audit's <1% budget before
promotion.

### R12.2 — Full-surface rounded clipping is a larger second phase, not a bulk rewrite

`SidebarLeftContent.qml` already has the correct lifecycle discipline:
its SwipeView mask is enabled only while the panel is presented and Game Mode
has not disabled the effect. However, while open, the full content surface is
still rendered through a same-bounds rounded `OpacityMask` layer.

If R12.1 proves the primitive itself on leaf/image cases, the next experiment is
one full-surface host using the same `ClippingRectangle` strategy. This has a
larger local FBO footprint than an icon/thumbnail mask, but also a wider
behavioral boundary:

- current/next/previous SwipeView loaders must stay warm exactly as today;
- swipe animation and clipping must not change;
- pointer/touch routing must be identical;
- animated corner radius must match at intermediate frames;
- closing the panel must retain the current zero-residency behavior;
- child content may be embedded elsewhere, so no child mask is removed merely
  because this parent clips in one host.

Do not combine the full-surface experiment with child-mask deduplication. Prove
one render-primitive substitution first, then audit host reachability separately.

### R12.3 — Findings deliberately not promoted from this pass

- **Settings World Clock process fan-out:** already present in the newest
  `CROSS_REPO_OPTIMIZATION_HANDOFF.md`; it is not a new candidate for this
  audit. The canonical direction is the existing one-Bash/`printf %(...)T`
  approach rather than another independent proposal.
- **Clipboard decode dedupe:** still relevant on current source, but already
  owned by earlier cross-repo/audit research. The current component still
  acknowledges simultaneous surfaces and retains one process per component;
  do not double-count it as R12 work.
- **`AppLauncher._configRevision` removal:** rejected. The revision looks local
  in `AppLauncher.qml`, but current Settings/Niri configuration code consumes it
  as an explicit reactive dependency. It is not dead state.
- **Downscaling Clipboard decode via `sourceSize`:** not a strict-lossless
  cleanup under the current contract. Native Clipboard regression checks use the
  decoded image's intrinsic dimensions during preview sizing; changing decode
  dimensions would alter those observations unless the sizing contract is
  redesigned separately.
- **`modules/sidebarLeft/Wallhaven.qml` persistent mask:** source inspection
  found the old-looking ungated mask, but current Sidebar composition does not
  establish that file as a live owner. Do not claim a saving until reachability
  is proven rather than inferred from a filename.
- **Abyss/Aqua automatic render-quality policy:** intentionally changes visual
  fidelity according to user/power policy. It is a product-controlled quality
  tradeoff, not a strict-lossless optimization and must not be credited here.

### R12.4 — Ranking implication

The leaf rounded-mask sweep is lower risk than replacing blur/shadow algorithms
because it reuses a clipping primitive already protected by Hadalis performance
regressions. It should nevertheless start with a focused raster oracle, not a
repository-wide mechanical replacement. If parity holds, prioritize repeated
list/grid instances first, then the full-sidebar surface; leave complex/inverted
masks under their existing specialized research owners.


## Research continuation — round 13

Baseline: `dev` at `e139c9c148766068ccb9ed5e448c7fd444fa6a2a`.

This round first reconciled the newest cross-repo handoff. Calendar bucketing,
LocalMusic payload/search work, WorldClock catalog lifecycle, Background
workspace occupancy, Hyprland collection passes, GameMode fullscreen snapshots,
DesktopItems snapshots and Niri toplevel app-id bucketing are already owned
there, so none is double-counted here.

Current source identity:

- `services/NiriService.qml`: `4c8194493fd380bf0ad8c51bc62990ad0c232738`.

### R13.1 — Workspace activation re-sorts an order whose sort key did not change

The authoritative full-workspace event correctly rebuilds and sorts:

```qml
root.workspaces = newWorkspaces
allWorkspaces = Object.values(newWorkspaces).sort((a, b) => a.idx - b.idx)
```

That is necessary when `WorkspacesChanged` can alter membership, output,
indices or topology.

The same sort is also executed by `handleWorkspaceActivated()`. That handler
changes only activation/focus flags on existing workspace records:

```text
is_active
is_focused
```

It does not add/remove workspaces and does not assign `idx`. Therefore the
previous `allWorkspaces` array is already in exactly the order required by the
same `a.idx - b.idx` comparator.

A strict-lossless replacement can keep the existing workspace-map construction
and existing per-record clone/reference choices, but derive the next ordered
array by walking the previous sorted projection:

```text
nextAll = []
for each old ordered workspace:
    next = updatedWorkspaces[old.id]
    append next
    track focused index from next.is_focused
```

This removes:

- one `Object.values(updatedWorkspaces)` array materialization;
- one stable O(W log W) sort;
- the later standalone O(W) `findIndex(w => w.is_focused)`, because focused
  index can be observed while publishing the ordered projection.

The existing `updateCurrentOutputWorkspaces()` filter can remain unchanged in
the first patch. Folding that filter into the same operation is possible, but it
would widen the proof surface for little additional value.

### R13.2 — Workspace urgency has the same redundant ordering rebuild

`handleWorkspaceUrgencyChanged()` replaces exactly one workspace record with a
copy whose `is_urgent` value changed, republishes `root.workspaces`, and then
again executes:

```qml
allWorkspaces = Object.values(updatedWorkspaces).sort((a, b) => a.idx - b.idx)
```

Urgency does not change membership or `idx`. The already-sorted projection can
therefore be remapped by id without sorting. This path has lower frequency than
workspace activation, but it is the same proof and should share one helper if
implemented.

### R13.3 — Identity/tie constraints make this narrower than “skip the sort”

The optimization must preserve more than values.

Current `handleWorkspaceActivated()` may clone workspace records even when a
particular record's final booleans equal their previous values. A proposed
optimization must initially keep those exact clone/reference decisions rather
than opportunistically retaining old records. QML consumers can observe object
identity indirectly, and strict-lossless research should not assume those
fresh objects are irrelevant.

Equal `idx` values also need an explicit oracle. JavaScript sort is stable on
the deployed runtime, so the old code preserves the pre-sort `Object.values`
tie order. Reusing the prior `allWorkspaces` order is equivalent only if:

- workspace membership is unchanged;
- ids still address the same records;
- `idx` is unchanged for every record;
- the previous projection was produced by the same canonical ordering.

Those conditions hold for the two targeted event handlers by current source,
but the helper must not be used for `WorkspacesChanged` or any future event
that can change `idx`/membership.

### R13.4 — Required oracle

Before promotion, compare old/new public state and notification behavior for:

- one workspace;
- many workspaces on one output;
- multiple outputs;
- focused and non-focused activation events;
- activation of the already-active workspace;
- equal/duplicate `idx` values and unusual id ordering;
- missing activation id (current early return);
- no focused workspace after update, including the current quirk where
  `focusedWorkspaceId` is cleared but `currentOutput` is not explicitly
  cleared in that branch;
- urgency true/false changes;
- untouched workspace object references versus records that current code
  clones;
- `allWorkspaces`, `focusedWorkspaceIndex`, `focusedWorkspaceId`,
  `currentOutput` and `currentOutputWorkspaces` value/order equality;
- signal/binding counts needed by Bar/Overview/Background/workspace consumers.

A useful structural benchmark should run repeated synthetic activation events
at workspace counts such as 10, 50 and 200 and report JS wall time/allocation
counts separately from whole-shell CPU. Real desktops normally have far fewer
workspaces, so this remains a targeted event-path reduction rather than a claim
of a large universal speedup.

### R13.5 — Adjacent ideas deliberately not promoted

- **Clone only records whose booleans actually changed:** values would usually
  match, but it changes workspace-object identity relative to current behavior.
  Keep that as a separate oracle-backed refinement, not part of the sort
  removal.
- **Mutate `root.workspaces` in place:** rejected for the first pass. The map is
  public reactive state; replacing it currently supplies a dependable property
  notification boundary.
- **Remove the full sort from `handleWorkspacesChanged()`:** rejected. That is
  the authoritative topology snapshot and can change membership/`idx`.
- **Optimize `MinimizedWindows` filter/sort selectors in the same round:**
  those paths are explicit minimize/restore actions and lower priority than the
  recurring workspace-activation event path.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.


## Research continuation — round 14

Baseline: `dev` at `33b9afaab5878defe6108fcf72587d9d8d5f9c5c`.

This round also consolidates all active optimization documentation under
`docs/optimization/`; superseded handoffs and completed/scoped journals move to
`docs/archive/optimization/`. Future optimization findings are written only to
this canonical audit.

Current source identities:

- `services/NiriService.qml`: `4c8194493fd380bf0ad8c51bc62990ad0c232738`;
- `modules/altSwitcher/AltSwitcher.qml`: `313928e4d55afca9ff188d9323f7de959f68f3ea`;
- `modules/altSwitcher/AltSwitcherNoVisual.qml`: `d362feb228a20227c726a85aac24382a505a71da`;
- `modules/waffle/altSwitcher/WaffleAltSwitcher.qml`: `00a169d62a31d4b3ae12aba6d6ab85f995b9fbd9`.

### R14.1 — MRU value can be republished even when its order is unchanged

Current `handleWindowFocusChanged()` rebuilds a fresh MRU array for every
non-null focus id. If that id is already at index 0 and does not occur later,
the produced array is element-for-element identical to the current value.

Qt QML `var` properties use reassignment as the change-notification boundary,
so assigning the fresh JS array can wake consumers even though the logical MRU
order did not change. The ii AltSwitcher explicitly listens to
`onMruWindowIdsChanged` in its closed/no-visual event-driven path and schedules
snapshot reconstruction; visual/Waffle switcher paths consume the same MRU
state when building their item order.

Strict-lossless direction:

1. keep the rest of `handleWindowFocusChanged()` unchanged;
2. prove the current MRU is already the exact output of the existing algorithm:
   index 0 equals the focused id and no later duplicate exists;
3. only in that exact case skip MRU array construction/reassignment;
4. if a later duplicate exists, retain the existing rebuild so duplicate cleanup
   stays identical;
5. do not skip window-focus normalization or workspace active-window
   reconciliation in the same patch.

A bounded guard can scan for a later duplicate. Worst-case inspection remains
O(N), but the no-op case avoids a new array, one public property publication and
any downstream rebuild caused solely by that publication.

### R14.2 — Notification parity is the blocker

Skipping a property publication changes signal count even if the value is
identical. The candidate is therefore not CONFIRMED until an oracle proves a
duplicate same-id `WindowFocusChanged` event carries no semantic refresh duty
that is delivered solely by the MRU signal.

Required oracle:

- first focus with empty MRU;
- A -> B -> A ordering;
- duplicate A -> A with canonical MRU;
- malformed MRU containing duplicate A later in the list;
- null/undefined focus id;
- clean and pending window batches;
- stale/missing workspace active-window metadata;
- ii visual AltSwitcher closed/open;
- ii no-visual mode and its event-driven snapshot refresh;
- Waffle AltSwitcher;
- Game Mode gating;
- exact MRU/item ordering and signal/rebuild counts.

Trace Niri as well: if duplicate same-id focus events are rare, retain this as a
correct micro-candidate but rank it below Round 13 and higher-leverage
render/process work.

### R14.3 — Close-event no-op is adjacent but separate

`handleWindowClosed()` similarly republishes a filtered MRU array even when the
closed id was never present. Do not bundle that path until R14.1 establishes the
notification contract; then extend the same oracle deliberately.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.


## Research continuation — round 15

Baseline: `dev` at `c51490a438e2534d1f980ce247f5b1786726c5a3`.

This round deliberately revalidated one useful historical finding from the
archived handoff before promoting it into the canonical ledger, then added a
new shell-process candidate. The archived note is not treated as active by
itself; current source identities were checked first.

Current source identities:

- `services/CalendarSync.qml`: `6e0b89c56eda5ee612be8438d9c20d4851a09617`;
- `services/Events.qml`: `dcc3671e7c6d640fdbe5d3ee8dce45bc412148e7`;
- `modules/dashboard/DashAgenda.qml`: `222f16088cf07d53c0ad606d1cc8a68d3abe717c`;
- `modules/sidebarRight/calendar/CalendarWidget.qml`: `4b5c53bc6392e7ce5f99df8e2643029969cdb98e`;
- `modules/waffle/notificationCenter/CalendarWidget.qml`: `820a50373bd475e583e8ce4cd9b66515a4acba01`;
- `modules/common/widgets/CalendarView.qml`: `767c8d6c9345f92925ad395b489be45262b62e72`;
- `modules/common/widgets/WeekRow.qml`: `e95df323efdbf6fbcc5f3e6e855e1450fa869507`;
- `scripts/scan-widgets.sh`: `d1176e3508335d0ad8d18fc884a4382fcd6a63a6`;
- `services/CustomWidgets.qml`: `fe4b1ef553fe7ed437b4e0de947615eee83752c9`.

### R15.1 — CalendarSync already has the exact batch primitive; two remaining views still bypass it

`CalendarSync.getEventsForDate(date)` performs a full `root.events.filter()`
and reparses event dates for every queried day. Current source already contains
`_getEventBucketsForDates(dates)`, which accepts an ordered date list and
constructs corresponding buckets while preserving the per-day multi-day/all-day
membership semantics.

Three current consumers have already moved to that helper:

- EventsWidget: 30 dates;
- CompactSidebarRightContent: 14 dates;
- CalendarUpcomingWidget: 30 dates.

Two remaining paths still perform repeated full external-list scans:

- DashAgenda loops over `lookaheadDays = 14` and calls
  `CalendarSync.getEventsForDate()` for every date;
- Waffle notification-center upcoming events repeats the same pattern for 3
  dates.

The strict-lossless migration is intentionally narrow: construct the same dates
in the same order, call `_getEventBucketsForDates()` once, then leave every
existing per-day clone, past-event filter, per-day sort, global merge and cap
unchanged.

Do **not** replace these loops with `getUpcomingEvents(days)`. Range semantics
are not identical: a multi-day all-day event is intentionally present in every
matching per-day bucket, whereas the range helper returns the event object once.

Required oracle:

- timed events;
- single-day all-day fallback with absent/degenerate DTEND;
- exclusive RFC5545 DTEND;
- multi-day all-day event repeated into every matching day;
- today with an already-past timed event;
- month/year boundary;
- empty list;
- exact object identity/order entering the existing downstream sort/cap.

### R15.2 — Visible calendar grids multiply the same list-wide work

The classic Sidebar month view computes exactly six weeks × seven days = 42
cells. For every cell it derives both count and dot colors:

```text
count
  -> Events.getEventsForDate()
  -> CalendarSync.getEventsForDate()

colors
  -> Events.getEventsForDate()
  -> CalendarSync.getSourceColorsForDate()
       -> CalendarSync.getEventsForDate()
```

Therefore a complete 42-cell invalidation can perform up to:

- **84 full local-event list scans**;
- **84 full external-event list scans**.

The Waffle notification-center Calendar is even broader. The shared
`CalendarView` uses `totalWeeks = 6 + paddingWeeks * 2` with default
`paddingWeeks = 2`, so it instantiates **10 WeekRow objects**. `WeekRow` builds
7 day delegates each, giving **70 day delegates**. Each delegate independently
binds both `eventCount` and `sourceColors` through the same pair of local and
external queries. A full event-trigger invalidation can therefore drive up to:

- **140 local full-list scans**;
- **140 external full-list scans**;
- **280 aggregate list scans** before count/dot rendering.

Those are structural upper counts for one full binding recomputation, not
measured CPU percentages.

Strict-lossless direction:

1. derive the exact ordered visible dates already owned by each calendar;
2. batch external events with the existing CalendarSync helper;
3. build equivalent local buckets from `Events.list` in one bounded pass, or
   add a narrowly specified local batch helper with exactly
   `Events.getEventsForDate()` semantics;
4. derive per-date metadata once: local count, external count, local-accent
   presence and ordered-unique external source colors;
5. bind cells/delegates to that private metadata snapshot;
6. invalidate on exactly the existing event triggers and month/week navigation.

The local path must preserve the current rule that notified timed events are
hidden but all-day events remain visible. External source-color order must remain
first-encounter order with duplicate source ids removed. Previous/current/next
month spill cells must use their actual resolved dates, not just day numbers.

Keep this snapshot widget-local first. A service-wide long-lived date cache would
introduce a larger invalidation/lifetime proof with no need for the initial gain.

### R15.3 — Custom-widget manifest scanning spawns avoidable per-entry helpers

`services/CustomWidgets.qml` owns one scanner process:

```text
scan-widgets.sh <widgets-dir>
```

That ownership is already bounded. The avoidable fan-out is inside the shell
loop in `scripts/scan-widgets.sh`:

```bash
wdir="$(dirname "$manifest")"
wid="$(basename "$wdir")"
content="$(cat "$manifest" 2>/dev/null)" || continue
```

For each discovered manifest this launches three child programs in addition to
the scanner shell. The input glob is fixed to `$dir/*/widget.json`, so the same
values can be derived in Bash itself:

```text
wdir = manifest minus trailing /widget.json
wid  = final path component of wdir
content = Bash direct file read
```

This does not require changing QML service ownership, manifest validation,
config seeding, reload behavior or the public widget list. It is a process-only
cleanup with a bounded saving of **up to three child processes per manifest**.

Required byte/behavior oracle:

- missing widget directory;
- empty directory;
- one and many manifests;
- spaces and Unicode in directory/widget names;
- unreadable manifest preserves the existing skip/failure behavior;
- manifest with and without trailing newline;
- malformed JSON remains malformed in the same way for the QML parser;
- exact scanner stdout for normal fixtures;
- CustomWidgets resulting `widgets` list/config seeding equality.

Do not combine this with deferred CustomWidgets service materialization in the
same patch. Background currently references CustomWidgets for live custom widget
ownership, and changing when the service scans/seeds config is a separate
behavior/lifecycle problem.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.


## Research continuation — round 16

Baseline: `dev` at `5aeaf5cff9acd48e46059937ff976e20b33a726f`.

This round revalidated a historical LocalMusic memory/transport finding against
current source and current contract tests before promoting it into the canonical
ledger.

Current source identities are unchanged from the archived research baseline:

- `services/LocalMusic.qml`: `88263668b48d85323a576c4c3645d9f40909f466`;
- `modules/sidebarLeft/LocalMusicView.qml`: `d5b1880d5a1a3796f0faefe343cf3f2f9909953a`;
- `native/inir-mpdd/src/main.rs`: `1c63b8e5281dad2a28e88ea3cb660f7cc0c0cb88`;
- `scripts/local_music_mpd.py`: `0e05af4f8a308072fbed7bed96994559b66bf6f1`.

### R16.1 — QML retains a duplicate folder tree that the live Songs browser does not use

`LocalMusic._applyPayload(..., includeLibrary=true)` currently retains:

```qml
libraryTracks = payload.tracks ?? []
playlists = payload.playlists ?? []
folderCollections = payload.folders ?? []
```

The live Songs browser does not consume that pre-grouped folder structure.
`LocalMusicView.qml` derives folder navigation, child counts, folder selection
and folder track sets directly from `LocalMusic.libraryTracks`.

Current repository search returns `folderCollections` only from
`services/LocalMusic.qml`, while the explicit qualified search for
`LocalMusic.folderCollections` returns no consumer. Because the service/view
blobs also match the archived research identities exactly, the earlier
no-consumer conclusion remains strongly supported at this baseline.

Strict-lossless first step:

1. remove the `folderCollections` property;
2. stop assigning `payload.folders` in `_applyPayload()`;
3. leave `libraryTracks`, `playlists`, queue/status/current-track state and every
   backend payload byte unchanged;
4. leave Songs folder derivation exactly as it is today.

This is deliberately smaller than changing the MPD snapshot protocol. The JSON
parser may still materialize `payload.folders` transiently, but after
`_applyPayload()` returns the subtree no longer has an intentional QML root and
can become collectible.

Why the retained subtree can be substantial:

- Rust builds a `BTreeMap<String, Vec<Value>>` and pushes
  `Value::Object(track.clone())` into folder buckets;
- Python groups the already-built track dictionaries into `folders_map` and
  emits a `folders` list;
- the payload therefore carries `tracks` plus another folder-organized
  representation proportional to library size.

No RSS percentage is claimed: actual V4/JSON representation, sharing and GC
need measurement.

Required oracle before implementation:

- current-dev reference search for unqualified and qualified
  `folderCollections` usage;
- empty/small/large libraries;
- nested folders and same-name leaf folders;
- root/child Songs navigation;
- search results;
- Ctrl/Shift selection and folder bulk actions;
- playlists and queue playback;
- refresh/rescan and MPD reconnect;
- QML warnings/property references;
- compare all public LocalMusic state except the intentionally removed dead
  property.

### R16.2 — Removing `folders` from the transport is a separate contract decision

After R16.1, the shell frontend no longer needs `payload.folders`, but the
backend field cannot simply be deleted under strict compatibility assumptions.

Current Rust snapshot generation:

```text
tracks
  -> group by folder
  -> clone each track object into folder buckets
  -> sort/build folder objects
  -> serialize tracks + playlists + folders
```

Python builds the equivalent `folders_map/folders` representation.

More importantly, current regression infrastructure explicitly treats
`folders` as a stable deep-snapshot field. The native benchmark contract checks:

```text
[connected, musicRoot, tracks, playlists, folders]
```

Therefore the higher-value backend optimization is **compatibility-gated**, not
a free cleanup.

Safe promotion options are:

1. formally revise the stable snapshot schema and update Rust/Python/tests in one
   contract change after proving no supported external/manual caller needs
   `folders`; or
2. add a lean/internal snapshot mode used by LocalMusic while retaining the
   legacy full snapshot shape for compatibility/deep parity.

Do not remove `folders` from only Rust or only Python. Native/fallback parity is
part of the maintained selector contract.

If a lean mode is adopted, measure:

- serialized stdout bytes versus track count;
- backend CPU time for grouping/cloning/serialization;
- transient process RSS;
- QML parse time/RSS;
- identical frontend library, folder-navigation and playback state.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.


## Research continuation — round 17

Baseline: `dev` at `4677288dc9d3bee5d3a65969ebb3c8b031e33030`.

This round adds one entirely new Niri minimize/restore candidate, promotes a
revalidated archived tray finding into the canonical ledger, and identifies a
separate Material tray duplication that the archived service-only analysis did
not cover.

Current source identities:

- `services/MinimizedWindows.qml`: `ced7e049ef5942dea1ca5f3395eb9b614e9ecaf6`;
- `modules/waffle/bar/tasks/TaskAppButton.qml`: `500c22e179e8ab88988e0bfc40f97b9d4e67fe81`;
- `services/TrayService.qml`: `3f5e1f2580aebadf87ab40b91b4876c9ca68e76b`;
- `modules/bar/SysTray.qml`: `df3d21edca72eaf173f015c00a4cc122386d1e5e`;
- `modules/waffle/bar/tray/Tray.qml`: `1f00cc4a96fa861470d40fd47c23b0d8666b7946`.

### R17.1 — MinimizedWindows sorts whole workspace subsets just to choose one result

`stashWorkspaceForOutput()` currently builds the occupied-workspace Set and
then executes:

```qml
const workspaces = (NiriService.allWorkspaces ?? [])
    .filter(workspace => workspace.output === output && !occupied.has(workspace.id))
    .sort((a, b) => b.idx - a.idx)
return workspaces[0] ?? null
```

Only the workspace with maximum `idx` is needed. A single pass can track the
best eligible workspace and avoid both the filtered array and sort.

Strict equivalence requires explicit tie handling. JavaScript sort is stable on
the supported runtime. For equal `idx`, descending sort preserves source order,
and `[0]` selects the first source-order candidate. Therefore a one-pass
selector must update only when `workspace.idx > best.idx`, not on equality.

### R17.2 — Restore fallback can also be one pass, but its tie rule is different

When the original workspace id no longer exists, `restoreWorkspace()` does:

```qml
const outputWorkspaces = allWorkspaces
    .filter(workspace => workspace.output === originalOutput)
    .sort((a, b) => a.idx - b.idx)

return outputWorkspaces.find(workspace => workspace.idx === originalWorkspace)
    ?? outputWorkspaces.reduce((best, workspace) =>
        abs(workspace.idx - originalWorkspace) < abs(best.idx - originalWorkspace)
            ? workspace : best)
```

The sort is not needed for distance itself, but it defines tie behavior:

- exact duplicate `idx`: stable ascending sort + `find` returns the first
  source-order duplicate;
- equal distance around the requested index, e.g. 4 and 6 around 5: ascending
  order sees 4 first, and the strict `<` reducer keeps 4 on the tie.

A strict one-pass equivalent can track:

1. first exact match in source order;
2. otherwise smallest absolute distance;
3. on equal distance, smaller `idx`;
4. on equal distance and equal `idx`, first source-order record.

That reproduces the current sorted semantics without allocating/sorting the
output subset.

Required oracle for R17.1/R17.2:

- empty workspace list;
- one/many outputs;
- all candidate workspaces occupied;
- equal max `idx` duplicates for stash selection;
- original workspace id still present;
- original id missing but exact original `idx` present;
- duplicate exact `idx` records;
- nearest lower only / upper only;
- symmetric nearest tie around the requested index;
- duplicate nearest records;
- negative/unusual indices if accepted by current Niri fixture model;
- compare selected workspace **object identity**, not only id/value.

This is action-path work, not frame-path work, so the expected gain is modest in
normal use despite the clean complexity reduction.

### R17.3 — countMinimizedForApp allocates a result array only to read length

Current service code:

```qml
function countMinimizedForApp(appId) {
    return getMinimizedForApp(appId).length
}
```

`getMinimizedForApp()` filters `minimizedIds` into a new array. The only
external count consumer found on current dev is Waffle
`TaskAppButton.minimizedCount`, instantiated once per task-app delegate.

Keep `getMinimizedForApp()` unchanged for ID-returning behavior. A direct count
loop can reuse the same lowercase substring predicate and remove one temporary
array per count binding evaluation.

This is a micro-candidate and ranks below the workspace selector cleanup.

### R17.4 — TrayService archived finding remains valid on current source

The current TrayService blob is identical to the archived research identity.
It still derives three outputs with three separate source filters:

- `fcitxItems`;
- `itemsInUserList`;
- `itemsNotInUserList`.

The archived one-pass partition remains valid and is now promoted into this
canonical ledger. Membership can use a Set without altering persisted pin order
or duplicates because this path only asks exact membership.

The service semantics to retain are asymmetric:

- Fcitx bypasses the normal lists;
- pinned items remain in `itemsInUserList` even when passive;
- passive filtering applies only to `itemsNotInUserList` when smartTray is on;
- final Waffle-visible pinned/unpinned composition still depends on
  `invertPins`.

### R17.5 — Material SysTray duplicates the same work but cannot blindly reuse TrayService outputs

Current Material `modules/bar/SysTray.qml` separately scans
`SystemTray.items.values` three times again. Its semantics differ from the
service in two important ways:

1. configuration comes from `Config.options.bar.tray`, while TrayService uses
   the generic `Config.options.tray` namespace consumed by Waffle;
2. Material has an explicit Spotify exception:
   a passive Spotify item remains visible when smart filtering is enabled.

Therefore the safe first optimization is **not** to replace Material lists with
`TrayService.pinnedItems/unpinnedItems`. Instead, Material can build one private
partition snapshot from its own pins/filter flag while preserving the Spotify
exception exactly.

For each valid non-Fcitx item, compute lowercase id/title once, determine the
Spotify exception once, perform pin membership once, and append to exactly one
of the Material user-list arrays. Fcitx remains its own always-visible group.

Required Material oracle:

- Fcitx by id/title;
- pinned/unpinned active item;
- pinned/unpinned passive item;
- passive Spotify by id and by title;
- smartTray on/off;
- duplicate bar pin ids;
- invertPins on/off;
- item status mutation without insertion/removal;
- overflow closes when the final unpinned item disappears;
- exact item identity and source order for all four public arrays.

Longer-term unification into one shared parameterized classifier may be useful,
but only after both service/Waffle and Material snapshots have parity tests.
Do not merge config namespaces or Spotify policy as part of the optimization.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.


## Research continuation — round 18

Baseline: `dev` at `ec13cf37718991f79a2c7b8b253c20d638ef0cd0`.

This round revalidated the archived Network helper-process candidate and corrected
one semantic detail before promotion into the canonical ledger. It also checked a
separate first-run shell wrapper and deliberately left that lower-value path
unpromoted.

Current source identities:

- `services/Network.qml`: `a20c4c1edf1fbeb2f2a8285518af053bf72a09dc`;
- `services/FirstRunExperience.qml`: `1b58bea64a235c24ea69b7afc260a69ea6c004f9`.

### R18.1 — Network's architecture is already event-driven; the remaining debt is helper fan-out

The broad canonical conclusion remains correct: Network uses one long-lived
`nmcli monitor`, coalesces bursts through a 200 ms one-shot debounce, and does
not need a new polling redesign.

However, after each successful connected-state reconciliation it may launch two
secondary detail paths:

```text
connection name:
  sh
   └─ nmcli ...
       └─ head -1

Wi-Fi strength:
  sh
   └─ nmcli ...
       └─ awk ...
```

Those shell/text-filter helpers are not required for lifecycle ownership. QML
already collects/parses stdout elsewhere in the same service.

### R18.2 — Connection name can be direct argv with first-line parsing

Current source:

```qml
command: ["sh", "-c", "nmcli -t -f NAME c show --active | head -1"]
onStreamFinished: root.networkName = text.trim()
```

Strict-lossless direction:

1. execute directly:
   `nmcli -t -f NAME c show --active`;
2. collect stdout;
3. select the first output line exactly as `head -1` does;
4. apply the same surrounding trim before publishing `networkName`.

Do not sort, prefer Wi-Fi, or select by active device. The current contract is
simply the first row emitted by `nmcli connection show --active`.

Required cases:

- zero/one/multiple active connections;
- Wi-Fi + Ethernet + VPN combinations;
- names containing spaces;
- empty first line / trailing newline fixtures;
- nonzero nmcli exit;
- transition to no active link, preserving the existing explicit stale-name
  clear performed by the parent status path.

### R18.3 — Archived Wi-Fi-strength note needed a row-order correction

Current source:

```qml
command: ["sh", "-c",
    "nmcli -f IN-USE,SIGNAL,SSID device wifi | awk '/^\\*/{if (NR!=1) {print $2}}'"]
stdout: SplitParser {
    onRead: data => root.networkStrength = parseInt(data)
}
```

The older archived note described this as a first-active-row selection. That is
not exact. The awk program prints **every** row whose first character is `*`
(except a hypothetical matching row at NR=1), and `SplitParser.onRead` assigns
`networkStrength` once per emitted line. If several active rows are present,
the **last emitted active row wins**.

A correct direct-argv replacement therefore should not arbitrarily stop at the
first active row.

Safe shape:

1. run directly:
   `nmcli -f IN-USE,SIGNAL,SSID device wifi`;
2. collect/iterate output lines in original order;
3. for every line beginning exactly with `*`, parse the same second
   whitespace-delimited field;
4. assign/update the candidate strength for every match so the final matching
   row wins, matching today's SplitParser effect;
5. if no active row is present, retain the current parent-path ownership of
   stale clearing rather than inventing a new value transition.

An alternate terse nmcli format may be possible, but it widens the parser proof
and is not necessary to remove the shell and awk processes.

Required oracle:

- one active AP;
- multiple visible APs with one active row;
- fixture with multiple active-marker rows proving **last-match** behavior;
- no active row;
- signal 0 and 100;
- malformed/non-numeric signal;
- SSID with spaces and punctuation;
- localized/header variants (current row matching depends on the literal active
  marker, not the header text);
- nonzero nmcli exit;
- exact final `networkStrength` value and publication timing relative to the
  parent status reconciliation.

### R18.4 — Structural process saving

For a connected Wi-Fi detail refresh, these two helpers currently account for:

```text
name:     shell + nmcli + head = 3 processes
strength: shell + nmcli + awk  = 3 processes
```

Direct argv keeps the two required nmcli processes and removes the four
intermediaries:

```text
name:     nmcli = 1
strength: nmcli = 1
```

So this specific subpath falls from six processes to two: **4 fewer helper
processes per detail refresh**. This is a bounded structural count, not a
whole-shell CPU percentage.

Do not mix this patch with the larger `updateConnectionType` shell pipeline,
which intentionally sequences three nmcli commands and has partial-failure/radio
fallback semantics. That deserves a separate proof if researched later.

### R18.5 — First-run wallpaper discovery shell wrapper is valid but too low leverage to promote now

`FirstRunExperience.qml` currently uses:

```text
/bin/sh -c 'find <wallpaper-dir> ...'
```

The shell could theoretically be removed by expressing the same `find` argv
directly through Process. That would save one helper process, but this path runs
only when the first-run marker is absent and wallpaper discovery is required.
It is therefore much lower leverage than the recurring Network detail path.

Leave it unpromoted unless a broader startup-helper cleanup is later assembled.
Any direct-find change must preserve stderr suppression, extension predicate,
path handling, completion/failure timing and deterministic final wallpaper
selection after the existing QML sort.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.


## Research continuation — round 19

Baseline: `dev` at `48459a53a76b785c2927b4834b53a27112378a43`.

This round revalidated two archived collection-hot-path findings against current
source and promoted them into the canonical ledger. Their current blobs match
the archived research identities, so the original structural observations still
apply.

Current source identities:

- `services/AppSearch.qml`: `74ea3c9e92860af62f10850c89118d79b7837543`;
- `services/TaskbarApps.qml`: `b05b0b39988a40faf7fa3cb84e6b0c747cf4a3ee`;
- `modules/bar/BarTaskbar.qml`: `3aca1b63e2633584c86f75c6a2e5eb2ebaebfdb3`;
- `modules/dock/DockApps.qml`: `11b3ea8cc17c91a1cf3b6a1f41f64f392d4dfcc9`.

### R19.1 — AppSearch identity-rule cache still fingerprints on every lookup

Current source keeps a compiled rule cache but validates it with:

```qml
const rules = Config.options?.windows?.appIdentityRules ?? []
const key = JSON.stringify(rules)
if (root._identityRulesKey === key)
    return root._identityRules
```

That means a logical cache hit still serializes the complete rule list.
`resolveWindowIdentity()` calls this path once per non-empty window identity.

Current repository search confirms collection-pass callers in:

- `services/TaskbarApps.qml`;
- `modules/dock/DockApps.qml`;
- `modules/bar/BarTaskbar.qml`;
- `modules/bar/BarTaskbarPreview.qml`;
- `modules/altSwitcher/AltSwitcher.qml`;
- `modules/altSwitcher/AltSwitcherNoVisual.qml`;
- `modules/waffle/taskview/WaffleTaskViewContent.qml`.

So one compositor snapshot can cause the same unchanged rule list to be
serialized repeatedly across multiple N-window passes.

Strict-lossless direction:

1. keep `_identityRules` as the compiled resident representation;
2. split parsing into an explicit rebuild helper;
3. rebuild once on initial demand/Config-ready;
4. bind a `Connections` target to the current
   `Config.options?.windows` object and rebuild on
   `appIdentityRulesChanged`;
5. if config reload can replace the nested JsonObject instance, ensure the bound
   target follows that replacement and performs one rebuild against the new
   object;
6. let `resolveWindowIdentity()` read the resident compiled list directly with
   no per-window JSON fingerprint.

Behavior oracle:

- empty/missing rule list;
- app-id-only rule;
- title-only rule;
- both-regex rule;
- malformed app-id/title regex;
- malformed rule followed by valid rule;
- multiple matches proving first-rule ownership;
- case-insensitive matches;
- empty window app id early return;
- live rule mutation;
- config file reload and nested-object replacement;
- desktop entries becoming available after rule compilation, proving the
  configured `desktopId` remains a string and is not eagerly resolved.

Compare every returned identity string and malformed-rule behavior against the
current implementation.

### R19.2 — Taskbar's local identity revision is not a real dependency

Current TaskbarApps owns:

```qml
property int _identityRulesRevision: 0

function onAppIdentityRulesChanged() {
    root._identityRulesRevision++
    refreshApps.restart()
}

function computeApps() {
    const identityRulesRevision = root._identityRulesRevision
    ...
}
```

The local variable is never used after assignment. Because `computeApps()` is
called imperatively from the one-shot timer, this read does not establish a
binding dependency for `apps`. The same signal handler already restarts the
actual refresh path.

Once R19.1 gives AppSearch explicit rule invalidation, remove the counter/read
but keep `refreshApps.restart()`. Treat this only as companion cleanup.

The nearby ignored-app RegExp compilation remains lower priority. TaskbarApps
recompiles configured ignored regexes on every model rebuild, but invalid regex
patterns currently emit a warning each time. A cache that silently remembers a
failure would change diagnostic log frequency, so do not bundle that behavior
into R19.1.

### R19.3 — BarTaskbar repeats pinned-list scans inside its sort comparator

In separate-pinned mode, BarTaskbar sorts running groups with:

```qml
const aIndex = pinnedApps.findIndex(p => p.toLowerCase() === a.lowerAppId)
const bIndex = pinnedApps.findIndex(p => p.toLowerCase() === b.lowerAppId)
...
return a.lowerAppId.localeCompare(b.lowerAppId)
```

and later publishes:

```qml
pinned: pinnedApps.some(p => p.toLowerCase() === lowerAppId)
```

For R running groups and P pins, the sort performs repeated O(P) scans during
O(R log R) comparator calls, then publication adds another O(R·P) pass.

The sibling Dock path already demonstrates the intended structural shape with a
precomputed rank/membership map. Bar cannot copy Dock blindly because the
fallback order differs: Bar deliberately keeps unpinned running apps
alphabetical.

Strict-lossless Bar algorithm:

1. build `Map<lowercaseId, firstIndex>` once from `pinnedApps`;
2. **only set a key if absent**, matching current `findIndex` first-occurrence
   behavior for exact/case-variant duplicates;
3. use map membership/rank for pinned-vs-unpinned and pinned-order comparison;
4. preserve `lowerAppId.localeCompare()` for two unpinned groups;
5. publish the `pinned` field from map membership;
6. leave pinned-only item creation, separator placement, focused state and
   toplevel grouping unchanged.

Required oracle:

- empty pin list;
- one/many running groups;
- all pinned/all unpinned/mixed;
- exact duplicate pins;
- case-variant duplicate pins;
- pinned id with no installed desktop entry;
- case normalization;
- alphabetical fallback among unpinned groups;
- focused/running flags and separator placement;
- exact final item identity/order.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.


## Research continuation — round 20

Baseline: `dev` at `43b5ab1a6417d7f566822c6e6d731b3eed3b5cf6`.

This round repairs a post-consolidation ownership gap. Round 13 said several
findings were “already owned” by the then-active cross-repo handoff. That handoff
is now archived by design, so high-confidence findings that still match current
source must be promoted into this canonical ledger rather than remaining only in
history.

Current source identities:

- `services/GameMode.qml`: `692f3e200b7c46835f44f152c88f231e2d0bd2b5`;
- `services/DesktopItems.qml`: `415be57a15cfe34f373c8d2290e481bf978643ae`;
- `modules/background/Background.qml`: `29bd40236ba9579077d361fb1012d4f994ef4a3a`;
- `modules/background/desktopItems/DesktopItemDelegate.qml`: `88000b9820fb3b68cee5a007cec6a698b50948ba`.

### R20.1 — GameMode recomputes the same fullscreen facts for many consumers

Current GameMode exposes three related reads over the same published Niri state:

- `hasAnyFullscreenWindow`;
- `hasVisibleFullscreenWindow`;
- `hasFullscreenOnOutput(outputName)`.

The first two are derived properties/functions in the singleton itself, while
`hasFullscreenOnOutput()` is called from many resident consumers. Current
repository search finds consumers in Bar, Screen Edges, Screen Corners, classic
Background, Waffle Background, SidebarHost, Abyss Perimeter,
WidgetPowerManager and family work-area guards.

Each consumer can therefore rescan the same `NiriService.windows` snapshot after
one windows/workspaces/outputs publication.

Strict-lossless derived state:

```text
fullscreenSnapshot = {
    any: bool,
    visible: bool,
    activeOutputs: { outputName: true, ... }
}
```

Build it once from the same authoritative inputs already used today.

For each window:

1. resolve its workspace from `NiriService.workspaces[workspace_id]`;
2. evaluate fullscreen with the existing fullscreen helper logic;
3. update `any` using the exact current fallback rules;
4. only for a resolved active workspace, update `visible`;
5. for a resolved active workspace with a known output, set that output in
   `activeOutputs`.

Then:

- `hasAnyFullscreenWindow` reads `snapshot.any`;
- `hasVisibleFullscreenWindow` reads `snapshot.visible`;
- `hasFullscreenOnOutput("")` returns `snapshot.visible`, matching current
  empty-name semantics;
- `hasFullscreenOnOutput(name)` becomes an O(1) output lookup.

The critical semantic boundary is missing workspace metadata. Current “any”
fullscreen detection can still become true through the service's single-output
fallback even when the workspace record is temporarily unavailable. Visible and
per-output state do **not** inherit that fallback: they require a resolved active
workspace. The snapshot must preserve that asymmetry exactly.

Do not merge focused-window auto-detection into this patch. GameMode's focused
window path handles ordering/freshness details separately; this candidate only
removes duplicate secondary scans.

Required oracle:

- zero outputs/windows;
- one output with temporarily missing workspace metadata;
- fullscreen on inactive workspace;
- fullscreen on active workspace;
- two outputs with one or both fullscreen;
- direct `is_fullscreen` path;
- size-heuristic path and ±2 px tolerance;
- layout update before workspace update;
- output geometry change;
- active/inactive workspace transition;
- fullscreen exit;
- empty and named output query parity;
- complete boolean parity for every existing consumer after each source update.

Structural saving is one O(N) derivation per relevant source snapshot instead of
O(C·N) scans for C fullscreen-query consumers.

### R20.2 — DesktopItems clones the full model once per output

`DesktopItems.items` is stored as an id->record object. Current `listItems()`
returns a fresh array of fresh shallow clones:

```qml
return Object.keys(root.items).map(itemId =>
    Object.assign({ id: itemId }, root.items[itemId]))
```

Classic Background renders one desktop-item model per output. Its per-output
helper begins from `DesktopItems.listItems()` and only then filters the result to
that output. Therefore every output independently clones the entire item set.

For M outputs and I items, a single items revision can create approximately
M·I presentation record clones before output filtering. The repeated full-list
copy is unnecessary because current DesktopItemDelegate does not mutate its
`itemData` object directly; writes go back through explicit service operations
such as update/remove/repair and drag persistence.

Strict-lossless direction:

1. let DesktopItems own one derived read snapshot:
   `[{id, ...record}, ...]`;
2. rebuild it only when `root.items` changes;
3. let Background consume that snapshot and perform only its existing
   per-output/fallback filter;
4. retain `listItems()` as a defensive-copy API if any imperative caller relies
   on receiving independent mutable records;
5. do not expose invalid storage-only records through the shared presentation
   snapshot.

A later service-level output-bucket cache is possible but unnecessary for the
first strict-lossless step because it would pull screen/focus invalidation into
the persistence service.

Required oracle:

- zero/one/many items;
- one/multiple outputs;
- create/update/remove/undo;
- rename/lock/layer changes;
- drag persistence;
- cross-output move;
- saved output that is no longer connected;
- focused-output fallback for orphaned items;
- invalid-record preservation remains storage-only;
- exact Repeater item order and identity after every `items` reassignment;
- proof that current presentation delegates never mutate shared snapshot records.

### R20.3 — DesktopItems grid-candidate sort remains MEASURE-FIRST

The archived DesktopItems research also noted that `arrangePosition()` builds
and sorts all grid candidates by squared distance before searching for the first
collision-free cell. That path is not promoted here.

It runs on bounded interaction/layout events rather than pointer-frame updates,
and the candidate count is constrained by the desktop-item pitch. Replacing the
sort with a custom nearest-cell traversal could change tie/order behavior for
small practical gain. Keep it MEASURE-FIRST until profiling shows arrangement
CPU matters on realistic grids.

### R20.4 — Canonical ownership rule after consolidation

Any older section that says a finding is “owned by the cross-repo handoff” is now
historical wording only. `docs/archive/optimization/CROSS_REPO_OPTIMIZATION_HANDOFF.md`
is evidence/history, not an active owner. A still-valid candidate must appear in
this canonical audit to be considered active research.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.


## Research continuation — round 21

Baseline: `dev` at `da982e25fdb13bcee446a7332b98d4c913e10cd1`.

This round continues the post-consolidation promotion pass. Three archived
findings were revalidated against current source; all three source blobs are
unchanged from their archived research baselines, so they are now active in the
canonical ledger rather than remaining history-only.

Current source identities:

- `services/NiriService.qml`: `4c8194493fd380bf0ad8c51bc62990ad0c232738`;
- `modules/common/widgets/SettingsSearchRegistry.qml`: `836c9c061039bae7508aa6b44973722409ddf1dd`;
- `modules/settings/ThemesConfig.qml`: `fa617e33a5a4672e970a46ee19c2a3dae2c309be`.

### R21.1 — Niri layout sort is repeated at the toplevel-match boundary

Normal window publication already does:

```qml
const nextWindows = sortWindowsByLayout(_pendingWindows)
windows = nextWindows
```

and output changes re-sort `windows` as well. Yet `sortToplevels()` starts from:

```qml
for (const niriWindow of sortWindowsByLayout(windows)) {
    ...
}
```

so every compositor sort pass allocates another enriched array, sorts it, maps
it back, and only then begins the Niri↔foreign-toplevel match.

A direct replacement with `for (const niriWindow of windows)` is **not**
strict-lossless because `handleWorkspacesChanged()` can change workspace
`idx` or `output`—both layout sort keys—without reassigning public
`windows`. It emits `windowOrderChanged()` instead. The extra sort inside
`sortToplevels()` currently repairs that derived order.

Strict-lossless direction:

1. maintain a private layout-sorted window view;
2. rebuild it on normal batched window publication;
3. rebuild it on `WorkspacesChanged`;
4. rebuild it on output geometry/topology changes and initial output fetch;
5. keep public `windows` assignments and `windowsChanged` signal count exactly
   as today;
6. keep `windowOrderChanged()` emissions unchanged;
7. let `sortToplevels()` iterate the private sorted view directly.

This composes with the existing Niri app-id bucket research: cached layout order
removes repeated O(W log W) preparation while app-id bucketing removes
impossible cross-app match comparisons.

Required oracle:

- open/close/change publication;
- focus-only changes;
- `WindowLayoutsChanged`;
- `WorkspacesChanged` changing idx;
- workspace moving outputs;
- `OutputsChanged` changing logical x/y;
- initial output fetch arriving after windows;
- zero-window transition;
- exact `windowsChanged`, `windowOrderChanged` and `activeWindowChanged`
  counts/order;
- complete `sortToplevels()` identity/order parity.

Do not switch `filterCurrentWorkspace()` to this private view as part of the
same patch. Its current ordering after workspace-only topology changes is a
separate correctness question, not an optimization entitlement.

### R21.2 — Settings search normalizes snapshot metadata again on every keystroke

`SettingsSearchRegistry.registerOption(meta)` already snapshots the searchable
metadata associated with a live control. There is no update-in-place API for
those search strings; lifecycle changes unregister/re-register entries.

Despite that, each `buildResults(query)` recreates normalized forms for every
entry:

```text
label.toLowerCase()
description.toLowerCase()
pageName.toLowerCase()
section.toLowerCase()
keywords.join(" ").toLowerCase()
```

Strict-lossless direction is to compute those private normalized strings once
when the entry is registered while retaining all current raw/public fields.
Search then reads the precomputed strings.

Required oracle:

- empty query;
- one/multiple terms;
- case variants;
- exact/prefix/mid-string matches;
- generated and provided keywords;
- page/section/description-only matches;
- unregister/re-register;
- page/control destruction/recreation;
- translated label/description as captured at registration time;
- exact score, matchedTerms and final result ordering.

Do not add a debounce. Immediate per-keystroke observability is part of current
behavior.

### R21.3 — Highlight markup is built before the top-50 cutoff

Current `buildResults()` computes highlighted label/description fields for every
matched entry, then sorts and returns only `out.slice(0, 50)`.

Highlight strings do not participate in scoring or sort order. A strict-lossless
pipeline can therefore:

1. score all entries exactly as today;
2. retain raw label/description and matchedTerms;
3. perform the identical sort;
4. take the exact same first 50;
5. call the existing `highlightTerms()` only for those returned entries.

The proof must compare the complete result object, not only count/order:
IDs, scores, matchedTerms, raw strings and generated markup all need parity.
Include overlapping terms and term-order-sensitive highlight cases.

### R21.4 — Saved-theme polling has O(T) child-process fan-out every two seconds

While the custom-theme editor is visible/expanded, ThemesConfig runs a repeating
2 s refresh. Current command shape:

```text
Bash
  for every saved *.json:
    basename
    jq
```

For T saved themes, an unchanged poll therefore starts approximately
`1 + 2T` processes.

The same output can be produced with:

- Bash parameter expansion for `name.json -> name`;
- a single jq process over the complete ordered input-file list, using
  `input_filename` (or equivalent explicit filename input) to derive the name;
- one compact JSON object per valid source file on stdout for the existing QML
  parser.

That bounds each poll to roughly one Bash + one jq regardless of T.

Required oracle:

- zero/one/many themes;
- spaces/dots/Unicode filenames;
- deterministic glob/output order;
- invalid JSON mixed with valid JSON;
- file deleted/replaced during scan;
- exact id/name/description/tags/colors parity;
- current warning/skip behavior;
- `savedThemePresets = []` reset and incremental SplitParser publication timing.

The larger idea—replace the fixed 2 s poll with filesystem-driven updates—is a
separate follow-up. Add/remove watchers are insufficient by themselves because
same-name overwrite must also be detected. Do not remove polling until overwrite
semantics are proven.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.


## Research continuation — round 22

Baseline: `dev` at `318e50891bf1e93475945926b64881ea489c357a`.

This round promotes four more archived findings whose source identities still
match current dev exactly. It also separates a small Hyprland fullscreen cleanup
from the larger Background range/occupancy work so the priority remains honest.

Current source identities:

- `services/WorldClock.qml`: `1260b2d2ed85cf70339c2c8f366c296655dc3c9a`;
- `modules/sidebarLeft/LocalMusicView.qml`: `d5b1880d5a1a3796f0faefe343cf3f2f9909953a`;
- `modules/sidebarLeft/SidebarLeftContent.qml`: `06c8e5aa355b97d14d606f7d152123d29a8b36ab`;
- `modules/background/Background.qml`: `29bd40236ba9579077d361fb1012d4f994ef4a3a`;
- `modules/waffle/background/WaffleBackground.qml`: `6e9bcbdf8daef77c9f8169ed998c44bc72b94fa6`;
- `modules/screenCorners/ScreenCorners.qml`: `3fc43bf7e1b7ec63fae6d27f55a5dd48fbb4cb00`.

### R22.1 — WorldClock eagerly owns editor-only timezone catalog state

The runtime clock needs the configured timezone set and current offsets/time.
Yet whenever WorldClock is materialized it also evaluates:

```qml
readonly property var timezoneList: ... Intl.supportedValuesOf("timeZone") ...
readonly property var comboModel: root.timezoneList.map(tz => ({
    label: root.labelFor(tz), tz: tz, icon: ""
}))
```

Repository occurrence inspection shows the full catalog is consumed by timezone
picker/editor surfaces, not ordinary clock rendering.

Strict-lossless direction:

1. replace eager picker catalog evaluation with an idempotent
   `ensureTimezoneCatalog()`;
2. keep catalog state empty until the first picker/editor requests it;
3. compute `Intl.supportedValuesOf("timeZone")` at most once per singleton;
4. build labels/model once and share them among picker instances;
5. retain the complete fallback timezone list and existing `labelFor()`
   formatting;
6. keep configured timezone values and clock entries independent of catalog
   readiness.

Required oracle:

- Intl supported-values path;
- fallback path when Intl support is absent/throws;
- normal clock rendering before catalog creation;
- widget edit popover opened first;
- Desktop Widgets Settings opened first;
- both surfaces opened in either order;
- selected index for every configured timezone;
- custom configured timezone absent from the catalog;
- change timezone and verify current clock/offset refresh parity.

The picker must still show the complete model on its first visible frame. No
permanent spinner/delayed-user-visible catalog is acceptable for this candidate.

### R22.2 — LocalMusic repeats immutable metadata normalization on every keystroke

Current search binding lowercases four fields and concatenates one haystack for
every track whenever `searchField.text` changes:

```text
lower(title) + " " + lower(artist) + " " +
lower(album) + " " + lower(folder)
```

For N tracks and Q intermediate query states, this performs roughly O(N·Q)
normalization/concatenation even though track metadata is unchanged during the
search session.

The containing Sidebar keeps only current/adjacent SwipeView loaders active, so
the optimization can remain view-local rather than adding session-wide music
RAM.

Strict-lossless direction:

1. lazily build `[{track, searchText}]` when query transitions empty ->
   non-empty;
2. use the exact current `String(track?.field ?? "").toLowerCase()` values and
   single-space concatenation;
3. reuse the prepared array for subsequent query edits;
4. invalidate immediately on `LocalMusic.libraryTracksChanged`;
5. clear the prepared array when query becomes empty;
6. return the original track object references in original order.

Required oracle:

- empty/whitespace-only query;
- title/artist/album/folder matches;
- mixed case;
- null/missing metadata;
- multi-word substring queries;
- duplicate tracks;
- rescan while search is active;
- clear then re-enter search;
- exact result identity/order.

Do not add fuzzy search, Unicode normalization, token ranking or debounce.

### R22.3 — Niri Background occupancy is recomputed per output and per family

Classic and Waffle backgrounds each derive:

```text
Object.values(workspaces)
  -> find active workspace for this output
  -> scan windows for matching workspace_id
```

for every output instance. With M outputs, W workspaces and N windows, a relevant
publication can therefore trigger work shaped like O(M·(W+N)) in each family.

Strict-lossless shared derivation:

- `activeWorkspaceIdByOutput` from the authoritative workspace snapshot;
- `occupiedWorkspaceIds` Set/map from the authoritative Niri windows snapshot;
- helper/read model returning whether one output's current active workspace is
  occupied;
- replace the derived map/revision whenever windows/workspaces change so QML
  consumers invalidate reactively.

Do not derive this from foreign toplevels. Current behavior intentionally trusts
Niri's own window/workspace ids.

Required oracle:

- zero windows/workspaces;
- one/multiple outputs;
- active workspace change;
- open/close/move window;
- cross-output move;
- workspace id/index/output topology change;
- focus-only change must not alter occupancy;
- output remove/re-add;
- exact classic/Waffle `hasWindowsOnCurrentWorkspace`, focus-presence and blur
  progress parity.

### R22.4 — Hyprland Background keeps a sorted array stronger than its consumers need

Classic Background currently constructs a monitor-local `relevantWindows`
array by filtering `HyprlandData.windowList` and sorting it by workspace id.
The array is then used only for:

- first workspace id;
- last workspace id;
- whether the active workspace has a window.

One scan can derive `{first,last,hasCurrent}` without retaining/sorting the full
array.

The current fallback must be copied exactly:

```qml
firstWorkspaceId = summary.first || 1
lastWorkspaceId = summary.last || 10
```

That means workspace id 0 remains treated as falsy even though the existing
filter permits it. Do not silently convert to `??` and change semantics.

Required oracle:

- no windows;
- negative/special workspace ids;
- workspace id 0;
- out-of-order workspace ids;
- current workspace occupied/empty;
- active workspace change without window-list reorder;
- monitor migration;
- one/multiple outputs;
- exact first/last range and occupancy parity.

### R22.5 — Hyprland fullscreen nested filters are a clean secondary cleanup

Background and ScreenCorners both build monitor workspace arrays, filter again
for active+fullscreen, and inspect element 0. The requested answer is only a
boolean/existence result.

Equivalent allocation-light shape:

```qml
Hyprland.workspaces.values.find(workspace =>
    workspace.monitor
    && workspace.monitor.name == monitor.name
    && workspace.active
    && workspace.toplevels.values.some(window =>
        window.wayland?.fullscreen))
```

Preserve loose monitor-name equality, active-workspace requirement and
Wayland-only fullscreen detection. Keep Niri on the GameMode authority path.
This ranks below R22.4 because it removes smaller temporary arrays rather than an
entire sort pipeline.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.


## Research continuation — round 23

Baseline: `dev` at `cb5d11621cb793c06a10ee19c72b7e40cbfb4031`.

This round promotes three archived memo/index findings whose current source
blobs still match the archived research identities exactly. All three move work
from frequent read paths to existing authoritative rebuild/invalidation
boundaries.

Current source identities:

- `services/AppSearch.qml`: `74ea3c9e92860af62f10850c89118d79b7837543`;
- `services/MprisController.qml`: `3a8184f9308f0816ea395ea26f182bb5a3fbcf15`;
- `services/Notifications.qml`: `a05c6744c123d8ed96ee19c8d04cccdbcdeeae0e`;
- `modules/dock/DockAppButton.qml`: `e82cf611338e518d70f8c95e45808217c7b90934`.

### R23.1 — AppSearch repeats the complete desktop-entry resolution chain for stable ids

`lookupDesktopEntry(appId)` already benefits from reverse maps, but each call
still re-enters the resolution chain from the top:

1. `DesktopEntries.heuristicLookup(appId)`;
2. direct lowercase/kebab/reverse-map probes;
3. scoped/reverse-domain normalization candidates;
4. suffix stripping;
5. last-resort token-overlap scans across desktop-id/startup-class maps.

The same app identity is requested repeatedly from Taskbar, Dock, Bar/Waffle
buttons, AltSwitcher, MPRIS hint resolution, ScreenTime repair, Settings and
other icon/desktop-entry helpers.

Strict-lossless memo:

- key by the **exact incoming appId string**;
- cache the final `DesktopEntry` object or an explicit miss sentinel;
- check the memo before running the existing chain;
- invalidate the entire memo immediately in
  `DesktopEntries.applications.onValuesChanged`;
- keep the existing debounced reverse-map rebuild unchanged.

Immediate invalidation is essential. Today a new/removed desktop entry can be
observed by `DesktopEntries.heuristicLookup()` before the 500 ms local map
rebuild completes. If memo invalidation waited for `_cacheRevision`, an old
hit/miss would remain stale during that window.

Required oracle:

- exact desktop id/stem;
- StartupWMClass;
- executable basename;
- whitespace/kebab normalization;
- scoped ids;
- reverse-domain ids;
- suffix stripping;
- token-overlap fallback;
- no match;
- case variants;
- repeated hit/miss;
- DesktopEntry add/remove/change between calls, including lookup before the
  debounced map rebuild fires;
- exact returned object identity/null parity.

### R23.2 — MPRIS has a second expensive resolver after AppSearch misses

`MprisController._desktopEntryForHint()` first tries AppSearch. On a miss it
runs an MPRIS-specific fuzzy resolver across DesktopEntries, inspecting fields
such as id/name/genericName/startupClass/command and performing normalization,
substring/token scoring.

The same hint can be resolved repeatedly while building:

- player display names;
- stream desktop entries;
- stream display names;
- stream icons;
- volume-mixer/media reactive bindings.

The R23.1 AppSearch memo accelerates only the first stage. It does not eliminate
this MPRIS-specific catalog scan after an AppSearch miss.

Strict-lossless memo:

1. clean the incoming hint with the existing helper;
2. key by that exact cleaned hint;
3. cache the **final** `DesktopEntry|null` result;
4. invalidate immediately on DesktopEntries changes;
5. leave every score, threshold, token and first-best/tie rule untouched.

Required oracle:

- direct AppSearch hit;
- exact fallback-field match;
- substring match;
- token-overlap match;
- below-threshold miss;
- equal-score candidates proving current tie behavior;
- empty/malformed hint;
- case/whitespace/version-suffix variants;
- repeated hit/miss;
- DesktopEntry add/remove/change between calls;
- exact `streamDisplayName()` and `streamIconName()` parity for representative
  players/nodes.

### R23.3 — Notification badge lookup repeats group normalization once per Dock app

Current Dock button badge code calls:

```text
Notifications.countForApp([originalAppId/appId, desktopEntry.name])
```

The helper normalizes its small identifier list, then walks every popup group
and normalizes each group appName again on every call.

Popup groups already have a clear authoritative rebuild boundary in
`Notifications._updateGroups()`. Derive a private normalized lookup in the same
transaction as `_cachedPopupGroupsByAppName`.

Parity rule is subtle: current semantics are **not** “sum every normalized
collision” and not “first caller identifier wins”. The outer iteration is popup
group order. Therefore the first popup group in current object enumeration order
that matches any normalized caller id wins.

Strict-lossless index should retain, for every normalized group key:

- the earliest group rank/order;
- that group's notification count.

When caller identifiers map to multiple normalized keys, choose the candidate
with the lowest stored group rank.

Required oracle:

- empty groups/identifiers;
- app-id versus display-name match;
- punctuation/case normalization;
- two caller ids matching different groups;
- two distinct group names normalizing to the same key;
- no match;
- timeout/read transition;
- group insertion/order change;
- exact count parity after every popup-group rebuild.

This composes with existing notification timer/object-reuse research but remains
a separate patch and oracle.

### R23.4 — New-service pass deliberately produced no promotion

A separate current-dev audit covered BluetoothStatus, Updates, RecorderStatus,
KeyboardIndicators and WindowPreviewService.

- **Updates** already uses the real `checkupdates` spawn as its availability
  probe instead of a duplicate command-v helper; its long-interval poll and
  timeout are intentional service behavior.
- **RecorderStatus** already separates 15/30 s idle polling, 1 s visible-demand
  polling and 1 s active-recording polling; it is substantially demand-gated.
- **KeyboardIndicators** prefers the native/event-driven lock-state monitor and
  uses coarse sysfs discovery only as fallback.
- **BluetoothStatus** performs two small connected-device scans, but normal
  Bluetooth device counts are tiny and static analysis does not justify adding
  another retained snapshot solely to save that micro-work.
- **WindowPreviewService** already bounds/caches capture ownership and coalesces
  request bursts; no new high-confidence saving was established in this pass.

These are intentionally not promoted merely to increase candidate count.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.


## Research continuation — round 24

Baseline: `dev` at `dc6813ff2ebf7fddff2d62c5fe18980918922316`.

This round revalidated four strict-lossless process/collection findings plus one
higher-leverage timer-ownership idea that remains timing-sensitive. Existing
canonical entries for MPRIS grace state and default-off startup probes were
found and deliberately not duplicated.

Current source identities:

- `services/Notifications.qml`: `a05c6744c123d8ed96ee19c8d04cccdbcdeeae0e`;
- `services/Weather.qml`: `53ef5db3a161e6df18a29b1e6a7c6192d2e35a79`;
- `services/ScreenTime.qml`: `1eabb174c464bf0a1e372ebbe8a43f671d2e9d89`;
- `modules/regionSelector/RegionSelection.qml`: `05fe24280c78cfe065dc70660827dedb68f316c0`.

Current MPRIS producer identities were also re-read on this baseline:

- Bar media: `7286bbfaa8bac3b29ee7e818cd937d60405556e8`;
- Vertical Bar media: `f95416165769171cf98031cb115cbfd7dc59cf0e`;
- BarMediaPlayerItem: `bb51644c4558b3362105ea262a1b41c4b865b920`;
- PlayerControl: `db9881c7ed6b20d7b26b1503c9256e8529a3677b`;
- PlayerBase: `df900423be11198b5aaf34474f2c2b2cc8dc7f41`;
- Sidebar MediaPlayerWidget: `e29709da3645e344fd302f2f37ff9d8f58aa4b81`;
- Control Panel MediaSection: `5abcef65e7c66160b3742d9c0abfaf48fb8043a9`;
- LockMediaWidget: `9e5d2434d656457568eac7578973061385ecc4f6`;
- Waffle MediaPaneContent: `dfea7b4e2cfb5a0629f8b77911dd56e7c883c354`;
- VolumeMixer: `612903a3b1d8cdd5ebb933a53abd90c79aa93f7b`.

### R24.1 — Notification timer paths rediscover objects they already own

Current public helper:

```qml
function cancelTimeout(id) {
    const index = root.list.findIndex(notif => notif.notificationId === id)
    ... stop/destroy/null timer ...
}
```

That helper remains useful when a caller owns only an ID, but several internal
paths already own the authoritative notification object.

**timeoutNotification(id)**

It first performs `findIndex`, then immediately calls `cancelTimeout(id)`,
which performs the same lookup again. Preserve the first lookup, retain the
object, cancel its timer directly, then keep popup mutation/list-change/signal
order unchanged.

**timeoutAll()**

`popupList` already contains the live objects. Current code does one ID lookup
per popup solely to reach each object's timer. For P popups in a retained
history list of N notifications, this can add P full-list scans.

**markReadForApp()**

The function already iterates `root.list`. Each matching object again calls the
ID helper, creating a nested scan.

Strict-lossless shape:

- introduce a private object helper such as `_cancelTimerForNotification(notif)`;
- stop, destroy and null the timer exactly as today;
- retain `cancelTimeout(id)` for external/ID-only paths and have it delegate to
  the object helper after its single lookup;
- in object-owning paths call the private helper directly;
- preserve `timeout(id)` signal order and the current two-pass popup clearing in
  `timeoutAll()` unless an oracle explicitly proves phase collapse equivalent.

Required oracle:

- one popup / long history;
- many popups;
- notification without timer;
- missing ID;
- `timeoutNotification`;
- `timeoutAll` exact timeout-signal sequence;
- `markReadForApp` zero/one/many matches;
- final timer=null, popup flags, group snapshots and list-change count.

### R24.2 — Weather primary provider carries an unnecessary Bash process

Current primary path builds:

```qml
const cmd = `curl -s --max-time 15 'https://wttr.in/${query}?format=j1'`
fetcher.command = ["/usr/bin/bash", "-c", cmd]
```

There is no pipe, redirect, conditional or shell expansion needed. The same
Weather service already invokes curl by direct argv for Open-Meteo fallback and
air-quality requests.

Strict-lossless replacement:

```text
["/usr/bin/curl", "-s", "--max-time", "15",
 "https://wttr.in/" + query + "?format=j1"]
```

Keep query calculation and encoding exactly as current source. This removes one
Bash process for each primary request or retry while retaining curl itself.

Required oracle:

- lat/lon request;
- city with spaces and non-ASCII characters;
- request-generation cancellation;
- curl nonzero exit;
- empty/non-JSON/valid JSON;
- three primary failures and existing Open-Meteo bypass window;
- force-refresh during another provider request;
- exact URL argument parity with the shell command's effective curl argv.

The GPS Geoclue path still uses a real parsing pipeline and is not included.

### R24.3 — ScreenTime already owns the file primitive needed for startup

ScreenTime persists today's state with `todayFileView.setText()`, but its startup
read separately spawns:

```text
bash -c 'test -f PATH && cat PATH || echo __NOFILE__'
```

The FileView can own this read as well:

1. when `_loadTodayFromFile()` begins, set `todayFileView.path` to the resolved
   current-day file URL;
2. retain the existing `_loadingToday` guard;
3. on FileView loaded, call `_finishStartupRead(todayFileView.text())` only for
   the active startup load;
4. map FileNotFound to `_finishStartupRead("__NOFILE__")`;
5. map other failures to the same current fallback behavior;
6. remove `startupReadProc` only after start/load failure parity is tested.

Important boundary: do not mechanically replace `rangeReadProc`. It batches
multiple history files into one ordered shell read; converting that path into
many FileViews could increase event-loop work and change ordering.

Required oracle:

- valid/missing/empty/malformed current-day file;
- enable/disable around initialization;
- duplicate load request while pending;
- first persistence after missing/valid startup;
- day rollover;
- non-FileNotFound FileView error;
- exact `ready`, `_todayData`, `_dirty`, session state and `dataChanged()`
  timing/order.

### R24.4 — Region Selector has two shell-string boundaries that do not need shell composition

Recorder start currently emits:

```qml
bash -c "<recordScript> --region '<region>' [--sound]"
```

The same record script is already directly exec'd for `--stop`, so executable
ownership is established. Start can use direct argv:

```text
[recordScriptPath, "--region", slurpRegion]
[recordScriptPath, "--region", slurpRegion, "--sound"]
```

Content-region detection currently uses an outer `bash -c` around a Bash
wrapper. Keep one interpreter because the wrapper is a Bash script, but pass the
script and args directly:

```text
["/usr/bin/bash", find-regions-venv.sh,
 "--image", screenshotPath,
 "--max-width", ...,
 "--max-height", ...]
```

This removes command-string parsing and quoting without changing the wrapper.

Required oracle:

- normal/negative-coordinate region if supported;
- record with/without sound;
- startup failure;
- exact region argument observed by fixture;
- image path with spaces/Unicode;
- exact max-width/max-height values;
- malformed detector output;
- RecorderStatus quick-check scheduling;
- detached process behavior.

Do not apply this mechanically to Copy/Edit/Search/OCR/screenshot capture paths;
those branches use real pipelines/conditionals or depend on temp-directory
ownership.

### R24.5 — Shared MPRIS ticker is higher leverage but not raw-signal-lossless yet

Current repository search still finds ten `positionChanged()` occurrences in the
media path: nine producer-style refresh owners plus LyricsService's listener.
Independent producers use roughly three cadence classes:

- PlayerBase: 500 ms;
- rich media surfaces: 1000 ms;
- Bar/VerticalBar/VolumeMixer: configured resource interval, commonly ~3000 ms.

Multiple visible surfaces can target the same `MprisPlayer`. The fastest timer
already emits that player's signal frequently enough for all attached bindings,
while slower timers can add redundant emissions and wakeups.

Candidate architecture:

- one lease owner per player identity;
- each visible/demanding consumer requests its current interval;
- ticker interval is the minimum active lease;
- zero leases stops the ticker;
- lease acquisition performs the equivalent of current `triggeredOnStart`;
- multi-player surfaces create one logical ticker per player, not one global
  active-player ticker;
- non-MPRIS/YtMusic direct playback paths remain outside this mechanism.

This remains **MEASURE THEN ADAPT**, because independent timers currently have
separate phases and signal count/timing is observable. A shared minimum-cadence
ticker could make positions fresher while still changing listener callbacks.

Capture signal/value traces for Bar-only, popup-only, Bar+popup,
Sidebar/ControlPanel, Lock transition, Waffle Action Center, two-player surface,
open/close, pause/resume and a non-default resource interval before deciding the
parity contract. The correct target is likely visible progress freshness and
bounded wakeups, not identical raw signal count, but that must be explicit.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.


## Research continuation — round 25

Baseline: `dev` at `14ca9f7415d6a30e3f8e862820c77ad2247d7b89`.

This round promotes three direct-argv process cleanups, repairs the archived
Settings World Clock ownership gap, and keeps the more ambitious Sidebar World
Clock cadence redesign explicitly oracle-gated.

Current source identities:

- common/Waffle Cloudflare model:
  `0ec62b42e71e805b3c18f2cbfc9ffb5cd78b0e3c`;
- Classic Cloudflare toggle:
  `fee5c5fa1e85ba12daa2fb963fb2d80239558059`;
- Android Cloudflare toggle:
  `6c0e743dd92f2aa3016cc08e108d1576bde025e2`;
- `services/Hyprsunset.qml`:
  `ad37a89247439f2133ba65fb2248b81edbdc90b3`;
- `services/ResourceUsage.qml`:
  `1d8e8693c230ee7450072366557b6070d433af58`;
- `modules/settings/InterfaceConfig.qml`:
  `6f9e2c644aafebc0b3b54ba34df14c272bbbe52d`;
- Sidebar `WorldClockWidget.qml`:
  `5f9272b1aeedc3fa91b76e3a13de150bb6e61829`;
- shared `services/WorldClock.qml`:
  `1260b2d2ed85cf70339c2c8f366c296655dc3c9a`.

### R25.1 — WARP status polling pays an unnecessary shell per refresh

All three WARP toggle families currently use:

```qml
command: ["/bin/sh", "-c", root.warpCliPath + " status"]
```

with a fixed `warpCliPath = "/usr/bin/warp-cli"`. There is no pipe,
redirection, expansion, condition or user-controlled shell composition.

Strict-lossless replacement:

```qml
command: [root.warpCliPath, "status"]
```

Keep the existing 5 s cadence, `triggeredOnStart`, visibility gates and explicit
post-action refreshes. This is not a cadence change; it removes only the
intermediate process.

At a 5 s cadence, one continuously open toggle instance can avoid about twelve
shell launches per minute. That count is structural, not a whole-shell CPU
claim.

Required oracle across common/Waffle, Classic and Android variants:

- installed connected/disconnected;
- daemon unavailable;
- nonzero status exit;
- current connected/disconnected/error stdout forms;
- panel open/close poll start/stop;
- connect/disconnect/service-start actions and immediate refresh;
- exact available/daemon/toggled/status/tooltip behavior.

### R25.2 — Hyprsunset probe can be direct argv without touching state ownership

Current probe:

```qml
["/usr/bin/bash", "-c", "hyprctl hyprsunset temperature"]
```

The Process already owns stdout, timeout and completion/error state. Replace only
execution with:

```text
["hyprctl", "hyprsunset", "temperature"]
```

or a project-standard resolved hyprctl path if PATH ownership is intentionally
made explicit.

Keep the 5 s timeout and every current output check, including empty output,
`Couldn't...` and `6500` inactive interpretation.

This is lower leverage than WARP because probes are not short-cadence periodic,
but it is a clean strict-lossless companion candidate.

### R25.3 — ResourceUsage process-backed GPU probes can drop Bash independently of demand gating

The larger canonical ResourceUsage optimization remains metric-demand gating.
For samples that still occur, NVIDIA and Intel paths currently add one Bash
process each.

**NVIDIA**

Run directly:

```text
nvidia-smi
  --query-gpu=utilization.gpu,temperature.gpu
  --format=csv,noheader,nounits
```

Consume stderr with the existing QML Process facilities. Reproduce current
`head -n 1` semantics by selecting the **first non-empty output row** before
parsing usage/temperature. Do not accidentally average or choose another GPU.

**Intel**

Run directly through timeout:

```text
/usr/bin/timeout 1 <intel_gpu_top> -J -s 500
```

Preserve the one-second hard timeout, 500 ms sampling request and existing
maximum-engine-busy parser.

Required oracle:

- NVIDIA one/multiple GPU;
- empty/malformed/stderr-only/nonzero NVIDIA output;
- Intel valid multi-engine JSON;
- absent busy field;
- malformed/partial output;
- timeout/nonzero/missing executable;
- exact final `gpuUsage`/`gpuTemp` parity and no new stderr noise.

At the default expensive-source minimum around 6 s, direct argv can remove up to
about ten shell launches per minute of active NVIDIA/Intel monitoring. If metric
demand gating eliminates those samples entirely, that larger saving naturally
wins first.

### R25.4 — Settings World Clock still carries N external date children per visible refresh

The Widgets Settings preview refreshes every 20 seconds while its section is
active. Current QML generates Bash source containing one command substitution
per configured timezone:

```text
$(TZ='zone' date '+...')
```

For N zones, each refresh therefore starts one Bash plus N `date` processes.

Current sibling implementations already prove the one-process shape:

- pass each timezone as an argv entry;
- loop over `"$@"`;
- set `TZ="$tz"` for Bash builtin `printf '%(...)T' ... -1`;
- emit one line per timezone.

Strict-lossless Settings migration must preserve:

- 20 s cadence and section visibility gate;
- 12/24-hour formatting;
- positive/negative offsets;
- output protocol `timezone|time|offset`;
- configured order;
- one process owner and current in-flight behavior.

For valid IANA timezone inputs this removes N child processes per refresh. For a
malformed string containing shell-significant characters, current code has
accidental command-string semantics. Safe argv handling is preferable, but the
project should explicitly classify such input as unsupported/sanitized rather
than pretending shell injection side effects are a strict contract.

### R25.5 — Sidebar World Clock process cadence is a larger but timing-sensitive target

The Sidebar widget currently launches one Bash process on every display refresh:

- every 30 s when seconds are hidden;
- every 1 s when seconds are shown.

That process emits time, UTC offset, localized date, day-of-year and hour24 for
all configured zones. The newer shared WorldClock service demonstrates that
timezone offset metadata can be refreshed sparsely while a local `now` value
advances display state in-process.

Candidate architecture:

1. resolve timezone metadata/offsets at startup, timezone changes and a sparse
   safety cadence;
2. tick visible time in-process;
3. when seconds are disabled, use a one-shot timer aligned to the next minute
   boundary rather than fixed 30 s polling;
4. when seconds are enabled, update once per second in-process with no shell;
5. retain the current Bash formatter as deterministic oracle/fallback until
   parity is proven.

Required corpus/oracle:

- UTC;
- DST and non-DST zones;
- +05:30, +05:45, -03:30 and date-line zones;
- minute boundary;
- midnight and year rollover;
- known DST transition;
- 12/24 h and seconds on/off;
- date text, offset label, dayDelta, local highlight;
- system-clock jump;
- timezone config change during an in-flight metadata refresh.

Also record child-process counts for five minutes of sidebar-open operation in
both normal and seconds modes before/after. This remains ORACLE-GATED rather than
declared strict-lossless from static analysis alone.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.


## Research continuation — round 26

Baseline: `dev` at `f5d0806c0bea4f8a9486ce68eb4345872fe30d23`.

This round returns to GPU/RAM residency. The archived media-art decode-size
finding was revalidated against current source. The relevant blobs remain at the
same identities as the original research, and direct foreground/background art
paths still decode without explicit source-size bounds.

Current source identities:

- `modules/common/widgets/MediaCrossSlideImage.qml`:
  `99aacfef3bc12d58ab341e5cd530a5d776263ab6`;
- `modules/mediaControls/presets/CompactPlayer.qml`:
  `4642a25def2eff69ffe450dd09ca336d8f4b68bf`;
- `modules/mediaControls/presets/FullPlayer.qml`:
  `e51ef3d470192a245fe19b26bef3fcca8dc2a98a`;
- `modules/mediaControls/presets/AlbumArtPlayer.qml`:
  `f9c123d6b82073872dcafb7d1b9ba99b4ffeddf9`;
- Waffle Action Center `MediaPaneContent.qml`:
  `dfea7b4e2cfb5a0629f8b77911dd56e7c883c354`;
- Waffle `WidgetsContent.qml`:
  `7919f08b523479a5348660f0b95993d0b0b57544`;
- Waffle lock / safe lock:
  `9cc7e75e21650c26572a17f61140b7d56fd9a734` /
  `86d038cdb3503b0aaae1d3c78b6fdb580263235b`;
- ii `VolumeMixer.qml`:
  `612903a3b1d8cdd5ebb933a53abd90c79aa93f7b`.

### R26.1 — Existing Hadalis media code already proves a conservative decode-bound shape

`MediaCrossSlideImage.qml` requests both transition layers at approximately 2×
logical presentation size. That is a strong in-tree precedent: it keeps the
cross-slide sharp while preventing an arbitrary source cover from dictating
steady decoded texture size.

The current direct-art paths below do not consistently have such a bound.

Confirmed examples on current dev:

- Waffle Action Center foreground art: ~104×104 logical px, no sourceSize;
- Waffle Widgets foreground art: ~108×108, no sourceSize;
- Waffle Lock and Safe Lock media art: 48×48, no sourceSize;
- ii VolumeMixer cover: 96×96, no sourceSize;
- CompactPlayer blurred card background: card-sized, no sourceSize;
- FullPlayer cover-art background: card-sized, no sourceSize;
- AlbumArtPlayer blurred/full cover background: card-sized, no sourceSize;
- Waffle Widgets background art feeding `FastBlur`: panel/card-sized, no
  sourceSize.

Several of these use `cache:false`, so simultaneously resident surfaces are not
relying on the shared Image cache to guarantee one retained representation.

### R26.2 — First promotion phase should target small foreground slots

For fixed/small cover slots, use a conservative policy no more aggressive than
current MediaCrossSlideImage precedent:

```text
requested width  >= ceil(presentation width  × 2)
requested height >= ceil(presentation height × 2)
```

or a DPR-aware physical-pixel equivalent proven at the supported fractional
scales.

Recommended first A/B surfaces:

1. 48×48 Lock/Safe Lock art;
2. 96×96 VolumeMixer art;
3. 104×104 Waffle Action Center art;
4. 108×108 Waffle Widgets foreground art.

These have the cleanest bounded presentation geometry and no blur-radius
interaction.

Keep unchanged:

- source URL/cache-busting;
- `PreserveAspectCrop`;
- async/cache policy;
- opacity/visibility transitions;
- smooth/mipmap flags where present;
- rounded clipping/masks;
- MediaArtwork resolver lifecycle.

### R26.3 — Blurred/card-sized backgrounds need a separate oversampling oracle

The same 2× rule should not be copied mechanically to every blurred background.
Blurred/card-wide sources are sampled across a larger surface and filtering can
amplify decode-size differences.

For CompactPlayer, FullPlayer, AlbumArtPlayer and Waffle Widgets background art:

1. request at least the actual visible card/body dimensions;
2. test 1×, 1.5×, 2× and DPR-aware variants;
3. preserve blur radius/kernel, crop, smooth/mipmap and opacity exactly;
4. choose the smallest target that remains below the project <1% visual budget
   across all required scales/covers.

Do not combine this experiment with opacity-mask removal, blur substitution or
MediaArtwork in-flight deduplication. Isolate decode residency first.

### R26.4 — Why the RAM opportunity is structurally meaningful

Illustrative raw RGBA arithmetic:

- 2000×2000 source: 16,000,000 bytes (~15.3 MiB) of pixel data;
- 216×216 target for a 108×108 2× slot: 186,624 bytes (~0.18 MiB).

This is **not** a claim that Qt/Hadalis RSS or VRAM will fall by exactly that
amount. Decoder implementations can use transient full-resolution buffers,
textures may have alignment/mipmap/effect overhead, and formats differ.
Nevertheless, the steady presentation texture has a large upper-bound gap when
a multi-megapixel cover is displayed in a ~100 px slot.

The opportunity compounds when the same large cover is independently loaded by
multiple `cache:false` surfaces.

### R26.5 — Required visual/resource oracle

Use fixture artwork covering:

- low-resolution source;
- 512 px, 1k, 2k and 4k covers;
- square and non-square ratios;
- high-frequency/text/detail-heavy artwork;
- 1.0 / 1.25 / 1.5 / 2.0 output scale;
- 48 / 96 / 104 / 108 px foreground slots;
- Compact/Full/AlbumArt/Waffle blurred backgrounds;
- track-change/cross-slide state where applicable.

Compare baseline and bounded variants with:

- global normalized pixel-difference ratio;
- detail/edge crop around cover boundaries;
- max per-channel delta;
- subjective cover/text sharpness inspection;
- RSS/PSS under the same visible-surface set;
- renderer texture/GPU memory when available.

Acceptance remains the user's original optimization policy: **<1% measured
visual difference**. If a target exceeds that budget, increase the decode bound
or reject it for that surface.

### R26.6 — Existing bounded paths are non-targets

Do not reduce these from static reasoning:

- `MediaCrossSlideImage.qml`: already uses 2× bounds;
- Waffle MediaOSD: already bounded;
- existing explicitly bounded wallpaper/avatar images;
- Clipboard decoded images: intrinsic decoded dimensions participate in current
  preview-sizing regression contracts and are a separate non-candidate.

No whole-Hadalis RAM/GPU percentage is claimed without measurement.


## Research continuation — round 27

Baseline: `dev` at `74701f6fc1e79a4259378bd0f9d4e5adce7971cd`.

This round promotes the remaining wallpaper/private-cache findings that were
still archive-only and carries the Niri focus-only idea into the active ledger
at its correct MEASURE/PROVE confidence. Current source identities still match
the archived research baselines.

Current source identities:

- `services/Wallpapers.qml`: `162dc98dcb742d7dec918a1da01659ef64265330`;
- `modules/common/widgets/ThumbnailImage.qml`:
  `64386a41505f5b1a3dc4942b2a549b04d0f0cf59`;
- `scripts/thumbnails/thumbgen.py`:
  `fdc9ce7e4557a4296e45e8d25aea9101caf90fa1`;
- `services/Wallhaven.qml`: `ce28a24564a964df2de7748080f8f7893e788ef8`;
- `modules/background/Background.qml`:
  `29bd40236ba9579077d361fb1012d4f994ef4a3a`;
- `services/CompositorService.qml`:
  `017c1405d39a2a2f954bb8d90d350ca4d4356f1d`;
- `services/NiriService.qml`:
  `4c8194493fd380bf0ad8c51bc62990ad0c232738`.

### R27.1 — Wallpapers private bookkeeping currently pays reactive-copy cost without reactive consumers

Two wallpaper bookkeeping structures are imperative sets in practice:

```qml
property var _singleThumbPending: ({})
property var _knownThumbnailOutputs: ({})
```

Current enqueue/remember paths clone the entire object, mutate one key, then
reassign. Drain/forget paths clone again before delete.

Repository-wide current-source search returns each private name only from
`services/Wallpapers.qml`. No binding, `Connections`, change handler or external
consumer depends on object identity. Public access to known outputs is through
imperative helpers such as `hasKnownThumbnail()`, `rememberThumbnail()` and
`forgetThumbnail()`.

Strict-lossless direction:

- set/delete keys directly on the private object;
- retain `_singleThumbQueue` order and current one-process-at-a-time ownership;
- retain duplicate-request suppression and every success/failure callback;
- do not mutate `videoFirstFrames` in place because that map deliberately wakes
  presentation bindings.

For n distinct pending keys, copy-on-write insertion alone copies approximately
0+1+...+(n-1) existing keys; draining repeats shrinking copies. This is a clear
allocation/GC shape even though individual maps are session-bounded by actual
requests.

Required oracle:

- repeated/distinct thumbnail requests;
- queue success/failure interleaving;
- pending membership before/during/after completion;
- remember/forget/hasKnownThumbnail parity;
- empty/malformed paths and multiple sizes;
- explicit assertion that no private-map Changed signal is observed.

### R27.2 — Batch thumbnail generation still leaves per-delegate existence-process fan-out

`ThumbnailImage.reloadThumbnail()` checks the shared known set first. If the
expected path is not known, an instantiated delegate can still launch:

```text
test -f <expected-thumbnail>
```

The bulk Python generator already centralizes expensive image/video creation and
emits machine progress, but its current token is only progress:

```text
PROGRESS completed/total FILE source
```

It is not proof of output readiness. `make_thumbnail()` can return false for an
already-fresh cache item and for failure, while the parent currently ignores the
result.

Strict-lossless protocol extension:

1. after every worker result, Python checks expected-output existence in-process;
2. emit a machine token such as `READY <source>` or `FAILED <source>`;
3. QML converts READY source+size to the exact expected thumbnail path and calls
   `rememberThumbnail()` before existing source notification/reload;
4. affected delegates then satisfy the shared known-set branch with no child
   `test`;
5. FAILED never enters the known set and retains today's fallback/retry path;
6. the shell fallback generator can keep end-of-directory reload checks until a
   comparable per-file success protocol exists.

Required fixture:

- already-fresh item;
- newly generated image;
- newly generated video;
- intentional decode/generation failure;
- partial gallery with mixed results;
- exact visible state/retry parity;
- process-count trace for representative gallery open.

### R27.3 — Video first-frame pending map has a success-side stale key

`ensureVideoStill()/first-frame` ownership keeps `_ffPending[videoPath]` as an
in-flight/no-retry marker. Current source does not remove the key after success.

Once success publishes `videoFirstFrames[videoPath]`, the stale pending entry
cannot change later answers because success cache is consulted first. Deleting
the pending key at successful publication is therefore behaviorally redundant
state removal.

Do **not** extend this cleanup to failure. Today a failed path leaves pending
true for the session and suppresses repeated ffmpeg attempts. Clearing it on
failure would be a product/correctness change and could create retry loops.
If retry behavior is ever repaired, model explicit failed/backoff state instead
of silently repurposing the optimization.

### R27.4 — Wallhaven's bounded private caches clone themselves on every insertion

Current private caches include bounded suggestion/count/tag structures with
limits up to 256. `_boundedCacheInsert()` performs:

```text
clone cache object
clone key-order array
remove existing key from order
write value
append key
shift/delete until within limit
reassign both properties
```

Current repository search finds the cache structures only inside
`services/Wallhaven.qml`. Reads are imperative request/cache checks; there is no
presentation binding on cache identity.

An in-place helper can therefore preserve exact LRU semantics:

1. if key already exists, remove its first key-order occurrence;
2. write/update value;
3. append key as newest;
4. evict from the front until at limit;
5. keep TTL/request queue/network behavior unchanged.

This removes O(K) object+array copying for each insert/update. Filling a bounded
cache from empty creates O(K²) cumulative copied entries today, even though K is
capped.

Required oracle:

- empty insert;
- same-key refresh moves key to newest position;
- eviction exactly at/past limit;
- repeated same key;
- TTL hit/miss;
- suggestion/count/detail request dedup;
- no cache/key-array Changed observer.

### R27.5 — Background wallpaper-size cache is the same safe class at lower leverage

Background owns a private 64-entry LRU for `magick identify` results. Successful
probes clone both object and key array before publishing one record. Current
repository search finds no reader outside `Background.qml`, and local reads are
imperative cache lookups.

Use the same in-place LRU rule as R27.4 while keeping exact ordering and
64-entry eviction. This ranks lower because wallpaper dimension writes are much
less frequent than Wallhaven tag enrichment.

Do not generalize in-place mutation to reactive/public maps such as
`videoFirstFrames`, ScreenTime data, WindowPreview cache or GlobalStates lease
maps. The qualification is specifically **private imperative cache with no
identity/change observer**.

### R27.6 — Niri focus-only fast path remains measurement-gated

Current Niri compositor wiring schedules `scheduleSort()` for both:

```qml
onWindowOrderChanged()  -> scheduleSort()
onActiveWindowChanged() -> scheduleSort()
```

and the 100 ms coalesced timer republishes:

```qml
sortedToplevels = NiriService.sortToplevels(ToplevelManager.toplevels.values)
```

A pure focus change should not alter membership, app id, title, workspace or
layout order; it should only alter which enriched item reports `activated`.
Structurally, rebuilding the already matched array by `niriWindowId` would be
cheaper than rerunning full matching.

Do not implement this from static reasoning alone. Quickshell may also emit
`ToplevelManager.toplevels.valuesChanged` on activation changes, and that signal
already schedules the full sort. If so, a separate focus fast path can be
redundant or race a structural update.

Measurement/oracle:

- instrument ordinary focus switches;
- count/order `activeWindowChanged`, `windowOrderChanged` and
  `ToplevelManager.valuesChanged`;
- record whether sort timer is scheduled once/coalesced or repeatedly;
- only run a focus-only refresh when no full structural sort is already pending;
- compare complete `sortedToplevels`: order, `_sourceKey`, `niriWindowId`,
  title/appId, action functions and activated flags;
- open/close/title/app/workspace/output changes must always keep the full path.

This remains lower priority than already source-proven Niri app-id bucketing and
private layout-sort reuse.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.


## Research continuation — round 28

Baseline: `dev` at `3dfb4305258d754e92fa4976fc3ebfe7a360956d`.

This round moved from archived findings to a fresh source audit. The strongest
new result is in AppCatalog's interactive search/reactive model path. Several
other files were inspected and deliberately not promoted when their current
lifecycle already bounded the work or when the only optimization would alter
persistence semantics.

Current source identities:

- `services/AppCatalog.qml`:
  `93d5902401311e3bdf68b49196e5d80a23a3ed61`;
- `modules/sidebarLeft/SoftwareView.qml`:
  `0ac749b6e09d09f3f2e4b326129dbda6e85c2351`;
- `modules/sidebarLeft/widgets/CryptoWidget.qml`:
  `c122a7d6f46ba669b0ce673205e6512e44ffa216`;
- `modules/sidebarLeft/plugins/PluginsTab.qml`:
  `8a0ece31a439468d2793a09669295da01b41f71a`;
- `modules/sidebarLeft/SidebarLeftContent.qml`:
  `06c8e5aa355b97d14d606f7d152123d29a8b36ab`.

### R28.1 — AppCatalog repeats immutable string normalization on every keystroke

Current search binding:

```qml
const _q = root.searchQuery.toLowerCase().trim()
...
result = result.filter(app =>
    app.name.toLowerCase().includes(_q)
    || app.description.toLowerCase().includes(_q)
    || (app.tags ?? []).some(t => t.toLowerCase().includes(_q)))
```

The curated catalog is loaded from one JSON file and those searchable strings do
not mutate during a normal AppCatalog session. The current implementation
therefore recreates the same lowercase strings for every query state.

Strict-lossless direction:

1. when the catalog JSON loads successfully, build private normalized search
   metadata once per entry;
2. preserve the public `root.catalog` records unchanged;
3. normalize with the exact current operations:
   - `name.toLowerCase()`;
   - `description.toLowerCase()`;
   - each tag's `toLowerCase()`;
4. preserve category filtering before text filtering;
5. for matched results return the original catalog record references in their
   original order;
6. rebuild the private index if catalog data is ever reloaded/replaced.

A parallel representation can be as small as:

```text
{id/reference, nameLower, descriptionLower, tagsLower[]}
```

or one exact-equivalent searchable structure. Do not introduce token/fuzzy
ranking or concatenate fields if that would change the current per-field
substring semantics.

Required oracle:

- empty query;
- leading/trailing spaces;
- mixed case;
- name-only, description-only and tag-only matches;
- multiple matching fields;
- category + query combination;
- no result;
- duplicate names/tags;
- exact result object identity/order;
- catalog reload/parse failure behavior.

### R28.2 — installedPackages currently forces an unchanged model to rebuild

`filteredCatalog` explicitly contains:

```qml
const _installed = root.installedPackages
```

but never uses `_installed` in the filtering or ordering result. This makes
package-status refreshes invalidate the entire filtered model anyway.

SoftwareView separately binds every card's installed state through:

```qml
readonly property bool isInstalled:
    AppCatalog.isInstalled(card.app?.id ?? "")
```

and `isInstalled()` directly reads:

```qml
root.installedPackages[appId]
```

So installed state has its own narrow reactive read at the presentation leaf.
The app list itself is determined only by:

- catalog;
- selected category;
- search query.

Strict-lossless direction:

1. remove the dummy `installedPackages` read from `filteredCatalog`;
2. leave `AppCard.isInstalled` and `AppCatalog.isInstalled()` unchanged;
3. leave package detection/refresh timing unchanged;
4. verify installed-map publication still updates badges/action icons/button
   behavior without replacing the Repeater model;
5. preserve list identity/order across installed-status refresh.

This matters after AppCatalog's package probe, manual refresh and the delayed
post-install/remove refresh. An installed-state change should update status
bindings, not rebuild an otherwise identical search/category projection.

Required oracle:

- package map empty -> populated;
- one app toggling installed/uninstalled;
- many statuses changing in one publication;
- active category/search during refresh;
- badge text/color/action icon/click behavior;
- exact Repeater item order and no false empty-state transition;
- explicit proof that QML dependency capture through `isInstalled()` fires on
  `installedPackages` reassignment.

### R28.3 — Fresh-source paths deliberately not promoted

**CryptoWidget** is already presentation-gated and uses direct curl argv. One
refresh writes its FileView cache after the price response and again after each
successful coin sparkline. Coalescing those writes could reduce JSON/disk churn,
but it changes crash/restart durability: today a completed intermediate
sparkline is persisted immediately and each write advances the persisted cache
timestamp. This is not a free strict-lossless cleanup. Only revisit with an
explicit cache-durability contract.

**PluginsTab** contains a 30-second Python rescan while Sidebar Left is open, but
current Sidebar composition has the Web Apps tab/component commented out and the
qmldir notes webapps are disabled pending quickshell-webengine rebuild. The file
is therefore not proven live/reachable in current production composition. Do
not claim runtime saving from changing its timer.

**NewsTickerWidget** uses only an in-process 12-second headline rotation timer
that is gated by visible + powerActive + not-paused and delegates network data to
the shared NewsService. No new child-process or hidden-work candidate was found.

**Hotspot toggles** already use direct `nmcli ... show --active` argv for the
recurring 5-second status poll. The remaining shell on hotspot start performs a
real ordered delete-then-create transaction with safe positional parameters, so
it is not equivalent to the WARP direct-argv cleanup.

**Idle**, **DeviceStatePersistence**, **DankSocket** and **ConflictKiller** were
also re-read. They are event-driven/bounded; ConflictKiller already consolidates
startup conflict detection into one deferred /proc scan. No promotion from this
pass.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.


## Research continuation — round 29

Baseline: `dev` at `9e45af654d13f4591a30cbd0d2d40d164eabfc9a`.

This round audits interactive collection transforms that had not appeared in the
canonical ledger. Two source-proven candidates are promoted; Wi-Fi/Bluetooth
list sorting was inspected but deliberately not promoted because the collections
are normally small and the family comparators are not identical.

Current source identities:

- Waffle `AllAppsContent.qml`:
  `50966e997860a152816487dca16900e64fd30577`;
- `services/AppSearch.qml`:
  `74ea3c9e92860af62f10850c89118d79b7837543`;
- Material `AutostartConfig.qml`:
  `643b5e1d2eee312986aa2cbc04c136ce8d061ad3`;
- Waffle `WAutostartPage.qml`:
  `ebc34416e01e1a0a8b940bd8626e2784bb5f9f2a`;
- `services/Autostart.qml`:
  `f94fa382ed7fed199f416106940817f5cdf31ea6`.

### R29.1 — Waffle All Apps re-sorts the desktop-entry catalog on every filter edit

Current `groupedApps` performs:

```qml
const all = DesktopEntries.applications.values
    .filter(e => !e.noDisplay
        && (filter.length === 0
            || (e.name || "").toLowerCase().includes(filter)))
    .sort((a, b) => (a.name || "").localeCompare(b.name || ""))
```

then groups that sorted list alphabetically. A second property, `flatApps`, walks
all groups and reconstructs the flat list solely so Enter can launch the first
filtered application.

The alphabetic order depends on DesktopEntries membership/name changes, not on
the query. Search edits only remove elements from an already ordered set.

Strict-lossless projection shape:

1. derive one private base list whenever
   `DesktopEntries.applications.values` changes:
   - keep only `!noDisplay` entries;
   - sort with the exact current
     `(a.name || "").localeCompare(b.name || "")` comparator;
   - optionally pair the original object with its lowercase name once;
2. for every `filterText` edit, linearly filter that already sorted projection;
3. build letter groups from the filtered ordered array without a second sort;
4. let `flatApps` be the same filtered array (or a direct alias/reference),
   rather than flattening the groups;
5. keep grouping/letter derivation exactly as current source.

Do **not** simply replace the source with `AppSearch.list` in the first patch.
AppSearch is indeed already alphabetically sorted, but it intentionally rebuilds
500 ms after DesktopEntries `valuesChanged`. All Apps currently reacts directly
to the source collection, so that substitution would alter update latency.
A local/source-revision projection preserves today's timing.

Required oracle:

- empty app catalog;
- no filter;
- every-keystroke filter sequence;
- leading/trailing spaces and mixed case;
- equal-name apps proving stable tie order;
- noDisplay entry add/remove/toggle if mutable in fixtures;
- DesktopEntry insert/remove/rename while page is resident;
- non-ASCII/locale-sensitive names;
- section letters and letter-index scrolling;
- Enter launches exactly the same first app;
- exact original DesktopEntry object identity/order.

Structural work changes from filter + O(M log M) sort + grouping + flatten on a
query update to ordered filter + grouping, where M is the query-matching subset.

### R29.2 — Autostart settings sort invokes a list-scanning status predicate inside the comparator

Both Material and Waffle settings pages currently implement the same logical
pipeline:

```text
AppSearch.list
  -> filter by lowercase name/genericName
  -> sort:
       Autostart.isAppOn(a)
       Autostart.isAppOn(b)
       enabled first
       then localeCompare(name)
```

`AppSearch.list` is already rebuilt alphabetically:

```qml
Array.from(DesktopEntries.applications.values)
    .sort((a, b) => a.name.localeCompare(b.name))
```

so the second alphabetical sort is only needed because the comparator is also
partitioning enabled apps ahead of disabled apps.

More importantly, `Autostart.isAppOn(app)` is not an O(1) field read. It:

1. calls `isAppEnabled(app.id)`, which scans managed `entries`;
2. if not enabled there, calls `isAppExternal(app)`, which scans external
   startup lines and performs token matching.

Calling that predicate for both operands across O(A log A) comparator calls can
therefore multiply managed/external scans substantially.

Strict-lossless replacement:

```text
enabled = []
disabled = []
for app in already-alphabetical AppSearch.list:
    if query does not match: continue
    if Autostart.isAppOn(app): enabled.push(app)
    else: disabled.push(app)
return enabled + disabled
```

This evaluates `isAppOn()` exactly once per filtered app. Because the input is
already alphabetically ordered, each partition preserves that order. JavaScript's
current stable sort likewise preserves source order for equal names/status, so a
stable partition reproduces duplicate-name ordering.

Required oracle for both Material and Waffle pages:

- no apps / no startup entries;
- managed enabled/disabled entry;
- external `gtk-launch` match;
- external raw executable match;
- same app represented by managed + external lines;
- disabled external line;
- search by name and genericName;
- mixed case and empty query;
- duplicate/equal app names;
- Autostart entries/externalLines changed while page is visible;
- exact app object identity/order;
- per-row `isOn` and `isExternal` behavior unchanged.

A future service-side index for managed/external app membership may further
reduce `isAppOn()` cost, but that has a broader parser/invalidation contract.
The one-pass UI partition is already valuable without adding retained service
state.

### R29.3 — Wi-Fi/Bluetooth sort duplication is not promoted from static analysis

Waffle and classic Wi-Fi surfaces currently use the same active-first,
strength-descending comparator. Centralizing that projection might remove a
second sort if both surfaces are resident, but Network device sets are usually
small and moving the sort into the always-resident Network singleton can also
create work while no list surface is visible. No demand/lifecycle proof yet
shows a net strict-lossless win.

Bluetooth is even less suitable for a mechanical shared sort:

- Waffle orders connected -> paired -> alphabetical;
- classic dialog additionally places meaningful names before MAC-like names.

Do not merge those policies merely to share computation. Revisit only if a
trace shows list sorting is material in dense-device environments.

### R29.4 — Deferred search services are already doing the important preparation

`services/deferred/Cliphist.qml` and the emoji search path were inspected in
this collection pass. Cliphist already maintains revision-keyed prepared fuzzy
entries, bounded top-K insertion for limited queries and equality suppression on
list refresh. Those are precisely the kinds of transforms this audit would
otherwise propose. No new high-confidence optimization is promoted there.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.


## Research continuation — round 30

Baseline: `dev` at `d0e554030d3962c9080bd95db54c0c04d85dcc8f`.

This round follows the previous collection-pass work one level deeper. Autostart
has an authoritative parse/mutation boundary suitable for exact membership
indexes, while Dock Settings has immutable-per-revision app metadata suitable for
a prepared search projection.

Current source identities:

- `services/Autostart.qml`:
  `f94fa382ed7fed199f416106940817f5cdf31ea6`;
- Material `AutostartConfig.qml`:
  `643b5e1d2eee312986aa2cbc04c136ce8d061ad3`;
- Waffle `WAutostartPage.qml`:
  `ebc34416e01e1a0a8b940bd8626e2784bb5f9f2a`;
- `modules/settings/DockConfig.qml`:
  `b8c63a0e49425c038e99812b6cd01668622304ca`;
- `services/AppSearch.qml`:
  `74ea3c9e92860af62f10850c89118d79b7837543`.

### R30.1 — Autostart status reads repeatedly scan already-parsed startup state

Current public helpers are scan-based:

```text
isAppEnabled(id)
  -> scan entries until first matching app desktopId

isAppExternal(app)
  -> scan externalLines
       -> enabled?
       -> _appMatchesTokens(app, tokens)

isAppOn(app)
  -> isAppEnabled
  -> if false, isAppExternal

appEntrySource(app)
  -> scan entries for any managed match
  -> if none, isAppExternal
```

Those helpers are used by both Autostart settings families for list partitioning
and again by each row's `isOn` / `isExternal` bindings.

The source data changes only at clear authoritative boundaries:

- startup-file parse/reload publishes `entries` and `externalLines`;
- managed mutations replace `entries` through add/remove/toggle/setAppEnabled;
- external lines change only through file reload.

That makes lookup indexes safer and cheaper than repeated view-local memoization.

### R30.2 — Exact managed index must preserve first-match behavior, not merely membership

Current `isAppEnabled(desktopId)` walks `entries` from index 0 and returns the
**first** matching managed app's `enabled` flag. That matters if malformed or
hand-edited managed content contains duplicate desktop ids.

Current `appEntrySource(app)`, in contrast, returns `managed` if **any** managed
entry exists for the exact desktop id, regardless of enabled state.

Therefore one boolean Set is insufficient. A strict index can keep:

```text
managedPresence[exactDesktopId] = true
managedFirstEnabled[exactDesktopId] = first matching entry.enabled === true
```

Keys must remain exact/case-sensitive because current managed lookup compares:

```qml
e.desktopId === String(desktopId ?? "")
```

Do not lowercase managed ids as a convenience.

Rebuild/update this index after every `entries` replacement. The simplest proof
surface is a derived/rebuild helper called at the same assignments rather than
trying to maintain many incremental branches first.

### R30.3 — External matching can be indexed without changing its token semantics

Current `_appMatchesTokens()` lowercases external tokens/app identity and has two
forms.

For enabled `gtk-launch` lines:

```text
tokens[0].toLowerCase() == "gtk-launch"
key = tokens[1].toLowerCase().replace(/\.desktop$/, "")
match iff key == app.id.toLowerCase()
```

For every other enabled external spawn line:

```text
t0 = lowercase(tokens[0])
b0 = lowercase(basename(tokens[0]))
match iff app.idLower == t0 || app.idLower == b0
      || app.command0BasenameLower == t0
      || app.command0BasenameLower == b0
```

Equivalent derived indexes are therefore:

```text
externalGtkLaunchIds = Set(normalized t1)
externalRawKeys      = Set(t0 and b0 for enabled non-gtk lines)
```

Then `isAppExternal(app)` checks at most:

- normalized app id in `externalGtkLaunchIds`;
- normalized app id in `externalRawKeys`;
- normalized command-0 basename in `externalRawKeys`.

Disabled external lines must never enter either set.

This changes repeated O(E) scans into bounded key lookups while preserving the
current matching language exactly.

Required Autostart oracle:

- empty state;
- one/many managed entries;
- duplicate managed ids with first entry enabled/disabled permutations;
- exact-case and case-variant managed ids;
- external enabled/disabled `gtk-launch`;
- `.desktop` suffix stripping on external gtk-launch only;
- external raw absolute executable path;
- raw basename match against app id;
- raw basename match against app command basename;
- managed+external match where managed source still wins;
- every add/remove/setEntryEnabled/setAppEnabled operation before file-save
  completion;
- external file edit/reload;
- identical `isAppEnabled`, `isAppExternal`, `isAppOn` and
  `appEntrySource` results for all fixtures.

R29's stable partition and this service index compose cleanly: R29 ensures one
status query per app during list construction, and R30 makes that query O(1).

### R30.4 — Dock Add Applications rebuilds stable searchable metadata on each query edit

Current `DockConfig.filteredAddApps()` performs on every binding evaluation:

1. lowercase every configured pinned id and create a Set;
2. walk all `AppSearch.list` apps;
3. skip pinned ids;
4. build for every remaining app:

```text
(name + " " + genericName + " " + comment + " " + id).toLowerCase()
```

5. substring-filter by query;
6. sort results by `name ?? id`.

App metadata and pin membership do not change on every keystroke. Prepare them at
their actual invalidation boundaries instead.

Strict-lossless shape:

1. when `AppSearch.list` or `dock.pinnedApps` changes, build an unpinned
   projection containing:
   - original app object;
   - exact lowercase haystack from today's four fields;
2. sort that prepared projection once with the exact current comparator:
   `String(name ?? id ?? "").localeCompare(...)`;
3. on `pinnedAppSearchField.text` change, lowercase/trim the query once and
   filter the prepared projection;
4. return original app references only.

Even though AppSearch itself is alphabetically sorted, retain Dock's explicit
`name ?? id` comparator during preparation for strict parity with unusual
entries missing a name.

Required Dock oracle:

- zero/many apps;
- zero/many pins;
- case-variant pinned ids;
- missing name/generic/comment/id fields;
- match from each searchable field;
- query whitespace/case;
- pin add/remove while dialog is open;
- AppSearch list revision while open;
- duplicate/equal sort keys;
- exact original object identity/order and Add button behavior.

### R30.5 — TLP/monitor-settings pass did not justify a new canonical candidate yet

The current TLP Settings service performs substantial schema grouping/filtering,
but those transforms mix runtime capability filtering, version adaptation,
pending/stale value preservation and label generation. A simple “cache all
lowercase labels” patch would have a broader invalidation surface than the
AppCatalog/SettingsSearch cases. Profile before promoting another retained
schema index.

Monitor visibility/Niri settings paths were also inspected. Their collections
are bounded by monitor/workspace configuration size and are dominated by user
interaction rather than recurring large-list work. No source-only high-value
candidate is added from those files in this round.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.

## Research continuation — round 31

Baseline: `dev` at `e5f7e26345fd10b5c8256f9297155f1044220975`.

This round deliberately moves away from the search/indexing cluster covered by
rounds 28–30. The strongest new work is in shared shell-layout/widget-layout read
paths that allocate or normalize immutable/revision-scoped data repeatedly. A
smaller DateTime candidate removes formatting work that inherits the global
clock's highest precision without needing that precision itself.

Current source identities:

- `services/ShellLayoutController.qml`:
  `88820adc872f6f0d5f54ed45e178251b87503d9b`;
- `services/DesktopWidgetLayout.qml`:
  `a2e472cb702fdeb69fcdb758f4aa63ebdce1bf22`;
- `services/DateTime.qml`:
  `6e99a0a319dbbd84635492c0ca6fcd617c2f175c`;
- `services/DailyNoteTodoBackend.qml`:
  `b43c4daaee1c6fc6c99a154bc9cbde168b72edfb`.

### R31.1 — ShellLayoutController deep-clones static descriptors on internal read paths

`_descriptors` is a readonly five-record literal. Public `descriptor()` and
`surfacesForFamily()` intentionally return deep copies through:

```qml
JSON.parse(JSON.stringify(value))
```

That is a sensible mutation-isolation boundary for callers. The controller's own
read-only paths currently cross the same boundary unnecessarily:

```text
currentState()       -> descriptor()
legalSlots()         -> descriptor() -> clone(desc.slots)
validatePlacement()  -> descriptor() -> currentState() ...
setProperty()        -> descriptor()
resetSurface()       -> descriptor()
```

This matters because the controller is used from persistent/reactive surfaces:
sidebar hosts and Abyss perimeter bindings call `currentState()`, Settings and
the live layout editor call state/slot helpers, and validation can nest multiple
state lookups. A single placement validation can therefore serialize/parse the
same tiny immutable descriptor more than once before doing the actual config
work.

Strict-lossless shape:

1. add a private `_descriptorRef(surfaceId)` that returns the first matching
   object in `_descriptors`;
2. keep public `descriptor()` as a deep-copy wrapper around that reference;
3. keep `surfacesForFamily()` returning fresh cloned descriptors;
4. use the private reference only inside controller code that does not mutate
   descriptor fields;
5. keep `legalSlots()` returning a fresh array, so callers cannot mutate the
   canonical `slots` array.

Required oracle:

- all five known ids and one unknown id;
- both `ii` and `waffle` family filtering/order;
- mutate every nested array in a returned public descriptor, then prove a later
  `descriptor()` / `surfacesForFamily()` call is unchanged;
- prove repeated public calls still return fresh object/array identities;
- exact `currentState()` output for sidebar, bar, dock and Waffle bar states;
- exact `legalSlots()` values/order plus fresh-array identity;
- `validatePlacement()`, `moveSurface()`, `setProperty()`, `resetSurface()`
  and `diagnosticState()` output parity across valid/invalid inputs.

This is a pure serialization/allocation removal. No config, geometry, visual,
input or output-ownership behavior needs to change.

### R31.2 — DesktopWidgetLayout rebuilds output-policy structures for repeated widget reads

The read path is currently intentionally reactive but recomputes more structure
than its answers require.

`enabled(output, widget, fallback)` does:

```text
outputAllowed(output)
  -> read Config.revision
  -> rebuild configured output array
  -> rebuild connected-screen name array
  -> includes/some membership scans

value(output, widget, "enable", fallback)
  -> widgetOverride()
  -> outputRecord()
  -> linear scan of outputOverrides
```

This is called from the desktop Background, Widget Manager, monitor-visibility
Settings and the Waffle background clock. A Config revision can therefore make
multiple widget/output bindings repeat the same configured-screen normalization,
connected-screen projection and output-record scan.

There is a second avoidable read-side cost:

```text
effectiveEnabled()
  -> savedOutputNames()
  -> _normalizedRecords()
       -> deep clone records/widgets
       -> merge duplicate output records
  -> map(output)
  -> enabled() for saved outputs
```

`_normalizedRecords()` is appropriate for mutation paths because those paths
need a detached, merge-safe structure before writing Config. It is stronger than
necessary just to obtain the ordered unique output names used by
`effectiveEnabled()`.

Strict-lossless shape:

- retain `_normalizedRecords()` for writes;
- derive a private **first raw record by normalized output** index for
  `outputRecord()` so current first-match behavior is preserved exactly;
- derive ordered unique saved-output names directly from raw records without
  deep cloning widget payloads;
- derive configured-output and connected-output membership snapshots from their
  actual Config/screens invalidation boundaries;
- ensure the snapshots themselves depend on `Config.revision` where the
  current code deliberately uses it to force reevaluation;
- keep `widgetOverride()` returning the original stored override object, not a
  clone, because current callers may observe that identity.

Important malformed/legacy contracts:

- `outputRecord()` currently returns the **first** raw record whose trimmed
  `record.output` equals the trimmed query;
- `_normalizedRecords()` merges later duplicate records for mutation output,
  which is a different contract and must not be substituted for the read index;
- configured `screenList` entries are stringified but not trimmed;
- if configured outputs exist but none are currently connected,
  `outputAllowed()` falls back to allowing the queried output;
- empty/malformed records and widget maps must keep current fallback behavior.

Required oracle:

- empty records and empty screen list;
- one/many outputs and widgets;
- duplicate raw records for one output with conflicting override values;
- leading/trailing whitespace in record output names;
- leading/trailing whitespace in configured screen-list entries;
- missing/null/non-object widget maps;
- one configured connected output, multiple connected outputs and no matching
  connected configured output;
- hotplug/remove while bindings are live;
- unrelated `Config.revision` changes;
- exact original override-object identity;
- `effectiveEnabled()` ordering/result parity;
- all mutation functions still publish the same normalized Config payload.

The expected gain is repeated CPU/allocation reduction, especially on
multi-widget/multi-output config updates. The tiny derived maps/sets are a
bounded RAM trade, not a RAM-saving claim.

### R31.3 — DateTime's date-only strings inherit 1 Hz invalidation

The shared clock currently selects:

```qml
precision: secondPrecision || screenLocked
    ? SystemClock.Seconds
    : SystemClock.Minutes
```

Five formatted string bindings then depend directly on `clock.date`. Two need
time precision, but these three are calendar-only:

- `shortDate`;
- `date`;
- `collapsedCalendarFormat`.

With second precision enabled—or simply while the screen is locked—those three
bindings can run locale date formatting on every second tick even when the
calendar day is unchanged.

A conservative replacement does **not** add another clock or reduce the shared
clock precision. Instead, keep observing the same `clock.date` and maintain a
private key such as:

```text
year / month / day
+ shortDateFormat
+ dateFormat
+ effective locale identity
```

Only when that key changes should the three date-only strings be reformatted.
`time`, `timeDisplay`, and the existing `onMinutesChanged()` uptime refresh
remain untouched.

Required oracle:

- minute precision and second precision;
- lock/unlock precision transitions;
- 23:59:59 -> midnight rollover;
- manual clock jump across a date boundary;
- timezone change crossing the local calendar day;
- date-format changes while the day is unchanged;
- locale change if supported live by the session;
- exact strings before/after plus unchanged `time`, `timeDisplay` and
  `uptime` notification cadence.

This is a CPU/string-allocation micro-optimization, not a priority above the two
layout-service candidates.

### R31.4 — DailyNoteTodoBackend's 60 s timer is not a minute scan

A timer/process pass inspected `DailyNoteTodoBackend.qml` because it owns both a
60 s repeating timer and a Python scanner. Static inspection shows they are not
coupled on every tick.

The repeating timer only:

1. formats today's `yyyy-MM-dd`;
2. compares it to `sourceDate`;
3. schedules a refresh only when the date changed.

Actual note edits are already watched by `FileView.watchChanges` and coalesced
through `scanDebounce`. The Python scanner is therefore **not** launched once
per minute by the steady-state timer.

Replacing this with a computed “next midnight” one-shot timer would add
suspend/resume, wall-clock jump and timezone-change edge cases for very small
wake-up savings. Do not promote this path without profiler evidence that the
single active minute comparison is material.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.

## Research continuation — round 32

Baseline: `dev` at `04d40521412561718dbbffc9fcfeeec0eedabcc1`.

This round was reconciled against five concurrent companion commits that landed
after round 31. The new HEAD changes Aqua/Octo companion code but does not modify
the canonical optimization ledger or the ShellUpdates, Waffle Task View,
NiriService, MinimizedWindows and Waffle TaskAppButton sources underlying the
three larger findings below. AquaMind was re-read from the new HEAD before its
micro-candidate was retained.

Current source identities:

- `services/ShellUpdates.qml`:
  `51e7eff2300e169ee0021673757dc9f4f79556d9`;
- `setup`:
  `f185edf66e9fb57d81e8441134af55dbddaa769d`;
- `modules/waffle/taskview/WaffleTaskViewContent.qml`:
  `8ee8ff511dafab601a840ebc0475e18563b41034`;
- `services/NiriService.qml`:
  `4c8194493fd380bf0ad8c51bc62990ad0c232738`;
- `services/MinimizedWindows.qml`:
  `ced7e049ef5942dea1ca5f3395eb9b614e9ecaf6`;
- `modules/waffle/bar/tasks/TaskAppButton.qml`:
  `500c22e179e8ab88988e0bfc40f97b9d4e67fe81`;
- `services/AquaMind.qml`:
  `8f237b0fe8225ae0d15d112d75419928b383ba60`;
- `modules/abyss/companion/OctoTentacles.qml`:
  `eb5754f499d9dd7cf24c7e1d44f3f30f6dc55b63`;
- `modules/abyss/companion/WaterDropletBody.qml`:
  `d8d248b692c8b693204a1b17852adf6a3d0cbaa3`;
- `modules/abyss/companion/AquaPresence.qml`:
  `d579b5d9cfca7b314e4185f23091d9e7e76abc4e`.

### R32.1 — ShellUpdates spawns a process every two seconds only to read one file

The live update-progress path is:

```text
Timer updateProgressPoller
  interval: 2000
  repeat: true
  while isUpdating:
      updateProgressReader.running = true

Process updateProgressReader
  command: ["cat", updateStatusPath]
  -> parse progress / updating / failed
```

A second `Process updateStatusReader` runs `cat` for watchdog checks. These
children do not perform update work; they only transport a few bytes already
stored in a known local state file.

The service already owns `updateResumeFile`, a blocking `FileView` pointing
at the same status path, and already calls `reload()` / `text()` during
restart recovery. The strict-lossless first step is therefore narrower than an
event-driven redesign:

1. keep `updateProgressPoller.interval === 2000` and its start/stop lifetime;
2. on each tick, reload/read a FileView and feed the exact current parser;
3. use the same helper from the 120 s watchdog;
4. preserve `updateResumeReader` separately because it also computes boot epoch
   and compares status-file mtime to reject stale previous-boot state.

Why not promote pure `watchChanges` yet? The writer in `setup` is:

```sh
printf '%s\n' "$status" > "$_update_status_file"
```

That truncates then writes the same inode rather than publishing by atomic
rename. An event watcher may therefore expose an empty/intermediate state unless
extra debounce/reload semantics are proven. Keeping the two-second schedule
removes process fan-out without changing update presentation timing.

Required oracle:

- missing/empty status file;
- `updating`;
- valid `progress:STEP:TOTAL:MESSAGE`, including colons in MESSAGE;
- malformed step/total values;
- `failed:CODE:MESSAGE`;
- shell restart at initial marker, mid-progress and final step;
- stale previous-boot status;
- watchdog sees same progress twice -> stuck;
- watchdog sees changed progress -> extends timeout;
- success-without-restart and unknown status;
- exact UI fields, poll start/stop state and clear-status behavior.

This removes one child process per progress tick while deliberately preserving
the existing polling cadence.

### R32.2 — Waffle Task View repeatedly rescans the same flat window cache

`refreshCache()` currently loops every current-output workspace and, for each
one, filters the complete Niri window snapshot:

```text
for each workspace:
    wins = NiriService.windows.filter(window.workspace_id == workspace.id)
    wins.sort(by pos_in_scrolling_layout[0])
    compute total width
    append flattened presentation records
```

If there are W workspaces and N windows, membership discovery is O(W×N) before
the per-workspace sorts.

Two later paths repeat related work:

```text
previewCounts:
    for every workspace slot:
        cachedWindowItems.filter(slot && not dragged).length

getWindowsInSlot(slot):
    cachedWindowItems.filter(slot)
```

The latter feeds keyboard next/previous/focused-window navigation; previewCounts
reacts while drag state changes.

Strict-lossless shape:

1. build `workspaceId -> slot` once from `cachedWorkspaces`;
2. allocate one ordered bucket per workspace;
3. scan `NiriService.windows` once and append only windows whose workspace is
   in that map;
4. run the **same existing column comparator** independently on each bucket;
5. build today's identical flattened `cachedWindowItems` while also retaining
   an internal per-slot presentation array/count;
6. make drag preview counts one pass (or derive from those bucket counts with
   the dragged-id adjustment);
7. let keyboard helpers read the prepared slot array; return a fresh slice if
   fresh-array identity is part of any direct helper test.

Required oracle:

- zero/one/many workspaces and windows;
- windows belonging to outputs absent from `cachedWorkspaces`;
- missing `layout.pos_in_scrolling_layout` (current comparator falls back to 0);
- equal column positions and stable source-order ties;
- missing tile sizes and current screen-size fallback;
- exact cumulative width/proportion/proportionOffset;
- active/focused workspace selection;
- drag from/to same and different slots, including dragged-window exclusion;
- workspace rename, open/close and delayed refresh;
- exact flattened record ordering/fields and keyboard navigation result.

No preview-capture, drag timing or visual geometry changes are required.

### R32.3 — Published Niri windows have no shared ID lookup despite repeated finds

The public `NiriService.windows` list is a committed/sorted snapshot. It is
published from the batched window-update timer and is also re-sorted when output
geometry/order changes.

Consumers then rediscover records by numeric id. Examples on current dev:

- Waffle `TaskAppButton.focusedWindowIndex` loops an app's toplevels and calls
  `NiriService.windows.find(...id...)` for each Niri toplevel before sorting
  their column positions;
- `MinimizedWindows` performs the same published-list lookup in restore and
  output-visibility paths.

A derived lookup can be rebuilt once whenever **public `windows`** changes:

```text
firstWindowById[id] = first window carrying that id
```

The first-occurrence qualification matters. JavaScript `Array.find` returns the
first duplicate; naïvely assigning every map entry would make the last duplicate
win and would not be a strict replacement for malformed input.

Scope boundary is equally important: several NiriService handlers intentionally
choose:

```qml
_windowsDirty ? _pendingWindows : windows
```

to operate on data newer than the public snapshot. Those paths must keep their
current scan or gain a separately proven pending index. The new shared lookup is
only for consumers whose contract is explicitly the published `windows`
property.

Required oracle:

- empty list;
- one/many unique numeric ids;
- duplicate ids with distinct object payloads -> first object wins;
- missing/null/zero ids exactly as today's requested lookups behave;
- window open/change/close publication;
- focus-only publication;
- output geometry reorder that republishes/reorders `windows`;
- lookup returns the exact original window object;
- pending-window handlers still observe pending state before public publication.

This trades a bounded O(N) lookup structure for lower repeated O(N) scans; it is
a CPU candidate, not a RAM-saving claim.

### R32.4 — Aqua's one-minute reminder path sorts more data than it consumes

On the current concurrent HEAD, `AquaMind.reminderRows()` still:

1. clones the optional journal schedule;
2. appends up to 128 eligible Todo rows for today;
3. appends up to 32 non-all-day calendar rows;
4. sorts the combined rows by `start`.

`offerAutomatic()`, driven by the existing one-minute proactive timer, then
immediately asks only for the first row within the ±10-minute condition that has
not already been reminded.

For this automatic selection path, a stable one-pass minimum is equivalent:

- visit journal rows first, then Todo rows, then Calendar rows, matching today's
  construction order;
- apply the existing normalization/validity/window/reminded predicates;
- replace the winner only for a **strictly earlier** `start`;
- therefore equal-time rows retain the first source-order item, matching stable
  `sort((a,b) => a.start-b.start)` followed by `find()`.

Keep `reminderRows()` unchanged for direct callers/tests unless a repository
reference audit proves it private.

Required oracle:

- no reminders;
- journal-only, Todo-only, Calendar-only and mixed sources;
- invalid Todo time;
- done/not-today Todo rows;
- all-day/invalid calendar rows;
- exact 128/32 source bounds;
- before/inside/after the current ±10-minute predicate;
- already-reminded first row with a later eligible row;
- equal start time across and within sources;
- exact reminder key/text/type/time;
- Obsidian auto-context refresh still runs before reminder selection and can
  defer the current pass exactly as today.

This is intentionally a low-priority micro-candidate.

### R32.5 — New Aqua/Octo rendering and companion deadlines remain profile-first

The concurrent companion commits add an Octo tentacle render path. Current
`OctoTentacles.qml` creates a liquid ShaderEffect per rig tentacle with a vector
fallback for software/error rendering. That is a visible new GPU workload, but
source shape alone is insufficient to claim that reducing tentacles, shader
steps or quality is lossless.

The existing Aqua reflection is already strongly bounded:

- `sourceRect: 76 × 82`;
- `textureSize: 76 × 82`;
- live only while the body is visible, grounded and detailed effects are active;
- source is detached when software/error/fidelity conditions reject it.

The AquaPresence timers inspected after the concurrent changes are state-machine
deadlines (full-visit, reaction, pointer notice, recovery, peek and surface
deadline), not a set of recurring idle polling loops.

Therefore no companion GPU/timer candidate is promoted from counts alone. First
profile Aqua vs Octo frame time/GPU activity at identical presentation states
and retain the existing production/fixture visual oracles. A later shader
candidate must prove deterministic visual error below the audit budget rather
than assuming fewer passes is acceptable.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.

## Research continuation — round 33

Baseline: `dev` at `42e0855aa762218eaff9bb0f91c94bbe09184cc2`.

Round 33 started from the Round 32 documentation commit, then reconciled one
concurrent wallpaper/carousel commit before writing. That commit touched
wallpaper infrastructure, `GlobalStates`, Config defaults and related tests,
but did not modify the TaskbarApps, Overview, NiriService, desktop-clock
diagnostic, AbyssBar or Fcitx sources used by the findings below. The only
overlap was `defaults/config.json`, which does not affect the verified
`AbyssLayout.normalize()` string-ID invariant.

Current source identities:

- `services/TaskbarApps.qml`:
  `b05b0b39988a40faf7fa3cb84e6b0c747cf4a3ee`;
- `modules/bar/BarTaskbar.qml`:
  `3aca1b63e2633584c86f75c6a2e5eb2ebaebfdb3`;
- `modules/dock/DockApps.qml`:
  `11b3ea8cc17c91a1cf3b6a1f41f64f392d4dfcc9`;
- `services/NiriService.qml`:
  `4c8194493fd380bf0ad8c51bc62990ad0c232738`;
- `modules/overview/OverviewNiriWidget.qml`:
  `79ac2d4d96937d6874fa5fa5a53066e89c1b86f0`;
- `modules/overview/Overview.qml`:
  `431e4443dbde6afc00b2e88a0d9db55e3dbe11b4`;
- `modules/background/Background.qml`:
  `29bd40236ba9579077d361fb1012d4f994ef4a3a`;
- `modules/background/widgets/clock/ClockWidget.qml`:
  `dc15f302bdf78fe161b1565e9c6dbeb95cc09f62`;
- `modules/background/widgets/clock/CookieClock.qml`:
  `9f92f22494a4baea5b0091b591b280e17288aa95`;
- `modules/background/widgets/WidgetSurface.qml`:
  `f574f968a97cf548ac255a6e1e847a6b400347d6`;
- `modules/background/widgets/AbstractBackgroundWidget.qml`:
  `16603c04327503fad558fb6886e61a7738295b73`;
- `modules/abyss/bar/AbyssBar.qml`:
  `b9d91627734d0cfdf3057d598f7ec600649be45c`;
- `modules/abyss/looks/AbyssLayout.js`:
  `a8fa6cac478f90376041da5e00d53017f78bd019`;
- `modules/settings/FcitxInputSettings.qml`:
  `61181ca2589bbbf496898c92f02290935b998888`;
- `scripts/input-method/fcitx5-settings.py`:
  `606cd57c0b5d640099f2b96ef850f70bb41ae06b`.

### R33.1 — Waffle Taskbar recompiles unchanged ignored-app regexes on every rebuild

`TaskbarApps.computeApps()` is intentionally imperative and coalesced through a
16 ms timer. It can be scheduled by:

- compositor sorted-toplevel changes;
- foreign-toplevel changes;
- AppSearch list changes;
- pinned/ignored-app config changes;
- broad Config options/readiness changes;
- app-identity-rule changes.

Every computation nevertheless repeats:

```qml
const ignoredRegexStrings = root._stringArray(
    Config.options?.dock?.ignoredAppRegexes)
const systemIgnored = [
    "^$", "^portal$", "^x-run-dialog$", "^kdialog$",
    "^org.freedesktop.impl.portal.*"
]
const ignoredRegexes =
    root._compileRegexes(ignoredRegexStrings.concat(systemIgnored))
```

The compiled regexes depend only on the ignored-pattern config, not on windows,
pins, AppSearch or compositor order. `_compileRegexes()` also has an important
contract: each invalid pattern is caught, warned about and skipped rather than
aborting the whole list.

Strict-lossless direction:

1. retain a private compiled ignored-regex list;
2. rebuild it on first use and when the actual ignored pattern list changes;
3. cover Config readiness/nested-object replacement so a reload cannot strand a
   stale compiled list;
4. leave `computeApps()` window/pin/identity semantics untouched;
5. preserve user-pattern order followed by the five fixed system patterns;
6. preserve per-pattern try/catch and warning behavior.

Classic `BarTaskbar` and `DockApps` contain a related but smaller issue:
their compiled lists are already cached, yet every rebuild fingerprints both
current and cached arrays with `JSON.stringify`. They also construct regexes
directly rather than through TaskbarApps' tolerant helper. Do not unify these
three implementations merely for deduplication; their malformed-pattern
behavior is currently different. A later cleanup may replace the fingerprint
with narrow invalidation locally while preserving each owner's error policy.

Required oracle:

- empty user pattern list;
- one/many patterns and duplicate patterns;
- case-insensitive matching;
- user pattern ordering before system defaults;
- one or several invalid patterns among valid patterns;
- config ready transition and full Config reload/object replacement;
- unrelated compositor/AppSearch/config updates do not compile regexes again;
- exact final taskbar app identities/order/pinned state.

### R33.2 — Overview sorts output workspaces that NiriService already sorted

Current NiriService publishes `allWorkspaces` from every observed assignment
site as:

```qml
Object.values(updatedWorkspaces).sort((a, b) => a.idx - b.idx)
```

The same invariant is maintained for the full workspace snapshot, activation
updates and urgency updates. `updateCurrentOutputWorkspaces()` already relies
on `filter()` preserving that source order.

Two Overview paths still redo the same ordering:

```qml
// OverviewNiriWidget
NiriService.allWorkspaces
    .filter(workspace => workspace.output === outputName)
    .sort((a, b) => a.idx - b.idx)

// Overview.qml — independently in Left and Right key handlers
NiriService.allWorkspaces
    .filter(workspace => workspace.output === outputName)
    .sort((a, b) => a.idx - b.idx)
```

JavaScript `filter()` is stable and preserves source order. Removing only the
second `sort()` therefore changes neither selected workspace nor presentation
order while eliminating a temporary sorting pass.

Do not generalize this into “all Niri consumers may assume arbitrary maps are
sorted.” The invariant applies specifically to the public `allWorkspaces`
array. The keyed `workspaces` object and pending window state have different
contracts.

Required oracle:

- zero/one/many outputs and workspaces;
- interleaved outputs in the pre-sort map;
- equal `idx` values preserve current stable source order;
- workspace snapshot replacement;
- focus/activation changes;
- urgency changes;
- Overview current slot and preferred-workspace slot;
- classic Overview Left/Right boundary behavior;
- exact workspace ids selected before/after.

### R33.3 — Desktop clock diagnostics perform production work even when nobody asks

`Background.qml` describes the desktop-clock diagnostics as bounded/inert
unless `INIR_REGION_DEBUG=1`. The mutating IPC functions are indeed guarded,
but the data-production path is not.

The normal ClockWidget instance is wired unconditionally:

```qml
onDebugPaletteReportChanged:
    backgroundScope.clockDebugPaletteReport = debugPaletteReport
onEditControlsGeometryReportChanged:
    backgroundScope.clockDebugControlsReport = editControlsGeometryReport
```

That makes the diagnostic properties observed reactive outputs. Their dependency
chain currently includes:

- `ClockWidget.debugPaletteReport`: builds a nested object and
  `JSON.stringify`s it;
- `WidgetSurface.surfaceReport`: separately `JSON.stringify`s surface state,
  then ClockWidget parses that JSON again to embed it;
- CookieClock's `diagnosticReport`, copied through
  `onDiagnosticReportChanged`;
- contrast-ratio calculations included only for the diagnostic payload;
- `AbstractBackgroundWidget.editControlsGeometryReport`: invokes
  `_resolveEditControlsGeometry()` for diagnostic coordinates and serializes
  the result whenever relevant geometry changes.

This work is not required to paint the clock.

However, the read-only IPC contract must remain intact. `docs/IPC.md` documents
`clockDebugState` as returning palette, renderer and quick-control geometry
diagnostics, and only the **mutating** diagnostic functions are documented as
requiring `INIR_REGION_DEBUG=1`. Therefore simply disabling diagnostic
properties when the environment flag is absent is not strict-lossless.

Safer direction:

1. stop continuously copying serialized diagnostic strings into Background;
2. expose on-demand builders that read the same current raw properties;
3. when `clockDebugState()` is invoked, build the same palette/surface/cookie
   and geometry objects at that moment and serialize once;
4. keep `enabled`, config, injected-region and snapshot fields identical;
5. keep all mutating debug functions and their env guard unchanged;
6. explicitly define/preserve behavior when the clock widget is disabled,
   unloaded or between loader transitions before implementation.

This converts diagnostics from a render-time/reactive workload into a diagnostic
request workload without weakening the documented read IPC.

Required oracle:

- debug env unset/set;
- digital and cookie styles;
- static/adaptive wallpaper color modes;
- surface on/off and every supported surface dialect used by the payload;
- clock enabled/disabled and loader transition states;
- quick controls closed/open;
- diagnostic layout probe active/inactive;
- region injection active/inactive;
- exact `clockDebugState()` parsed object before/after for all cases;
- zero changes to rendered clock geometry/colors and normal edit controls.

### R33.4 — AbyssBar serializes two string arrays just to suppress a no-op publish

Each AbyssBar owns:

```qml
property var moduleIds: []

function syncModuleIds(): void {
    const next = placements.filter(p => p.enabled).map(p => p.id)
    if (JSON.stringify(next) !== JSON.stringify(moduleIds))
        moduleIds = next
}
```

This runs whenever `placements` changes and is useful because avoiding a
no-op `moduleIds` assignment prevents unnecessary Repeater churn. The no-op
guard itself, however, allocates two JSON strings.

The type proof is stronger than it first appears. All production placements
reach `AbyssLayout.normalize()`, which:

- rejects unknown module kinds;
- deduplicates by normalized id;
- publishes `id: String(p.id || p.kind)`.

The fallback seed also enters `normalize()`. Thus `moduleIds` is an ordered
array of canonical strings. Equality can be:

```text
same length
AND every next[i] === moduleIds[i]
```

with no JSON serialization.

Keep this optimization local to normalized AbyssBar placements. Editor draft
objects elsewhere may not have passed through the same canonicalization boundary
and should not inherit the assumption automatically.

Required oracle:

- no enabled modules;
- one/many modules;
- enable/disable without order change;
- reorder/move while id order stays same;
- reorder that changes id order;
- configured placements and output-specific profiles;
- duplicate/malformed raw ids normalize to the same current canonical result;
- exact Repeater item count/order and unchanged no-op publication suppression.

### R33.5 — Fcitx Settings polling is real process work, but timing is a product contract

`FcitxInputSettings.qml` performs a status refresh every five seconds while the
settings section is visible:

```qml
Timer {
    interval: 5000
    repeat: true
    running: root.visible
    onTriggered: root.refresh()
}

Process {
    command: ["python3", fcitx5-settings.py, "status"]
}
```

The Python status action is not process-free. When Fcitx is installed it invokes
`fcitx5-remote` once for state and, when running, again with `-n` for the
current input-method name. It also probes executable/file/config state.

This means a visible settings page can launch one Python process plus one or two
helper processes every five seconds. The work is bounded and user-visible
settings-only, so it is not a startup/system-idle problem.

Do **not** promote “remove polling” as strict-lossless yet. External Fcitx state
can change outside Hadalis, and the existing five-second freshness window is
observable. Candidate research paths are:

- split static installation/config-file probes from dynamic daemon/input-method
  state so unchanged static data is not rediscovered every poll;
- investigate a D-Bus/event subscription for dynamic state while keeping a
  bounded fallback reconciliation;
- or retain polling if profiler evidence shows the visible-settings cost is
  immaterial.

Any event-driven replacement must prove the same external-change visibility,
failure recovery and first-visible refresh behavior.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.

## Research continuation — round 34

Baseline: `dev` at `4bbb3bbbaff5a4dccdf2ef0facc179f830f8fd6c`.

This round began after the Round 33 documentation commit and reconciled two
concurrent feature commits before writing:

- `0c804b5ac511733958ad9ac1fd1073b215264f75` reorganized Settings and added the
  consolidated Integrations page;
- `4bbb3bbbaff5a4dccdf2ef0facc179f830f8fd6c` composed the Abyss on-screen keyboard into the connected
  output field.

Neither commit modified the Hotspot, Abyss Clipboard, SidebarHost or
NotificationGroup sources underlying the promoted findings. The second commit
did touch Abyss Perimeter/GlobalStates, so the Abyss candidate was revalidated
against current `dev` rather than inferred from an older code-search snapshot.

Current source identities:

- common `modules/common/models/quickToggles/HotspotToggle.qml`:
  `129d9ed0148dde14d1d12f98aaab1c698177c1fe`;
- Waffle `ActionCenterTogglesDelegateChooser.qml`:
  `9e36f70c7b2f97d84ebbb99ea9a375b3c529a3d5`;
- Waffle `hotspot/HotspotControl.qml`:
  `4adab074147681052d00c23749ef70a0720bb61c`;
- Classic `quickToggles/classicStyle/HotspotToggle.qml`:
  `e3b2bf13eb566a18bfa299d001cee61f34ee49a0`;
- Android `AndroidHotspotToggle.qml`:
  `72e8598bee293151528d4eb22d40c6527f577f7e`;
- `modules/abyss/content/AbyssClipboardContent.qml`:
  `1a2e0a9ccbf7100d354ada0ccc2c969b5b1789c5`;
- `services/deferred/Cliphist.qml`:
  `edfcd8969d5fcb2fd0bcda7ae8269fbe21d924b1`;
- `modules/sidebar/SidebarHost.qml`:
  `d4a23a437453beac90881b40772091eff293ad51`;
- `modules/common/widgets/NotificationGroup.qml`:
  `dd579e3aab8f4d73b3764b653d27fff89cede7ec`;
- `modules/common/widgets/PopupToolTip.qml`:
  `d1acfd15cec4645bd3a8e438a88b3db3c105a32e`;
- `services/deferred/EasyEffects.qml`:
  `b20be1b930b93622f43803b12eaa68415b32917a`;
- `modules/settings/NiriConfig.qml`:
  `ffdcf546f099b8666ac076f159c3e31313b08f8a`.

### R34.1 — Hotspot state/process ownership is duplicated, including inside one Waffle Action Center

Round 28 already established that the recurring hotspot status command is
appropriately direct argv:

```qml
["nmcli", "-t", "-f", "NAME", "connection", "show", "--active"]
```

and that the remaining shell used to start a hotspot performs a real ordered
delete-then-create transaction. Round 34 therefore does **not** reopen shell
removal.

The new issue is ownership duplication.

The common Hotspot model owns:

- one status `Process`;
- start and stop `Process` objects;
- a repeating 5 s status timer;
- an initial refresh;
- action-completion refresh.

Its timer is live whenever either Sidebar Right or the Waffle Action Center is
open.

Waffle then creates that model twice in one feature flow:

```qml
ActionCenterToggleButton {
    toggleModel: HotspotToggle {}
    menu: Component { HotspotControl {} }
}
```

and `HotspotControl` contains another:

```qml
HotspotToggle { id: hotspotToggle }
```

When the menu is materialized while the Action Center remains open, both
instances satisfy the same `waffleActionCenterOpen` timer condition and both
can issue the same external status query every five seconds.

Classic and Android quick-toggle implementations independently duplicate the
same status/action transport as well. Those style surfaces are usually mutually
exclusive, but the architectural duplication makes process ownership depend on
component residency rather than on hotspot demand.

Strict-lossless direction:

1. create one shared hotspot state/action owner;
2. keep the current direct `nmcli` status parser and start/stop transaction
   semantics;
3. let each visible surface acquire/release status demand;
4. run one five-second reconciliation cadence while demand count is nonzero;
5. refresh immediately on first demand and after start/stop completion;
6. expose the same `available/toggled/busy/error` facts needed by the existing
   presentation components;
7. keep visual styling and surface-specific notification wording outside the
   transport owner when they differ.

Required oracle:

- neither sidebar nor Action Center open -> no recurring status poll;
- each surface individually;
- Waffle button plus opened Hotspot menu simultaneously;
- switch between Classic/Android/Compact sidebar styles;
- externally start/stop Hotspot and observe within the current five-second
  freshness bound;
- open a surface with externally active Hotspot -> immediate correct state;
- start with stale `Hotspot` connection profile;
- start success/failure and stop success/failure;
- one surface closes while another still demands state;
- rapid toggle while a status/action process is already running;
- exact SSID/password/config and user notification behavior.

This is process coalescing, not a change to network policy or status cadence.

### R34.2 — Abyss Clipboard rebuilds all display/search metadata on every query character

`AbyssClipboardContent.rows` currently contains both source preparation and
query filtering in one binding:

```qml
const query = search.text.toLowerCase()
const pins = Cliphist.pinned.map(text => ({
    pin: true,
    value: text,
    preview: Cliphist.pinPreview(text)
}))
const history = Cliphist.entries.map(entry => ({
    pin: false,
    value: entry,
    preview: String(entry).slice(String(entry).indexOf("\t") + 1)
}))
return pins.concat(history)
    .filter(row => row.preview.toLowerCase().includes(query))
```

Because the binding reads `search.text`, every query edit also repeats every
pin/history map, preview extraction, object construction, concat and lowercase.

`Cliphist` bounds history to 400 entries and already demonstrates the desired
pattern elsewhere: it keeps revision-scoped prepared caches for fuzzy/filter
searches. Abyss should use the same ownership principle, but **not** reuse those
prepared rows directly because their cleanup/markup semantics are intentionally
different from Abyss' raw preview.

Strict-lossless shape:

1. prepare Abyss-specific source metadata only when `Cliphist.pinned` or
   `Cliphist.entries` changes;
2. retain pins first, then history;
3. store the exact current preview plus a lowercase search key;
4. on query change, filter only by the stored lowercase key;
5. if delegate/model-data fresh identity is part of current QML behavior,
   publish fresh matched `{pin,value,preview}` records from the prepared
   metadata rather than exposing the cache objects themselves.

Required oracle:

- empty sources/query;
- empty query returns every pin then every history entry;
- one/many pins and up to the 400-entry history bound;
- mixed-case query and preview;
- history with no tab, one tab and several tabs;
- binary/image history rows remain byte-identical as `value`;
- pin preview remains exactly `Cliphist.pinPreview(text)`;
- pin/unpin/delete/wipe/refresh while a query is active;
- keyboard current-index reset/navigation and Enter copy;
- exact visible row text/order and image classification.

### R34.3 — Sidebar presentation readiness is polled at 16 ms even when readiness cannot advance

`SidebarHost.requestPresentation()` marks the request pending and starts:

```qml
Timer {
    id: presentationTimer
    interval: 16
    repeat: true
    onTriggered: root.tryPresent()
}
```

`tryPresent()` then checks:

1. request still pending and presentation is open;
2. window/content geometry is positive;
3. Loader status is `Loader.Ready`;
4. after readiness, one warm or two cold timer frames have elapsed.

The last step is an intentional compositor contract and should remain.

The first three are readiness conditions, not frame-by-frame work. While a cold
Loader is still Loading, every 16 ms tick merely returns. More importantly,
`Loader.Error` or geometry that never becomes positive has no terminal branch,
so a pending open can retain an unbounded ~62.5 Hz timer.

A strict redesign does not remove the ready-frame delay. It changes only how the
timer reaches that phase:

- while Loader/geometry prerequisites are false, stop the frame ticker;
- Loader status and relevant geometry changes re-evaluate the pending request;
- once prerequisites are valid, start the same 16 ms timer;
- require the same one warm / two cold successful ready frames;
- any regression back to not-ready stops/reset the ready-frame phase;
- close/role change/resume paths retain their explicit cancellation behavior.

This also makes a Loader error quiescent rather than a permanent heartbeat while
still allowing a later status/geometry recovery signal to re-arm the pending
presentation.

Required oracle:

- warm open and cold open;
- Loader Loading -> Ready;
- Loader Error and later recovery if supported;
- zero -> positive window/content dimensions;
- close while waiting;
- close during the one/two-frame settle;
- editor presentation without role open;
- idle resume / lock-unlock remap;
- plugin-role change;
- animations enabled/disabled;
- exact frame count between first fully-ready state and `_sidebarShown`.

### R34.4 — Collapsed NotificationGroup reverses an entire group to show two records

The notification body model is currently:

```qml
root.expanded
    ? root.notifications.slice().reverse()
    : root.notifications.slice().reverse().slice(0, 2)
```

The collapsed result is mathematically just the last two source records in
reverse order. Reversing a fresh copy of the entire group first therefore does
O(N) copy/reverse work even though the UI consumes at most two elements.

Strict-lossless collapsed projection:

```text
start = max(0, notifications.length - 2)
notifications.slice(start).reverse()
```

Keep the expanded branch exactly as it is.

Required oracle:

- 0, 1, 2 and many notifications;
- exact newest-first object identity/order;
- source mutation while collapsed;
- collapse/expand transitions;
- second-row opacity when total count > 2;
- dismiss/action/timeout behavior;
- popup and sidebar layouts.

This is a deliberately low-priority micro-candidate and does not replace the
larger Notification service derived-state candidate already in the ledger.

### R34.5 — Rejected / measure-first paths from this pass

**PopupToolTip 50 ms anchor heartbeat:** the repeating timer is active only while
the tooltip is actually presented, and the source explicitly uses it to follow
anchors whose geometry moves through layout/animation without a reliable single
change signal at the tooltip boundary. Do not replace it with a slower timer
from source inspection alone. An event-driven replacement first needs an oracle
covering animated parents, window mapping and cross-item coordinates.

**EasyEffects active-state verification:** the service already runs its fast
five-second poll only while Sidebar Right/Action Center is visible and slows to
30 seconds when EasyEffects remains active in the background. Repository
performance tests explicitly protect that slow background verification because
EasyEffects may be stopped externally. Do not remove it without a trustworthy
process/D-Bus lifecycle subscription plus bounded fallback.

**NiriConfig:** current Settings code already loads only the active Niri section
plus validation/customization metadata on initial page construction. Most other
processes are explicit apply/persist/open-folder transactions. No new recurring
process candidate is promoted from its size alone.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.

## Research continuation — round 35

Baseline: `dev` at `5f257833f337c1424a8a607b8c3be022bacc98f8`.

This round started from the Round 34 documentation commit and then reconciled one
concurrent integrations commit:

- `5f257833f337c1424a8a607b8c3be022bacc98f8` adds Obsidian theme-follow
  integration and touches Config/Settings/shell registration only.

It does not modify the HyprlandData, HyprlandXkb, Bar workspace/active-window or
Internal Todo sources underlying the findings below.

Current source identities:

- `services/HyprlandData.qml`:
  `8bf55cb5fa688fcc0eebef53da2b0f0bf8f4d0eb`;
- `modules/bar/ActiveWindow.qml`:
  `7b6edafc7d90adc58c399f672d02a334eec385e1`;
- `modules/bar/Workspaces.qml`:
  `f7c51bb42b984ba8d3da078652a36ca75bd2db71`;
- `services/deferred/HyprlandXkb.qml`:
  `80ccd5ce450eaa1c9be3146c88285880ad69e425`;
- `services/InternalTodoBackend.qml`:
  `1ef24e7967ca04c4bbb94fb4a0d4fd8f3cfedadb`.

### R35.1 — HyprlandData refreshes every snapshot after every raw event

The current raw-event handler is intentionally simple:

```qml
function onRawEvent(event) {
    updateAll()
}
```

and `updateAll()` starts four refresh domains:

```text
updateWindowList()   -> hyprctl clients -j
updateMonitors()     -> hyprctl monitors -j
updateLayers()       -> hyprctl layers -j
updateWorkspaces()   -> hyprctl workspaces -j
                      + hyprctl activeworkspace -j
```

So one raw event can request five external child processes.

The service already has per-domain in-flight queue flags, which prevents
unbounded parallel spawning, but that does not solve ownership fan-out: an event
arriving while processes are active marks the unrelated domains for another
refresh too.

The Hyprland event stream itself distinguishes the invalidation classes. Hadalis
already consumes examples such as:

- `activewindowv2` / `windowtitlev2` in the anti-flashbang path;
- `workspacev2`;
- `activelayout`;
- `configreloaded`.

A conservative strict-lossless router can therefore begin with:

- window lifecycle/focus/title/fullscreen/floating/pin/group events -> clients;
- layer open/close -> layers;
- workspace create/destroy/move/rename/activate and focused-monitor events ->
  workspaces/activeworkspace and monitor state as required;
- monitor add/remove and `configreloaded` -> full refresh;
- keyboard-layout/submap/screencast events -> no HyprlandData snapshot refresh;
- **unknown event name -> full refresh**.

The unknown fallback is important because Hyprland adds events over time and
Hadalis must not silently stop observing a new state mutation.

Do not combine this with a debounce in the first patch. Event-specific routing
already removes unnecessary work without adding a new freshness delay.

Required oracle:

- record a current Hyprland socket event trace and snapshot hashes before/after
  each event class;
- open/close/focus/title/fullscreen/float/pin/move windows;
- create/destroy/rename/move/switch normal and special workspaces;
- focus another monitor;
- layer open/close;
- monitor add/remove and mode/layout change;
- config reload;
- keyboard layout, submap and screencast events;
- unknown synthetic event -> verify full fallback;
- event bursts while each process is already running -> preserve current
  queued-one-more-refresh semantics;
- compare published `windowList`, `windowByAddress`, `addresses`,
  `monitors`, `layers`, `workspaces`, `workspaceById`,
  `workspaceIds` and `activeWorkspace` after the system settles.

This candidate targets process fan-out, not Hyprland feature removal.

### R35.2 — biggestWindowForWorkspace repeats an allocative O(N) scan per consumer/workspace

Current helper:

```qml
const windowsInThisWorkspace = HyprlandData.windowList.filter(
    w => w?.workspace?.id == workspaceId)

return windowsInThisWorkspace.reduce((maxWin, win) => {
    const maxArea = (maxWin?.size?.[0] ?? 0) * (maxWin?.size?.[1] ?? 0)
    const winArea = (win?.size?.[0] ?? 0) * (win?.size?.[1] ?? 0)
    return winArea > maxArea ? win : maxWin
}, null)
```

Bar Workspaces invokes this by workspace, and ActiveWindow invokes it for the
monitor's active workspace. For W visible workspaces and N windows, the Bar can
therefore cause repeated full `windowList` scans and temporary filter arrays
after one client snapshot publication.

`HyprlandData` already walks every published window to construct
`windowByAddress`, then separately executes:

```qml
root.addresses = root.windowList.map(win => win.address)
```

A single publication pass can instead produce:

- the existing `windowByAddress`;
- the existing ordered `addresses` array;
- a private `largestWindowByWorkspace` index.

Strict parity detail: the current reducer starts with `null`, treats its area
as 0 and replaces only on `winArea > maxArea`. Therefore a workspace
containing only zero-area windows returns **null**, not its first window. Equal
positive areas keep the first strictly-largest record. Preserve both behaviors.

Workspace ids are compared with loose `==` today. A string-keyed private map
covers the normal numeric/string schema, but an implementation oracle should
include 0, positive/negative ids and numeric strings before relying on that
normalization.

Required oracle:

- empty window list;
- missing/null workspace id;
- one/many workspaces;
- numeric id vs numeric-string query;
- zero-area-only workspace -> null;
- negative/zero workspace ids;
- equal-area ties -> first winner;
- later strictly larger window;
- malformed/missing size arrays -> current 0-area behavior;
- exact object identity returned to ActiveWindow/Workspaces;
- exact `addresses` ordering if the companion loop fusion is implemented.

### R35.3 — HyprlandXkb rereads and reparses base.lst once per first-seen layout description

When `currentLayoutName` is not cached, HyprlandXkb:

1. clears `currentLayoutCode`;
2. spawns `cat /usr/share/X11/xkb/rules/base.lst`;
3. splits the complete file;
4. searches lines in source order;
5. caches only the requested description.

That means switching through several new layouts pays one child process plus one
full-file parse/search for each distinct description.

A stronger strict-lossless boundary is the rules-file revision:

1. own one read-only `FileView` for `base.lst`;
2. watch disk changes and reload/rebuild on revision;
3. parse lines once in source order into description -> code;
4. on layout change, clear the visible previous code exactly as today, then
   resolve from the current index;
5. if the file is missing/unreadable or no row matches, keep the code empty.

The index must reproduce **first matching line wins**. Layout rows and variant
rows use different extraction rules; a later duplicate description must not
overwrite an earlier match if the current `find()` would have stopped there.

Quickshell's FileView contract explicitly supports watched read-only files via
`watchChanges` plus `reload()`, so this does not require polling.

Required oracle:

- missing/unreadable `base.lst`;
- empty layout name;
- simple layout line;
- variant line and exact existing concatenation;
- duplicate descriptions proving first-row ownership;
- comments/blank/malformed lines;
- rapid layout changes while a file load/rebuild is in flight;
- rules file replacement/edit while running;
- Hyprland and Niri synchronization paths;
- exact visible uppercase code in ii/Waffle lock surfaces and keyboard
  indicators.

### R35.4 — Internal Todo uses cat only because the writer FileView owns stale write state

The Internal Todo backend correctly documents why it does **not** read external
changes back through `txtFileView`:

> `FileView.setText()` caches content internally; subsequent
> `reload()+text()` on that writer can return its cached buffer rather than
> fresh disk bytes.

So after the existing 300 ms external-edit debounce it currently runs:

```qml
Process {
    command: ["cat", root.txtFilePath]
    ...
}
```

The restriction applies to the **writer instance**, not to the concept of
FileView as a reader. Quickshell's documented watched-file pattern is a
read-only FileView with `watchChanges: true` and `reload()` on disk changes.

Candidate shape:

- keep `txtFileView` as the writer and current watch/invalidation source;
- keep the startup lock and 300 ms debounce unchanged;
- create a second FileView that never calls `setText()` or `setData()`;
- when the debounce fires, reload the reader;
- only in its successful `onLoaded` path read `text()`, parse, compare and
  update JSON exactly as the current `cat` collector does;
- keep load failure explicit and do not treat an asynchronous old buffer as new
  disk content.

This should be fixture-proven before promotion to implementation because
self-writes use atomic replacement and both FileViews point at the same path.
The test must demonstrate that the reader observes the final disk bytes, not a
pre-rename/truncated or writer-cached state.

Required oracle:

- startup with missing/existing JSON and txt files;
- Hadalis UI write -> txt watcher -> no semantic self-reimport;
- external editor overwrite;
- atomic rename-style save;
- rapid multiple external saves inside/outside 300 ms;
- empty file, comments, checkbox and plain-text parsing;
- file deletion/recreation;
- simultaneous JSON persistence in flight;
- exact list/persistenceBusy/readiness outcomes.

### R35.5 — Rejected / lower-priority paths from this pass

**LockContext fingerprint capability shell:** the deferred Lock component starts
one Bash chain that checks `fprintd-list` and resolves `whoami`. It can
probably be reduced to a smaller direct process sequence, but it is a one-shot
capability probe and identity/error semantics are security-adjacent. It is lower
value than the Hyprland event fan-out and is not promoted in this round.

**Settings search code duplication:** Focus/Rail/Waffle settings surfaces contain
similar search orchestration, but they are alternative presentations rather
than simultaneously active search engines. The canonical ledger already tracks
the runtime-important normalized-search and post-limit-highlighting work. A
shared helper may improve maintainability, but duplicate source text alone is
not a performance candidate.

**Full-screen task/session blur:** several full-screen surfaces still own
full-screen blur effects, but unlike panel glass they actually present the full
output. The existing bounded-wallpaper-capture candidate cannot claim an
area reduction there without changing the effect itself.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.

## Research continuation — round 36

Baseline: `dev` at `998239aaca31a33d270af278bc2a705679ff3aee`.

Round 36 deliberately moved away from the Hyprland/Todo cluster used in round 35.
Five concurrent Aqua/Abyss commits landed after that round and a final Abyss
documentation commit moved `dev` to the baseline above. Those commits do not
modify the LauncherSearch, YtMusic, Config, Emojis or Bar UtilButtons sources
used below.

Current source identities:

- `services/deferred/LauncherSearch.qml`:
  `c745ca2ef404433ced39384766479461f12806bd`;
- `services/YtMusic.qml`:
  `063ef1bd591d222d9a60b240dec218c1c4171213`;
- `modules/common/Config.qml`:
  `673b17d2eded53385ba456783fe7d297ecb8ef4e`;
- `services/deferred/Emojis.qml`:
  `c4e164bb2d7ad2abf3ad241b320e53842e8a600d`;
- `modules/bar/UtilButtons.qml`:
  `5a81a3162e5a9a16280fb4fe7f926acbed26ba4f`;
- `modules/sidebarLeft/widgets/QuickWallpaper.qml`:
  `b8e6bf35ee224fee0a88e9071875a6c5b57b783f`;
- `services/ObsidianTheme.qml`:
  `4617b0d15a89251684a922b8ad5a926cca97c01b`;
- `scripts/integrations/obsidian_theme.py`:
  `41ff3accaaa579b4db5cd7cbe99082fc313926cf`.

### R36.1 — Launcher math work is scheduled from a reactive output binding

Launcher query text first passes through the existing 80 ms debounce:

```qml
onTriggered: root._debouncedQuery = root.query
```

The problem is later in `results`:

```qml
property list<var> results: {
    const q = root._debouncedQuery
    ...
    mathTimer.restart()
    ...
    const mathObj = ({
        name: root.mathResult,
        ...
    })
}
```

That binding is not an event handler. It can re-run because any dependency it
reads changes. One of those dependencies is `mathResult`, populated by qalc:

```qml
stdout: SplitParser {
    onRead: data => root.mathResult = data
}
```

Therefore the normal sequence can be:

```text
debounced query changes
 -> results binding evaluates
 -> mathTimer.restart()
 -> qalc runs
 -> mathResult changes
 -> results binding evaluates again
 -> mathTimer.restart() again
```

The second qalc result often equals the first and therefore stops the chain, but
the extra process is still avoidable. Other unrelated dependencies of
`results` can also restart the timer while the query itself is unchanged.

The strict-lossless change is about **ownership of scheduling**, not about
reducing calculator capability:

1. `results` becomes a pure derivation with no timer mutation;
2. when `_debouncedQuery` changes, schedule one math calculation using today's
   exact delay and prefix stripping;
3. when the configured math prefix changes while the same query is resident,
   perform the same re-evaluation/schedule that the current binding dependency
   would have caused;
4. preserve `mathProc.calculateExpression()` stopping a prior in-flight
   process before starting the new expression;
5. leave current result composition/fallback visibility unchanged.

Do **not** optimize by assuming only queries beginning with a number or `=` are
valid qalc expressions. qalc accepts expressions/functions/units whose textual
shape can differ, and the current launcher deliberately exposes a default math
fallback.

Required oracle:

- empty query clears immediately;
- normal app-like text;
- numeric expression;
- explicit math prefix;
- shell/web/action/app prefixes;
- arbitrary valid qalc text not beginning with a digit;
- rapid typing faster/slower than the 80 ms debounce;
- new query while qalc is still running;
- qalc success/error/empty output;
- live math-prefix and non-app-delay config changes;
- exact launcher result ordering/content before/after;
- instrumented process count proving at most one scheduled calculation per
  corresponding query/prefix invalidation.

### R36.2 — YtMusic writes the same resume payload every five seconds while paused

YtMusic keeps a crash-resume checkpoint with:

```qml
Timer {
    interval: 5000
    repeat: true
    running: root.currentVideoId !== ""
    onTriggered: root._persistResume()
}
```

The timer remains live while a track is merely loaded and paused.

`_persistResume()` always submits the same nine-key Config transaction:

- video ID;
- title;
- artist;
- thumbnail;
- URL;
- position;
- `wasPlaying`;
- active playlist;
- current index;
- active playlist source.

Config's batching API does **not** compare old/new values before publishing the
mutation:

```text
for every key:
  record reload mutation
  apply nested key
  update JSON mirror

then:
  fileWriteTimer.restart()
  revision++
  configChanged()
```

So an unchanged paused track can cause a global Config revision +
`configChanged` publication and disk-write schedule every five seconds. At the
current cadence that is up to twelve mutation schedules per minute while no
resume state changes.

A local dirty checkpoint is safer than globally changing Config semantics:

1. maintain a private dirty bool/revision for the exact resume fields;
2. relevant property changes mark it dirty;
3. the existing five-second timer remains the checkpoint clock;
4. on a tick, persist only if dirty, then clear the dirty state;
5. explicit existing persistence sites remain immediate;
6. destruction retains the current force-persist + `Config.flushWrites()`;
7. stop/clear keeps the current explicit resume reset.

During normal playback, `currentPosition` changes and therefore keeps the
five-second persistence behavior. During a stable pause, the timer may still
wake, but it no longer causes Config/disk/global-listener churn.

This is deliberately narrower than changing the timer to `running: isPlaying`.
Stopping the timer on pause would require proving exact residual-time and pause
transition persistence semantics; the dirty guard avoids that timing change.

Required oracle:

- no video loaded;
- track start and metadata arrival ordering;
- playing for > 15 s -> checkpoints remain at the existing cadence;
- pause and remain paused for > 30 s -> no repeated identical Config mutation;
- seek while paused;
- play/pause transitions;
- playlist reorder/current-index/source changes;
- thumbnail/title/artist/URL updates after initial playback;
- currentPosition changes from MPRIS and IPC fallback;
- stop/clear resume;
- service destruction with force flush;
- restore after simulated shell crash at each checkpoint boundary;
- exact persisted JSON values and max playback-position staleness equal to
  current behavior.

### R36.3 — Emoji sloppy search bypasses the cache normal fuzzy search already owns

The emoji service already has the correct source-revision cache for normal
fuzzy search:

```qml
prepared[i] = {
    name: Fuzzy.prepare(`${entry}`),
    entry: entry
}
```

and rebuilds only when `list` changes.

When `search.sloppy` is enabled, however, both sloppy branches do this on
every query:

```qml
const entry = root.list[i]
const score = Levendist.computeTextMatchScore(
    entry.toLowerCase(), searchLower)
```

The path is bounded to the first 100 entries, which keeps the issue small, but
it is still repeated normalization on every keystroke even though the emoji
catalog is static for the entire list revision.

Extend the existing prepared record:

```text
{
  name: Fuzzy.prepare(entry),
  lower: entry.toLowerCase(),
  entry
}
```

and let sloppy mode use the first `min(100, prepared.length)` entries from that
cache.

Required oracle:

- empty/non-empty query;
- sloppy on/off switch at runtime;
- catalog shorter/equal/longer than 100;
- limit 0/negative/positive;
- score exactly at/below/above threshold;
- equal-score rows and current insertion order;
- limited top-K path and full-sort path;
- list reload invalidates both fuzzy and lowercase preparations;
- exact returned original entry identity/order.

### R36.4 — Bar utility ordering repeatedly rebuilds the same active subset

UtilButtons owns an ordered set of at most eleven utility IDs. Their active
status can depend on:

- individual util-button config switches;
- Niri layout availability;
- Privacy microphone state;
- Audio microphone access;
- Niri screen-cast support;
- power-profile support;
- compact Utilities policy.

Current derived state is split:

```qml
readonly property int visibleUtilityCount:
    root.utilityOrder.filter(id => root.utilityActive(id)).length

function utilityIndex(id): int {
    return Math.max(0, root.utilityOrder.filter(
        candidate => root.utilityActive(candidate)).indexOf(id))
}
```

Every Loader then calls `utilityActive(id)` for activation and calls
`utilityIndex(id)` for row/column placement. Thus one reactive input change can
re-evaluate the same full active predicate set repeatedly and allocate multiple
temporary filtered arrays.

Prepare once:

```text
activeUtilityOrder = utilityOrder.filter(utilityActive)
visibleUtilityCount = activeUtilityOrder.length
utilityIndex(id) = max(0, activeUtilityOrder.indexOf(id))
```

Loader `active` can remain bound to the existing exact predicate or use
membership in the prepared list after dependency-parity testing. The first patch
need not change Loader activation at all to obtain most of the allocation win.

Required oracle:

- default/configured custom order;
- invalid and duplicate configured IDs;
- every show/hide switch;
- keyboard-layout multiplicity changes;
- mic config + live Privacy/Audio access combinations;
- Niri vs non-Niri screen-cast state;
- performance-profile availability;
- compact/expanded Utilities;
- horizontal and vertical layout;
- exact visible count and row/column index for all active items.

The list is intentionally small, so this is a low-priority micro-candidate.

### R36.5 — Paths deliberately not promoted

**QuickWallpaper directory scan:** the widget runs a direct `find` scan on
construction/sidebar open and sorts by file ctime. The central Wallpapers
service has a FolderListModel, but that model is user-navigable/searchable and
its active directory can differ from the default wallpaper directory; its
sorting/file-type contract is also not identical to QuickWallpaper's static
image/ctime list. Reusing it directly is therefore not a strict-lossless
centralization. A future shared immutable default-folder catalog would need its
own ownership/lifetime proof.

**ObsidianTheme appearance watcher:** enabling the Hadalis snippet can cause the
appearance-file watcher to debounce one follow-up apply after the helper itself
adds the snippet. The Python helper is idempotent and does not rewrite an
unchanged appearance/snippet payload. That extra process is bounded to snippet
membership changes, not a recurring loop; suppressing self-events adds state and
race handling around external Obsidian writes for little current gain. Keep
unless process traces show meaningful churn.

**Images.thumbnailSizeNameForDimensions():** it currently allocates
`Object.keys(thumbnailSizes)` for each call. Replacing that with a constant
ordered name list is safe but too small to promote ahead of the four candidates
above; callers usually re-evaluate on geometry/DPR changes rather than every
frame.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.

## Research continuation — round 37

Baseline: `dev` at `1afd09f2ca0944da8bbc26da471898e446883da0`.

This round deliberately moved into the local-music and desktop-widget derived
state paths, then revisited deferred clipboard search only where a source-level
gap remained after the earlier prepared-cache work. No concurrent commits landed
after round 36 during this audit.

Current source identities:

- `services/LocalMusic.qml`:
  `88263668b48d85323a576c4c3645d9f40909f466`;
- `modules/sidebarLeft/LocalMusicView.qml`:
  `d5b1880d5a1a3796f0faefe343cf3f2f9909953a`;
- `scripts/local_music_lyrics.py`:
  `cd46821e435fd74f50d83e5bf811e6d1ca0cfe8d`;
- `native/inir-mpdd/src/main.rs`:
  `1c63b8e5281dad2a28e88ea3cb660f7cc0c0cb88`;
- `services/LyricsService.qml`:
  `69df76941fa3d0fd7f069d9df6488950eb5972f3`;
- `services/WidgetPowerManager.qml`:
  `da0d6feffdcfc7682d08d92460222dddaa3d06d0`;
- `modules/background/widgets/AbstractBackgroundWidget.qml`:
  `16603c04327503fad558fb6886e61a7738295b73`;
- `services/deferred/Cliphist.qml`:
  `edfcd8969d5fcb2fd0bcda7ae8269fbe21d924b1`.

### R37.1 — Local Music rebuilds stable library strings on every interactive search

The Songs search binding currently walks the complete MPD library for every
query change:

```qml
for (const track of LocalMusic.libraryTracks) {
    const title = String(track?.title ?? "").toLowerCase()
    const artist = String(track?.artist ?? "").toLowerCase()
    const album = String(track?.album ?? "").toLowerCase()
    const folder = String(track?.folder ?? "").toLowerCase()
    const haystack = title + " " + artist + " " + album + " " + folder
    if (haystack.includes(root.query))
        result.push(track)
}
```

Those four source fields are stable for the complete lifetime of the published
`libraryTracks` snapshot. Query edits only change the comparison needle, yet
they currently repeat four conversions/lowercase operations and one joined
string allocation per track per keystroke.

The same view performs other immutable-per-library transformations separately:

- `buildSongEntries()` rescans all tracks and normalizes each folder path while
  constructing the current folder projection;
- `resolveSelectedTracks()` rescans all tracks and reconstructs `trackKey` /
  normalized-folder strings when selected keys/folders change.

For a large MPD library these are catalog-sized transforms on UI-local state
changes, not on music-library changes.

A strict-lossless projection can be built only when
`LocalMusic.libraryTracks` is replaced:

```text
preparedTrack = {
  track: originalTrackReference,
  key: String(track.uri ?? track.path ?? ""),
  folder: normalizedFolder(track.folder),
  searchKey:
    lower(title) + " " + lower(artist) + " " + lower(album) + " " + lower(folderRaw)
}
```

Then:

1. non-empty search filters `preparedTrack.searchKey`, but returns the original
   track reference in source order;
2. folder browsing uses `preparedTrack.folder`;
3. selection resolution uses the prepared key/folder;
4. empty search may continue returning the exact original
   `LocalMusic.libraryTracks` object, preserving today's binding identity;
5. `buildSongEntries()` may still create its fresh UI entry objects exactly as
   it does now.

Do not move this cache into the always-resident LocalMusic service unless there
is a reason for another consumer to share it. The view-local cache is sufficient
and respects current UI lifecycle ownership.

Required oracle:

- empty library / one / many thousands of tracks;
- empty query returns the existing source-list semantics;
- leading/trailing search spaces and mixed case;
- empty/null title, artist, album, folder, URI and path;
- non-ASCII strings using exact JS `toLowerCase()` behavior;
- URI-before-path key precedence;
- root, leading-slash, trailing-slash and nested folders;
- direct tracks mixed with child folders;
- source order and original track object identity;
- selected individual tracks and selected parent folders;
- MPD rescan replacing the library while query/folder/selection is resident;
- exact Songs list and resulting play/enqueue payloads.

### R37.2 — Local synchronized lyrics linearly rescan a sorted timeline

`LocalMusic.localLyricsActiveIndex` currently walks from the beginning:

```qml
let index = -1
for (let i = 0; i < localLyricsLines.length; i++) {
    const time = Number(localLyricsLines[i]?.time ?? -1)
    ...
    if (time <= position)
        index = i
    else
        break
}
return index
```

This reactive property follows `lyricsPosition`, which prefers live MPRIS
position when available. As playback advances, work grows with the current song
position: near the end of an N-line file, each evaluation reads nearly N rows.

The sortedness needed for an upper-bound binary search is not an assumption.
Both authoritative producers explicitly establish it before QML receives synced
lines:

Python fallback:

```python
timed.sort(key=lambda item: float(item["time"]))
```

Rust `inir-mpdd` path:

```rust
timed.sort_by(|left, right| left.0.total_cmp(&right.0));
```

Hadalis also already uses the same algorithmic class in
`LyricsService._indexForPosition()`, which binary-searches a sorted lyric
timeline and then schedules the next lyric transition with a one-shot timer.

The narrow candidate is only the lookup algorithm in LocalMusic. It does not
change MPRIS cadence, local-lyrics loading, auto-scroll behavior or the producer
payload.

Parity detail: the current loop uses `<=` and keeps advancing, so duplicate
timestamps resolve to the **last** row at that timestamp. Implement an upper
bound (first timestamp > position, then index - 1), not a lower-bound lookup.

Required oracle:

- unsynced/plain lyrics -> -1;
- empty synced list -> -1;
- playback before first timestamp -> -1;
- timestamp 0;
- exact first/middle/last timestamp;
- duplicate timestamps -> last equal row;
- between timestamps;
- after final timestamp;
- rapid forward and backward seeks;
- MPRIS-backed and MPD-status fallback positions;
- exact ListView currentIndex / auto-scroll behavior.

### R37.3 — Every desktop widget computes the same pause state twice

The power service exposes:

```qml
function widgetsActiveForOutput(outputName: string): bool {
    return !root.shouldPauseForOutput(outputName)
}

function reducedModeForOutput(outputName: string): bool {
    return root.shouldPauseForOutput(outputName)
}
```

The values are exact logical complements.

Each `AbstractBackgroundWidget`, however, binds both independently:

```qml
readonly property bool powerActive:
    WidgetPowerManager.widgetsActiveForOutput(root.outputName)
readonly property bool powerReduced:
    WidgetPowerManager.reducedModeForOutput(root.outputName)
```

That means one reactive invalidation can call `shouldPauseForOutput()` twice for
the same widget/output.

The cheap branches are not the concern. When
`pauseWhenWindowsPresent` is enabled, the calculation calls
`_hasWindowsOnActiveWorkspace()`, which:

1. creates a new Set;
2. iterates all Niri workspaces to find the active ids for the output;
3. scans Niri windows until a visible active-workspace window is found.

It also evaluates output eligibility through DesktopWidgetLayout. With multiple
resident widgets on an output, repeating the full calculation twice per widget
multiplies the same derived work.

The smallest strict-lossless change is local:

```text
powerActive = WidgetPowerManager.widgetsActiveForOutput(outputName)
powerReduced = !powerActive
```

Do not introduce a global service cache in the first patch. A per-output cache
would require a much broader invalidation proof across Niri windows/workspaces,
GameMode, DesktopWidgetLayout, edit mode and Config. Removing the exact duplicate
client call gives deterministic savings with almost no new state.

Required oracle:

- power manager disabled/enabled;
- widget edit mode;
- manual GameMode;
- fullscreen globally and on another/same output;
- `pauseWhenWindowsPresent` false/true;
- zero/multiple active workspaces;
- minimized vs visible windows;
- Niri vs non-Niri;
- output allowed/disabled by DesktopWidgetLayout;
- multi-monitor widgets;
- assert `powerReduced === !powerActive` through every transition;
- animation, clock, visualizer and WidgetSurface power bindings unchanged.

### R37.4 — Cliphist sloppy search still normalizes raw rows per query

Round 29 correctly found that Cliphist already owns important prepared state:

- revision-keyed Fuzzy.prepare records;
- bounded top-K insertion for limited fuzzy queries;
- equality suppression when the source list has not changed;
- a separate source-revision cache for classic/Waffle display-filter keys.

That did not cover the sloppy/Levenshtein branch.

Current sloppy search still does:

```qml
const searchLower = search.toLowerCase()
const count = Math.min(100, root.maxEntries)
...
const entry = entries[i]
const score = Levendist.computeTextMatchScore(
    entry.toLowerCase(), searchLower)
```

in both the limited and unlimited result paths. So up to the first 100 raw
history strings are lowercased again for every sloppy query even though
`entries` is unchanged.

This is now the exact same source-proven class as Emoji promotion #98. Extend
the existing fuzzy prepared record:

```text
{
  name: Fuzzy.prepare(displayText),
  lower: rawEntry.toLowerCase(),
  entry: rawEntry
}
```

and use those first prepared records in sloppy mode.

Do not substitute the display-filter cache's `iiKey` or `waffleKey`.
Sloppy search currently scores the **raw cliphist entry string**, including the
stored id/preview representation. Changing it to a cleaned display key would
change fuzzy scores/results.

Required oracle:

- empty search fast path unchanged;
- sloppy off/on at runtime;
- 0, <100, =100 and >100 history entries;
- `maxEntries < 100`;
- positive and non-positive result limits;
- exact score threshold boundary;
- equal-score insertion order;
- limited top-K and unlimited sort paths;
- binary/image preview rows;
- entries replacement invalidates the prepared lowercase key;
- exact original raw-entry identity/order returned.

### R37.5 — Findings deliberately not promoted from this pass

**LyricsService:** its synchronized network/media lyric path already uses binary
search and a one-shot timer to the next lyric boundary. It is the positive
precedent for R37.2, not another optimization candidate.

**DeviceStatePersistence / PowerProfilePersistence:** the device restore paths
are event-driven and their timeout timers are one-shot. Power-profile/TLP
probing already has explicit demand/capability gating documented in earlier
rounds. No recurring source-proven waste was found here.

**ConflictKiller / FirstRunExperience:** both perform bounded lifecycle work:
ConflictKiller consolidates conflict discovery into one delayed startup /proc
scan, while the wallpaper discovery path exists only for first-run bootstrap.
Removing those probes would trade correctness for negligible steady-state gain.

**GowallService per-line list publication:** `gowall list` and color extraction
currently publish by immutable array copy for each output line. Collecting into
one array would reduce cumulative copying, but it would also change observable
incremental publication timing. No source-only proof shows that timing is
irrelevant, so this remains unpromoted until a focused UI fixture or profiler
justifies a different collector contract.

**Classic ClipboardPanel:** its search path already calls
`Cliphist.filterEntries()`, which caches sanitized/lowercase display keys by
entries revision. The remaining sloppy-search raw lowercase gap belongs in the
shared Cliphist service (R37.4), not as another panel-local cache.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.

## Research continuation — round 38

Baseline: `dev` at `8c8988f532963954944ab802e44a1c730a36a226`.

This round focused on asynchronous network/process work that had not appeared in
the canonical ledger. The key constraint was stricter than "these calls look
duplicated": a candidate was promoted only when the current source exposes an
exact boundary where work can be removed without changing the authoritative
data or visual result. That excludes attractive but freshness-changing schemes
such as sharing one Anime schedule snapshot across all seven weekdays.

Current source identities:

- `services/deferred/AnimeService.qml`:
  `fcbc0c1c47ccb137161b5a43054ecc220c0c9bc5`;
- `modules/sidebarLeft/animeSchedule/AnimeScheduleView.qml`:
  `4023dc68759dd68d245cced7b01ef1d4a33400b1`;
- `services/deferred/NewsService.qml`:
  `59e6de2a6fd856ffd9f26eeaa9c3c743af12086a`;
- `scripts/test-news-service-contract.sh`:
  `cf168ab8e6299d9fb7101db884e6a9727960a157`;
- `modules/sidebarLeft/anime/BooruImage.qml`:
  `69e9db92e3a900c0295f6eee309e900f30a503b6`;
- `modules/sidebarLeft/anime/BooruResponse.qml`:
  `413ac078b642828cb27d6d169df35dd9482de153`;
- `modules/common/Directories.qml`:
  `0fb9ae0b8ce77bb5b280c3aef16c9b3d22d73f27`;
- `services/Booru.qml`:
  `952e5af0962dcfd913f7aa62c020cfb3263889b2`;
- `services/deferred/CavaService.qml`:
  `8f343598ec100a3f98e4fc41746a82cfbbef6e6c`;
- `services/TlpRuntimeCapabilities.qml`:
  `a5cff8cba0f14473d6676c416946507ebd0a0c01`;
- `services/TlpSettingsService.qml`:
  `72eb106e8b2334d1e3a1734ad822de941235972b`;
- `scripts/test-performance-lifecycle.sh`:
  `dcbbc9b28ce2258589df2daee5d1d7daa4c439c6`;
- `services/Translation.qml`:
  `3d26f05cb1fdd4ac6bc3cd792e4834ef11e28c54`;
- `translations/en_US.json`:
  `137668675855e7769df9bfb2d844d54b938a5363`;
- `services/DisplayMode.qml`:
  `dee42cadbac0ff4dd583909836fb23644b694c55`.

### R38.1 — Anime Schedule can issue the same "today" request twice during construction

`AnimeService` owns a 10-minute cache keyed by resolved weekday, but the cache
does not help while the first request is still in flight.

The singleton performs:

```qml
Component.onCompleted: {
    if (Config.options?.sidebar?.animeSchedule?.enable) {
        Qt.callLater(() => root.fetchSchedule("today"))
    }
}
```

while `AnimeScheduleView` independently performs:

```qml
Component.onCompleted: {
    AnimeService.fetchSchedule("today")
}
```

Both resolve `"today"` to the same `root.currentDay`. If the view is created
before the call-later request completes, or vice versa, the cache timestamp is
still absent and both calls POST the same `scheduleQuery`. Both responses then:

1. parse the same GraphQL JSON;
2. walk up to 50 `RELEASING` media rows;
3. construct a Date for every row with a next airing episode;
4. resolve weekday;
5. normalize every row matching the same target day;
6. write the same per-day cache/output.

Repeated clicks on the same weekday during a slow request have the same shape.

The strict candidate is deliberately narrow:

```text
if scheduleInFlight[targetDay]:
    return existing pending work
else:
    mark targetDay in flight
    issue the existing GraphQL request
    clear targetDay on every completion/error path
```

This does **not** make all weekdays share one cache validity window. Although the
network query itself is identical for every weekday, current behavior requests
a fresh snapshot when a different day's cache is missing. Pre-populating all
seven day caches from one earlier response could make a later weekday up to ten
minutes older than it is today; that is not strict-lossless and is therefore
not promoted.

The same function also constructs two values that are never consumed:

```qml
const dayNum = root._dayToNum[targetDay] ?? 1
const query = `query ($day: Int, $isAdult: Boolean) { ... }`
```

Actual transport uses `scheduleQuery`, which has only `$isAdult`. Removing
that dead integer lookup and large legacy query-string allocation is safe, but
it is a small secondary cleanup rather than a separate promotion.

Required oracle:

- feature disabled vs enabled;
- service construction without view construction;
- view construction before/after the singleton's call-later callback;
- two/three rapid calls for the exact same resolved day;
- simultaneous requests for two **different** weekdays remain independent;
- cache hit during no in-flight request;
- successful/HTTP/API/parse error paths always clear only the relevant in-flight key;
- NSFW false/true;
- exact `schedule`, `_scheduleCache[targetDay]`, cache timestamp and normalized
  row order/identity shape;
- loading/error state and refresh-button lifecycle;
- manual refresh after cache expiry.

### R38.2 — NewsService fully parses successful stale bodies before rejecting them

`NewsService.fetch()` already has last-request-wins generation semantics.
For a 200 response the current order is:

```qml
const parsed = root._parseRss(xhr.responseText)
if (generation !== root._requestGeneration)
    return
root._cache[url] = parsed
root._cacheTimestamps[url] = Date.now()
root.articles = parsed
```

The existing regression contract intentionally proves that stale responses
cannot mutate cache/timestamps/articles, but it currently encodes
`parse < generation guard < cache write`.

That ordering leaves pure waste on the stale branch. `_parseRss()`:

- runs a global `<item>` regex over the RSS document;
- extracts title/link/date/source with four additional regexes per item;
- decodes entities;
- parses timestamps;
- allocates up to 30 article objects.

After all of that, the stale generation returns without publishing any result.

Moving the generation test before parsing is unusually strong strict-lossless
evidence: current source already declares that a stale response has no authority
to mutate any public state. Skipping computation whose result is guaranteed to
be discarded cannot change the active-generation output.

The focused regression should be strengthened rather than removed:

```text
DONE + status 200
  -> generation guard
  -> parse only if current
  -> cache
  -> timestamp
  -> articles
```

Required oracle:

- one successful fetch;
- cache hit;
- A starts -> B starts -> A(200) completes -> no parse/publication from A;
- A starts -> B starts -> A(non-200) completes -> no active error overwrite;
- stale malformed 200 body must not surface a parse error;
- active malformed 200 body keeps today's parser/error behavior;
- B success publishes exact same articles/order/timestamps;
- local-city URL changes while an old local feed is in flight;
- rapid topic-board changes and return to a cached board.

A separate same-URL in-flight coalescer may also be useful because NewsTicker
and NewsView can request the same configured feed. It is **not** promoted in
this round because a robust design must preserve the current A -> B -> A
last-request-wins semantics when multiple XHRs overlap. The pre-parse guard gives
a deterministic win without introducing request ownership state.

### R38.3 — Manual Booru previews repeat directory creation once per thumbnail

For `danbooru`, `waifu.im` and `t.alcy.cc`, `BooruResponse` enables
`manualDownload`. Each image delegate then creates:

```qml
Process {
    command: ["/usr/bin/bash", "-c",
        `mkdir -p '${root.previewDownloadPath}'
         && [ -f ${root.filePath} ]
         || curl -sSL '...' -o '${root.filePath}'`]
}
```

and starts that process from the delegate's `Component.onCompleted`.

A normal Booru request defaults to 20 images, so one response can create many
Bash processes and, inside each Bash, an external `mkdir` child before the
existing cache-file test. Missing cache entries then additionally launch curl.

Hadalis already has central directory ownership. `Directories.qml` performs
one ordered bootstrap command that:

1. removes transient `booruPreviews` along with other transient media trees;
2. recreates `booruPreviews` with the required cache/state directories.

That bootstrap is asynchronous. Therefore this is **not** a license to simply
delete every delegate's `mkdir`: an owner who opens the sidebar immediately
after shell startup could race the bootstrap.

The strict direction is to turn directory readiness into one explicit owner:

1. the shared Directories/bootstrap owner, or a response-scoped manual-preview
   owner, runs/observes the one required directory creation;
2. it publishes a ready/failure state;
3. manual preview delegates start their unchanged cache-test/curl path only
   after readiness;
4. on a directory failure, delegates preserve a bounded failure state rather
   than each retrying an uncontrolled mkdir;
5. ordinary providers that render remote preview URLs directly remain untouched.

This collapses the directory-preparation part from O(images) child processes to
one while preserving why those three providers use local manual previews.

Do **not** mechanically reuse `ImageDownloaderProcess.qml` in the first patch.
That component also validates files through ImageMagick and uses temporary-file
rename semantics, adding work and changing the current Booru cache contract.
Likewise, do not introduce a serial/bounded download queue yet: changing
concurrency changes thumbnail arrival timing and needs a separate UI/performance
oracle.

Required oracle:

- cold shell + immediate sidebar open before directory bootstrap completion;
- warm shell after directory ready;
- 0/1/20 manual-provider images;
- cached preview file -> no curl and exact existing image source;
- uncached preview -> one curl per missing file and exact local destination;
- directory creation failure;
- duplicate filenames/URLs across historical responses;
- provider switch manual -> ordinary -> manual;
- response destruction while downloads are active;
- sidebar close/reopen;
- exact final image pixels/file names/cache paths and context-menu actions.

### R38.4 — Paths deliberately not promoted

**Cross-day Anime snapshot reuse:** the schedule GraphQL query is identical for
every weekday, so one response could technically be partitioned into all seven
days. Doing so would also make later weekday requests reuse the earlier
snapshot within the ten-minute cache window. That changes freshness relative to
current per-day cache timestamps, so it is not strict-lossless.

**CavaService:** the shared CAVA owner already keeps one process, writes parsed
bars into a reused frame buffer, suppresses unchanged frame publication and
uses lifecycle consumers. The remaining high-frequency details such as watchdog
restarts are tied to exact no-data timeout semantics; no new change is promoted
without profiling.

**TLP runtime/settings safety timers:** both services retain a 30-minute safety
refresh, and `scripts/test-performance-lifecycle.sh` explicitly requires that
cadence. Those are intentional sparse correctness probes, not missed busy
polling.

**Translation runtime:** `Translation.tr()` is extremely high fan-out, but the
5,613-line English catalog currently contains only two `/*keep*/` values.
Scanning/pre-normalizing the whole catalog during startup merely to avoid a tiny
`endsWith()` branch on ordinary lookups is not proven to be a net win. Keep it
unpromoted until profile evidence says translation lookup matters.

**DisplayMode mirror probe:** the `wl-mirror` availability check is a one-shot
probe owned by the display-mode singleton, whose concrete consumer is the Abyss
Utilities display page. It is not a recurring poll and no source evidence shows
material steady-state cost.

**Booru `responseFinished()` ready-state emissions:** the signal is currently
emitted from the XHR ready-state callback and is consumed by the Bar ping
indicator. Restricting it to `DONE` may be semantically cleaner, but it changes
observable notification timing. Treat that as a correctness/API-contract issue,
not a strict-lossless performance candidate.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without comparable
before/after measurement.

## Research continuation — round 39

Baseline: `dev` at `7ec2321994de87f3d32c094668f7bd71a150e919`.

This round deliberately moved away from the network/process work in round 38 and
looked for active render paths that were absent from the canonical ledger. The
search was cross-checked against current `dev`; candidates already covered by
the Bar/Dock glass work, Waffle Task View CPU grouping, classic AltSwitcher, or
wallpaper-selector research were not re-promoted under new names.

Current source identities:

- `modules/ii/overlay/OverlayTaskbar.qml`: `bb432c65ea7256030767aacdc0c1879104c6340e`;
- `modules/ii/overlay/OverlayContent.qml`: `64a277d10a8d89b58ec8d4b040a859d0424db488`;
- `modules/waffle/altSwitcher/WaffleAltSwitcher.qml`: `00a169d62a31d4b3ae12aba6d6ab85f995b9fbd9`;
- `modules/waffle/altSwitcher/WaffleAltSwitcherContent.qml`: `2f4c8a398d6d4bf515a0f002c43dacf1d8772132`;
- `modules/waffle/taskview/WaffleTaskView.qml`: `37ddd9d8318efab3b435e23e2b5dfd4f8baa785d`;
- `modules/waffle/taskview/WaffleTaskViewContent.qml`: `8ee8ff511dafab601a840ebc0475e18563b41034`;
- `modules/waffle/taskview/WorkspaceThumbnail.qml`: `1d18942c2480d04b426e2ff537d4411dbba2d48d`;
- `modules/common/widgets/EscalonadoShadow.qml`: `ecc4d46d5aef91a9893cdc045ec00d2ef925685f`;
- `modules/dashboard/DashWeather.qml`: `243aab28a3d51934980ae90a78da54457dbf8cbf`;
- `services/ConflictKiller.qml`: `b6ebab2f51b0ec00c19bddb5e3704a6739e0a001`;
- `services/Idle.qml`: `ee6eed98adaa4164a9bc0cb891159c805e3f8507`.

### R39.1 — Overlay taskbar still blurs a full output to paint a small retained strip

`OverlayTaskbar` is a missed sibling of the already documented Bar/Dock bounded
wallpaper-blur family. The taskbar itself is content-sized, yet its Angel path
creates an image at the dimensions of `Quickshell.screens[0]`, requests the
same full-screen source size, and enables a `MultiEffect` blur on that image.
The surrounding taskbar then clips and masks the result back to its rounded
content-sized geometry.

The expensive resources are lifecycle-gated correctly: `presentationActive`
keeps them alive while the Overlay is open or the taskbar is still fading, then
releases the image source/effect after opacity reaches the retained threshold.
Therefore the candidate is not to shorten that lifetime. The strict direction
is to reduce only the raster area:

1. preserve the exact screen-aligned `PreserveAspectCrop` transform;
2. derive the taskbar rectangle in the same screen coordinate space;
3. expand that rectangle by the exact support required by `blurMax: 64`;
4. materialize/capture only that padded area;
5. present the same cropped pixels through the existing rounded owner mask;
6. keep `presentationActive`, opacity animation, content sizing and widget state unchanged.

This is structurally the same class as the canonical Bar/Dock candidate but has
a separate transient owner and was not named by the existing ledger. A full
RGBA8 output is about 7.9 MiB at 1920×1080 and 31.6 MiB at 3840×2160 before
effect intermediates. Those figures describe texture dimensions only; they are
not whole-shell RAM or GPU savings.

Required oracle:

- Angel style with effects on/off;
- Overlay closed, opening, fully open, closing and the final retained fade frame;
- narrow/wide taskbar content, battery present/absent and multiple widget-button counts;
- 1920×1080, 4K, fractional scale and multi-output layouts;
- taskbar at non-zero screen-relative x/y;
- wallpapers with strong edge/detail patterns that expose crop misalignment;
- exact corner/edge alpha through the full blur support;
- identical input/focus/pinned-widget behavior because the render optimization must not touch Overlay ownership.

Target 0% pixel deviation for the crop-only path.

### R39.2 — Waffle skew Alt Switcher builds a captured mask surface for every slice

The Waffle skew preset has a stronger structural signal than a generic
`MultiEffect` search. Each ListView delegate already defines the same
parallelogram three ways: its width/skew constants, an analytic
`containmentMask.contains(point)` equation, and a white `ShapePath` used only as
the visual mask. Despite that known geometry, the visible path currently does:

- `maskedBody.layer.enabled: root.cardVisible`;
- 4× MSAA when effects are enabled, otherwise 1×;
- `MultiEffect { maskEnabled: true }` on that content layer;
- a `ShaderEffectSource` mask whose source item enables another layer;
- a white antialiased parallelogram Shape inside that captured mask.

The ListView is configured for twelve visible skew positions and an additional
`cacheBuffer` equal to the expanded slice width. The exact number of instantiated
delegates is runtime-dependent, so this round does not invent an FBO count, but
the offscreen chain is unquestionably per delegate while the skew card is visible.

The strict first experiment should leave the Canvas shadow, preview Image,
WindowPreviewService capture, slice width animation and ListView lifecycle
untouched. Only the parallelogram clipping step should be replaced by one
analytic mask/render pass using the existing skew equation. This isolates the
render-pass saving from shadow appearance and preview timing.

Required oracle:

- 1, 2, 12 and more windows;
- current expanded slice versus narrow non-current slices;
- first/last visible slices and delegates entering/leaving the cache buffer;
- preview missing, preview arriving during the 30 ms card reveal, and preview already cached;
- effects enabled (4× samples) and disabled (1×);
- rapid Alt cycling, close during preview capture and reopen;
- focus/currentIndex/navigation and exact containment hit-testing;
- fractional scale and width-animation frames;
- global raster comparison plus a dedicated alpha/edge-band comparison on both slanted sides.

Target 0% for an exact mask-only collapse. If the AA implementation differs,
the candidate remains unpromoted until global normalized visual error is below
1% and the slanted-edge oracle also passes.

### R39.3 — Paths deliberately not promoted

**Waffle Task View root blur:** `WaffleTaskView.qml` already captures only the
horizontal `blurStrip` with `ShaderEffectSource.sourceRect` before applying its
`MultiEffect`. It is a useful positive baseline for R39.1, not another missed
full-screen-blur candidate.

**Waffle workspace thumbnails:** carousel mode can show one blurred/masked
wallpaper per workspace, so sharing a prepared wallpaper texture may have
value. Centered mode already suppresses wallpaper presentation for non-selected
workspaces, however, and moving blur ownership to a shared texture could change
first-presentation timing or AA/mask behavior. Keep this at measure-first until
GPU/FBO evidence and a raster oracle justify a concrete ownership design. The
existing round-32 `WaffleTaskViewContent` CPU grouping candidate remains
separate and must not be duplicated.

**EscalonadoShadow:** the component contains the same screen-sized glass-blur
shape, but current code search finds no runtime instantiation outside its own
definition/qmldir/config/tests. Optimizing an unused helper cannot produce a
demonstrated runtime win; do not promote it unless an active owner appears.

**DashWeather:** its 30 s timer updates the date object only while visible.
Changing it to a coarser/day-boundary wakeup would save very little and changes
the exact date-flip observation boundary. No candidate is promoted without
profile evidence.

**ConflictKiller and Idle:** ConflictKiller performs one deferred consolidated
`/proc` conflict scan after config readiness. Idle is event/config driven and
uses a bounded 30 s retry only after `swayidle` failure. Neither is a recurring
healthy-state hot path worth complicating.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without comparable
before/after measurement.

## Research continuation — round 40

Baseline: `dev` at `3081bbf461ca3f71cf0a0405f5cadc65f21d011d`.

This round moved away from graphics and audited collection publication paths
that are active only when their owning feature is used. Candidate promotion
required both a current runtime owner and a removal boundary that preserves
observable array order, object identity and notification timing.

Current source identities:

- `services/ai/AiProviderCatalog.qml`: `188a129bc2302b5d1af24dd8976332d7d4e174e0`;
- `modules/common/AiProviderPresets.qml`: `3d3ba9eba45a58bbcaf4926d19e748aaa58e1da9`;
- `modules/settings/AiConfig.qml`: `483e77ec09b09c99ffafd97c6e8365b8e38cf9ba`;
- Waffle `WAiPage.qml`: `03992467529e32cff8af550a4375a6aad0dd61d5`;
- `modules/sidebarRight/events/EventsWidget.qml`: `f505dc6331e2f1d56eac547dfe7c4b0e713a162a`;
- `modules/background/widgets/calendar/CalendarUpcomingWidget.qml`: `a47d5740b2b6739106fb67b2ec3be8552b53430d`;
- `services/Events.qml`: `dcc3671e7c6d640fdbe5d3ee8dce45bc412148e7`;
- `services/CalendarSync.qml`: `6e0b89c56eda5ee612be8438d9c20d4851a09617`;
- `modules/sidebarRight/calendar/CalendarDayDetail.qml`: `4deaddeed8ac427f8e4fe44cf8c0b7bbd942f0f5`;
- `modules/overview/Overview.qml`: `431e4443dbde6afc00b2e88a0d9db55e3dbe11b4`;
- `modules/overview/OverviewAllAppsGrid.qml`: `777fe6f79cd90e9585d19cdfd79fdd01b6b6c4d1`;
- `modules/abyss/content/AbyssPopupContent.qml`: `0430fddb89baac3f0f7c5bf58e564bc42c722fec`;
- `modules/abyss/content/AbyssLauncherContent.qml`: `5af7fb7b59fd8dfe4b6183218aafc67318314a87`;
- `modules/dashboard/DashTodo.qml`: `7a18bf0693ad12e837cca44b95b82d2c89c9d425`;
- Sidebar `TodoWidget.qml`: `84cb458f602ad40583cfa37282585d175426e5f6`.

### R40.1 — AI model publication copies the catalog, then every provider card scans it again

`AiProviderCatalog._publishModels()` currently assembles the discovered catalog
with repeated immutable concatenation:

```qml
let merged = []
for (const providerId of Object.keys(root._catalogByProvider))
    merged = merged.concat(root._catalogByProvider[providerId] ?? [])
merged.sort(existingComparator)
root.models = merged
```

Each `concat` allocates a new array and copies every model already accumulated.
With multiple non-empty providers, publication therefore performs avoidable
prefix copies before the one sort that is actually required.

The public helper then discards the provider ownership that was just traversed:

```qml
function modelsFor(providerId: string): var {
    return root.models.filter(model => model.providerId === providerId)
}
```

The Material AI Settings provider grid has one delegate per
`AiProviderPresets.presets`; current source contains eleven presets, and every
delegate owns `discoveredModels: AiProviderCatalog.modelsFor(preset.id)`.
Therefore a single `models` publication can trigger multiple complete scans of
the same catalog. Waffle also calls `modelsFor()` when opening a provider form.

A strict implementation can retain today's single authoritative `models`
publication:

1. append every provider bucket into one `merged` array with `push`, preserving
   `Object.keys(_catalogByProvider)` order and each bucket's order exactly;
2. apply the current sort comparator unchanged;
3. before assigning `root.models`, clear/fill a stable private JavaScript
   `Map` from exact `providerId` values to arrays of references encountered in
   that **sorted** result;
4. assign `root.models = merged` exactly once as today;
5. make `modelsFor(providerId)` deliberately read `root.models` to retain the
   current QML dependency, then return `bucket.slice()` so callers still get a
   fresh array on every call;
6. do not reassign the private Map itself, so building the index does not add a
   second QML NOTIFY wave before `modelsChanged`.

This keeps exact model object identity and the global sort as the authority;
the index only removes repeated membership scans.

Required oracle:

- zero providers/models;
- one provider and many models;
- all eleven current presets with empty/non-empty mixtures;
- duplicate/equal display names proving stable sort ties keep source order;
- local/free/name ordering exactly matches current output;
- missing/null/unusual providerId values, preserving strict `===` membership;
- `modelsFor()` unknown provider returns a new empty array;
- repeated `modelsFor()` calls return equal contents but distinct array objects;
- cache load, successful refresh, partial provider failure/stale catalog, and
  queued refresh;
- exact `modelsChanged`, provider-card update and `catalogUpdated` cadence;
- Material provider form and Waffle provider form choose the same first model.

### R40.2 — 30-day merged event lists parse dates inside every sort comparison

`EventsWidget` and the desktop `CalendarUpcomingWidget` independently build
30-day merged local + external event arrays. Both already do useful batching
through `CalendarSync._getEventBucketsForDates()`, but after cloning records
they sort with date parsing inside the comparator:

```qml
all.sort((a, b) =>
    new Date(a.dateTime || a.startDate)
    - new Date(b.dateTime || b.startDate))
```

A comparison sort invokes that expression many times. For N merged events this
turns timestamp parsing/object construction into comparator-multiplied work even
though each event's sort field is immutable within that rebuild.

The strict direction is local preparation, not a new calendar cache:

1. create one temporary timestamp map/parallel key set for the rebuild;
2. when cloning a local event, parse its current `dateTime || startDate` once;
3. for an external event, reuse the `evtTime` Date already created by the
   existing past-event filter and store its millisecond value;
4. sort the same event objects with `time[a] - time[b]`;
5. leave publication/cloning/order and CalendarUpcoming's later
   `slice(0, maxEvents)` unchanged;
6. keep invalid timestamps as `NaN`: subtraction then still yields `NaN`, which
   has the same comparator effect as the current invalid-Date subtraction.

`Events.getUpcomingEvents(30)` already uses a private start-time Map for its own
sort. This proposal does not change that service or assume its local ordering
is enough after external records are merged.

Required oracle:

- zero/one/many local and external events;
- all-day and timed events;
- external event before `now`, including today's all-day exception;
- equal timestamps from local/external sources and stable source order;
- invalid/missing date strings;
- timezone offsets and DST-boundary dates;
- CalendarSync bucket order variations;
- exact cloned fields (`_source`, normalized external `dateTime`, category and
  priority in EventsWidget);
- CalendarUpcoming maxEvents 0/1/3/5/8/12 and arbitrary configured values;
- exact `_showDayHeader` sequence with grouping on/off;
- midnight `_todayKey` rollover and both local/external update signals.

### R40.3 — Paths deliberately not promoted

**OverviewAllAppsGrid inactive-mode projection:** the component does eagerly
build both alphabetical and category projections, so gating the unused mode
would be source-safe *if the component were active*. Current `Overview.qml`,
however, sets `allAppsGridLoader.dashboardMode: true` and requires
`!dashboardMode` in `active`, making this loader unreachable at this HEAD.
Optimizing an uninstantiated tree has no current runtime value. The contradictory
loader gate is a product/correctness cleanup, not an optimization finding.

**AbyssLauncherContent window/app filtering:** current runtime search finds this
component only in its qmldir/docs. `AbyssPopupContent` maps kind `launcher` to
`AbyssLauncherControlsPopup`, not `AbyssLauncherContent`. Do not promote list
filter work from a component with no current runtime owner.

**Todo projections:** Dashboard and Sidebar both partition `Todo.list` into done
and unfinished records, and each could be reduced to one local loop. The lists
are normally small and update on user/backend task mutations rather than a hot
clock/compositor path. Keep this below the promotion line unless profiling or a
large-task workload makes the allocation visible.

**CalendarDayDetail:** the selected-day view also constructs Dates inside three
time-group sort comparators. Its input is only one selected day, so the same
prepared-key technique is valid but lower value than the two 30-day builders.
Do not inflate the promoted scope without measurement.

**AiProviderCatalog aggregate counters:** free/local/provider-health counts each
use simple filters, but they update at catalog/provider-state cadence rather
than an interactive hot loop. Folding them into publication could alter NOTIFY
ordering for very small savings; leave them unchanged in the first optimization.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without comparable
before/after measurement.

## Research continuation — round 41

Baseline: `dev` at `01050f572d0669e6bb1d9c991a28b2717a7433f3`.

This round returned to Niri presentation fan-out, but deliberately avoided
service-authority changes. The strongest findings remove repeated reads over
the same already-published `NiriService.windows` snapshot while preserving
today's batching, fallback and signal order.

Current source identities:

- `modules/bar/BarTaskbar.qml`: `3aca1b63e2633584c86f75c6a2e5eb2ebaebfdb3`;
- `modules/bar/BarTaskbarButton.qml`: `15430646fe40a7e4708dc0d5de8c19858259713d`;
- `modules/dock/DockApps.qml`: `11b3ea8cc17c91a1cf3b6a1f41f64f392d4dfcc9`;
- `modules/dock/DockAppButton.qml`: `e82cf611338e518d70f8c95e45808217c7b90934`;
- Waffle `WaffleTaskViewContent.qml`: `8ee8ff511dafab601a840ebc0475e18563b41034`;
- Waffle `WindowThumbnail.qml`: `466f1b9477641fe1588f3c3468da6801e321579e`;
- `modules/bar/Workspaces.qml`: `f7c51bb42b984ba8d3da078652a36ca75bd2db71`;
- `modules/bar/ActiveWindow.qml`: `7b6edafc7d90adc58c399f672d02a334eec385e1`;
- `services/NiriService.qml`: `4c8194493fd380bf0ad8c51bc62990ad0c232738`;
- `services/GameMode.qml`: `692f3e200b7c46835f44f152c88f231e2d0bd2b5`;
- `services/ScreenTime.qml`: `1eabb174c464bf0a1e372ebbe8a43f671d2e9d89`;
- `modules/sidebarLeft/widgets/QuickLaunch.qml`: `de61cc5eccb5f5b2b926aa8da7594cbdb394676e`;
- Waffle `StartPageContent.qml`: `bd9f6188b5c4bbcafb1fe61b982836aa145d7098`.

### R41.1 — Focused-window discovery is repeated once per app/window delegate

`NiriService` already derives `activeWindow` while publishing a batched window
snapshot, but several UI paths intentionally do not trust that property alone.
Bar and Dock delegates both use the same expression:

```qml
NiriService.windows?.find(window => window.is_focused)
    ?? NiriService.activeWindow
    ?? null
```

That published-windows-first ordering is important enough that this round does
**not** propose replacing the expression globally with `activeWindow`.
`windows` is assigned before `activeWindow` inside the service update timer, and
other freshness-sensitive consumers intentionally use different precedence.

The problem is ownership fan-out:

- every `BarTaskbarButton` executes the complete find;
- every `DockAppButton` executes the complete find;
- every visible Waffle `WindowThumbnail` independently scans the same window
  list for the focused id.

Those delegates share existing owners that are already invalidated by the same
state and can perform the lookup once:

1. `BarTaskbar` derives the exact current Niri focused-window expression once
   and passes the resulting object to every `BarTaskbarButton`;
2. `DockApps` does the same for `DockAppButton`;
3. `WaffleTaskViewContent` derives the focused window id directly from
   `NiriService.windows` once and passes only that integer to every
   `WindowThumbnail`;
4. delegate active/focused matching code stays byte-for-byte equivalent after
   substituting the supplied object/id;
5. Hyprland paths remain untouched.

This avoids introducing a new singleton property, nested mutable cache, or
NOTIFY ordering contract. It is purely a common-subexpression ownership move.

Required oracle:

- zero windows;
- one focused window;
- multiple windows with exactly one focused flag;
- malformed snapshot with zero focused flags, preserving Bar/Dock
  `activeWindow` fallback and Waffle's current `-1` behavior;
- malformed snapshot with multiple focused flags, preserving first-match order;
- focus-only change without membership change;
- title/app-id change on the focused window;
- open/close and layout-sort publication;
- Bar/Dock one-window and multi-window app groups, including identical app ids
  where title matching disambiguates the active toplevel;
- Task View cached membership remaining unchanged while focus moves;
- exact active dot/pill state and Waffle focus ring before/after every step;
- identical non-Niri behavior.

Do not fold `GameMode`, `ScreenTime` or other service consumers into the first
patch. Their precedence/freshness contracts differ and are not required for
the high-fan-out delegate saving.

### R41.2 — Workspace app-icon delegates each filter the full Niri window list

`Workspaces.qml` currently has three related reads over the same published
window snapshot.

Column mode filters once for the active workspace:

```qml
NiriService.windows?.filter(w => w.workspace_id === currentWs.id)
```

The workspace-mode button delegate then repeats a stronger version once per
rendered workspace:

```qml
const wins = NiriService.windows?.filter(w => w.workspace_id === niriWorkspace.id) ?? []
return wins.find(w => w.is_focused) || wins[0]
```

Separately, `doUpdateWorkspaceOccupied()` scans every window again to construct
`occupiedWorkspaceIds`.

For W rendered workspaces and N windows, app-icon representative discovery alone
is O(W×N) and allocates W filtered arrays after every relevant publication.
Yet its result needs only two facts per workspace: membership and a
representative window.

A strict one-pass summary can preserve the current semantics without retaining
full per-workspace buckets:

```text
occupiedIds
representativeByWorkspace
focusedChosenByWorkspace
```

For every window in **published source order**:

1. add valid `workspace_id` to `occupiedIds`;
2. if the workspace has no representative, store this first window;
3. if no focused representative has been chosen yet and this window is
   focused, replace the representative and mark focused chosen;
4. once a focused representative exists, never replace it with a later focused
   window.

That exactly reproduces `filter(...).find(is_focused) || wins[0]`: first
focused wins; if none is focused, first source-order member wins.

Consumers then become:

- workspace icon delegate: O(1) representative lookup;
- occupancy refresh: reuse `occupiedIds` rather than rescan N windows;
- column mode: keep its existing active-workspace filter in the first patch.

Keeping column mode separate is intentional. A full bucket index would retain
O(N) additional window references in every Workspaces instance and would begin
to overlap conceptually with Round 32's Waffle Task View grouping. The summary
above captures the larger workspace-mode fan-out with only O(workspaces) state.

Required oracle:

- 0/1/many workspaces and windows;
- per-monitor and focused-output workspace modes;
- dynamic and fixed workspace counts;
- `showAppIcons` true/false and number-overlay transitions;
- empty workspace;
- one/multiple windows in a workspace;
- focused window first/middle/last;
- malformed multiple focused windows: first focused must win;
- no focused window: first source-order window must win;
- duplicate, null and undefined workspace ids;
- focus-only, title/app-id, open/close and workspace-move publications;
- exact `workspaceOccupied`, icon source and active-workspace presentation;
- vertical/horizontal bars and multiple outputs.

Relation to earlier work: Round 11.1 remains valid because its config snapshot
guard prevents unrelated Config writes from assigning workspace properties and
arming the occupancy debounce at all. If both candidates are implemented, the
R41 summary additionally removes the N-window scan when a legitimate occupancy
refresh does run. Do not add both savings as independent whole-shell gains.

### R41.3 — Paths deliberately not promoted

**NiriService `activeWindow` as a universal replacement:** rejected for the
first patch. Current Bar/Dock code explicitly prefers a focused flag from the
published `windows` snapshot and only then falls back to `activeWindow`.
Changing that precedence or the service assignment order can create a different
transient focus result. R41.1 removes repeated scans without touching authority.

**ActiveWindow.qml:** each instance also scans the published window list for
the first focused record. This is one scan per ActiveWindow component, not one
scan per app/window delegate, so it is lower fan-out. It can later consume a
proven shared focus projection, but it is not needed to justify R41.1.

**GameMode focused-window path:** its fallback exists because Niri focus flags
can lag layout events; Round 20/27 already separates fullscreen/focus freshness
work. Do not replace its scan under this common-subexpression patch.

**ScreenTime:** it intentionally prefers `NiriService.activeWindow` and only
scans `windows` as a startup fallback. That short-circuit makes it a different
and usually cheaper contract.

**QuickLaunch:** `isAppRunning()` scans windows for each configured shortcut
using substring matching against lowercased app id/title. The default list is
small and this widget is sidebar-scoped. A normalized window-token index could
help large custom shortcut lists, but changing substring semantics or retaining
all lowercase titles needs workload evidence first.

**Waffle Start recent apps:** `getRecentApps()` stops after four unique app ids.
Its bounded scan/lookup is not promoted without evidence that Start-page rebuild
frequency makes it material.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without comparable
before/after measurement.

## Research continuation — round 42

Baseline: `dev` at `822cae55e9699d7de9a2c0bd0da9f4a2b18ee967`.

This round moved from compositor snapshot fan-out to interactive search paths.
Promotion required a stable source snapshot plus a way to move normalization or
ranking work off the text-query hot path without changing returned object
identity, ordering, readiness or live-provider state.

Current source identities:

- `modules/wallpaperLauncher/WallpaperLauncherList.qml`: `ca1ff0267883263e8e334f9c826b0938fc9ada2d`;
- `modules/wallpaperLauncher/WallpaperLibrary.qml`: `09d84346de34cfd23e65826e2436df7dda264aab`;
- `modules/wallpaperLauncher/WallpaperLauncherContent.qml`: `b0a9e8ee0bacfdc00a6efeedff4651b1df86aca1`;
- `modules/cheatsheet/CheatsheetKeybinds.qml`: `934bdc0a8f3de4e85ec662fc2008a877dc0e5637`;
- `modules/cheatsheet/Cheatsheet.qml`: `583e6b33842a4e250ad2639fab1781220c09dff7`;
- `services/deferred/NiriKeybinds.qml`: `a127f97a691e7d348e72889c2137c80e954a4b36`;
- `services/deferred/HyprlandKeybinds.qml`: `58cf069d1e20120fc12038aeea5b7144df431b82`;
- `modules/sidebarLeft/aiChat/AiModelSelector.qml`: `9581a8ba5c4f9132d904e5673bf29dd2a0328c53`;
- `modules/sidebarLeft/AiChat.qml`: `6b9b2b860559f238e81fade02daafded65a71d25`;
- `services/Ai.qml`: `6dc315458f7827f96a55dc2259365e814e8d1ed2`;
- `services/ai/AiProviderCatalog.qml`: `188a129bc2302b5d1af24dd8976332d7d4e174e0`;
- `modules/common/widgets/FontSelector.qml`: `fe938851d7d2b74f56dc371be7f5e8f5564128d3`;
- Waffle `WSettingsFontSelector.qml`: `7ef736232412a7e3b616c0476703adcea2aa1610`;
- `modules/common/widgets/IconThemeSelector.qml`: `19a7b8ceea8540ff5d8d46594e38df73a5761484`.

### R42.1 — Wallpaper search renormalizes every path on every keystroke

`WallpaperLibrary.consume()` already owns the complete snapshot boundary:

1. parse the `find` output;
2. deduplicate paths;
3. compute `relativePath` and animation kind;
4. sort static and animated lists by `relativePath`;
5. publish each list as a new property value.

Between scans/mode changes, each entry's `relativePath` is immutable.

`WallpaperLauncherList.filteredEntries` nevertheless does:

```qml
const query = searchText.trim().toLowerCase()
if (!query) return entries
return entries.filter(entry =>
    entry.relativePath.toLowerCase().includes(query))
```

So an N-wallpaper library recreates the same N lowercase strings for every
character typed.

Strict shape:

1. retain the current `entries` property as the only presentation model;
2. prepare an aligned lowercase relative-path key array only when that entries
   snapshot changes (or lazily on the first non-empty query);
3. keep `trim().toLowerCase()` for the query exactly;
4. for a non-empty query, iterate the keys and push the corresponding **original
   entry object** into a fresh result array;
5. for an empty query, continue returning `entries` directly;
6. invalidate preparation on Static/Animated mode switch and every library scan.

This does not change ScriptModel values, selection identity, current-index
matching or preview/apply paths.

Required oracle:

- 0/1/many entries;
- empty/whitespace query;
- case variants and Unicode paths under the current JavaScript lowercasing
  contract;
- duplicate basenames in different folders;
- paths outside the configured root where `relativePath === path`;
- Static -> Animated -> Static;
- forced refresh while a query is non-empty;
- browse-folder change;
- current wallpaper filtered in/out;
- exact filtered object identity/order and `visibleItems`;
- exact current-index, preview debounce and apply target after each edit.

The tradeoff is a bounded lowercase-key cache proportional to relative-path
text. A lazy cache can avoid that RAM until the user actually searches.

### R42.2 — Cheatsheet search repeats four stable normalization families per row

`CheatsheetKeybinds.allKeybinds` already rebuilds only from the compositor
keybind snapshot. It clones each row and adds the category once:

```qml
let item = Object.assign({}, kb)
item.category = cat.name
result.push(item)
```

But the text-query binding repeats stable transforms:

```qml
kb.key?.toLowerCase().includes(q)
|| kb.mods?.some(m => m.toLowerCase().includes(q))
|| kb.comment?.toLowerCase().includes(q)
|| kb.category?.toLowerCase().includes(q)
```

Niri publishes a replacement `keybinds` tree after parser/editor reloads;
Hyprland replaces its parsed keybind trees on compositor config reload. These
are natural invalidation boundaries.

The strict implementation should remain lazy because the Cheatsheet loads the
Keybinds page even when another page is visible:

1. when search is empty, keep returning `allKeybinds` and allocate no search
   projection;
2. on the first non-empty search for an `allKeybinds` snapshot, prepare a
   wrapper for each cloned item containing separate lowercase `key`,
   `mods[]`, `comment` and `category` values;
3. keep the four current predicates separate — **do not** join the fields into
   one haystack, which could create matches spanning field boundaries;
4. each query creates the same fresh filtered result array but pushes the
   existing cloned item objects;
5. clear/rebuild preparation when `allKeybinds` changes; optionally release it
   again when search becomes empty.

Required oracle:

- empty search and whitespace-only search;
- key-only, modifier-only, comment-only and category-only matches;
- query matching multiple fields;
- multiple modifiers with match at first/middle/last element;
- missing optional fields;
- unusual/malformed field values: no new eager normalization before a search
  begins;
- Niri enriched reload, Niri legacy fallback, Hyprland config reload;
- compositor switch;
- exact result identity/order/count and row rendering;
- clear search -> exact original `allKeybinds` reference behavior.

### R42.3 — AI model search reruns recommendation ranking even when only query text changes

`AiModelSelector.entries` currently begins every reevaluation with:

```qml
const query = root.filter.trim().toLowerCase()
const recommended = new Set(Ai.recommendedModelIds("auto", 18))
```

The selector's default filter is `recommended`, so typing in the search box
can rerun the full recommendation pipeline even though recommendation inputs
have not changed.

That pipeline itself currently does:

```qml
root.runnableModelList
    .map(id => ({ id, model: root.models[id] }))
    .filter(item => root._profileAllows(item.model, profileId))
    .sort((a, b) =>
        root._profileScore(b.model, profileId)
        - root._profileScore(a.model, profileId))
```

A comparison sort can call `_profileScore()` many times for the same model.
Each score call rebuilds/lowercases `${model.model} ${model.name}` and runs
the same regex/capability/context checks.

Two changes compose without caching dynamic selector rows:

1. in `recommendedModelIds()`, build the allowed candidate array in source
   order and compute each candidate's score exactly once; sort by the stored
   numeric score with the same descending comparator, preserving stable ties;
2. in `AiModelSelector`, derive the resulting 18-id Set in a property whose
   dependencies are the exact recommendation inputs (runnable model list,
   relevant model fields/readiness/policy/credential state), **not**
   `root.filter`; the `entries` query binding then only performs membership
   reads;
3. when a non-recommended catalog filter is active, do not invoke recommendation
   ranking merely to build an unused Set.

Do not cache complete `entries`. `Ai.modelCanRun()`, API-key state and
`AiProviderCatalog.stateFor()` have independent reactive lifetimes and must
continue updating row readiness/status even when search text is unchanged.

Required oracle:

- zero/one/many models;
- runnable and locked models;
- free/private/vision/coding/fast/quality/long-context profiles;
- code-name regex match versus toolCalling capability;
- equal scores: exact original runnable-list tie order;
- string/numeric context-token coercion exactly as today;
- `limit` 0/1/8/18/larger-than-catalog;
- policy changes;
- keyring load/add/remove key;
- provider catalog refresh/status change;
- local model add/remove;
- default model selection and `recommendedModelIds()` callers outside the
  selector;
- repeated search keystrokes with no recommendation input change -> zero new
  recommendation sort;
- exact selector row order/readiness/status and selected model behavior.

### R42.4 — Paths deliberately not promoted

**AI selector full search-entry cache:** model name/id/provider text looks
cacheable, but the same loop also publishes `ready`, `hasKey` and provider
status. A monolithic cached row risks stale authentication/health state. R42.3
moves only ranking work whose dependency boundary is clear.

**FontSelector / WSettingsFontSelector:** both call `Qt.fontFamilies()` and
lowercase family names while typing. Caching looks attractive for large font
sets, but Qt does not expose an obvious font-database change signal here. The
current function call can observe a font installed/removed while the selector
remains alive on the next query reevaluation; a component-lifetime cache could
silently stop doing so. Measure/profile first or add a proven invalidation
source before promotion.

**IconThemeSelector:** its search similarly lowercases theme names, but
`IconThemeService.availableThemes` is already an explicit shared list and
normal theme counts are much smaller than wallpaper/keybind/model catalogs.
Keep this below the promotion line unless profiling shows the settings search
path is material.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without comparable
before/after measurement.

## Research continuation — round 43

Baseline: `dev` at `e44dfec306f0cd4b7257e5560d8caef18e7a9dbc`.

This round moved from interactive list/search work into weather rendering and
geometry preparation. Every promoted finding was re-read by exact current-dev
SHA; default-branch code-search hits that could not be fetched from this SHA
were rejected as evidence.

Current source identities:

- `modules/bar/weather/LiquidOrbitalField.qml`:
  `1883b6877a02f6013fcacc7e30142e5f522b6165`;
- `modules/bar/weather/OrbitalWeather.qml`:
  `1a341d0102095971212f06903365cf572b7bad6b`;
- `modules/bar/weather/AbyssOrbitalWeather.qml`:
  `642f72c2f5156e66debb1917b613cdeed8e75dbd`;
- `modules/dashboard/DashWeather.qml`:
  `243aab28a3d51934980ae90a78da54457dbf8cbf`;
- Waffle `WifiControl.qml`:
  `08b6b7e4af2f08f61940ea443a3a7f527c38ca2b`;
- classic `WifiDialog.qml`:
  `0a1239bf078d52a7a7b3cdc55ddd22c3a217031a`;
- `services/Network.qml`:
  `a20c4c1edf1fbeb2f2a8285518af053bf72a09dc`;
- `services/BluetoothStatus.qml`:
  `43da62258e210755c5a89dfecd36fc2e151ba356`;
- Overlay `Recorder.qml`:
  `0bd8c4314cc72b2ce39cf3d3acc98e7b8dab2b98`;
- Overlay `OverlayContent.qml`:
  `64a277d10a8d89b58ec8d4b040a859d0424db488`;
- Overlay `StyledOverlayWidget.qml`:
  `64a5ef8176811b2c15b542238a3fe0d80b80eb70`;
- shared `CloudflareWarpToggle.qml`:
  `0ec62b42e71e805b3c18f2cbfc9ffb5cd78b0e3c`.

### R43.1 — Canvas liquid orbit repeats node-invariant geometry inside every sample

The normal weather popup prefers the compiled `ShaderEffect`. When that path
is unavailable or still compiling, `LiquidOrbitalField` renders the accepted
continuous liquid sheet through its Canvas fallback.

The Canvas has `sampleCount: 120` and its paint currently invokes
`liquidSample(angle, time)` from four families:

- 120 main contour samples;
- up to 1 active-node glow sample;
- one sample for each painted hour pod, currently up to 8;
- 4 moving streaks × 19 points = 76 samples.

With eight hourly nodes, the maximum visible paint therefore performs:

```text
120 + 1 + 8 + 76 = 205 liquidSample() calls/frame
```

That is a structural source count, not a benchmark.

Each `liquidSample()` then loops every node and calls `nodeGeometry()`.
Today every `nodeGeometry()` repeats:

```qml
const nodeAngle = Number(root.hourAngles[nodeIndex] ?? 0)
const nodeFrame = root.ellipseFrame(nodeAngle)
...
const radius = root.nodeRadius(nodeIndex, time)
```

For eight nodes, the paths above can therefore cause roughly
`205 × 8 = 1640` node-geometry preparations in one fallback paint before
counting the rest of the liquid arithmetic. The node angle, its ellipse frame
and its radius are all constant for a given node during that paint because
width/radii, active index and `time` are sampled once by the paint.

Strict-lossless shape:

1. at the start of `onPaint`, after reading the current `time`, create one
   transient prepared record per current node:
   `{angle, frame: ellipseFrame(angle), radius: nodeRadius(i,time), active}`;
2. let the sample helper consume that prepared array instead of recomputing
   node angle/frame/radius for every sample;
3. keep `ellipseFrame(angle)` for the **sample angle** inside each
   `liquidSample` unchanged because that geometry genuinely varies by sample;
4. reuse the prepared active node radius in the pod pass rather than calling
   `nodeRadius()` a second time;
5. pass the same prepared records to contour, active glow, pod and streak
   sampling;
6. keep all signed-arc, circular-support, smooth-max, drift, gradient and path
   calculations in the existing order.

No QML-visible cache is necessary. Preparation can live entirely inside one
Canvas paint invocation, so width/height/node/active/time invalidation ownership
does not change.

Required oracle:

- 0 through 8 hourly nodes;
- `activeIndex` -1, first, middle, last and out-of-range;
- animation running and frozen `timeSeconds === 0.73`;
- node width/height changes;
- orbit radius and Canvas size changes;
- ordinary hardware path while the shader is compiling;
- ShaderEffect Compiled transition, proving Canvas release/handoff is unchanged;
- Software and Null graphics APIs where Canvas is the permanent renderer;
- exact outer/inner/mid path coordinates for fixed timestamps and geometries;
- glow center/radius, pod centers/radii and every streak point;
- image/raster parity against current fallback for representative frames.

This candidate intentionally claims no saving on the compiled shader path. Its
value is that the CPU fallback is exactly the environment where repeated
JavaScript geometry work is most expensive relative to available rendering
headroom.

### R43.2 — Dashboard orbital hour placement rebuilds the same arc table per hour

The shared `OrbitalWeather` has two placement modes.

Liquid popup mode uses the direct reference geometry:

```qml
return -Math.PI / 2 + shiftedHour * Math.PI / 12
```

The non-liquid Material Dashboard path instead preserves equal **arc-length**
placement around an ellipse. For each hour, `arcAngle()` builds a 72-sample
cumulative length table between that hour's quadrant boundaries:

```text
start angle
 -> 72 ellipse points
 -> cumulative segment lengths
 -> target = total × fraction
 -> linear interpolation inside the matching segment
```

The current `hourAngles` binding calls `orbitAngleForHour()` independently
for every hourly record. During one binding evaluation:

- `orbitRadiusX` and `orbitRadiusY` are the same for every record;
- a quadrant has the same start/end angle for every hour inside it;
- only the target fraction within that quadrant differs.

So multiple hours in one quadrant rebuild an identical 72-sample table.

Strict-lossless direction:

1. in one non-liquid `hourAngles` evaluation, keep a local table keyed by the
   existing quadrant integer;
2. on first use of a quadrant, execute the **same current 72-sample loop** and
   store its cumulative lengths and total;
3. for every hour in that quadrant, compute the same `target = total*fraction`,
   first matching sample, local interpolation and final parametric angle;
4. discard the tables when that binding evaluation returns;
5. leave liquid mode on its current direct formula;
6. keep the existing public/helper `orbitAngleForHour()` behavior available
   for the delegate fallback unless a later patch proves it can be folded
   without changing dependency behavior.

Do not use quarter-ellipse symmetry to synthesize other quadrants. Although an
ideal ellipse is symmetric, the strict target here is to reuse the exact table
that the current arithmetic would have built for that specific start/end range,
not to introduce a numerically different derivation.

Required oracle:

- 0 through 8 hours;
- all hours in one quadrant;
- hours spread across 2/3/4 quadrants;
- exact quadrant-boundary hours;
- malformed/empty labels and minute parsing;
- positive/negative/very small orbit radii under current clamping;
- horizontal/vertical Dashboard resize;
- compact and wide weather cards;
- panel-family Material/Abyss switching;
- exact `hourAngles` values and node x/y positions before/after;
- liquid Weather popup proving its direct placement remains unchanged.

For an eight-hour model, the present non-liquid path can build eight
72-sample tables in one geometry evaluation. The strict projection builds at
most the number of quadrants actually touched, never more than four. This is a
local geometry saving, not a whole-Dashboard or whole-shell percentage claim.

### R43.3 — Paths deliberately not promoted

**Wi-Fi shared sorted projection:** classic `WifiDialog` and Waffle
`WifiControl` currently use the same active-first/strength comparator.
However they belong to different shell-family presentation paths that are not
proven to be simultaneously resident consumers. Moving the sort eagerly into
the resident `Network` singleton could make every network publication pay for
a projection even when no Wi-Fi list is visible. A lazy shared cache would also
need to preserve the current list-mutation/update timing. Do not promote source
duplication as runtime duplication without that lifecycle proof.

**Bluetooth shared sort:** not equivalent even at source level. Waffle sorts
connected -> paired -> name. The classic dialog additionally moves MAC-like
names after meaningful names. A common sorted list would change one surface.

**BluetoothStatus connected-device scan:** the singleton currently does one
`find(connected)` plus one `filter(connected).length`. A one-pass summary is
valid in principle, but Bluetooth device counts are normally small and the
saving is below the promotion threshold without profiling.

**Overlay Recorder disk-free polling:** the Recorder runs `df` every 10 s
while `GlobalStates.overlayOpen`. Owner tracing shows the Recorder delegate
exists only when `Persistent.states.overlay.open` includes `recorder`;
`StyledOverlayWidget` then makes it visible whenever the Overlay is open (or
when pinned). The poll therefore serves a presented free-space label rather
than a hidden retained tab. Slowing it would change freshness semantics.

**Cloudflare WARP central polling:** Round 25 already owns the proven
strict-lossless improvement: remove the unnecessary shell around
`warp-cli status`. A stronger singleton polling owner would need evidence that
multiple WARP toggle implementations are live at the same time and a parity
contract for their slightly different visible/available semantics. Do not
re-promote the same 5 s polling family under a new name.

**YtMusic liked-song membership:** a liked-id Set could remove repeated
`likedSongs.some()` calls, but the service documentation marks YtMusic as a
legacy compatibility backend while LocalMusic is the current user-facing music
route. Keep this below active optimization work unless that route becomes
product-relevant again.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without comparable
before/after measurement.

## Research continuation — round 44

Baseline: `dev` at `e96e30a49f1fdde17a32b43fce955a2a62adb111`.

This round moved into shared animation primitives and the production connected
surface shader feed. A concurrent Utilities UI commit advanced `dev` while the
audit was in progress; the branch, canonical audit and every promoted source
were re-fetched from the new HEAD before this round was written. The relevant
source blobs were unchanged by that concurrent commit.

Current source identities:

- `modules/common/widgets/shapes/ShapeCanvas.qml`:
  `c03d7b2ee1bb94048d43878ba47b4cd0c08a143d`;
- `modules/common/widgets/shapes/shapes/morph.js`:
  `ae149b9dff609286b93a59dc027bec73fcacde20`;
- `modules/common/widgets/shapes/shapes/cubic.js`:
  `1e3b0bdc5edd83447933ed2d47d800721c6d9cc1`;
- `modules/common/widgets/MaterialShape.qml`:
  `225fc41396c0aa0b9260d3bcad96b3cfb652425a`;
- `modules/common/widgets/MaterialCookie.qml`:
  `89e0e348548a1d67418fce606ab143f837191d91`;
- `modules/common/widgets/CookiePlate.qml`:
  `5183b71c47729c559357b1f63f9f2c558417e0b4`;
- `modules/common/perimeter/ConnectedSurfaceIrisField.qml`:
  `8accfa340c430cbb1b794b166527a6305c7fab52`;
- `modules/common/perimeter/ConnectedSurfaceIrisFrame.qml`:
  `e703046f2a527ad30afc1a83ccd71f5e5a78cba7`;
- `modules/common/perimeter/ConnectedSurfaceConnector.qml`:
  `0f755095820759ae741462a041e81f5e437fbfec`;
- `modules/common/widgets/CavaWavyLine.qml`:
  `6b31e221f1121fb3c6164838e4243322de77f189`;
- `modules/common/widgets/CavaSpectrum.qml`:
  `aa320a70be09ff47603d80fc16d290e511724c62`.

### R44.1 — ShapeCanvas materializes an allocation-heavy cubic list on every paint

`ShapeCanvas` is the shared renderer underneath `MaterialShape`,
`MaterialCookie`, `CookiePlate` and many shell/dashboard/sidebar/lock
consumers.

Every paint currently begins with:

```qml
const cubics = root.morph.asCubics(root.progress)
```

`Morph.asCubics(progress)` constructs each interpolated segment as:

```js
new Cubic.Cubic(
    Array.from({ length: 8 }).map((_, it) =>
        Utils.interpolate(a.points[it], b.points[it], progress)))
```

For M matched cubic segments, one paint therefore structurally creates:

- one returned `ret` array;
- M `Array.from({length:8})` temporary arrays;
- M mapped eight-number arrays;
- M interpolated `Cubic` objects;
- one additional eight-number array plus one additional `Cubic` for the final
  closure segment.

The last object is not redundant semantics. `asCubics()` deliberately
replaces the final segment's endpoint with the **first interpolated anchor** so
the closed path has no sub-pixel seam.

The library already contains `Morph.forEachCubic(progress, mutableCubic,...)`,
which proves mutable interpolation is supported, but using it directly is not
strict-lossless because it does not perform that final-anchor repair.

Strict-lossless direction:

1. retain one `MutableCubic` with an eight-number backing array per
   `ShapeCanvas`;
2. add/derive a closed streaming iterator over `morphMatch`;
3. interpolate the first segment into the mutable cubic and capture its
   `anchor0X/anchor0Y`;
4. stream every non-final segment directly to the Canvas with the exact current
   control/end coordinates;
5. for the final segment only, keep its interpolated anchor0/control0/control1
   but overwrite the endpoint with the captured first anchor before issuing
   `bezierCurveTo`;
6. allocate no returned cubic list during paint.

Do not rebuild or alter `morphMatch`; the expensive polygon feature matching
already belongs to the shape-change boundary rather than each paint.

This applies beyond geometry-progress animation. `ShapeCanvas` also calls
`requestPaint()` from `onColorChanged`, `onStrokeColorChanged` and
`onStrokeWidthChanged`. A Material shape whose geometry has already settled
can therefore still recreate the complete cubic list on every color-animation
frame even though `progress` is unchanged.

Required oracle:

- start shape === end shape;
- unlike start/end shapes with different original polygon complexity;
- progress 0, intermediate values, 1 and easing overshoot outside the nominal
  0..1 range;
- rapid shape changes before the previous morph settles;
- reduced-motion duration 0;
- color-only animation while progress is stable;
- stroke-only changes;
- normalized `MaterialShape`;
- non-normalized aspect-aware `CookiePlate` with `fitToCanvas: true`;
- width/height changes during morph;
- exact cubic control points and segment order;
- exact final endpoint == first interpolated anchor;
- raster parity around the closing seam at fractional sizes/scales.

The claim is allocation/local CPU reduction only. No whole-shell percentage is
inferred from the broad consumer count.

### R44.2 — Visible and shadow iRiS fields independently prepare identical shape uniforms

`ConnectedSurfaceIrisFrame` owns two instances of the same production field:

```text
shadowMaskField: ConnectedSurfaceIrisField
visible field:   ConnectedSurfaceIrisField
```

The shadow field explicitly uses:

```qml
shapes: field.shapes
smoothing: root.fuse
```

and the visible field also uses `smoothing: root.fuse`. Therefore their
shape-derived shader data are identical for every frame.

Inside each `ConnectedSurfaceIrisField`, one shapes/smoothing update
independently derives:

- `shape0..shape19`: 20 `vector4d` values;
- `radiiA..E`: 5 vectors, backed by 20 `blockValue()` reads;
- `fuseA..E`: 5 vectors, backed by another 20 reads;
- `joinA..E` + `alsoA..E`: 10 vectors, backed by 40 `joinValue()` calls;
- one id -> index object for join resolution.

That is 40 shape-derived vectors per field, plus the repeated object/list/index
work. The production frame computes the same logical packet twice before the
two ShaderEffects consume it.

Strict-lossless direction:

1. define one prepared packet from exactly `(shapes, smoothing)`;
2. preserve the current capacity of 20 and zero-fill missing slots;
3. build the id map with the same loop/order so duplicate ids retain the same
   current last-write result;
4. preserve `Number(value ?? fallback)` coercion and current missing-shape
   behavior;
5. preserve join normalization exactly:
   scalar -> one-element list, array -> itself, missing -> empty;
6. materialize the same 20 shape, 5 radius, 5 fuse and 10 join vectors once;
7. expose that packet from the visible field/frame owner and bind the
   shadow-mask field to it;
8. leave viewport, screen size, tint, rim and edge uniforms field-local because
   they differ between the visible and shadow passes.

A standalone `ConnectedSurfaceIrisField` can retain self-preparation when no
external packet is supplied; sharing is only an optimization for owners that
already have identical shape/smoothing inputs.

Required oracle:

- zero through capacity-20 shapes;
- production five-shape owner/frame/popup arrangement;
- dormant zero-size tangent owner records;
- one and both tangent joins;
- duplicate ids;
- missing ids and missing join targets;
- joins supplied as scalar and array;
- explicit/missing radius and fuse;
- smoothing changes;
- popup move/resize/reveal animation;
- output resize/fractional scale;
- shadow disabled/enabled transitions;
- exact every named ShaderEffect shape/radius/fuse/join uniform before/after;
- visible plate and shadow-mask raster parity.

This is deliberately separate from Round 2.2. That older candidate targets
removing a shadow capture/pass. R44.2 changes no GPU pass, QSB, blur or capture;
it removes duplicated **CPU-side preparation** for the two passes that remain.

### R44.3 — Paths deliberately not promoted

**ConnectedSurfaceConnector:** the Canvas draws one small two-shoulder Bézier
path when extent/edge/color/stroke inputs change. There is no per-frame
intermediate array or deep geometry loop. Its source duplication cost is below
the promotion threshold compared with the iRiS field preparation above.

**Material shape construction:** `material-shapes.js` already memoizes every
named polygon through `getCircle()/getSquare()/...`. Do not propose rebuilding
that cache; the active allocation is in per-paint interpolation, not named
shape construction.

**CavaWavyLine:** smoothing is already a rolling-window pass and explicitly
avoids an N-element smoothed-array allocation per CAVA frame. No new candidate
was found beyond that existing optimization.

**CavaSpectrum:** the renderer already reuses scratch arrays for selected,
smoothed, primary, secondary and baseline data. Its per-paint gradient still
builds color stops, but caching Canvas gradient/color state has a larger
context/geometry/theme invalidation surface than the local saving justifies
without profiling.

**iRiS shadow-pass removal:** already owned by Round 2.2. Do not count the
shared-uniform packet as GPU-pass reduction or re-promote the older shadow
candidate.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without comparable
before/after measurement.

## Research continuation — round 45

Baseline: `dev` at `3881227eb8a626d470d05db1d68cdb2be04dab2b`.

This round moved away from render primitives into Settings search publication
boundaries. The audit first found repeated dynamic-entry normalization, but
duplicate checking showed that work is already canonical candidate #43, with
discarded pre-limit highlight construction already candidate #44. Those were
therefore not re-promoted.

Current source identities:

- `modules/settings/SettingsPageRegistry.qml`:
  `3ff65883143160c60a740efae802b4a5d6f27ed0`;
- `modules/settings/SettingsPageRegistryData.qml`:
  `3746cb7184edd6747634ec43255c30b9cfbe4e28`;
- `modules/common/widgets/SettingsSearchRegistry.qml`:
  `836c9c061039bae7508aa6b44973722409ddf1dd`;
- `modules/settings/SettingsOverlay.qml`:
  `dcc55af98cfbf0c628f8ab37edd474a4085d80f7`;
- `modules/settings/SettingsFocus.qml`:
  `3bad6c434fb735ba90d46bca5c676c5a23dcff45`;
- standalone `settings.qml`:
  `d490bc816cf5c12a9c1e057e04667092fec9a85e`;
- `modules/overview/OverviewWidget.qml`:
  `09c67be3c1d7d88a5964b66ac1633d1e53a49509`;
- `modules/common/widgets/GroupButton.qml`:
  `0dfd4cd803053029222bc566aff0d0dec37b21a0`;
- Waffle `WMenu.qml`:
  `b2a5840e2f2a6b0e4bae1fbfd708955140dc337f`.

### R45.1 — The static Settings index is cached raw but rerouted and renormalized per query

`SettingsPageRegistryData.searchIndex()` already owns one useful cache. It
materializes the large translation-aware static index once and invalidates that
raw cache on:

```qml
Translation.onLanguageCodeChanged
Translation.onTranslationsChanged
```

The public wrapper still does work every time it is called:

```qml
return SettingsPageRegistryData.searchIndex()
    .filter(entry => !root.isHiddenLegacyIndex(entry.pageIndex))
    .map(entry => {
        const route = FamilyPolicy.settingsRoute(
            Config.options?.panelFamily,
            entry.pageIndex,
            entry.section)
        if (route.pageIndex !== entry.pageIndex)
            return Object.assign({}, entry, route, { pageName: "Abyss" })
        if (root.abyssFamily && entry.pageIndex === root.barPageIndex)
            return Object.assign({}, entry, { pageName: "Abyss" })
        return entry
    })
```

All three current static-search consumers call this from their query rebuild:

- standalone `settings.qml`;
- `SettingsOverlay.qml`;
- `SettingsFocus.qml`.

The standalone and Overlay search loops then recreate the same normalized
metadata for each routed static entry on every query edit:

```qml
label.toLowerCase()
description.toLowerCase()
pageName.toLowerCase()
section.toLowerCase()
keywords.join(" ").toLowerCase()
```

`SettingsFocus` also consumes the same routed static snapshot and performs
its own matching policy. The search policies should remain consumer-owned; the
shared opportunity is only the immutable family/translation preparation below
them.

Strict-lossless direction:

1. retain `SettingsPageRegistryData.searchIndex()` as the raw,
   translation-owned source;
2. in `SettingsPageRegistry`, prepare one private routed snapshot for the
   current `Config.options.panelFamily`;
3. execute the current hidden-legacy filter and
   `FamilyPolicy.settingsRoute()` loop exactly once for that epoch;
4. retain the exact raw/public fields that callers currently receive;
5. add private normalized fields for label, description, page name, section and
   joined keywords to each prepared record (or to an aligned private metadata
   array);
6. invalidate/rebuild on every raw translation-index revision and every panel
   family transition;
7. let each Settings surface keep its existing applicability/allowed filtering,
   query-term matching, score bonuses, dynamic-result merge, deduplication and
   top-50 policy.

Do not cache final query results. Query text is intentionally immediate and
different Settings surfaces apply different allowed/page filters.

The prepared snapshot must preserve current route semantics exactly. In
particular:

- legacy hidden indexes stay absent;
- Abyss family routing may redirect page/section and clone that routed record;
- the active Abyss Bar slot presents `pageName: "Abyss"`;
- ii/Waffle/Abyss transitions must immediately expose the new route set;
- consumer-side `isPageApplicable()` remains authoritative rather than being
  silently moved into the shared snapshot.

Required oracle:

- empty query (no search work/result behavior change);
- one and multiple terms;
- label/description/page/section/keyword-only matches;
- upper/lower/mixed case;
- prefix and mid-string label matches;
- ii -> Waffle -> Abyss -> ii without restarting Settings;
- redirected Abyss entries and Bar page-name substitution;
- legacy hidden page indexes;
- translation revision while Settings remains alive;
- standalone Settings, SettingsOverlay and SettingsFocus;
- exact raw result fields and object-visible values;
- exact scores, tie ordering, dynamic/static merge order, dedup result and final
  top-50 set.

This composes with, but does not duplicate, older candidates:

- #43 prepares normalized fields for **dynamic registered controls**;
- #44 moves dynamic result highlighting after the top-50 selection;
- R45.1 prepares the **static family-routed registry snapshot** before any query
  exists.

If implementation also notices that static result highlighting is generated
before the final merged top-50 cutoff in standalone/Overlay search, fold that
work into the same proof envelope as #44 rather than assigning another
promotion number.

### R45.2 — Paths deliberately not promoted

**SettingsSearchRegistry dynamic normalization:** rediscovered during this
round, but it is exactly canonical candidate #43 / Round 21.2. No new number.

**Settings dynamic pre-limit highlighting:** likewise already owned by candidate
#44 / Round 21.3. The static half can be covered as an implementation extension,
not counted as an independent optimization.

**OverviewWidget monitor scans:** every visible Overview window does a
`HyprlandData.monitors.find()` for its window monitor and another identical
lookup for the Overview's widget monitor. A per-owner monitor-id map could make
those O(1), but monitor counts are normally tiny and the whole path is scoped
to an open Hyprland Overview. Keep below promotion threshold without profiling.
The larger toplevel model projection is also presentation-specific and should
not be rewritten from source inspection alone.

**GroupButton parent scans:** each grouped button computes its visible index and
visible-child count by walking `parent.children`. This is structurally
quadratic across a group after visibility changes, but normal button groups are
small and the scans do not run on every width/color animation frame. A shared
group summary would add ownership complexity for little proven value.

**Waffle WMenu implicit-width scan:** the menu uses `Array.from(count)` plus a
max-width reduction over instantiated items. It is bounded by menu population
and tied to child implicit-size changes; no evidence shows this as a material
hot path.

**AutomationConfig search hits:** repository code search still returns an
`AutomationConfig.qml` path, but fetching that file and the guessed Automation
services from this exact `dev` SHA returns 404. Search-index hits that cannot be
reproduced from current `dev` are not optimization evidence.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without comparable
before/after measurement.

## Research continuation — round 46

Baseline: `dev` at `587778963ea08215dc374c2f9f28c1d3bc14ec57`.

This round moved from Settings search into process-heavy desktop-widget
auto-placement. The strongest source-proven work is complementary: reduce the
cost of each image-analysis invocation, then stop Waffle from launching that
invocation for unrelated desktop-widget record writes.

Current source identities:

- `scripts/images/least_busy_region.py`:
  `d93dd6c596370c2dbcc22d5e21e52497c535a906`;
- `scripts/images/least-busy-region-venv.sh`:
  `48a956bb8e52c2eddf8a363895b7c10456a02b23`;
- `modules/waffle/background/WaffleBackgroundClock.qml`:
  `9ae299d5e17249c3b177ffa5e3d76eba1dd5d156`;
- `modules/waffle/background/WaffleBackground.qml`:
  `6e9bcbdf8daef77c9f8169ed998c44bc72b94fa6`;
- `modules/background/widgets/AbstractBackgroundWidget.qml`:
  `16603c04327503fad558fb6886e61a7738295b73`;
- `services/DesktopWidgetLayout.qml`:
  `a2e472cb702fdeb69fcdb758f4aa63ebdce1bf22`;
- `killDialog.qml`:
  `1df0740c6d540d66f89728aedfd1f3711d794e87`;
- `modules/lock/LockMediaWidget.qml`:
  `9e5d2434d656457568eac7578973061385ecc4f6`;
- horizontal `modules/bar/Media.qml`:
  `7286bbfaa8bac3b29ee7e818cd937d60405556e8`;
- vertical `modules/verticalBar/VerticalMedia.qml`:
  `f95416165769171cf98031cb115cbfd7dc59cf0e`.

### R46.1 — least_busy_region decodes and resizes the same grayscale wallpaper twice

The auto-placement helper is shared by the generic desktop-widget framework and
the Waffle background clock through `least-busy-region-venv.sh`.

In ordinary least/busiest mode the current process does:

1. `find_least_busy_region()`:
   - `cv2.imread(..., IMREAD_GRAYSCALE)`;
   - scale with `INTER_LANCZOS4`;
   - center-crop to screen size;
   - build integral + squared-integral images;
   - scan candidate regions;
2. `get_dominant_color()`:
   - independently decode color pixels and scale/crop them;
3. `get_region_brightness()`:
   - **decode grayscale again**;
   - **repeat the same scale/crop**;
   - slice the already-selected region and run `np.mean/std`.

Largest-region mode has the same repeated grayscale path after its search.

The strict opportunity does not require changing any math in the region search
or dominant-color clustering:

1. factor the existing grayscale decode + exact resize/crop arithmetic into a
   helper that returns the processed grayscale array;
2. let normal/largest search consume that array rather than reloading internally
   (or return the processed array alongside the current search result through a
   private helper);
3. after the final region is known, apply the current brightness clamp/slice and
   exact `np.mean(region)` / `np.std(region)` to that same array;
4. retain the independent color `cv2.imread()` used by
   `get_dominant_color()`;
5. keep public helper compatibility if any direct callers/tests depend on the
   existing signatures.

Do **not** optimize by reading color once and converting it to grayscale.
`cv2.imread(path, IMREAD_GRAYSCALE)` is the current pixel source and codec
conversion; deriving grayscale from the color decode can introduce pixel-level
differences.

Likewise keep `--color-only` unchanged in the first patch. That mode performs
one color read and one grayscale read for two genuinely different
representations; it has no duplicate grayscale search image to reuse.

Required oracle:

- PNG/JPEG/WebP wallpapers with different aspect ratios;
- exact-size image (no resize);
- fill and fit screen modes;
- screen crop in horizontal and vertical directions;
- least-busy and `--busiest`;
- largest-region mode;
- region clamped by horizontal/vertical padding;
- requested region larger than feasible space;
- 1×1/small edge cases;
- exact selected coordinates/size/variance;
- exact brightness and brightness_std JSON values after current rounding;
- exact dominant color;
- missing/unreadable file behavior;
- visual-output mode remains independent unless separately optimized.

The normal strict-parity fixture should keep the source wallpaper immutable for
one invocation. Current code can theoretically observe two different file
versions because it reads grayscale twice; that incidental mid-process
replacement race is not a useful product contract and should not be silently
used as an optimization oracle without a dedicated requirement.

This candidate removes one full grayscale decode and one potentially
screen-sized Lanczos resize/crop per normal/largest invocation. It does not
claim reduced subprocess count; R46.2 addresses avoidable invocations.

### R46.2 — every desktop-widget records write can launch one Waffle image-analysis process per output

A Waffle background owns one `WaffleBackgroundClock` for every screen.

The clock reads these per-output values from `DesktopWidgetLayout`:

```text
enable
placementStrategy
x
y
```

It already owns exact change handlers:

```qml
onPlacementStrategyChanged: {
    syncFreePositionFromConfig()
    refreshPlacementIfNeeded()
}
onClockEnabledChanged: {
    syncFreePositionFromConfig()
    refreshPlacementIfNeeded()
}
onWallpaperPathChanged: refreshPlacementIfNeeded()
onWidthChanged: refreshPlacementIfNeeded()
onHeightChanged: refreshPlacementIfNeeded()
```

Free-mode `x/y` are consumed by `syncFreePositionFromConfig()`.

Nevertheless every global desktop-widget record replacement also does:

```qml
Connections {
    target: DesktopWidgetLayout
    function onRecordsChanged(): void {
        root.syncFreePositionFromConfig()
        root.refreshPlacementIfNeeded()
    }
}
```

When this clock is in `leastBusy` or `mostBusy`, the second call starts
`least-busy-region-venv.sh`, which activates Python/OpenCV and scans the
wallpaper. The subprocess command itself contains no DesktopWidgetLayout record
payload. Its effective inputs are:

- scaled screen width/height;
- current clock content width/height;
- screen-derived paddings;
- wallpaper path;
- least versus busiest strategy.

Therefore an edit to a weather widget, another background widget, or another
output can make **every** auto-placed Waffle clock rerun the same image analysis
even though none of those command inputs changed.

Strict-lossless ownership can be narrower:

1. retain `onRecordsChanged` only for
   `syncFreePositionFromConfig()`, because free x/y may change without a
   dedicated scalar signal;
2. remove its unconditional direct `refreshPlacementIfNeeded()`;
3. continue relying on `onClockEnabledChanged` and
   `onPlacementStrategyChanged` for the two record fields that can change
   whether/which auto-placement analysis is needed;
4. retain wallpaper, width and height handlers exactly;
5. retain the Config-ready initial refresh;
6. do not add a debounce or slower timer.

The key proof is QML notification ordering. A record replacement that changes
`enable` or `placementStrategy` must still reevaluate the derived property
and fire its change handler even though the broad `recordsChanged` callback no
longer forces the process directly.

Required oracle:

- one and multiple screens;
- Waffle family active and retained/inactive family lifecycle;
- unrelated widget record update on same output -> zero Waffle clock analysis;
- unrelated widget record update on another output -> zero analysis on all
  unaffected clocks;
- free-mode x/y write -> exact immediate position sync, no analysis;
- auto-mode stored x/y-only write -> no analysis and no visual change;
- enable false -> true and true -> false;
- free -> leastBusy -> mostBusy -> free;
- simultaneous enable + strategy record update;
- wallpaper path change;
- clock style/time/date/scale changes that alter width/height;
- screen resize/hotplug;
- lock force-center enter/exit;
- exact final targetX/targetY/dominantColor and process-launch count.

This composes directly with R46.1: R46.2 reduces the number of expensive
invocations, while R46.1 removes duplicate grayscale work inside every
invocation that remains.

### R46.3 — Paths deliberately not promoted

**DesktopWidgetLayout output-record index:** rediscovered while tracing Waffle
records, but it is already canonical candidate R31.2. No new promotion.

**Generic AbstractBackgroundWidget request serialization:** its auto-placement
path also toggles `leastBusyRegionProc.running` false/true, while its color-only
path has explicit serialization and stale-result rejection. Extending that
policy to auto-placement may improve correctness/process churn, but it can
change transient result ordering. Keep it outside strict-lossless promotion
until an oracle defines whether intermediate stale placement updates are
observable contract or a bug.

**Waffle request-key memoization:** caching completed image-analysis results by
command arguments could avoid repeated width combinations, but a pathname does
not prove the wallpaper file bytes are unchanged. Do not introduce a persistent
result cache without a file-revision identity.

**killDialog conflict probing:** the standalone dialog owns two one-shot
`pidof` processes (kded6 and notification-daemon group). Batching two startup
probes would save at most one short child process and is below the promotion
threshold.

**Bar/Vertical/Lock media position timers:** these belong to the broader MPRIS
position-refresh ownership question already represented by candidate #58.
Do not assign a second candidate from another visible consumer until signal
timing/freshness measurement defines the shared ticker contract.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without comparable
before/after measurement.

## Research continuation — round 47

Baseline: `dev` at `f843d78e46eec124896c7552edfc0da938499e09`.

This round continued the image-analysis audit one level deeper, then moved to a
separate interactive Settings path. The Python candidate changes neither search
algorithm nor image pixels; it removes avoidable Python control flow around the
existing integral-image math. The theme candidate moves immutable baseline
parsing to the session boundary already present in the editor.

Current source identities:

- `scripts/images/least_busy_region.py`:
  `d93dd6c596370c2dbcc22d5e21e52497c535a906`;
- `modules/settings/CustomThemeEditor.qml`:
  `958aab18b34578b4d80b0dad86288db3c5f11578`;
- `modules/abyss/AbyssSurfaceController.qml`:
  `1fbbe81d2c9f62827c2e6835600caec01e24227f`;
- `services/Notepad.qml`:
  `6f17567be8417cef499086138db5884336e2eb3f`;
- `modules/waffle/background/WaffleBackground.qml`:
  `6e9bcbdf8daef77c9f8169ed998c44bc72b94fa6`.

### R47.1 — region sums discard OpenCV's free zero border and rebuild it with Python branches

Both `find_least_busy_region()` and `find_largest_region()` currently build
their integral images as:

```python
integral = cv2.integral(arr, sdepth=cv2.CV_64F)[1:,1:]
integral_sq = cv2.integral(arr**2, sdepth=cv2.CV_64F)[1:,1:]
```

OpenCV originally returns the conventional one-pixel zero border. The slices
discard that logical border, although the NumPy views still keep the full base
arrays alive.

The code then compensates for the missing border with a helper:

```python
def region_sum(ii, x1, y1, x2, y2):
    total = ii[y2, x2]
    if x1 > 0:
        total -= ii[y2, x1-1]
    if y1 > 0:
        total -= ii[y1-1, x2]
    if x1 > 0 and y1 > 0:
        total += ii[y1-1, x1-1]
    return total
```

Each candidate window calls it twice: once for the ordinary integral and once
for the squared integral.

The full padded integral already encodes those boundary cases as literal zeros.
For the same inclusive source rectangle `[x1..x2] × [y1..y2]`, the exact
corresponding operands are:

```text
current trimmed[y2, x2]       == full[y2+1, x2+1]
current trimmed[y2, x1-1]     == full[y2+1, x1]
current trimmed[y1-1, x2]     == full[y1,   x2+1]
current trimmed[y1-1, x1-1]   == full[y1,   x1]
```

Therefore the branch-free strict replacement can execute in the **same numeric
operation order** as today:

```python
total  = ii[y2 + 1, x2 + 1]
total -= ii[y2 + 1, x1]
total -= ii[y1,     x2 + 1]
total += ii[y1,     x1]
```

When `x1 == 0` or `y1 == 0`, the relevant padded value is exactly zero, so
the result is the same without a branch.

Strict-lossless direction:

1. retain the full result of both existing `cv2.integral(..., CV_64F)` calls;
2. use one small branch-free padded-integral helper or inline the four accesses;
3. keep the four arithmetic operations in the current
   initial/subtract-x/subtract-y/add-corner order;
4. keep candidate x/y ranges and current out-of-bounds guard unchanged;
5. keep the row-major loops and `<` / `>` min/max comparisons unchanged so
   equal-variance ties still choose the same first encountered candidate;
6. in `find_largest_region()`, compute `area = region_w * region_h` once per
   binary-search size, before the x/y loops, rather than once per candidate.

Required oracle:

- direct current-vs-proposed rectangle sums over random grayscale arrays for
  every valid rectangle, including x1/y1 zero;
- exact squared sums;
- exact variance bit/value parity for scanned candidates;
- default stride and stride 1/2/large;
- horizontal/vertical padding zero and nonzero;
- tiny images after padding reduction;
- requested region size clamping;
- least-busy and busiest ties;
- largest-region threshold just below/equal/above a candidate variance;
- exact binary-search decisions and final center/size/variance;
- the R46 grayscale-reuse oracle, proving both candidates compose.

This is not a vectorization proposal. Vectorizing whole rows/grids could change
temporary-memory footprint and floating operation behavior. R47.1 keeps the
same Python scan and comparison order while removing only avoidable helper
branches/calls.

### R47.2 — quick theme sliders reparse a frozen baseline up to every 50 ms

`CustomThemeEditor` already defines a useful semantic boundary:

```qml
function captureOriginalColors() {
    if (!originalColors) {
        originalColors =
            JSON.parse(JSON.stringify(
                Config.options?.appearance?.customTheme ?? {}))
    }
}
```

The three quick-adjustment sliders call this and restart a 50 ms debounce.
Therefore one drag session intentionally applies every slider position relative
to the **same frozen original theme**, not relative to the output of the previous
tick.

However `applyQuickAdjustments()` repeats invariant work every debounce:

```qml
const colorKeys = Object.keys(originalColors)
for (const key of colorKeys) {
    if (!key.startsWith("m3"))
        continue
    const original = originalColors[key]
    if (typeof original !== "string" || !original.startsWith("#"))
        continue
    let c = Qt.color(original)
    ...
    let newColor = Qt.hsla(newHue, newSat, newLight, c.a)
}
```

For the lifetime of that baseline:

- key enumeration/order is unchanged;
- m3 eligibility is unchanged;
- original strings are unchanged;
- each `Qt.color(original)` result and its HSL/alpha values are unchanged.

Strict-lossless direction:

1. when `originalColors` is first captured, enumerate
   `Object.keys(originalColors)` once;
2. apply the exact current `m3`, type and leading-`#` predicates in that same
   order;
3. call `Qt.color(original)` once for each accepted row;
4. store private ordered metadata
   `{ key, h: c.hslHue, s: c.hslSaturation, l: c.hslLightness, a: c.a }`;
5. on every debounce tick, iterate only that prepared array, preserving current
   saturation/lightness clamps, temperature target/shift, hue wrapping and
   `Qt.hsla(...).toString()`;
6. clear the prepared metadata whenever the code sets `originalColors = null`
   today, so preset/import boundaries still capture a fresh baseline.

Do not automatically refresh the prepared baseline merely because some other
theme property changes while `originalColors` is non-null. Current behavior is
explicitly baseline-relative and would overwrite such an intervening edit on
the next slider tick from the old snapshot. The optimization must preserve that
behavior rather than silently improve it.

Required oracle:

- all three sliders independently and simultaneously;
- 50 ms coalescing under rapid pointer movement;
- saturation 0/100/200;
- brightness -50/0/+50;
- temperature -50/0/+50;
- hue values around wrap boundaries 0 and 1;
- alpha-bearing colors;
- black/white/gray achromatic colors;
- malformed/edge `#...` strings accepted by the current predicate;
- non-m3 and non-string keys remain excluded;
- exact update-key insertion order and resulting strings;
- preset load and import reset baseline/sliders;
- intervening manual color edit while a baseline exists retains current frozen
  baseline semantics;
- exact `Config.setNestedValues()` payload and `applyToShell()` cadence.

The optimization deliberately leaves the potentially larger cost of applying
the theme to the shell on every debounce unchanged. Reducing that cadence would
change interactive presentation semantics and requires separate UX/latency
authority.

### R47.3 — Paths deliberately not promoted

**OpenCV `integral2`:** it may be possible to replace the separate
`cv2.integral(arr)` and `cv2.integral(arr**2)` construction with a single
OpenCV squared-integral call, also avoiding the full `arr**2` temporary.
However this changes the OpenCV execution path and possibly numeric
accumulation details. Promote only after an exact randomized sum/variance oracle
proves equality for the supported image-size range.

**Whole-grid NumPy vectorization:** potentially much faster than Python nested
loops, but it introduces large temporary arrays and may change floating
evaluation/tie details. It is not a strict-lossless source-only candidate yet.

**Notepad copy-on-write:** text edits copy the tabs array and one changed tab
object, but the service already coalesces persistence while a FileView write is
in flight: later edits set `_saveQueued` before serialization. Avoiding the
small array/object publication would require a different QML reactivity model
and is below the promotion threshold without profiling.

**AbyssSurfaceController unified participant snapshot:** placement requests,
vacancy roles, geometry and input bounds are currently separate derived
properties. A single combined snapshot would share `Object.keys(participants)`
work but would also make every participant field invalidate every downstream
consumer, broadening the reactive graph and potentially increasing work.
Do not trade narrow dependency ownership for fewer source loops without runtime
measurement.

**Waffle Background Niri occupancy:** rediscovered while checking resident
background work, but the per-output active-workspace/window derivation is
already owned by R22.3. No new promotion.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without comparable
before/after measurement.

## Research continuation — round 48

Baseline: `dev` at `7a31777674ae8e1ccb69824f988e720118ad038a`.

This round moved away from the Round 47 image-analysis/theme-baseline work and
audited two different fan-out boundaries: Settings-triggered external theming
and raw DateTime clock propagation into date-only consumers. A concurrent
Abyss/audio/Obsidian/weather commit advanced `dev` while the round was being
prepared; the write was aborted, the branch was re-read, and every promoted
source blob was verified unchanged before this round was written.

Current source identities:

- `modules/settings/AdvancedConfig.qml`:
  `baf79c0311a105c3cbf871628f9a4dec4d0e64f4`;
- Waffle `modules/waffle/settings/pages/WThemesPage.qml`:
  `b4c1f8e1282ab97ea4fdf1bf032b88294a157772`;
- `scripts/colors/apply-targets.sh`:
  `8196c1d71db336ad473a7b6491f2e852750c4d03`;
- `scripts/colors/modules/90-cava.sh`:
  `e2cd64b5fde250057e8a50c852bfb0ec2824f932`;
- `scripts/colors/switchwall.sh`:
  `31daa6590491bf39a096f8d1a83edcad0492f9aa`;
- `services/CavaTheme.qml`:
  `b60aaaef87c070e9940934ec4f76aeeba2c79edf`;
- `services/DateTime.qml`:
  `6e99a0a319dbbd84635492c0ca6fcd617c2f175c`;
- `modules/verticalBar/VerticalDateWidget.qml`:
  `c72b372c3eee330e4d1dd51cba178b1ad3a2fe7a`;
- `modules/common/widgets/WeekRow.qml`:
  `e95df323efdbf6fbcc5f3e6e855e1450fa869507`;
- `modules/bar/ClockCalendarContent.qml`:
  `9d56664adc9acb307acb0a2a38f77b9c0ff62491`;
- `modules/controlPanel/DateTimeHeader.qml`:
  `efed96608a8bcc23049268426d32fb4dc4246b8f`;
- date-indicator `BubbleDate.qml`:
  `ba7ae9da666319f8aebd0aec38773695ddb3ce03`;
- date-indicator `RectangleDate.qml`:
  `0dba4da79e1c289486dd547f7796ac0e5718b083`;
- date-indicator `RotatingDate.qml`:
  `c787ccfd8a658210b2806126a20c3c11040f5d25`;
- Material `modules/lock/LockSurface.qml`:
  `ceb678a43c171de48fdceee407e0a615b1ec4591`;
- Waffle `WaffleLockSurface.qml`:
  `9cc7e75e21650c26572a17f61140b7d56fd9a734`;
- Waffle `WaffleLockSurfaceSafe.qml`:
  `86d038cdb3503b0aaae1d3c78b6fdb580263235b`;
- Sidebar `GlanceHeader.qml`:
  `01b3bb7a62335d2d492b1e21bbf5484de1a5d656`;
- Waffle `WidgetsContent.qml`:
  `7919f08b523479a5348660f0b95993d0b0b57544`;
- `AnimeScheduleView.qml`:
  `4023dc68759dd68d245cced7b01ef1d4a33400b1`.

### R48.1 — Cava-specific Settings changes currently regenerate the entire wallpaper theme

Both Material/ii Advanced Settings and Waffle Themes Settings use the same
pattern:

```qml
function setCavaValue(path, value, regenerateStandalone) {
    Config.setNestedValue(path, value)
    if (regenerateStandalone)
        cavaConfigDebounce.restart()
}
...
Timer {
    interval: 500
    onTriggered: Quickshell.execDetached([
        Directories.wallpaperSwitchScriptPath, "--noswitch"])
}
```

The affected values include:

- `appearance.cava.colorSource`;
- `gradientCount`;
- `sensitivity`;
- `bars`;
- `framerate`;
- `stereo`;
- reset-to-defaults for the same group.

`waveOpacity` is already correctly marked as runtime-only and does not request
standalone regeneration.

Repository-wide source search shows the color pipeline's only reader of
`appearance.cava.*` is `scripts/colors/modules/90-cava.sh`. That module:

1. reads Cava-specific configuration;
2. if `appearance.wallpaperTheming.enableCava=true`, generates/replaces the
   managed Cava block using existing generated palette/cover artifacts;
3. otherwise strips the managed block.

The repo already owns the exact narrow orchestrator:

```bash
scripts/colors/apply-targets.sh cava
```

which resolves the target manifest and executes only `90-cava.sh`.

By contrast, `switchwall.sh --noswitch` re-enters wallpaper color generation
from the current wallpaper. The resulting palette publication is watched by
the shell's external-theme owner, so a Cava-only setting edit can wake work for
targets whose inputs did not change.

Strict-lossless direction:

1. keep each Settings surface's existing 500 ms debounce;
2. keep Config writes immediate;
3. when a Cava setting requires external Cava regeneration and the generated
   palette prerequisites already exist, execute only the Cava target;
4. the external-Cava enable toggle must also execute that target in **both**
   directions:
   - enable -> add/update managed block;
   - disable -> strip the existing managed block;
5. if the required generated palette artifact is missing/unusable, fall back to
   the current full regeneration path so first-run/recovery behavior does not
   regress;
6. keep `CavaTheme` runtime palette/reactivity independent: internal shell
   visualizers continue to react directly to Config regardless of whether the
   external Cava target is enabled.

Do not simply skip all work when `enableCava=false`: the transition from true
to false has a required filesystem side effect. The optimization is **target
narrowing**, not “never run while disabled”.

Required oracle:

- external Cava initially disabled with no managed block;
- disabled with stale managed/legacy managed block;
- false -> true -> false;
- theme/vibrant/cover color source;
- gradient count 1..8;
- sensitivity/bars/framerate/stereo changes;
- reset defaults;
- repeated slider/spin changes inside 500 ms -> one target apply;
- generated palette present;
- generated palette missing/corrupt -> full-regeneration fallback;
- cover-art path present/missing;
- Cava binary present/missing;
- exact final `~/.config/cava/config` bytes;
- exact internal `CavaTheme.visualizerColors` behavior;
- prove unrelated GTK/editor/browser/terminal target scripts do not run on the
  narrow steady-state path.

This candidate removes both palette-generation work and unrelated target
fan-out, not merely one Bash process.

### R48.2 — raw shared clock identity leaks 1 Hz invalidation into date-only surfaces

`DateTime.clock` intentionally selects second precision when either:

```qml
Config.options.time.secondPrecision
|| GlobalStates.screenLocked
```

That is correct for clocks/second hands. The issue is that many unrelated
bindings consume the same raw `clock.date` object while using only day fields.

Current examples include:

- Vertical Bar day/month labels;
- Control Panel weekday/full-date labels;
- Material/Waffle lock-screen date labels, including multiple lock layouts;
- Cookie/Bubble/Rectangle/Rotating desktop-clock date labels;
- Sidebar Glance date;
- Waffle Widgets date;
- Anime schedule `todayName`;
- calendar/today comparisons and month ownership such as
  `ClockCalendarContent` and `WeekRow`.

Several event/calendar components already convert the raw date to a
`yyyy-MM-dd` string. Their downstream state does not republish when that
string stays equal, but the formatting binding still executes on each raw clock
tick.

Candidate #79 / R31.3 covers only three **internal DateTime strings**:
`shortDate`, `date`, and `collapsedCalendarFormat`. It does not stop these
external components from depending directly on the 1 Hz clock.

Strict-lossless direction:

1. keep the one existing `SystemClock` and its current precision rules;
2. in DateTime, maintain a stable calendar snapshot/epoch whose public value
   changes only when year/month/day or the required locale/translation epoch
   changes;
3. optionally maintain a stable minute snapshot for consumers whose explicit
   format contains hours/minutes but no seconds;
4. migrate only consumers proven not to need sub-boundary precision;
5. let actual second hands, rotating-second geometry, second-bearing time
   strings and other true second consumers retain the raw clock;
6. keep minute-sensitive policy such as notification quiet-hours on minute/raw
   time ownership rather than incorrectly downgrading it to the day snapshot.

A Date object used as the stable calendar snapshot must remain derived from the
same SystemClock/local timezone. Do not replace it with UTC or a separately
running midnight timer.

Important lock-screen point: lock forces the shared clock to 1 Hz. Lock surfaces
also contain several large date labels. With one lock surface per output, raw
date binding fan-out is multiplied exactly in the state where precision is
highest even though the calendar text is static for almost the whole lock
session.

Required oracle:

- minute precision and explicit second precision;
- lock/unlock transitions;
- one and multiple outputs/lock surfaces;
- 23:59:59 -> midnight;
- manual wall-clock jump within a day and across a day;
- timezone change that changes the local date;
- suspend/resume across midnight;
- live Translation/language change;
- effective Qt locale change where supported;
- date format config changes;
- leap day, month/year boundaries and DST transition dates;
- exact date labels for every migrated surface;
- exact `today`/same-date behavior in CalendarView/WeekRow;
- RotatingDate keeps its separate `clockSecond` dependency and identical
  second-hand/date-arc motion;
- Waffle tooltip's minute-only text may use a minute snapshot, but must still
  change at the same minute boundary;
- Notifications quiet-hours and any true minute/second policy remain unchanged.

The implementation should prefer narrow stable value/signal publication over
per-component private timers. Repository tests explicitly require lock date
labels to derive from the shared SystemClock; a DateTime-owned stable snapshot
satisfies that ownership while removing redundant 1 Hz downstream invalidation.

### R48.3 — Paths deliberately not promoted

**Gowall theme-list append copies:** `GowallService` currently publishes
`availableThemes = [...availableThemes, theme]` for each streamed theme line,
which gives quadratic prefix-copy behavior. Both Material and Waffle Gowall
editors bind directly to that list while `loadingThemes` is true, so replacing
it with one final publication would remove the currently observable progressive
theme list. A mutable in-place list would need a proven QML notification
contract. Do not trade UI semantics for the allocation saving from source alone.

**Lock fingerprint probe:** rediscovered in this process/timer sweep, but Round
35.5 already records it as a low-value one-shot, security-adjacent path. No new
promotion.

**Notification Center current-app lowercase:** `isCurrentApp()` lowercases the
same current id once per activity row plus each row id/originalId. A prepared
current id is valid, but the activity list is bounded and visible only on the
Activity tab. Keep below the promotion threshold unless profiling shows row
churn matters.

**VoiceSearch local backend probe:** backend probing is explicitly demand-driven
through `ensureInitialized()`, coalesces an in-flight refresh through
`_probeQueued`, and re-probes when the configured local model changes. No
steady-state polling or duplicated owner was found.

**SessionWarnings pidof pair:** refresh owns two short `pidof` processes for
package managers/downloaders. The caller controls refresh cadence and the two
domains are semantically separate. Combining them would save one occasional
process but complicate distinct result ownership; below promotion threshold.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without comparable
before/after measurement.

## Research continuation — round 49

Baseline: `dev` at `e094f125352b597cce68e071b8917a7ea9949fda`. Compared with Round 48's `7a31777674ae8e1ccb69824f988e720118ad038a`, GitHub reports **3 subsequent commits**. The runtime delta includes `Background.qml`, `WallpaperCrossfader.qml`, `WaveVisualizer.qml` and an IPC-registry edit plus tests. No runtime changes are authorized by this research round.

Exact source blobs inspected:

- `modules/common/widgets/BarCavaVisualizer.qml`: `f4f0d2ebc36a85d6fafdfa21b7d27ec47a67d06c`;
- `modules/bar/BarContent.qml`: `3afa7aa5e27c069ceed6c3db71d34f1e7ef445d1`;
- `modules/common/widgets/WallpaperCrossfader.qml`: `3511869bf7f731a31514eff645dd20d108605e63`;
- `modules/common/widgets/wallpaperTransitions/inirMelt.frag`: `5e530ac1c15de5b32b50a915cd7a92ad40385a3d`;
- `services/ObsidianTodoBackend.qml`: `75d8f69588f7e4a1f0eb922863544e52bb65fa02`.

### R49.1 — Bar CAVA applies frame-invariant frequency-profile functions to every sample on every audio publication

**HIGH-CONFIDENCE source-level CPU candidate; not an implemented or benchmarked optimization.**

`BarCavaVisualizer._processedSource()` is entered by `_rebuildLevels()`, which is directly triggered by `onPointsChanged`. In its per-sample loop, when `accentStrength > 0` and `frequencyProfile !== "flat"`, it computes each sample's normalized index/frequency, calls `_profileWeight(frequency)`, then multiplies the incoming value by `1 + (weight - 1) * strength`.

The profile calculation itself depends only on **source sample count, profile string, mirroredStereo and clamped accentStrength**, not on sample amplitudes. Bass/vocal profiles call `Math.exp`; treble/smile call `Math.pow`; warm has arithmetic-only weights. Under an unchanged active profile and sample count, the same scalar profile factors are recomputed for every frame. The Bar's actual consumer (`BarContent.qml`) forwards CAVA points and the configurable profile/strength into this renderer. Existing selection/smoothing scratch and dual output buffers already avoid per-frame array allocation; do not replace that correct design.

**Strict-lossless candidate:** maintain a private, reusable factor vector keyed by the exact source count + profile + mirroredStereo + **clamped** strength. Build the factor vector only on a key change; retain the exact existing `_profileWeight`, domain calculation and `1 + (weight - 1) * strength` arithmetic when populating it. The hot path retains `Number(source[i]) || 0`, writes the same selected scratch array in source order and multiplies by the precomputed factor. Bypass the vector for the existing flat / zero-strength fast path. Neither levels/smoothing/bar counts nor CAVA subscriptions, publish identity, rendering nodes, animation cadence or `onPointsChanged` may change.

For N samples and F incoming CAVA frames per second, the active non-flat path currently executes up to **N × F profile-function evaluations per second** (structural count only, not an FPS or CPU benchmark). The candidate should move profile-function evaluation to source-shape/config transitions; frame-by-frame per-sample multiplication remains.

**Oracle before promotion to implementation:** compare the real QV4 implementation's selected source and final `_levels` element-by-element across flat, warm, bass, vocal, treble and smile, stereo true/false, strength 0/boundary/out-of-range, N=0/1/2/64/128/256/variable, changing amplitude including 0/negative/non-finite input, smoothing radius cases, bar and all wave modes, repeated same-size frames, immediate config changes between frames and active/hidden/visible changes. Verify identical source-order math and factor invalidation when N/config changes, identical QML NOTIFY and double-buffer object identity, no additional per-frame allocations, and same rendered frames. Also instrument profile-function call counts and before/after CPU frame cost on a live Bar. Existing `scripts/test-performance-lifecycle.sh` asserts scene-graph and scratch-buffer contracts; extend behavioral tests rather than weakening those assertions.

### R49.2 — crossfader shader-source residency is an instrumentation target, not yet a GPU saving

**MEASURE FIRST.** The current `WallpaperCrossfader.qml` creates two full-parent `ShaderEffectSource` objects bound to `img0` and `img1`; they have `visible: false` and `live: root._shaderTexturePrimePending`. It also constructs a `ShaderEffect`, visible only during priming/requested shader transitions. The recently reinforced priming path deliberately waits for presented frames before starting the transition, and the inactive image is cleared after finishing. **QML object presence alone does not prove that idle ShaderEffectSources retain GPU textures/FBOs**; `visible:false` plus `live:false` may already avoid work.

Instrument QSG/RHI texture allocations and scene-graph resource residency for initial non-shader wallpaper, regular crossfade, `inirMelt` priming/animation/tail, subsequent idle, repeated transitions, multiple outputs and resize/DPR changes. Only if significant idle resource residency is actually observed, investigate cold/loading shader-source ownership while preserving the two presented-frame texture-prime handshake, image fill-mode/crop, transitions, cancellation, compile-failure/software-renderer fallback and exact first frame. No estimated VRAM or GPU percentage is justified before measurements.

**Explicit non-candidate:** `shaderTransition.time`'s 16 ms active timer is **not dead**: the actual `inirMelt.frag` samples `ubuf.time` to animate the wave edge. Do not remove or slow that clock under a strict-lossless claim.

### R49.3 — a possible duplicate legacy Obsidian capability probe is not promoted yet

`ObsidianTodoBackend._scheduleRefresh()` schedules a scan after 80 ms and a capability probe after 120 ms; a successful scan completion restarts the capability debounce. If the first probe runs and finishes before a slower scan, the scan can schedule a second probe. This is a **conditional process fan-out**, not proof of a duplicate every startup. The backend is the legacy managed-note route, whereas the normal Markdown mode uses `DailyNoteTodoBackend`. Probes can reflect external Obsidian/Tasks changes; their results also drive capability state and mutation authorization. Record timestamped process traces and capability publication order before coalescing, and retain the source-key/CLI-running safety contracts. No promotion without a freshness and read-order oracle.

Rechecked and rejected as duplicate/low value: `DailyNoteTodoBackend`'s 60 s date comparison was already classified MEASURE-FIRST in R31.4; its timer does **not** run a Python scan every minute. Existing `BarCavaVisualizer` scratch reuse, wave strip cap and CAVA subscription lifecycle are intentional baselines, not new optimization targets.

This is source research only. No tests or owner-session GPU/RAM profiling were performed for these proposals. Do not attribute whole-Hadalis CPU/GPU/RAM/FPS percentages to them.

## Research continuation — round 50

Baseline: `dev` at `556515012b8c9542e300f2009f83bb69fb3ab13c`. This round **reconciles old research against the current implementation**, rather than seeking extra source-only percentages. The canonical ledger was read through Round 49. Its main table contains **165 historical file/issue rows** (some contain no-action and already-optimized baselines); R2–R49 contain **207 numbered subsection headings**. These are historical heading/row counts, not numbers of unique unimplemented optimization opportunities. Findings were spot-checked against exact current source blobs. **Not all 165 rows have received a new current-source oracle**, so do not infer that every unmarked row remains actionable.

### R50.1 — Retire the QML LocalMusic folder retention candidate; keep transport reduction open

**RETIRED / IMPLEMENTED:** R16.1, main-table LocalMusic row, promotion-order slot #30.

The implementation commit `9376fa34f33ebf2852e47f52e235a6330a54b8aa` changes `services/LocalMusic.qml`, adds a frozen folder fixture and `scripts/test-local-music-folder-release.py`. At the baseline, the current LocalMusic blob is `c9abd1f07efda91d9545bd6ea1eda89d970c6c35` and has **zero occurrences** of `folderCollections`. QML keeps `libraryTracks` and `playlists`, including its `collections: playlists` semantic alias. The old R16.1 proposal to remove a long-lived QML reference has therefore already landed; do not attempt it again.

**Still OPEN / separate:** R16.2 and promotion #31. The Rust MPD snapshot builder (`1c63b8e5281dad2a28e88ea3cb660f7cc0c0cb88`) still inserts `"folders"`; Python (`0e05af4f8a308072fbed7bed96994559b66bf6f1`) still emits `"folders": folders`. Both duplicate transport building and serialized JSON still exist. Stable native/Python protocol fixtures must be explicitly versioned/compatibly extended before attempting elimination. R16.1 retirement is not proof that R16.2 can be changed silently.

### R50.2 — Retire the OrbitalWeather equal-arc table-reuse candidate; retain liquid Canvas work

**RETIRED / IMPLEMENTED:** R43.2, main-table OrbitalWeather/DashWeather row, promotion-order slot #117.

Commit `63ea47423e31a5b210350e6715094f3f48ae5d09` changed `OrbitalWeather.qml` and added a fixed reference fixture plus `scripts/test-weather-orbit-table-parity.py`. At current blob `307dcd5e0758922f388324286960defa51d541e0`, the `hourAngles` binding creates one transient `tables = {}` map, passes it to `orbitAngleForHour`, and `arcAngle` builds an exact 72-sample table once per present quadrant. Liquid mode keeps its direct parametric formula; public helper calls without the shared map still build their own table as before. The implementation test includes exact-angle/node and Qt/QV4 checks; do not conflate an in-tree fixture's presence with having run the test again at Round 50's HEAD.

**Still OPEN / separate:** R43.1's Canvas fallback `LiquidOrbitalField.liquidSample` node-geometry repetition: current blob `1883b6877a02f6013fcacc7e30142e5f522b6165` still has those sample calls. Do not retire R43.1 by association with R43.2.

### R50.3 — Current-source spot checks of earlier findings not eligible for retirement

The following **remain present in current source** and are not retired by this pass:

- Main table's `Wallpapers.qml` duplicated `wallpapers` catalog and `_wallpaperCacheBuilder` remain; source `4a50a93d6ebe4a87ad2ae8dac3d2ab0e09cb7a11`. **Still a candidate**, not an implemented reduction.
- R31.3 / R48.2 `DateTime` calendar-only format work still reads raw `clock.date`; source `6e99a0a319dbbd84635492c0ca6fcd617c2f175c`. **OPEN**, with strict midnight/locale/lock oracles.
- R48.1 CAVA external-theme narrowing is **OPEN**: `AdvancedConfig` still triggers `wallpaperSwitchScriptPath --noswitch`; source `baf79c0311a105c3cbf871628f9a4dec4d0e64f4`. The independent `apply-targets.sh` runner's existence is not implementation of the settings reroute.
- R49.1 Bar CAVA frame-invariant profile functions remain evaluated inside `_processedSource()`; source `f4f0d2ebc36a85d6fafdfa21b7d27ec47a67d06c`. **OPEN / need exact QV4 parity**; no run-time performance percentage.
- MPRIS `_playerGrace` retains the map-copy logic; source `3a8184f9308f0816ea395ea26f182bb5a3fbcf15`. **OPEN / existing historical candidate**.
- R49.2 WallpaperCrossfader shader-source residency remains **MEASURE FIRST**; no measured idle VRAM to retire or promote. R49.3 legacy managed-note capability probe remains **conditional / not promoted**, not an obsolete feature merely because Markdown mode is the default.

Revalidation method: current `dev` source reads, precise feature fingerprints, historical candidate-to-commit linkage and test-fixture inspection; no runtime behavior was changed and no benchmark/owner-desktop validation was executed. Continue with more source-backed retirement sweeps, especially after concurrent product/optimizer commits. Preserve historical evidence; mark statuses instead of deleting whole rounds or moving portions of the canonical active ledger into competing documents. No whole-Hadalis CPU/GPU/RAM/FPS improvement percentage is claimed.

## Research continuation — round 51

Baseline: `dev` at `a12dad671a81344e5d69fc405a45ad27c74ac2cc`, with the canonical audit through Round 50. The compare from the last Round-50 documentation completion `0fc74ac24c6675fa00a7b92329ca524974444f4d` to this baseline reports **four commits** touching `Config.qml`, `NotepadWidget.qml` and focused validation/fixtures. The new research therefore concentrates on those actual changed areas rather than repromoting the already-implemented R16.1/R43.2 findings.

Source identities from the exact baseline:

- `modules/common/Config.qml`: `312b8f7078f138e075bc2a979b751b57de3e4347`;
- `modules/sidebarRight/notepad/NotepadWidget.qml`: `9e301303f455e788652d9e8034ddb196b079a4f5`;
- `services/Notepad.qml`: `6f17567be8417cef499086138db5884336e2eb3f`;
- `scripts/test-config-inflight-mutation-runtime.py`: `bd7210fce5c3f9e8fa7b29d8feaf0431d3f38589`;
- `scripts/test-quick-notes-corner-contract.py`: `2c6334e00f3f92d7513829caa7909dfdbb18e32e`.

### R51.1 — Config's in-flight mutation overlay deep-copies all older edits on each new edit

**HIGH-POTENTIAL TEMPORARY-ALLOCATION/CPU CANDIDATE; strict-lossless proof is pending.** The recent Config in-flight mutation fix is correctness-critical and must not be reverted. `_recordPendingMutation(nestedKey,value)` returns immediately in the normal no-flight case. While `_reloadInFlight` it executes `_cloneObject(_reloadOverlay)`, writes the new dotted key, and replaces the QML var; while `_writeInFlight` it repeats the same sequence on `_writeOverlay`. `_cloneObject()` executes `JSON.parse(JSON.stringify(...))`; thus every mutation during a flight traverses all **previously recorded** pending values in the relevant overlay(s), even if the same large nested dashboard-array value is being overwritten. A single call to `setNestedValues` loops each key through that machinery, and a series of K distinct entries of similar size can approach cumulative O(K²) prior-value traversals within one flight. **That is an algorithmic opportunity, not a measured time/RSS saving.**

The ownership and data-race boundary is subtle:

1. `_beginLocalMutation()` cancels a merely pending reload, but an already-running asynchronous FileView reload cannot be cancelled this way.
2. `onLoaded` clones the reload overlay once, resets its QML var, restores the adapter/mirror, then replays recorded paths in `Object.keys` order. A nonempty overlay schedules a follow-up write; style-family migration also interacts with this path.
3. `_endWriteFlight` consumes the write overlay, replays it after FileView's older save, then schedules the next write/reload. `flushWrites` and a 2-second retry/guard can interleave with new edits. Both flight flags can overlap because the write timer does not explicitly block on an existing `_reloadInFlight`.
4. The old clone normalizes **earlier** entries through JSON but installs the **newest** entry by reference until a subsequent edit/replay. Naively mutating the overlay in place, or globally deep-cloning values at insertion, may change object identity, serialization/normalization, last-wins behavior or hidden QML observers. Do **not** classify such a replacement as proven strict lossless from source only.

Investigate a private sparse last-write-wins representation or other proof-backed reduction of previous-overlay deep copies while keeping each existing publication/merge boundary. First instrument clone count and serialized bytes per mutation under both flight flags. Required real Qt/QV4 oracle: zero/many mutations; same path repeated; mixed multiple paths; array/object payloads incl. Dashboard canvas; primitives, null, undefined and malformed entries; mutations from array path keys; style migration; custom widget paths; save success/failure/timeout, explicit flush; old load/new edit; old save/new edit; both flags active; reentrant signal ordering; object/reference parity where the existing contract exposes it; exact persisted bytes and mirror/JsonAdapter state. The in-tree `test-config-inflight-mutation-runtime.py` provides four overlapping-save regression rounds but **is not complete coverage** of read/reload/both-flight/equivalence cases. Extend it rather than weakening it.

### R51.2 — Notepad counts all words by materializing a full split array on each text change

**HIGH-CONFIDENCE STRUCTURAL ALLOCATION CANDIDATE, CPU gain MEASURE FIRST.** `NotepadWidget.wordCount` is bound to `textArea.text.trim().length > 0 ? textArea.text.trim().split(/\s+/).length : 0`. It performs a second trim and creates a transient array of every word even though the sole visible statistics label asks only for the integer count. This work depends on the complete editor string and is invalidated as the TextArea text changes. For a note with W words, an evaluation materializes roughly W split entries instead of maintaining a scalar word count. Each live NotepadWidget instance has the binding; whether hidden compact instances actually *evaluate* it as often must be instrumented rather than assumed.

Strict-lossless candidate: use a single pass that counts transitions from ECMAScript whitespace to non-whitespace without materializing substrings, but compare it against the **real QV4** `String.trim().split(/\s+/)` semantics for `\\s`/Unicode whitespace before promotion. Keep the `wordCount` property and exact *immediate* update semantics for the full Sidebar presentation; no debounce of visible stats. If a presentation-aware optimization is considered, prove the word-count public property and compact/full mode transitions remain equivalent before reducing any binding work.

Required oracle: empty/only ASCII spaces/tabs/newlines/CRLF, NBSP, BOM, U+2028/U+2029, emoji/surrogate pairs, mixed scripts, punctuation-adjacent tokens, trailing separators, long 10K–100K-word drafts, rapid keystrokes/deletes/paste/undo/redo, note/tab switching, asynchronous `Notepad.tabs` updates across Sidebar/Dashboard/Quick Notes, compact/full transitions, one or more concurrent editors, layout/stat label and exact timer behavior. Benchmark peak temporary allocation, GC and typing latency; a streaming regex-per-character approach may have lower memory but **not automatically lower CPU**.

Existing protections are deliberate: `NotepadWidget` owns an 800 ms autosave timer, tab-ID-scoped flush and multi-surface draft reconciliation; `Notepad` owns in-flight save coalescing and the complete JSON tab store. Those are *not* obsolete optimizations. In particular, do not silently replace the persistent multi-tab schema with per-note files or remove the save coalescer merely to avoid full JSON serialization. Existing `test-quick-notes-corner-contract.py` covers important tab-scoped persistence/multi-surface behavior; preserve it.

### R51.3 — Status/retirement reconciliation

R50's two verified completed findings remain `RETIRED / IMPLEMENTED`: R16.1 QML `folderCollections` root removal and R43.2 per-quadrant OrbitalWeather table reuse. The four intervening commits do not directly modify their implementation source, so there is no new evidence that either should be reopened. The nearby R16.2 transport `folders` candidate and R43.1 LiquidOrbitalField Canvas candidate remain separate, still open.

R51.1 differs from the existing domain-specific `Config.configChanged` invalidation proposals: it reduces *private in-flight snapshot copy work* and does not suppress signals or any consumer binding. R51.2 is specific to the multi-surface Notepad editor, not the already-studied search normalization, Settings search or CAVA profiles.

No runtime or tests executed through this GitHub-only research pass. The regression scripts are referenced as available fixtures, **not presented as passing on this baseline**. No whole-Hadalis CPU/GPU/RAM/FPS percentages are claimed. Continue strict-lossless source research and feature-specific oracle development.

## Research continuation — round 52

Baseline: `dev` at `f3034df8104831a3d1dfe61e86c815c819bf8458`. The branch ref matches the Round 51 documentation completion `f3034df8104831a3d1dfe61e86c815c819bf8458`; **there are no intervening source commits to attribute a new runtime change to.** The new work reviews a distinct custom-widget configuration batch path and a package-search process/latency boundary. Prior R50 retired implementations stay retired; no new retired finding is proven in this pass.

Verified source blob identities:

- `modules/common/Config.qml`: `312b8f7078f138e075bc2a979b751b57de3e4347`;
- `services/CustomWidgets.qml`: `fe4b1ef553fe7ed437b4e0de947615eee83752c9`;
- `services/deferred/PackageSearch.qml`: `8a2fdcc8dcf79589456797042d7ef245c8f72ab0`;
- `modules/overview/ActionModeView.qml`: `9b27d18f4b71fef013d7269d1ea22438a9f029b5`;
- `services/FontSyncService.qml`: `28a15b4f0a9008e6ccbb66eb6dbe058d20169824`;
- `services/KeyboardIndicators.qml`: `bde84eb8b229a2bd9e63eee048d702decbf149b3`.

### R52.1 — Custom widget default seeding traverses the full growing QML config tree twice for each new key

**HIGH-CONFIDENCE SOURCE-LEVEL ALLOCATION OPPORTUNITY / ORACLE REQUIRED BEFORE ANY CHANGE.** `CustomWidgets._seedMissingConfig()` waits until `Config.ready`, `Config.customWidgetDataSynced` and its manifest scan are complete. It enumerates each widget's default keys, checks `Config.getNestedValue("background.widgets.custom." + widgetId + "." + key)`, and builds an `updates` object of all missing values. It calls `Config.setNestedValues(updates)` **once**, correctly coalescing the outer revision/`configChanged`/write debounce.

Inside that batch, however, `Config.setNestedValues()` still calls `_applyNestedKey` for **each** path. The `background.widgets.custom.*` special case performs:

```qml
data = JSON.parse(JSON.stringify(root.customWidgetData ?? {}))
... // assign the converted leaf
root.customWidgetData = data
root._customSnapshotForInject = root._cloneObject(data)
root._pendingCustomInject = root._hasObjectKeys(root._customSnapshotForInject)
```

The first JSON traversal clones the previous whole custom-widget tree; the second clones the whole updated tree. Both occur again for the next missing default key, **even in an otherwise idle FileView session**. For K newly populated keys with similarly sized values, previous keys can be traversed repeatedly so aggregate copy work scales with approximately the sum of the growing snapshot sizes (quadratic in K for constant-size keys). If the existing config is already large, each new key also recopies unrelated existing widget subtrees. The exact number of allocations, loaded widgets and milliseconds is unmeasured.

**Do not confuse this with R51.1**: that candidate copies `_reloadOverlay`/`_writeOverlay` only while asynchronous I/O flight flags are active; this one copies *live `customWidgetData` and the injection snapshot* for every custom key in a single normal batch. The two costs can compound during a save flight but have different owners/invalidation contracts.

Strict-lossless research direction: collect per-batch `K`, tree sizes, JSON-stringify/parse invocations, bytes traversed and QML signal traces. Evaluate whether the batch can reuse a prepared snapshot or apply an identity-preserving/notification-preserving reduction of redundant copying. **Do not assume one final assignment is equivalent**: current code publishes a new `customWidgetData` object and refreshes `_customSnapshotForInject` on *every key*, so synchronous observers/NOTIFY and object identity may see each intermediate prefix state. Also the helper uses string conversion for values that look numeric/boolean; `_applyToMirror` deliberately bypasses the custom subtree, while `_prepareCustomInject`/`_injectCustomDataSync` publish it later.

Required oracle with real QV4 and the actual Config singleton: K=0,1,2,20,100,500; old tree empty/large; repeated same widget and many distinct widgets; existing keys/missing keys; default-config overrides and configKeys types; object/array/null/string values including numeric/boolean-looking strings; custom root assignment vs nested assignments; duplicate dotted keys and key-order differences; `customWidgetDataChanged` count and the sequence/identity/readable content of **every** intermediate signal; Config revision, `configChanged` and exact persisted JSON; external file reload, simultaneous write/reload, recoverable failed write, `_pendingCustomInject` and custom snapshot mutation; plugin manifests created/removed; multiple custom-widget delegates reading the same fields. Ensure the existing `test-config-inflight-mutation-runtime.py` remains green and add a separate batch/reference fixture. If fresh identity/NOTIFY preservation proves too expensive, keep this candidate unimplemented rather than weakening strict-lossless.

### R52.2 — Overview Remove-package query dispatch bypasses the shared search debounce

**MEASURE FIRST / UX-PARITY GATED — not promoted to strict-lossless implementation.** `ActionModeView.onPackageQueryChanged` calls `PackageSearch.searchInstalled(packageQuery)` directly when the query has at least two characters and the action prefix selects Remove. The Install/Search branches call `PackageSearch.search()`, which restarts a 300 ms debounce. Conversely `searchInstalled()` explicitly stops that debounce, increments the request generation, marks searching, and immediately queues the command `pacman -Qs "$1" | head -100` under Bash.

The installed-request queue retains at most one latest pending request while the process is running, and generation checks suppress stale *result publication*. That is useful and must remain. But it is **not a 300 ms typing debounce**: if each quick installed search finishes before the next keystroke, it can execute once per keystroke; on slow searches it still may execute intermediate searches as each process exits depending on input timing. Distinguish submitted requests, actual helper starts, completions, and visible results; do not assert N processes for N characters unconditionally.

Potential solution: introduce an installed-only debounce or coalescing boundary, but this changes when `searching`, `error` and results become observable and may reduce responsiveness for a single Remove query. This is **not source-only strict-lossless proof**. Test exact rapid typing, pasting, query erase, prefix mode switches, pending process completion after view destruction, 0/1/2+ query characters, AUR/available vs installed path and missing package manager. A before/after latency/process profile and explicit UX acceptance are needed before promoting. Do not weaken the active-generation stale-result protections or shell-command quoting.

### R52.3 — Paths checked but deliberately not promoted / retirement unchanged

- `FontSyncService` is already config-driven and uses a 500 ms debounce, one in-flight process and a 30-second **one-shot timeout**, not a recurring 30-second font-sync poll. It deliberately reconciles GTK/KDE font settings at startup. No new candidate merely from its timer count.
- `KeyboardIndicators` uses an event-driven native evdev lock-state monitor when available. Its `ledDiscoveryIntervalMs` 30 s/5 min (low power 2/10 min) fallback is for sysfs recovery with watcher failures. Do not treat the fallback discovery loop as an idle high-frequency default-CPU target; removal would lose device reconnect handling.
- R50's `RETIRED / IMPLEMENTED` R16.1 and R43.2 remain closed as research candidates. R51.1 overlay copying and R51.2 word-count arrays remain separately open; R52.1 explicitly does not duplicate either.

This is **research only**: GitHub source verification at the pinned baseline, no QML/native patch, no local tests/benchmark and no owner-desktop evidence. Preserve strict-lossless and avoid unmeasured whole-shell CPU/RAM/GPU/FPS percentage claims. Continue to next research round.

## Research continuation — round 53

Baseline: `dev` at `36935bae0c87f22449d9e62f3772b6f1cc6a33fd`. Relative to Round 52's committed `02f2b41255636bc29b118612f365a61140cc5443`, GitHub reports **one intervening commit**, `36935bae0c87f22449d9e62f3772b6f1cc6a33fd` (`fix(audio): restore IPC volume OSD on EasyEffects device routes`). That change touches the Audio facade, three OSD families and the focused audio-routing regression. This pass therefore audits **EasyEffects routing computation without changing the newly repaired IPC/OSD behavior**.

Pinned source identities:

- `modules/common/functions/audioRouting.js`: `c63e066476860faab4300f4400c3e6a8c1ffb38c`;
- `services/Audio.qml`: `a62722abc4d24495e6ee52b56989c18628150582`;
- `scripts/test-audio-output-routing.py`: `7b6e5ee37215c3bf7f36bac3c12a03af789ed96d`;
- `modules/abyss/AbyssOsdController.qml`: `96ad7614a8ed1aca9180b0132e07984126bec83d`;
- `modules/onScreenDisplay/OnScreenDisplay.qml`: `4e8eb67dd172a7cee2dbd83969ec5f78ae9e3738`;
- `modules/waffle/onScreenDisplay/WaffleOSD.qml`: `f3124e3a442a71e78be2ee7a43b11e0abef9211d`.

### R53.1 — Guarded adjacency exploration of EasyEffects directed PipeWire links

**HIGH-CONFIDENCE ALGORITHMIC OPPORTUNITY; only a guarded subset is eligible for a strict-lossless candidate.**

`Audio.resolveControllableSink(node)` passes `Pipewire.nodes.values`, `Pipewire.links.values` and native/Flatpak EasyEffects configured outputs into `AudioRouting.resolveSink`. Non-EasyEffects or no-audio nodes return directly, so this is **not a generic per-frame PipeWire hot path**. For an EasyEffects default sink, `resolveSink` constructs physical candidates, seeds `reached` with the starting sink ID and members of its explicit link group, then performs up to `nodes.length` *ordered complete scans* over `links`, breaking after a no-change pass. When link order opposes a directed chain, one new vertex may be added per pass: worst-case work is proportional to N×E source/target reads, not necessarily N×E milliseconds. Device selection then requires exact `linked`, exact `configured` tie resolution, and the guarded driver-id fallback.

**Crucial counterexample: unconditional BFS is not behavior-preserving.** Given `nodes=[1 (EasyEffects),2 (speaker)]` and reverse-ordered directed links `5→2,4→5,3→4,1→3`, the current algorithm performs only **two passes**. It reaches IDs `{1,3,4}` and does **not** reach speaker 2. A full BFS reaches `{1,3,4,5,2}`, potentially selecting speaker 2 instead of the unchanged default sink. The intermediate IDs 3,4,5 are absent from the nodes snapshot; the original pass cap is part of the observable behavior even if those links represent a stale/malformed graph. Therefore a naive "linear-time BFS is exactly equivalent" claim is **false**.

A possible strict-lossless **guarded fast path** may first validate that every positive-ID traversable edge's source *and* target exist in the **same** `nodes` snapshot. For such a closed snapshot, all reachable distinct positive IDs are among at most N listed nodes; the old N-pass algorithm reaches their full transitive closure regardless of link ordering, matching adjacency BFS membership. If the edge closure check fails, execute the original exact bounded scan without changing its order or count. Guard must not filter out links, silently replace an unknown ID with a known one, or treat a stale absent endpoint as safely complete.

**Analytical differential probes in this research turn (not repository/QV4 tests):**

- An isolated JavaScript transcription of the current reachability loop vs unconditional BFS was compared across 10,000 generated graph/selection examples and happened to show zero mismatches; **that is insufficient proof** because it missed the adversarial bounded-pass counterexample.
- The explicit two-node reverse phantom-chain case above **does differ** between original and unconditional BFS, exposing the invalid optimization.
- A second deterministic, pure-JS graph-reachability comparison of old bounded scans against a *guarded* adjacency algorithm ran **20,000** generated cases: **13,587 endpoint-complete fast-path cases; 6,413 fallback cases; zero observed reachability mismatches**. The explicit counterexample correctly selected fallback. These numbers validate only the locally transcribed graph-membership model. They do **not** validate actual `resolveSink` return-object identity, Qt/PipeWire object getters, QV4 implementation, notifications or timing.

**Required native/QV4 oracle:** run the real current `audioRouting.js` and candidate in a pinned test session; include missing/intermediate nodes, stale/removed links, malformed/zero/non-numeric IDs, duplicate IDs, cycles, channel duplicate edges, self-links, multi-driver/group cases, dynamic group membership, links arriving before nodes, and late EasyEffects config FileView completion. Compare the **returned PwNode identity** and every priority branch, configured fallback, physical candidate order and ambiguous/multiple-output behavior. Instrument getter/property read count and exception/NOTIFY ordering: even a closed graph can expose different reads if QML properties change during evaluation, so endpoint closure alone is not full QV4 proof. For each route change, retain exact default processing sink, selected physical control target, volume/mute actions, `sinkControlRequested`, sample invalidation/read-back, all existing OSD families and the test's nine ordered IPC steps. Repeat live hotplug, suspend, EasyEffects idle/active and multiple outputs. Profile N/E, resolution call count, CPU time and adjacency temporary allocation on real systems; the additional map construction may **lose** on common small topologies. Only promote implementation with demonstrated real benefits and exact parity.

### R53.2 — Relative volume keypress queue uses `Array.shift()`, but no unconditional batching is safe

**LOW PRIORITY / MEASURE FIRST, not a promoted strict-lossless change.** The newer `Audio` facade preserves each keypress by appending `{target: _sinkControlTarget(), direction}` to `_sinkSteps`, immediately emitting `sinkControlRequested`, and running one `wpctl set-volume` process at a time. `_dispatchSinkStep` consumes `_sinkSteps.shift()`; under a large backlog of K inputs this can move/reindex the remaining array on each dequeue, with potential quadratic total element movement. Existing QML test checks **five increments, three decrements, then a switch to a different output and one more increment**; no keypress can be removed, merged/reordered or retargeted without breaking that contract.

A head-index queue/ring buffer could reduce per-dequeue array movement, **but adds retained array slots, cursor state and compaction/cleanup complexity**. First measure maximum observed queue depth and wpctl launch/exit latency during normal single press, held key, rapid alternation, high-rate input and device switching. Maintain per-press OSD event emission, exact device-at-press target, read-back guard generations and the final read timer after drain; don't turn relative 2% steps into one absolute volume set, and don't pop stale steps after device changes. If queue depth remains tiny, preserve the simple array and classify as low-value.

### R53.3 — Non-promotions and retirement review

- Four PipeWire node projections (`outputAppNodes`, `inputAppNodes`, `outputDevices`, `inputDevices`) each apply a separate array filter. These are topology/reactivity work, **not** evidence of four independent process spawns or repeated 16-ms per-frame rescans. Check binding invalidation and actual topology size before proposing a fused projection; fresh property-list identities and `PwObjectTracker` ownership must not change.
- R50.1 LocalMusic QML retention and R43.2 OrbitalWeather equal-arc table reuse remain `RETIRED / IMPLEMENTED`; the new audio commit does not touch those source paths. Earlier R51/R52 Config, Notepad and package-search candidates remain independent and still lack native parity benchmarks.
- Existing audio dispatch timers and ramps were previously classified intentional/coalesced. Do not retire or rewrite them based only on this new graph analysis. The recent OSD repair must retain its behavior.

This round **does not change runtime**. No local repository, actual QV4/Quickshell test, GPU measurement, desktop acceptance or whole-Hadalis CPU/RAM/FPS benchmark was run. The two analytical pure-JS probes are explicitly scoped and are not acceptance evidence for a code patch. Continue research in the next round.

## Research continuation — round 54

Baseline: `dev` at `331901d624933eaaa707962b7ab04fe81ff2a8e7` (Round 53's research-only documentation commit). There is no intervening source change to justify reclassifying the recent EasyEffects repair or closing prior findings. To diversify after R53's audio-graph exploration, this round examines historical Activity / ScreenTime data projection, including both Sidebar and Waffle consumers. Historical ledger search found R24.3 on the *startup read process*, but **no earlier finding specifically targeting repeated in-memory `getCachedDays` merges per active UI refresh**. Do not confuse these different contracts.

Current source blob evidence:

- `services/ScreenTime.qml`: `1eabb174c464bf0a1e372ebbe8a43f671d2e9d89`;
- `modules/sidebarRight/screenTime/ScreenTimeWidget.qml`: `6e3f49ee2e8f0ac569c980e7b277cf41139b4c14`;
- `modules/waffle/actionCenter/screenTime/ScreenTimePage.qml`: `92726c36aaed062ba6674728cdba2198bc4dedf7`;
- `modules/notificationCenter/NotificationCenterPopup.qml`: `12f1c40b594e41ad0d95f7a314a864f2de8f2f0c`;
- `scripts/test-screen-time-lifecycle.sh`: `5eb6f6e4a6336076299a19ae0ec956a0ef1e7bb7`.

### R54.1 — Historical ScreenTime projection repeats the same merge 2–3 times within one owner refresh

**HIGH-CONFIDENCE SOURCE-LEVEL CPU/ALLOCATION OPPORTUNITY; QV4 contract proof pending.** `ScreenTime.getCachedDays(count)` retrieves `_rangeHistoryData[count]`, and, on a hit, returns `_mergeHistoricalData(getToday(), history)`. This does **not** return the cached object: `_mergeHistoricalData()` starts from `_mergeDays(todayData, "")`, cloning today's app records and their valid 24-element `hourly` arrays, then visits every historical app and updates another 24-element array for each one. This is valuable normalization but is repeated for unchanged data each time another caller requests the same range.

In `ScreenTimeWidget._refreshData()` and `ScreenTimePage._refreshData()`, for `currentDays > 1` and a populated history cache:

1. `ScreenTime.getCachedDays(currentDays)` produces the `_displayData` snapshot (**one merge**).
2. `ScreenTime.getAppList(currentDays)` fetches `getCachedDays(currentDays)` again, then creates/sorts app rows (**second merge**).
3. When `_selectedHour >= 0`, `ScreenTime.getHourBreakdown(_selectedHour,currentDays)` fetches `getCachedDays(currentDays)` once more, then builds/sorts hour rows (**third merge**).

Thus the *structural per-owner count* is two merges for a selected historical range, three with an open hour drill-down, and zero for today's data (which uses `getToday()`). If **both** UI owners receive the same update while loaded and both display a historical range with an open hour panel, they collectively perform **six** redundant-range rebuilds per event. On a successful range file read, `rangeReadProc.stdout.onStreamFinished` also constructs a merged `rangeLoaded(days,data)` payload: consumers currently ignore the already-merged `data` parameter and invoke `_refreshData()`, further multiplying work. Those are source-level call counts, **not observed frame time, process count, or allocated bytes**.

Strict-lossless strategy to explore: construct exactly one appropriate `_displayData` range snapshot per owner refresh, project both app rows and selected-hour rows *from that same snapshot* via private pure projection helpers; keep the public `ScreenTime.getCachedDays/getAppList/getHourBreakdown` signatures and semantics for unrelated consumers. Consider using the supplied `rangeLoaded` data only after proving equivalence to the current fresh cached merge and event ordering. Do not globally memoize solely by `days`: the current-day data is mutated as usage accrues and published via `dataChanged`, while `_rangeHistoryData` is replaced on range completion and invalidated on day rollover. A globally shared mutable merged object would introduce observable identity and stale-data hazards.

**Fresh-identity / QML ordering gate:** The existing service methods return freshly constructed objects/arrays for each query. The two owners assign `_displayData` before `_appList` and before `_hourApps`, so synchronous property observers may observe those intermediate states. A candidate must preserve **every assignment and signal sequence** and reproduce the same app/hour row allocation and sort tie ordering; only eliminate intermediate *unpublished* full-range snapshots. Also preserve `currentDays <= 1`, cache miss (clears `_displayData` and `_appList` but retains current `_hourApps` until selected hour reset), `rangeLoaded` identity payload, fallback-to-today behavior in the public projection methods, and all history-generation checks.

**Analytical prototype only:** An isolated, deterministic plain-JavaScript transcription of the merge/projection logic compared repeated range merges with single-snapshot projection across **2,048 generated today+history records and selected hours**. The baseline model invoked merge 6,144 times vs 2,048 single-snapshot invocations and observed **zero JSON-value projection differences** for `_displayData`, application list and selected-hour list. This is a scoped structural probe, **not** real source/QV4 or UI signal/identity acceptance, and does not prove CPU speedup. Tests included JSON-like app/hour records and missing fields but did **not** cover malicious getters, QML object types or concurrent source mutation.

**Required real oracle:** frozen fixture covering 1/3/14 days, K=0/1/50/500 apps, missing/legacy hourly arrays, partial/malformed history, zero/negative/non-finite seconds where supported, duplicate/same-name apps, equal-value sort ties, day rollover, idle/resume, focus handoff, in-flight range read & generation invalidation, `rangeLoaded` async order, two simultaneous owner instances and cross-family switching, disabled tracking and cache misses. Inspect the complete QV4 emitted property/row sequence, stable numeric totals/24 hourly buckets, app order, fresh list/object identity for public callers, persisted files and exact dataChanged/ready/rangeLoaded cadence. Instrument merges per UI event, copied app/hour array count, wall-clock GC and user-visible refresh latency on large data; preserve the existing test-screen-time-lifecycle contract rather than rewriting source-spelling checks as proof.

### R54.2 — Scope and rejected short-cuts

- **NOT a proposed Niri tick-rate reduction:** `ScreenTime.pollTimer` is already **30 seconds** on Niri, with active-window changes delivered through a reactive signal. The screen-time UI's historical merge redundancy is triggered by actual data/range refreshes, not a claimed 1 Hz timer. Do not retune persistence, idle detection, day rollover, or accounting timestamps.
- **NOT a proposal to suppress `rangeLoaded` data construction blindly:** it is a public signal payload and might be used by future callers. Optimizing one consumer's snapshot path must not remove the signal or change public payload identity/order. The popup `NotificationCenterPopup` currently queries today's `getToday`/`getAppList(1)` and is **outside the repeated historical-merge subset**.
- R24.3 proposed replacing the ScreenTime startup Bash `test/cat` process with the existing FileView primitive. This remains a separate unimplemented candidate; R54 does not retire it. R53.1's guarded EasyEffects graph fast-path, R52.1 custom-widget config clones and R51.1 overlays remain independent and await actual native parity/benchmark evidence.

Research only. No runtime QML/native/service changes, no actual repository tests, no real QV4/desktop profile and no whole-Hadalis CPU/GPU/RAM/FPS percentage claims. Continue the next research round after native oracle development.

## Research continuation — round 55

Baseline: `dev` `19c24b09298037034a762fe4d5e6e0168fe1daed`, following the latest canonical Round 54. Compared with Round 53 completion `331901d624933eaaa707962b7ab04fe81ff2a8e7`, the source delta is documentation-only Round 54; source files audited below were fetched by pinned SHA.

- `services/ResourceUsage.qml` blob `1d8e8693c230ee7450072366557b6070d433af58`;
- `modules/common/widgets/ResourceUsageMonitor.qml` blob `2abeafad618ddcd9e68b1da6928382bb8501f3ea`;
- `modules/common/widgets/Graph.qml` blob `1d41cd62dcf31d550e825fdbf390c90f76c4d663`.

### R55.1 — Per-sample history arrays publish append before their capacity shift

**MEASURE FIRST / strict-lossless proof required.** `ResourceUsage` declares five public `list<real>` histories (CPU, GPU, GPU temperature, memory and swap). Their five updater functions all perform the same sequence: `history = [...history, sample]`, then, when `history.length > historyLength`, `history.shift()`. `updateHistories()` calls all five sequentially after `_pollSensors()` but correctly exits when neither a persistent history consumer nor an unexpired transient request exists.

The current spread expression allocates a fresh array of H+1 values, while the following `.shift()` removes the first element in the QML sequence. The algorithmic work is O(H) or more per history per sample, depending on QV4/list conversion and shift behavior. At configured capacity H, the intermediate published property is of length H+1 **before** the shift, even though a normal UI frame may only see the final H samples. It is not established whether `list<real>` emits a second property change for `shift()`, and no source-only inference should claim the signal count. Any candidate must measure real QV4 property/NOTIFY and chart repaint behavior first.

A naive `history = [...history.slice(-(historyLength-1)), sample]` or circular-buffer conversion is **not proven strict-lossless**. It may alter the temporarily published length, property/list identity, mutation signal sequence, observable property reads during a binding notification, chronological order after capacity changes and edge cases for H=0/1, negative/non-integer configurations or future external callers. A private prepared buffer or bounded append projection is worth investigating only if it reproduces all supported states and notifications. Do not hide/disable history while a consumer is active: the existing history-demand gating in R2.3 is a good baseline and this finding is **not a repeat of it**.

Required oracle: native Quickshell/QV4 fixture with `historyLength` at 0,1,2,60,1,000 and malformed config; empty/partial/full histories; CPU/GPU/temperature/memory/swap sample ordering, NaN/nonfinite handling, simultaneous updateHistories and capacity changes, repeated duplicate samples; signal counts, synchronous `on...HistoryChanged` reads, list/object identity and graph `valuesChanged` paint requests; active vs transient/expired/persistent consumers; multi-surface charts and low-power polling. Compare full five-series array content at **every** published step and the final graph pixels; instrument per-sample copied elements, QV4 allocations/GC and latency before considering implementation.

### R55.2 — Related paths intentionally left alone

- `ResourceUsage` already gates history sample generation through `_historyConsumers`/`_historyTransientUntilMs`; zero-consumer history work is **not** the proposed saving. The independent R2.3 metric-demand work (GPU, temperature and disk subprocess leases) remains OPEN.
- GPU process helpers are already cadence-gated and distinguished from cheap sysfs reads; the historical candidate to eliminate Bash wrappers is independent and has an external command/exit-code oracle.
- Graph presentation consumers cannot be treated as passive holders of arrays. The basic `Graph.qml` Canvas listens for `valuesChanged` and calls `requestPaint()`; source-level repaint equivalence does not follow from equal final arrays alone.
- R53 guarded EasyEffects reachability, R54 ScreenTime history merges and previous retired R16.1/R43.2 statuses remain unchanged.

This is source-audit research only. No runtime changes, no native Qt/QV4 test execution and no measured whole-Hadalis GPU/RAM/CPU/FPS gains. Continue research after the native history-list oracle.

## Research continuation — round 56

Baseline: `dev` at `b6a13d79aad1317e15e8ce7b2e0c6078f5510f4b`, whose latest canonical continuation is Round 55. No source deltas were observed during this read pass; the source is evaluated at pinned file blobs, not inferred from historical examples. This round researches a **new subpath** inside the existing CalendarSync batch primitive, rather than duplicating R15.1's pending migration of remaining calendar consumers or R15.2's separate calendar-grid snapshot proposal.

Pinned source identities:

- `services/CalendarSync.qml`: `6e0b89c56eda5ee612be8438d9c20d4851a09617`;
- `modules/sidebarRight/events/EventsWidget.qml`: `f505dc6331e2f1d56eac547dfe7c4b0e713a162a`;
- `modules/sidebarRight/CompactSidebarRightContent.qml`: `af2670e333969d282101e29cd83c5847b9bb07b2`;
- `modules/dashboard/DashAgenda.qml`: `222f16088cf07d53c0ad606d1cc8a68d3abe717c`;
- `modules/waffle/notificationCenter/CalendarWidget.qml`: `820a50373bd475e583e8ce4cd9b66515a4acba01`;
- `scripts/test-calendar-sync-privacy.sh`: `ec4ea02d4594e6a0186e7561035fc9c369fc6f6f`;
- `scripts/test-calendar-weather-composition-contract.py`: `15a5281263ee6fb6aab0a4a3585c4761a36f9722`.

### R56.1 — Date-index timed events inside an existing batch CalendarSync bucket helper

**HIGH-CONFIDENCE ALGORITHMIC SOURCE OPPORTUNITY / performance and QV4 acceptance unproven.** `CalendarSync._getEventBucketsForDates(dates)` already builds the ordered requested `targetTimes` array once, then iterates `root.events`. For each event **without** `allDay`, the implementation parses one `startDate` local midnight and loops over **every target day** to test `eventTime === targetTimes[i]`. The inner scan is O(E_t×D) equality checks for E_t timed records and D query days, on top of date parsing and requested output. For events with `allDay`, the separate loop correctly evaluates inclusive start, RFC5545 exclusive end and degenerate/missing-end one-day fallback; it should remain untouched by the first optimization. The batch helper is actually used by `EventsWidget` (30-date owner) and `CompactSidebarRightContent` (14-date owner), not a purely dead hypothetical path. Other Dashboard/Waffle consumers still call `getEventsForDate` in per-day loops, the **already documented R15.1 migration**, and are *not* quietly claimed as existing batch consumers.

Strict-lossless candidate: in each invocation construct a **private** `Map` from each valid normalized target midnight number to an **ordered list of every index in dates**. Preserve `targetTimes` and `buckets` exactly. For each non-all-day event, calculate the exact original `eventTime` once, then append that same event *reference* to the buckets at the corresponding target indices; for all-day events execute the existing full target-day loop in original event order. This preserves each bucket's event-major source order and duplicate-date behavior without changing the API, published `events` property, event identities or when consumers refresh. Complexity for the timed subset becomes O(D+E_t+M_t) in ordinary key-lookup count, where M_t is the number of matched output entries, with extra Map/index allocations. A speedup on common small calendars is **not** demonstrated and may be negative due to index construction.

**NaN semantic trap that forbids naive Map lookup:** `new Date(invalid)` followed by `setHours(0,0,0,0)` may yield `NaN`. The old equality `NaN === NaN` is false, so **no invalid event matches an invalid target**. A Map key lookup `new Map([[NaN,[0]]]).get(NaN)` would match, yielding a false calendar event. Therefore never index nonfinite/NaN target timestamps or dispatch invalid event timestamps through a Map; alternatively preserve exact original equality on such cases. `Map` is safe for duplicate valid numeric keys, including signed zero, as both Map and `===` equate +0/-0. Do not index by UTC date string or textual `startDate` because the current logic first converts to a **local** midnight under the shell's timezone.

**Isolated analytical differential probe in this research turn — not repository native tests:** A deterministic pure-JS transcription of the exact original date bucketing and the proposed *timed-only* Map subset ran **16,000 cases** with random 0–42 requested dates and 0–84 events, including timed, all-day, duplicate target days, missing/degenerate/end-before-start spans, valid ISO offset timestamps, 2026 month/year and possible DST boundaries, malformed dates, null and non-number date values. Compared every bucket's **event reference identity and event ordering**; **16,000 cases matched, zero observed differences**. Aggregate loop-operation counters within this artificial probe recorded **10,516,348 baseline timed date comparisons vs 503,958 timed key lookups** in the proposed logic, with 1,181,314 total event-to-day insertions and 50,806 invalid timed dates. These are **not CPU cycles, duration, allocations or forecast percentages**, and plain JS does not prove QV4 signal/exception/order parity. The explicit NaN counterexample above demonstrates why an unchecked Map rewrite would be wrong.

**Required QV4/owner oracle:** instrument the actual file's batch method, same `root.events`, and a candidate using the native Quickshell/QV4 runtime; compare per-day array length, **each event object identity/order**, array fresh identity, and event getter count/ordering, including QML proxies/accessors that may be side-effecting or invalidated in-flight. Cases: 0/1/14/30/42 dates, duplicate/malformed days, event counts 0/1/50/1,000/10,000; all-day 1-day, exclusive multi-day and mixed timed; local daylight-saving boundaries, system timezone switches, missing, NaN and type-coerced dates; 2+ simultaneous calendar owners, refresh/disable/source removal, and eventsUpdated trigger cadence. Verify pixel/selection rendering in existing Sidebar and Compact owners, plus future migration owners separately; native behavior/spec regression tests and exact-source validation must pass. Record E_t/A/D, map size, collisions, GC/peak temporary allocation and per-refresh latency **before implementing**. Do not change ICS parser date semantics, persistence, curl fetch cadence, public `getEventsForDate` or all-day algorithm merely to achieve an asymptotic bound.

### R56.2 — Deliberate scope boundaries and promotion-order repair

- The existing R15.1 proposal to **migrate additional consumers** into `_getEventBucketsForDates` is separate. This round optimizes the *internal timed branch of the batch helper already in use*, so it will benefit migrated consumers only if those migrations later occur with their own strict-parity proofs.
- Existing R15.2 Calendar 42/70-cell redundant count/color full scans remain a distinct proposal and must not be counted as solved by this helper.
- The just-committed R54 ScreenTime historical merge and R55 ResourceUsage history list copy candidates are unchanged; both await real QV4/NOTIFY/performance evidence.
- Consolidation hygiene: Round 55 accidentally assigned priority number **131** to both ScreenTime and ResourceUsage. The single canonical promotion list is normalized here to **131 ScreenTime, 132 ResourceUsage**, and this new timed-bucket investigation is **133**. No older priority definitions or runtime files change.

This is source-only research and an isolated analytical JS test. No runtime QML/native code was edited; no repository regression, real QV4, visual-desktop acceptance or live profiler result was obtained; no whole-Hadalis CPU/GPU/RAM/FPS gain is claimed. Continue the following round with pinned native oracles.
## Research continuation — round 57

Baseline: `dev` at `114dc99ca1db584d7200e7a5e0aec49091e6e92f` (Round 56 is the latest canonical section at this read). The repository tree at this SHA contains 3,142 blobs among 3,526 tree entries; directory-wide inventory was used for selection, followed by targeted live-source reads, not a claim of opening every binary/source file. Audit search found no earlier dedicated `_streamMatchScore`, `streamNodeForPlayer`, `playerForStreamNode` or `_volumeTokens` candidate. R23.2 is a **different** MPRIS desktop-entry fuzzy-hint resolver, and R53.1 concerns **EasyEffects sink graph reachability**. Do not conflate these.

Pinned source blobs:

- `services/MprisController.qml`: `3a8184f9308f0816ea395ea26f182bb5a3fbcf15`;
- `modules/sidebarRight/volumeMixer/VolumeMixerEntry.qml`: `3d86e590bd0e633d06bf63a30ed10c4570a3e613`;
- `modules/ii/sidebarRight/volumeMixer/VolumeMixerEntry.qml`: `e7d5415cebd9bba0e74b883e64052ad981e98c17`;
- `modules/sidebarRight/volumeMixer/VolumeDialogContent.qml`: `90134a25b678ab11676c20826164fb0d21a3c595`;
- `modules/waffle/actionCenter/volumeControl/VolumeControl.qml`: `6d41e9b7151040f2f8d4d69d6d9bc9ee8d4156d8`.

### R57.1 — MPRIS stream matching re-normalizes the same 11 PipeWire identity fields for up to three player hints

**HIGH-CONFIDENCE SOURCE-LEVEL DUPLICATE WORK / MEDIUM-PRIORITY, MEASURE FIRST.** `MprisController._streamMatchScore(player,node)` scores one MPRIS player against one PipeWire output stream. It snapshots three player identity hints (`identity`, `desktopEntry`, stripped `dbusName`) and 11 node-side fields (`meta.appName/appId/binary/nodeName`, `node.name/description/nickname`, and four `node.properties` keys). For **each nonempty normalized player hint**, it loops all 11 node values, calls `_volumeKey(nv)`, and for each nonempty result calls `_volumeTokens(nv)`; these node inputs were already captured in the same invocation. The identical lowercasing, regex replacement and token splitting therefore repeat up to **3 × 11 = 33** times per call on the node side, where only 11 distinct node values were captured. This does **not** mean 33 process launches, one frame's measured CPU use or an unbounded background poll.

The matching function feeds both `streamNodeForPlayer` and `playerForStreamNode`. The latter also feeds `streamDesktopEntry`, `streamDisplayName` and `streamIconName` via the per-row mixer UI. Classic and ii volume-entry components request icon and display name separately; the Waffle volume control uses `mixerAppNodes`. These are concrete consumers, but the actual native binding invalidation frequency and number of simultaneously rendered rows have **not** been profiled. The 120 ms `_streamMetadataRefresh` timer is one-shot, not a permanent 120 ms poll, and `pw-dump` is state-triggered; this finding does **not** propose changing that command cadence or the existing debounce.

Narrow strict-lossless experiment: keep the public method and all selection logic unchanged. *Within one call*, after the first nonempty player key has been evaluated, lazily prepare the normalized key and token list for each of the same captured 11 node values; use the prepared pairs for the remaining player hints. Preserve the skip condition for blank node keys and the existing player-hint additive score semantics. Never cache globally by node ID, because node metadata, PipeWire properties, player titles and running/idle state can change. No `Map` of stream->player or reordered resolution is authorized by this finding.

**Pure JavaScript analytical differential probe — NOT an actual repository/QV4 test:** A standalone transcription of the source's key/token functions, media-title comparison, three player hints, 11 node fields, `identity` accumulation and running/idle `total` bonus compared baseline and lazily prepared node normalization over **16,000 seeded generated primitive-value cases** (including blank, mixed case, punctuation, null/undefined, numeric, Unicode and changing `state`). **Zero observed `{identity,total}` mismatches.** Instrumented calls within this synthetic model: baseline **422,708 node-key conversions / 339,176 node-token conversions**, prepared version **174,757 / 140,121**; both made 48,000 player-key conversions and 38,428 player-token conversions. In a fixed fully populated three-hint/11-field example, node-key/token conversions were **33/33 vs 11/11**; calculated matching result was identical. These counters are invocations of instrumented **toy JS functions**, not CPU instructions, wall time, QV4 allocations, real notification counts, or a speedup percentage. The candidate additionally allocates prepared records, which may offset savings for tiny real mixer topologies.

**Semantic and QV4 acceptance gates:** `_volumeKey` uses `String(value ?? "").toLowerCase().replace(...)` and `_volumeTokens` uses `String(...).toLowerCase().split(...).filter(...)`; their invocation order and count can be observed for exotic objects or getters. Capture all current QML/PipeWire value types, coercion, property-getter access and thrown-exception order before treating normalization hoisting as **strict** parity. In particular, later player-hint iterations currently re-coerce each captured `nv`; a value with a mutable or side-effecting `toString()` could produce a different result if reused. Do **not** silently declare those malformed/object states equivalent.

Real acceptance requires a native Quickshell/QV4 fixture with 0/1/many players and output streams, missing/empty/duplicate identity fields, metadata arrival/replacement, a browser plus plasma-browser-integration duplicate, MPD custom bridge, two equally scoring streams with running/idle and audio-volume tie-breaks, hotplug/removal, and rapid source switching. Compare `{identity,total}` for **every candidate pair**, stable first-match/tie resolution, selected `PwNode` **object identity**, `streamDesktopEntry`, labels/icons, and live signal/binding invalidation order for both ii and Waffle volume presentation. Include getter/exception probes before any source change. Instrument score calls per mixer opening/track change/topology update, node normalization counts, wall-clock, QV4 GC/peak allocation and real CPU before/after. Do not substitute equality of final strings for parity of observable selections or signals.

### R57.2 — Scope, priority and non-promotions

- Promotion index **134** is new and independent. R23.2 MPRIS desktop-entry hint memo, R53.1 EasyEffects graph traversal, R55 history-list mutation and R56 Calendar timed-event indexing are unchanged; none is marked done by this research.
- Do **not** broadly memoize `playerForStreamNode`/`streamNodeForPlayer` results across calls. Live PipeWire stream state, dynamic player metadata, duplicate filters, tie-breaks and object lifetime make stale selection possible.
- The MPRIS service already avoids unnecessary `players` and `displayPlayers` reassignments via `_samePlayerOrder`, and its list rebuild is debounced at 50 ms with a separate 1,800 ms empty-list grace. These are existing optimizations and should **not** be reversed or counted as new gains.
- `Network.qml` already uses `Map`/`Set` reconciliation for Wi-Fi AP rows. Its formerly quadratic stale-row scan is not re-promoted from this pass.

**Research only.** No QML, native, IPC, process command, config, display behavior or tests in the repository were changed in this round. No native Quickshell/QV4 run, local maintainer validator, pixel A/B, desktop acceptance or measured Hadalis-wide GPU/RAM/CPU/FPS percentage was performed. Continue with a pinned native matching oracle and actual consumer hit-rate measurement.

## Research continuation — round 58

Baseline: `dev` at `412822dc38f38109f10f07d0f638e63d242f7077`, whose newest canonical entry was R57. The current recursive tree was inventoried (3,142 blobs, 3,526 entries, not truncated). I selected and read representative current service and UI code and searched the entire canonical optimization ledger for the exact methods/paths. This is a repository-wide *inventory and targeted source audit*, **not** a claim that all binary and source contents or all supported desktop configurations were executed. Compared with R57's `0122584b4eb859b52a03ae2430ef2838f6aa599e`, this baseline includes **eight intervening product/test/packaging commits** touching `defaults/config.json`, `modules/abyss/AbyssCorners.qml`, `modules/abyss/companion/AquaPresence.qml`, `modules/common/widgets/WallpaperCrossfader.qml`, two wallpaper regression tests, `scripts/test-aqua-portal-runtime.py` and `sdata/dist-arch/install-deps.sh`. These files were outside the focused R58 candidates; the pinned GlobalActions, ActionModeView, Events and EventsWidget source blobs remained unchanged. This round makes **no claims** about optimization impact of the intervening wallpaper/companion changes. The sole active technical ledger stays here.

Pinned source blobs:

- `services/GlobalActions.qml`: `30c88a1edf2c6f70a2f6471631585e9b8fc566bd`;
- `modules/overview/ActionModeView.qml`: `9b27d18f4b71fef013d7269d1ea22438a9f029b5`;
- `services/Events.qml`: `dcc3671e7c6d640fdbe5d3ee8dce45bc412148e7`;
- `modules/sidebarRight/events/EventsWidget.qml`: `f505dc6331e2f1d56eac547dfe7c4b0e713a162a`;
- `services/Zettelkasten.qml`: `4535cc63176d0c61fdba5afa48adbe4a7474f9eb`;
- `services/WorldClock.qml`: `1260b2d2ed85cf70339c2c8f366c296655dc3c9a`.

### R58.1 — GlobalActions splits a constant fuzzy-search query once per action

**HIGH-CONFIDENCE SOURCE-LEVEL DUPLICATE WORK / REAL-WORLD GAIN MEASURE FIRST.** `GlobalActions.fuzzyQuery(query)` lowercases/trims the argument once but executes `const words = q.split(/\s+/)` *inside* the `allActions.map(action => ...)` callback. The `words` array is never mutated by scoring: it is used only to test `length > 1` and, in that case, calculate `words.filter(w => combined.includes(w)).length`. Consequently, a nonempty query against A actions creates A equivalent token arrays and performs A regex splits, even when the query is one word. `ActionModeView.displayItems` actually invokes this function for nonempty action-mode query text. The action view builds its own result objects and includes package results; this finding does not confuse action-search work with package-search transport or the already-audited R52 package debounce.

Narrow strict-lossless research candidate: for nonempty input, calculate `const words = q.split(/\s+/)` **once outside** the `map`, reuse it as a read-only local inside the callback, and preserve all existing name/description/id/keyword normalization, additive weights, filters, `.sort((a,b) => b.score-a.score)` and final action-reference array. Keep the early empty/whitespace query return of `allActions` exactly: it intentionally returns that same array rather than a fresh one. Preserve QML list<var> return type, action order, tie semantics, action execute closures and category filtering. Do not globally memoize `fuzzyQuery` results or reorder `allActions` publication: translated action labels, feature/config provider toggles, external user-script actions and package-result invalidation have their own ownership/revision boundaries.

**Analytical pure-JS differential probe, not actual QV4:** An isolated, source-shaped transcription generated **16,000** action catalog/query cases with 0–71 actions, blank/single/multiword/whitespace/Unicode queries, missing or mixed-case text fields, custom keyword arrays, scores and exact ties. Compared output action **reference identity and order**. Observed **zero differences**; returned list identity was also preserved for all **4,370** empty-query cases. Instrumented split calls: original **414,136**, hoisted **11,630**. For a fixed 3-action two-word query, **3 → 1 splits** with identical three-result order. These numbers describe only simulated regex split invocations; **no CPU time, memory allocation bytes, shell-wide speedup or native latency** was measured. The one-time split adds a small upfront allocation in a nonempty query with an empty catalog (original map would split zero times); benchmark that distribution rather than assuming benefit for every call.

Native acceptance: QV4/Quickshell execute the actual service method vs a candidate on pinned matching catalog snapshots, including translated strings/config changes, user-script arrival/removal, null/empty and duplicate metadata where the current providers allow it, one-word/multiword/tab/newline searches, equal-score stability and reentrant result bindings. Compare exact returned action-object references, order, `execute` closure identity, `IpcHandler.search` textual row order and `ActionModeView` keyboard selection. Instrument catalog size A, nonempty searches/keystrokes, splits, time and GC/peak allocations at visible UI. Do not weaken the existing debounce or discard score branches.

**Implementation follow-up — 2026-10-08:** `16673fe1b99afd0b93cfa80beba24427e272588a` implements private, per-call **lazy** token reuse in the actual service. It splits at the original first-use position after the first action's metadata reads; an empty catalog still performs zero splits. The frozen pre-change scorer and actual-source Node oracle cover **960 cases**, including sparse catalogs, getter read order, exact action/closure identity, ties, Unicode and blank-query list identity. That workload avoids **16,704 repeated splits**. The real service's native QV4 oracle passes **220 searches** across provider switches and custom/setup publication, with a maximum **62-action catalog**. For a nonempty 62-action catalog, the tokenization step changes **62 → 1 splits (98.39% fewer)**; this is an operation-count reduction, **not** a CPU/RAM/GPU/FPS or visible-latency percentage. There is no persistent cache, scoring/debounce change or approximation. Visible keyboard/IPC interaction and comparable whole-shell resource measurements remain outside these focused oracles; canonical validation is recorded separately on its printed exact SHA.

### R58.2 — Completed local event reminders still parse Date each minute

**HIGH-CONFIDENCE SOURCE-LEVEL CPU OPPORTUNITY IN HISTORICAL-LIST WORK; narrow guard only / QV4 parity pending.** `Events.Component.onCompleted` starts a **60,000 ms repeating** `checkTimer`; every tick `checkDueEvents()` traverses `root.list` at a fixed entry count. After checking that `event.dateTime` is nonempty, it always calls `new Date(event.dateTime).getTime()`, computes the reminder timestamp, checks the reminder-notification branch and then the event-notification/recurrence branch. For plain JSON records whose `notified === true` and `reminderNotified === true`, neither branch can fire, so date conversion is dead work for that invocation. List traversal and timer still occur; this is **not** evidence of an O(1) scheduler or that all retained events are completed.

Guarded experiment: keep `if (!event.dateTime) continue` first; immediately after it, consider `if (event.notified === true && event.reminderNotified === true) continue` for those **two exact booleans only**. Do not skip only on `notified`: a record whose event has been marked notified but whose reminder flag is still false can still enter the reminder branch under a rollback/manual-time edit. Do not skip a record when `reminderMinutes === 0` merely by assumption. Keep unmodified: per-index original traversal/order, fixed `eventCount` even as recurrence `addEvent` appends, `reminderTriggered` / `eventTriggered` arguments and sequence, legacy invalid date handling, `saveToFile` queuing, notification states and all recurrence rules (including DST/month rollover). Avoid an unconditional heap/index: the list is writable, recurrence mutates while scanning, wall clock can jump and late historical/manual edits can rearm reminders.

**Analytical pure-JS differential probe, not actual Events/QV4:** A deterministic source-shaped transcription compared **14,000** generated lists (0–75 records) with varied date strings, invalid dates, both flag values (boolean/missing/legacy falsy/truthy), reminder thresholds and recurrence requests. It modeled identical fixed-count iteration, state writes, signal order, appended recurrence placeholders and end-of-iteration save. Observed **zero list/signal differences** for plain serializable records. Instrumented `Date` conversions: **328,968 baseline vs 322,308** guarded (6,660 calls avoided *within the generated artificial workload*). A two-event fixed example retained the same event/save signal trace while conversions fell **2 → 1**. These are source-model operations, **not CPU percentages or observed time**.

**Explicit non-equivalence for general JavaScript object inputs:** For a completed record whose `dateTime` is an object with side-effecting `toString()`, the current code calls it once through `new Date(dateTime)`, but the guard calls it zero times. This exact probe returned **1 vs 0 toString calls**. The service normally reads plain data from `JSON.parse` in its FileView and constructs ISO strings in `addEvent`; nevertheless direct callers can use `updateEvent` or inject non-plain values. Therefore the proposed guard is **not strictly lossless over every JavaScript object**, even though it matches tested primitive records. A native gate must define/support the actual data-type contract or preserve all observable coercions; do not describe the guard as proven until this boundary is resolved.

Required oracle: pinned real `Events.qml` execution with 0/1/10/1,000/10,000 records, unnotified/reminded/notified/fully-settled combinations, missing malformed date/time, legacy non-booleans, side-effecting or throwing getters where representable, calendar/system clock jumps, DST shifts, changing recurrence, event mutation while scanning, storage reload and edited reminder flags. Compare every synchronous read/exception, emitted object **identity**, `reminderTriggered`/`eventTriggered` order, persistent JSON bytes after `saveToFile`, user-visible notification timing and `EventsWidget` listeners. Measure settled fraction, per-tick Date construction, QV4 CPU/GC and active list size in a live owner session. If the completed fraction is small, reject as low leverage.

### R58.3 — Deliberate non-promotions and status

- `Zettelkasten.qml` executes its Python capture helper on explicit `capture()`, with an **8-second one-shot timeout**, not a background 8-second process poll. Nothing to promote from its `Timer` alone.
- `WorldClock.qml` already ticks at minute precision with a dynamically aligned one-shot and refreshes timezone offsets every **five minutes** only while enabled. The earlier WorldClock catalog/startup work is independent and not reopened.
- `GlobalActions` setup-script scanning was already marked LOW/MEASURE FIRST in R9.5; R58.1 concerns a different synchronous per-query function. No action-run IPC semantic or setup scanner reduction is claimed.
- R57 MPRIS, R56 CalendarSync and R54/R55 ScreenTime/ResourceUsage remain **OPEN, QV4/owner benchmark gated**. R16.1 LocalMusic and R43.2 OrbitalWeather remain **RETIRED / IMPLEMENTED**; no candidate was marked done solely due to a pure-JS model.
- New promotion-order slots are **#135** (`GlobalActions`) and **#136** (`Events`); the latest unmodified previous slot was #134.

**Research-only write**: this round changes neither QML/service/native runtime code nor test fixtures or branch `stable`. No local repo regression, Quickshell/QV4 runtime test, canonical maintainer validator, owner-session visual verification, or whole-Hadalis before/after CPU/GPU/RAM/FPS measurement was executed. Continue into a separate round only with fresh SHA, nonduplicated paths and oracle-qualified evidence.

## Research continuation — round 59

Baseline: `dev` at `c1f8f5ea7a1545b97d5d98fa192f7f737541ee23`; the canonical ledger ended at R58. The recursive tree inventory has 3,142 blobs and 3,526 entries (not truncated). Source-file analysis was targeted, not an assertion that all 3,142 contents were opened. Since the previous source check at `2df34098fed67b0cad59c450effa9186cb8e3046`, concurrent changes were observed in `modules/screenCorners/ScreenCorners.qml`; this unrelated file was not edited.

Pinned blobs:
- `services/Notepad.qml`: `6f17567be8417cef499086138db5884336e2eb3f`;
- `modules/sidebarRight/notepad/NotepadWidget.qml`: `9e301303f455e788652d9e8034ddb196b079a4f5`;
- `services/LyricsService.qml`: `69df76941fa3d0fd7f069d9df6488950eb5972f3`;
- `services/LocalMusic.qml`: `c9abd1f07efda91d9545bd6ea1eda89d970c6c35`;
- `services/Audio.qml`: `a62722abc4d24495e6ee52b56989c18628150582`.

### R59.1 — Notepad duplicate-tab-ID repair repeatedly scans a growing array

**HIGH-CONFIDENCE ALGORITHMIC SOURCE OPPORTUNITY / LOW–MEDIUM PRODUCT PRIORITY / NATIVE PARITY PENDING.** On the storage file's `FileView.onLoaded` path, `Notepad._normalizeTabs(value)` traverses every persisted tab, rejects malformed item shapes, converts `tab.id` to a trimmed string and tests membership in `seenIds` using `Array.includes`. Valid unique tabs cost O(N²) aggregate visited-array positions as the seen-ID array grows, while invalid/duplicate IDs additionally test each generated candidate in the `do…while` loop. This is storage load/reload and migration-repair work, **not per-keystroke or per-frame**.

Narrow strict-lossless proposal: only inside `_normalizeTabs`, use a fresh private `Set` instead of the `seenIds` array; replace `includes(id)` with `has(id)` and `push(id)` with `add(id)`. Do not reorder the input iteration, normalize before membership, change the truthiness short-circuit for empty IDs, or move ID generation out of its `do…while`. Preserve `String(tab.id ?? "")`, `trim()`, titles, bodies, the default numbering based on `normalized.length + 1`, fresh record/array identity, `_normalizedTabsNeedSave`, generated ID collision order, and the exact persisted result. For a non-array top-level value the original method returns immediately **without resetting** `_normalizedTabsNeedSave`; preserve that precondition. Every collected ID is a primitive string, so Set membership and array includes use the same string equality, even with Unicode and unsafe object-property names. Do not replace this with a plain JavaScript object dictionary.

**Standalone seeded pure-JS differential probe (NOT repository/QV4 acceptance):** 16,000 cases of 0–94 tabs or malformed top-level values, with valid and invalid records, blank/duplicate/whitespace/Unicode/numeric IDs, missing/null fields, generated-ID collisions, initial save-flag state, and identical deterministic ID-generator sequences. Baseline and Set candidate matched **16,000/16,000 cases, zero mismatches** in final ordered records, IDs, title/text fields, save-required state and number/order of ID generations. Instrumented membership calls were **805,621 in each version**; the original growing array had an **18,825,044 upper bound** on inspected slots across cases. With 1,500 duplicate IDs, both produced identical outputs and made **2,999 membership calls**, while the original had a **2,248,500 inspected-slot upper bound**. Array slot bounds are deliberately *not exact comparisons* because `includes` can stop early; `Set.has` lookups have different overhead and temporary retained memory. These counts do not measure CPU time, real allocations, GC, frame rate or Hadalis-wide optimization percentages.

Real oracle required before implementation: QV4/Quickshell run actual `Notepad.qml` with 0/1/10/100/1,000/10,000 valid and malformed tabs; duplicate IDs including generator collisions; preservation of error/side-effect order for exotic `String` inputs, Unicode/trim, currentTab selection, `tabsChanged` notifications, fresh object identities, FileView loaded/saved/no-op/error state and exact healed JSON bytes. Check concurrent edits, reloads and mounted `NotepadWidget` editor ID/focus reconciliation. Measure actual size distribution, load latency, QV4 GC/temporary Set RAM and performance crossover. Most ordinary notebooks may have only a few tabs; do not assume a material benefit.

### R59.2 — Paths deliberately not promoted in this continuation

- The visible `NotepadWidget` already coalesces text edits through an **800 ms one-shot** `saveTimer`, compares text before calling `Notepad.setTabTextById` and flushes on relevant editor/tab transitions. The Notepad service serializes and coalesces FileView saves. Thus this round does **not** claim a disk write or full JSON serialization on each keystroke. Altering persistence timing is a separate data-loss/contract investigation, not a proven strict-lossless speedup.
- `LyricsService._indexForPosition` already uses an upper-bound binary search of sorted lyric time points and schedules one-shot lyric transitions. `LocalMusic.localLyricsActiveIndex` is a separate existing R37.2 open candidate; do not duplicate it.
- The four independent PipeWire node-filter projections in `Audio.qml` were already scoped as MEASURE FIRST in R53.3. They are reactive topology projections, not four subprocesses or unconditional per-frame rescans.
- A source-local call-site scan found no invocation of `LocalMusic._trackForIdentity` elsewhere **within that file**. Without proof of live external use, building an index for the entire music library has no established advantage; this path is not promoted.
- Existing R57 MPRIS, R58 GlobalActions and R58 Events candidates remain OPEN with native/QV4 oracles unmet. Round 59 adds only priority **#137** for Notepad's *load-time* ID membership.

**Research only.** No QML/native code, product behavior, timers, persisted config, tests, visual assets or `stable` branch changed. No native QV4 fixture, maintainer validator, live desktop A/B or measured whole-Hadalis GPU/RAM/CPU/FPS performance gain. Continue research with pinned newest source and native acceptance gates.

## Research continuation — round 60

Canonical baseline: `dev` at `ccc8ff79ef132e665c82d2ed313388e9336b2c9c`; previous current canonical section is R59. The recursive tree inventory (3,142 blobs / 3,526 entries, not truncated) plus target source reads covered relevant compositor, Overview, preview, sidebar, dashboard, media and wallpaper paths. This **does not** mean all 3,142 source contents were individually read or the desktop was executed. The task router's historical mention of “Round 60” and DashboardLayout `74.1 predates this canonical append; this section uses the actual last canonical section and promotion order, and does not reopen or duplicate the existing Dashboard layout oracles.

Pinned source blobs:
- `modules/overview/NiriOverviewModel.js`: `fb5296ef7a1acbab04d01eb9302f8df4eaafe8cd`;
- `modules/overview/OverviewNiriWidget.qml`: `79ac2d4d96937d6874fa5fa5a53066e89c1b86f0`;
- `services/NiriService.qml`: `4c8194493fd380bf0ad8c51bc62990ad0c232738`;
- `services/WindowPreviewService.qml`: `2bfca7368179e3f6cbaff32ac0375daa49ab8a38`;
- `modules/dashboard/DashGithub.qml`: `ec35d07e9ca5d8afc1230a33d50740fbf09eb1b4`;
- `modules/sidebarLeft/WallhavenView.qml`: `d96ec750e4aa1c247d658c74bb8f00754998a7fe`.

### R60.1 — Overview per-delegate window-record scans can share a snapshot-local ID index

**HIGH-CONFIDENCE SOURCE ALGORITHMIC OPPORTUNITY; native reactivity/identity oracle and profile required.** The `windowSpace.rebuildWindowItems()` owner computes `windowItems` by calling `OverviewModel.buildWindowItems(NiriService.windows, workspacesForOutput, firstVisibleWorkspaceSlot, workspacesShown)` while presentation is active, and clears it to an empty array when the Overview is inactive. `buildWindowItems` deduplicates window IDs using a `Set`, adds output-local workspace slot/count/geometry metadata to **new plain records**, and returns them as one ordered array. The `ScriptModel` deliberately exposes stable primitive window IDs using `windowItems.map(record => record.id)`, but each delegate's `windowRecord` binding invokes `OverviewModel.findWindowRecord(windowSpace.windowItems, windowItem.windowId)`. The helper calls `records.find(record => record.id === windowId) ?? null`: each reactive delegate lookup linearly scans some/all of a list already built for the same revision. With W visible windows, a full binding evaluation across W delegates can perform O(W²) ID comparisons; this is especially relevant on window topology changes or reflow **while Overview/TaskView is active**, not a background 16-ms/frame timer.

Candidate direction: build **one private first-wins index from the already-constructed `windowItems` snapshot**, once per `windowItems` assignment, and have all delegates read the indexed record by their exact `windowId`. Build lazily/reactively at the existing owner and release on presentation-close when the owner's array clears; do not make a permanent global Niri index. The index must preserve **the same returned record object reference**, fresh snapshot generation, list/`ScriptModel` ID order, selection and drag state, keyboard reflow, workspace indices/count, and preview URLs/capture timing. For canonical Niri window IDs that are positive safe integers, a `Map` keyed by unchanged numeric IDs with `if (!map.has(id)) map.set(id, record)` preserves first-match duplicate semantics. Any noncanonical argument (NaN, infinities, string IDs, objects) should stay on the original linear `find` fallback rather than relying on `Map` SameValueZero; in particular baseline `NaN === NaN` is **false**. Do not index arbitrary raw `NiriService.windows` records: the local `windowItems` are **enriched and output/window-slot filtered**, so R32.3's proposed *public* Niri window-ID index is a distinct ownership and value type. The two gains must not be double-counted.

**Independent pure-JS differential model, not real QML or CPU benchmark:** seeded **16,000** randomly generated record arrays (0–119 rows) and a total of **605,628 lookups**, including duplicate positive IDs, null/string/boolean/object/NaN/infinite IDs and absent IDs. Compared the **exact original result object reference** with a first-wins safe-positive-integer Map + linear fallback. **Zero mismatches**. Instrumentation: original `find` executed **12,915,417** predicate evaluations, the candidate's invalid-ID fallback performed **8,235,619**, alongside **952,369** record reads to build indexes and **237,399** numeric Map lookups. The generated workload contains many noncanonical IDs by design, so do **not** convert this into a purported runtime speedup. Fixed all-valid 100-window/100-lookup fixture: baseline **5,050** predicate evaluations; candidate **100** record reads to build its map and **100** map lookups, preserving all 100 record references. An explicit malformed fixture preserved first duplicate, string-ID vs numeric-ID, zero-ID and NaN non-match behavior. These are synthetic operation counts only; Map object bytes, hash overhead, QV4 execution time and widget CPU/GPU/FPS were not measured.

**Strict-lossless caveats / acceptance:** `find` reads only as far as the first match, whereas constructing an eager index reads *all* records at once; getter side effects or an invalid/holey array could throw or be observed in a different order. The current producer makes fresh plain record literals, but a native QV4 oracle must enforce this provenance or preserve exact malformed-state read/exception behavior. A new derived QML `var` property must also prove its invalidation on every `windowItems` revision happens without stale map/window-record/preview references; the view may refresh `ScriptModel` and delegates in different binding order than JS. Evaluate 0/1/many windows, duplicate IDs, malformed/wrapped IDs if supported, 0/many workspaces, output hotplug, window add/remove/title/focus/layout mutations, fullscreen and rapid Overview/TaskView open/close, drag/reorder, async previews and owner destruction. Compare action functions and actual `PwObject`/Niri record identity where relevant, all delegate geometry, ordering, preview source, `ScriptModel` reuse, input/focus and signal firing. Instrument windowCount, lookup re-evaluation per open/rebuild, QV4 time/GC/peak index RAM and visible frame latency. Reject if savings vanish for typical 1–6-window sessions or index churn dominates.

### R60.2 — Cross-repo scope and deliberate non-promotions

- The previous R32.3 `NiriService.windows` shared lookup is still an **unimplemented separate proposal**: it maps raw published Niri windows, whereas R60.1 maps output-local derived record objects with slot metadata; neither can replace the other without proving consumer value shape and freshness.
- R33/R41's per-output workspace sorting/focused-window projection and R52/R53's already-bounded service paths remain their original open/measure state, **not** counted again as new findings.
- `DashGithub.qml` performs a bounded 26 × 7 Canvas cell loop and caches remote results for 1 hour. A per-paint color lookup could eliminate repeated `Qt.alpha` calls for the four nonzero levels, but the limited repaint frequency and 182-cell bound do not justify a new candidate without actual repaint traces. Do not confuse that with a GPU render-pass reduction.
- `WallhavenView.qml`'s `next` command copies/reverses responses to find the latest matching page, but that code runs on user command rather than a render/keystroke loop; not a priority without huge history evidence.
- R57 MPRIS, R58 GlobalActions/Events and R59 Notepad remain research-only. The only new promotion is **#138**, scoped to an active Overview or TaskView snapshot.

**Research-only write:** no QML/JS runtime, compositor behavior, tests, images, config, native source or `stable` branch is changed. No native QV4 acceptance, canonical validator, desktop compositor session, pixel comparison or whole-Hadalis CPU/GPU/RAM/FPS measurement was performed. Continue with source-SHA-pinned parity evidence and measured workload frequency.

## Research continuation — round 61

Fresh canonical baseline: `dev` at `3ceab81d4e65da25ca3d2fa9ea2313da2fa43b7a`; the preceding canonical section is R60. The full recursive inventory still contains 3,142 blobs / 3,526 Git tree entries, not truncated. This is a **tree-wide inventory and targeted source review**, not a false claim that all 3,142 files were individually opened or desktop-run. General optimization scope remains **RESEARCH ONLY**; no product-code changes are authorized.

Pinned sources:
- `modules/overview/SearchWidget.qml`: `0a932508f950cd83d9f77e9f9bef4b525e39f283`;
- `modules/overview/SearchItem.qml`: `422fc428fe8d5466b000b412cd05251c5e9e2715`;
- `modules/common/functions/StringUtils.qml`: `921893ad2c04de455fd703e538b6e71a4a8b91ef`;
- `services/AppSearch.qml`: `74ea3c9e92860af62f10850c89118d79b7837543`.

### R61.1 — Search results repeat identical seven-prefix stripping inside every delegate

**HIGH-CONFIDENCE DUPLICATE WORK at source level / LOW–MEDIUM estimated product priority / native reactivity and benchmark NOT PROVEN.** `SearchWidget.qml` stores a debounced query in `root.debouncedSearchText`, sets a `ScriptModel` from `root.cachedResults`, and creates `SearchItem` delegates. In every delegate's `query` binding, it constructs a fresh array of the **same seven live prefix properties** (`prefixAction`, `prefixApp`, `prefixClipboard`, `prefixEmojis`, `prefixMath`, `prefixShellCommand`, `prefixWebSearch`), then calls `StringUtils.cleanOnePrefix(root.debouncedSearchText, prefixes)`. The helper tests prefixes *in their original array order*, returns `str.slice(prefix.length)` for the **first matching** `startsWith`, or the original str when none matches. Thus identical text/prefix inputs can be traversed repeatedly once for each created/live SearchItem. This is UI result-delegate work on search/prefix changes, **not an unconditional 60 Hz frame loop**, and the actual `ListView` virtualizes some rows.

Narrow candidate: a single owner property such as `readonly property string displayQuery: StringUtils.cleanOnePrefix(root.debouncedSearchText, [root.prefixAction, root.prefixApp, root.prefixClipboard, root.prefixEmojis, root.prefixMath, root.prefixShellCommand, root.prefixWebSearch])`, then change **only** the delegate `query` binding to `root.displayQuery`. Preserve the exact prefix order and `??` defaults already applied when computing each prefix property; do **not** replace the helper with a “longest prefix” algorithm, a regular expression or a trim/lowercase operation. Overlapping prefixes, an empty string prefix, multi-character symbols and user-configured Unicode prefixes must yield the same raw substring as today. Keep `debouncedSearchText` rather than `searchingText` as the dependency to preserve the visible debounce, Dashboard crossfade and non-App/qalc update timing. Do not alter `SearchItem.highlightContent` or HTML escaping, `ScriptModel` objectProp/key identity, list order, keyboard navigation, actions or cached results. Because inputs are typed QML string properties, the helper is deterministic for a single input snapshot, but **QML evaluation/dependency ordering** still requires a live native oracle.

**Isolated seeded JavaScript differential model, NOT a QV4 acceptance or CPU benchmark:** transcribed the exact `cleanOnePrefix` loop and compared per-delegate calls to a single owner computation on **24,000** query/prefix epochs with 0–51 simulated visible delegates (including 649 no-delegate epochs). Queries and the seven prefixes included blank/overlapping, ASCII, multicharacter, whitespace and Unicode fragments. Compared the full result string for every simulated delegate, with **zero mismatches** across **608,089 delegate evaluations**; five fixed edge cases (empty first prefix, overlapping prefix order, Unicode, unmatched prefix and slash prefix) also passed. Instrumented synthetic operation counts: per-delegate baseline **608,089** fresh prefix arrays, **3,216,156** startsWith checks, **303,570** slices; owner-once model **24,000** arrays, **126,988** startsWith checks, **11,989** slices. These numbers are synthetic and do **not** establish milliseconds saved or a Hadalis-wide CPU, RAM, GPU or FPS percentage. The owner model executes once on a query epoch even with **zero** delegates; in QML a lazily evaluated binding may not, so the lower bound and net gain must be measured with actual visible-row counts.

**Strict-lossless gates before runtime implementation:** pin actual Config prefix updates and `searchPrefixes` object replacements; instrument `query` and `displayContent` properties per delegate after rapid query edits, delayed 60 ms search, zero/one/many virtualized rows, prefix changes while search is open, empty and overlapping prefixes, qalc asynchronous result publication, focus/key Tab/Enter, and embedded Dashboard crossfade. Confirm no stale owner `displayQuery` binding after source changes, and that sharing adds no early/later update or missed QML dependency. Compare rendered escaped/highlighted text character-for-character and focus/selection/order/ScriptModel reuse. Run native QV4/Quickshell with realistic result limits, time per search update, QV4 allocations/GC and no-results case. If typical live delegate fan-out is small or owner invalidation overhead dominates, reject as nonmaterial. No new persistent cache or global service state is needed.

### R61.2 — Other paths examined but NOT newly promoted

- `SearchItem.highlightContent()` lowercases and escapes chunks per row; simplifying those loops risks changing the exact HTML highlight at Unicode case folding, partial matches, and special characters. Keep this separate and measure escape/paint time before proposing a second candidate.
- `SearchWidget.mathProcess`'s stdout handler calls `updateSearchResults()`; for unchanged query it can repeat `AppSearch.fuzzyQuery()` and rebuild result record objects while updating the math row. However, existing action/catalog/config reactivity and new record/closure identities make “reuse all previous app results” **not proven strict-lossless**. Do not implement a cache without a QV4 snapshot revision and async output-order oracle. Previous qalc process spawn-cycle repair remains intact.
- The existing audit already covers Bar Taskbar pinned-lookup comparator scans, Bar Workspace published-window fan-out, and calendar event parse-inside-sort; do not rename those as new candidates. R60 Overview snapshot indexing is also independent.
- Search/Widget work observed here does not override active runtime fixes or permit an unrequested code change. This round promotes only **#139**; all prior open QV4/owner-session gates remain open.

**Research-only artifact:** only `docs/optimization/STRICT_LOSSLESS_GPU_RAM_CPU_AUDIT.md` is intended to change. No production QML/JS/native, tests, animations, configs or `stable` ref changes. No maintainer validator, native QV4 test, physical desktop acceptance or comparable end-to-end CPU/GPU/RAM/FPS benchmark was executed. Continue with new head-pinned source and acceptance evidence.
