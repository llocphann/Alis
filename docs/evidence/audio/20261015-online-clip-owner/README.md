# Concurrent local and online playback observation

Owner reports near-continuous crackle/pop when scrolling online clips while Local Music plays, and no crackle in the comparison with Local Music paused. No timestamped audible markers were recorded. Preserve this listening report independently of PipeWire counters.

The first capture ended after about 32 seconds because a fixed pw-top refresh count expired; the retry ran 45.004 seconds but exited 1 because a live packet was incomplete at the deadline. Both receipts remain incomplete. Complete numeric records are retained for limited observation. A later 3-second collector smoke exited 0 after fixes; it does not upgrade either earlier capture or establish audio acceptance.

Physical driver 58/59 remained at 48 kHz with observed quantum 1024/2048 and zero observed ERR deltas. MPD remained running within each window; its identity differs between windows. No CAVA node appeared. Browser node churn differs between windows and must not be treated as the number of clip switches. These observations do not identify a cause or establish an audible cure.

Traces contain the collector whitelist only, without PCM, media titles, URLs or device labels. Runtime identity and original statuses/hashes are retained. Presets, routing and volume were not changed by these captures. Full canonical acceptance at the collector-fix SHAs is not established.

The Owner approved a separate 10-second global EasyEffects bypass comparison. State changed OFF to verified ON and was verified restored OFF; the 14-second surrounding metadata capture exited 0. Owner reports the pop stopped or clearly reduced during bypass while both sources played. This narrows investigation to the effects path or gain/headroom without proving a particular plugin or clipping mechanism. No preset/routing/volume command was issued.
