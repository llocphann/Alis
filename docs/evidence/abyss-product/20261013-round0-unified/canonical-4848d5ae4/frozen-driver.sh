#!/bin/bash
set -uo pipefail
export PATH=/usr/lib/qt6/bin:$PATH
export CARGO_BUILD_JOBS=2
export ALIS_VALIDATION_LOG=/tmp/alis-round0-canonical-4848d5ae462846db623a49e502b9515fe468a557.log
cd /tmp/alis-r13-gated-exact-20261013
bash scripts/validate-maintainer-local.sh --current-repo --strict-qml
