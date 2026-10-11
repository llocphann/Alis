# CFG-I02 — raw Config persistence and completion

The exact `b44899d504d106b7a6d65ff16030f583fb3b526d` baseline completes
legacy opacity migration but leaves the custom reinjection write in flight.
The original seven-second diagnostic confirms a later live .73 edit remains
.78 on disk. An explicit flush separately stalls after saving .41, so its
next .73 edit is also lost. The final regression on a clean exact baseline
fails its unchanged 1800ms startup-settle gate (expected exit 1).

The repair avoids reinjecting custom data already present in a complete raw
snapshot, starts guards before potentially synchronous callbacks, and retains
raw-flush intent across overlapping saves. A fresh write-only FileView forces
an actual atomic save when the primary view's cached bytes match; cache equality
is never treated as proof that disk is saved. Its saved/failed callback releases
the flight and destroys that temporary view. A still-running raw operation
blocks another submission, including when the guard has released its lease.

The final actual Config regression passes six cases and each restart: 12
headless processes, private files, actual byte-level JSON disk readbacks, custom
and unknown data, unchanged/overlapping/synchronous saves and denied-write retry.
Existing in-flight mutation, five opacity migration/restart cases and Thinkfan
serialization checks also pass. Source hashes and exact exits are in
[receipt.json](receipt.json). The first candidate's optional-key loss and the
invalid nonvisual QObject inspection remain retained; neither is a product PASS.
The source-spelling Thinkfan assertion is retired in favor of this stronger
actual flush/disk regression; other fan contracts are unchanged.

No owner configuration or clipboard was accessed/changed; no Window, Niri or
GPU workload was created. Canonical qualification of the committed repair and
owner acceptance remain separate; no resource improvement percentage is claimed.
