# Audio transition trace

For an owner-controlled reproduction, leave the same Local Music track playing
and keep the original DSP preset, route and volume unchanged. This command only
observes PipeWire; it does not start playback or change those settings:

```sh
python3 scripts/collect-audio-transition-trace.py /tmp/alis-audio-transition.jsonl --duration 45 --markers
```

Use a new output filename each time. During the bounded capture, optionally type
one marker per line: `new-online-clip`, `heard-crackle`, `ui-open`, or `ui-close`.
Marker timing is approximate; other input is discarded without being recorded.
Switch online clips yourself while the local track continues unchanged. Repeat
separate controlled cases for local-only, online-only, overlapping playback and
paused online playback. The tool does not authorize preset/bypass or volume changes.

The private file (mode 0600, exclusive creation) contains UTC and monotonic receipt
times, numeric node/serial and link/endpoints, whitelisted media class/state and
client-binary categories, numeric requested node latency, passive/always-process
and driver booleans/driver ID, plus mature `pw-top` quantum/rate/ERR samples. `local`
means an MPD client, not proof of its track or content. Names, titles, URLs,
device labels, raw arguments, raw tool output and audio/PCM are excluded. The
collector's own SHA-256 is retained; separately record the exact installed shell
SHA and confirm runtime identity stayed unchanged for the reproduction.

The first `pw-top` frame, non-running/zero-quantum rows and missing/reused node
identities are rejected. A first mature counter is a baseline, never an xrun
delta; decreasing counters reset the baseline. ERR combines errors and xruns,
so even a positive delta does not identify which one occurred. Driver rows show
actual graph quantum/rate; follower rows show their suggestions. Use driver
properties and link identities to interpret them, not media class alone. IDs can be
joined to graph events using serials. Graph changes invalidate samples if an ID
changes identity during the observed frame.

Capture lasts at most 60 seconds, followed by bounded child cleanup. Input,
object count and output size (4 MiB) are limited. Unsupported `pw-top` formats,
missing tools, premature tool exits or bounds fail closed with a nonzero exit.
Missing/reused identities reject affected rows; a run with fewer than two frames
or zero accepted mature samples is incomplete. Output must end with a `complete`
record containing accepted/rejected counts. Exit 0 means collection completed;
it is not active-playback, listening or owner acceptance. `--interval` bounds the event-loop wait; it
does not increase `pw-top`'s sampling frequency. Receipt timestamps are not
sample-accurate audio timing; top frames retain their header-receipt time as well
as their completion time, and short transitions can fall between samples.
Correlate the owner's marker with node/link events and mature ERR **deltas**.
This trace alone cannot prove clipping, limiter behavior, a cause or an audible cure.
