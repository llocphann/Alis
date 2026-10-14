#!/usr/bin/env python3
"""Exercise production cleanup decisions without signalling real processes."""
from pathlib import Path
import os
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    source = (ROOT / "scripts/alis").read_text()
    # Load just the production functions; do not run the launcher's CLI.
    functions = []
    for name in ("alis_cleanup_owns_pid", "cleanup_service_processes"):
        match = re.search(r"^" + name + r"\(\) \{\n.*?^\}", source, re.M | re.S)
        assert match, name
        functions.append(match.group())
    harness = r'''
set -euo pipefail
systemctl() { printf 'MainPID=%s\nControlGroup=%s\n' "$MAIN_PID" "$UNIT_GROUP"; }
pgrep() {
    if [[ "$1" == -x ]]; then printf '101\n201\n301\n401\n501\ninvalid\n'
    elif [[ "$2" == scripts/thumbnails/* ]]; then printf '103\n203\n104\n'
    else printf '102\n202\n'; fi
}
cat() { command cat "$FIXTURE/proc/${1#/proc/}"; }
kill() {
    if [[ "$1" == -0 ]]; then return 0; fi
    local mode=TERM pid="$1"
    if [[ "$1" == -KILL ]]; then mode=KILL; pid="$2"; fi
    printf '%s %s\n' "$mode" "$pid" >> "$FIXTURE/signals"
    # Simulate an ownership change/PID reuse during the escalation grace period.
    if [[ "$mode" == TERM && "$pid" == 104 ]]; then
        printf '0::/user.slice/other.service\n' > "$FIXTURE/proc/104/cgroup"
    fi
}
cleanup_service_processes
'''
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)
        group = "/user.slice/user-1000.slice/user@1000.service/app.slice/alis.service"
        for pid, cg in {101:group, 102:group, 103:group, 104:group,
                        201:"/user.slice/unrelated.service", 202:"/user.slice/apps.scope",
                        203:"/user.slice/worker.service", 301:group+"-other",
                        401:group+"/child"}.items():
            folder = base / f"proc/{pid}"
            folder.mkdir(parents=True)
            (folder / "cgroup").write_text(("5:cpu:/unrelated\n9:name=systemd:" if pid == 401 else "0::") + cg + "\n")
        script = "\n".join(functions) + "\n" + harness
        def run(main_pid, unit_group):
            (base / "signals").write_text("")
            env = dict(os.environ, FIXTURE=tmp, MAIN_PID=str(main_pid), UNIT_GROUP=unit_group)
            subprocess.run(["bash", "-c", script], env=env, check=True, timeout=5,
                           capture_output=True, text=True)
            return (base / "signals").read_text().splitlines()
        assert run(100, group) == [], "healthy service descendants must survive"
        assert run(0, "") == [], "unknown ownership must fail closed"
        assert run(0, group+"-other") == [], "similar unit name is not ownership"
        signals = run(0, group)
        assert signals == ["TERM 101", "TERM 401", "TERM 102", "TERM 103", "TERM 104", "KILL 103"], signals
    print("PASS: cleanup only signals stopped-service owners; independent sessions/jobs, healthy descendants, missing ownership and reused PIDs survive")


if __name__ == "__main__":
    main()
