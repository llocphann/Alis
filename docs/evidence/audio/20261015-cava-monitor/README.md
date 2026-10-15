# Native CAVA monitor qualification

Runtime source: `77439bddc018cf6e9486c5088f72c76a0efaf060` on Alis `dev`.
Issue: [AUDIO-I01](https://github.com/llocphann/Alis/issues/81).

The repository generator and runner launched one temporary, owned CAVA process.
PipeWire's client secure PID matched the child PID. Its node was passive, had
no `node.latency` property and no `node.always-process` property. The physical
output remained suspended before, during and after capture. CAVA emitted 66
complete silent frames and no malformed frames. The child was terminated after
the bounded probe, and no native analyzer remained.

This was an **idle** host test. Suspended `pw-top` rows show zero quantum/rate;
they do not establish active-playback quantum stability, xrun behavior, audible
quality or online/local overlap acceptance. Nonzero spectrum and the owner's
clip-switch reproduction remain separate gates. Earlier temporary experiments
from before the host restart are not included in this persisted receipt.

The installed shell was `a2d7d0ab3`, PID 1988, throughout this probe. Installed
file hashes and cached CAVA configuration were unchanged. The probe used the
committed repository runner directly; it did not deploy that runner or restart
the installed shell. No presets, routes, volume, global quantum settings or
playback were changed, and no PCM or media labels were retained.

The runner applies its child-only default only when both `PIPEWIRE_PROPS` and
`PIPEWIRE_LATENCY` are unset. Explicit values, including empty values, remain
inherited. Other owner overrides remain inherited too; there is no promise of
a specific quantum in arbitrary environments.

CAVA 1.0.0 sets a native latency request independently of its passive flag.
PipeWire applies `PIPEWIRE_PROPS` before `PIPEWIRE_LATENCY`; a null property
removes the request before creating a new stream. A zero latency numerator is
still a request, not an opt-out. See the exact upstream
[CAVA backend](https://github.com/karlstav/cava/blob/1.0.0/input/pipewire.c),
[PipeWire stream environment handling](https://github.com/PipeWire/pipewire/blob/1.6.9/src/pipewire/stream.c),
[property parsing](https://github.com/PipeWire/pipewire/blob/1.6.9/src/pipewire/properties.c)
and [quantum selection](https://github.com/PipeWire/pipewire/blob/1.6.9/src/pipewire/context.c).

`native-idle-trace.json` is the sanitized observation. `native-idle-probe.py`
records its procedure and requires repository and private output-directory
arguments. It refuses a pre-existing native analyzer or inherited PipeWire
latency/quantum overrides; it does not launch playback. Canonical validation
results are recorded separately at their actual tested SHA.
