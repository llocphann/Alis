# Interrupted validation driver

Source `8edd331797771924435a91ed1ed8abac382490c2` was tested in a clean clone, but the outer Bash validator was edited during execution to add the next material gate. The driver ended at check 232 with an unexpected quoted EOF, exit 2. **INTERRUPTED_DRIVER_ERROR; no full canonical result.** [Partial log](partial.log), [driver output](driver-output.log), [receipt](receipt.json).

Retain the partial positives within their scope; they do not turn this run or earlier runs into PASS. Subsequent runs must execute a frozen copy of the exact committed driver, or run from an immutable exact-source checkout. The next changed material source still needs its own complete qualification.
