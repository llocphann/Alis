#!/bin/bash
set -uo pipefail
export PATH=/usr/lib/qt6/bin:$PATH
export CARGO_BUILD_JOBS=2
export HADALIS_VALIDATION_LOG=/tmp/alis-region-canonical-180b9682e803197ce6c1ca1ee81ed6add842f5f0.log
cd /tmp/alis-popup-region-exact-20261013
bash scripts/validate-maintainer-local.sh --current-repo --strict-qml
