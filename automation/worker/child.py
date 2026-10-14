"""Fsync child identity before exec; die with the runner, including the spawn gap."""
import ctypes
import json
import os
from pathlib import Path
import signal
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from automation.manager.store import _write
from automation.worker.process import process_identity

expected=int(sys.argv[1]);path=Path(sys.argv[2])
libc=ctypes.CDLL(None,use_errno=True)
if libc.prctl(1,signal.SIGKILL,0,0,0)!=0 or os.getppid()!=expected:
    raise SystemExit(125)
intent=json.loads(path.read_text())
intent.update(phase="executing",process=process_identity(os.getpid()))
_write(path,intent)
os.execvpe(sys.argv[3],sys.argv[3:],os.environ)
