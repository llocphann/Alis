#!/usr/bin/env python3
"""Native Qt 5 INI interoperability; starts QCoreApplication, never Office/GUI.

All settings, binaries and HOME/XDG directories are disposable synthetic data.
This is a settings-format gate, not an ONLYOFFICE visual acceptance result.
"""
import importlib.util
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/colors'))
import office_theme as office

CPP = r'''
#include <QCoreApplication>
#include <QSettings>
#include <QJsonDocument>
#include <QJsonObject>
#include <QFile>
#include <QTextStream>
int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    QSettings settings(QSettings::NativeFormat, QSettings::UserScope, "onlyoffice", "DesktopEditors");
    if (argc > 1) {
        settings.setValue("Language", "vi");
        settings.setValue("Other/Fixture", QString::fromUtf8("Giữ nguyên"));
        settings.sync();
    }
    QJsonObject result;
    result["selector"] = settings.value("UITheme").toString();
    result["language"] = settings.value("Language").toString();
    result["other"] = settings.value("Other/Fixture").toString();
    result["path"] = settings.fileName();
    result["status"] = int(settings.status());
    QTextStream(stdout) << QJsonDocument(result).toJson(QJsonDocument::Compact) << '\n';
    return settings.status() == QSettings::NoError ? 0 : 1;
}
'''


def main():
    if not shutil.which('g++') or not shutil.which('pkg-config'):
        print('SKIP: native Qt 5 settings gate requires g++ and Qt5Core development metadata')
        return 77
    flags = subprocess.run(['pkg-config', '--cflags', '--libs', 'Qt5Core'], capture_output=True, text=True)
    if flags.returncode:
        print('SKIP: Qt5Core development metadata unavailable')
        return 77
    with tempfile.TemporaryDirectory(prefix='alis-office-qt-') as temporary:
        base = Path(temporary)
        source, binary = base / 'probe.cpp', base / 'probe'
        source.write_text(CPP)
        subprocess.run(['g++', '-fPIC', '-std=c++17', str(source), '-o', str(binary), *shlex.split(flags.stdout)], check=True, timeout=45)
        config_home, data_home, state_home = [base / name for name in ('config', 'data', 'state')]
        env = {**os.environ, 'HOME': str(base), 'XDG_CONFIG_HOME': str(config_home),
               'XDG_DATA_HOME': str(data_home), 'XDG_STATE_HOME': str(state_home)}
        config = config_home / 'onlyoffice/DesktopEditors.conf'
        config.parent.mkdir(parents=True)
        config.write_bytes(b'[General]\nUITheme=theme-night\n')
        palette = {'background': '#112233', 'on_surface': '#eeeeff', 'surface': '#223344',
                   'outline': '#778899', 'primary': '#aabbcc', 'on_primary': '#000011',
                   'on_surface_variant': '#aabbcc'}
        with patch.object(office, 'app_busy', return_value=False):
            office.update_onlyoffice(config_home, data_home, state_home, True, palette, '9.4.0-1')
            def read(*args):
                result = subprocess.run([str(binary), *args], env=env, capture_output=True, text=True, check=True, timeout=10)
                return json.loads(result.stdout)
            result = read()
            assert result['selector'] == 'alis-auto.json', result
            assert result['path'] == str(config), result
            result = read('edit-unrelated-preferences')
            assert result['language'] == 'vi' and result['other'] == 'Giữ nguyên', result
            palette['primary'] = '#bbccdd'
            office.update_onlyoffice(config_home, data_home, state_home, True, palette, '9.4.0-1')
            office.update_onlyoffice(config_home, data_home, state_home, False, {}, None)
            result = read()
            assert result['selector'] == 'theme-night', result
            assert result['language'] == 'vi' and result['other'] == 'Giữ nguyên', result
        version = subprocess.check_output(['pkg-config', '--modversion', 'Qt5Core'], text=True).strip()
        print('QSETTINGS_INTEROP_PASS', json.dumps({'qt_version': version, 'selector_read': True,
              'native_unrelated_edits_preserved': True, 'selector_restored': True,
              'office_application_started': False, 'owner_profile_accessed': False}))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
