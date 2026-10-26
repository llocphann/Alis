#!/usr/bin/env python3
"""Parser fallback rejects syntax diagnostics even if qmllint exits zero."""
from pathlib import Path
import importlib.util
import os
import tempfile

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("qml_check", root / "scripts/lib/qml-syntax-check.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as directory:
    stage = Path(directory)
    parser = stage / "qmlformat"
    linter = stage / "qmllint"
    fixture = stage / "Fixture.qml"
    fixture.write_text("import QtQuick\nQtObject { property string id: \"\" }\n")
    parser.write_text("#!/bin/sh\nexit 1\n")
    linter.write_text('''#!/usr/bin/env python3
import json,os,sys
if '--version' in sys.argv:
    print('qmllint 6.11.2'); raise SystemExit(0)
mode = os.environ['ALIS_PARSER_FIXTURE']
warning = {'id':'syntax','type':'warning'} if mode == 'syntax' else {'id':'unused-imports','type':'info'}
print(json.dumps({'files':[{'filename':sys.argv[-1],'success':mode == 'valid','warnings':[warning]}]}))
''')
    parser.chmod(0o755); linter.chmod(0o755)
    for mode in ("valid", "syntax", "failed"):
        os.environ["ALIS_PARSER_FIXTURE"] = mode
        assert module.check(str(parser), str(fixture)) == (mode == "valid")
    parser.write_text("#!/bin/sh\nexit 0\n")
    assert module.check(str(parser), str(fixture))
    del os.environ["ALIS_PARSER_FIXTURE"]
print("ok - Qt syntax diagnostics are authoritative over formatter round-trip and exit status")
