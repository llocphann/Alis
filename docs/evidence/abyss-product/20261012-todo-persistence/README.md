# Internal Todo durable writes

Unchanged backend at **37461128a446c8a0a797bcc412377dc2068fb1c6** loses
JSON updates: memory/TXT contain two tasks, JSON remains `[]`, save/queued
flags remain held. [Baseline disk receipt](baseline.json), [raw log](baseline.log).
The same new regression fails its original 1800ms startup-settle deadline
on that baseline, exit 1: [negative-control log](baseline-oracle.log).

Repair releases writes only on saved/failed receipts, coalesces later edits,
ignores unchanged *acknowledged* bytes, defers refresh through pending saves
and uses a fresh write-only view to retry bytes cached by a failed write.
Failed edits remain in memory with visible error feedback; migration stays
blocked until their canonical JSON is actually durable. Explicit refresh or
a subsequent user edit retries; no background retry loop is introduced.

Actual private headless Quickshell: **6 startup/restart processes, 77 QML
assertions and independent disk readbacks PASS, exit 0**. Covers missing and
existing storage, rapid Add/Done/Unfinished/Delete, repeated no-ops, refresh
while writes overlap, denied-write failure/retry, external TXT edit without
rewrite, and restart of the same store. [Summary](focused.log),
[process receipts](native-results.json), [source hashes](receipt.json).
Existing facade, optional settings and backend-feedback contracts also pass.

No owner files/preferences, optional backend activation or windows were changed.
Current committed canonical and owner desktop persistence remain separate gates.
