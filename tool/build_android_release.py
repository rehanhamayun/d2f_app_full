#!/usr/bin/env python3
"""Build a signed ARM64 release in a disposable workspace.

The current Flutter SDK can generate a release registrant containing the
integration_test dev plugin while Gradle excludes that plugin. Exclude only that
SDK test dependency from this disposable release pubspec; keep the real source,
lockfile and integration tests intact. Private signing files remain local.
"""
from pathlib import Path
import hashlib
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
flutter = shutil.which('flutter')
if not flutter:
    raise SystemExit('Install Flutter and add it to PATH before building.')
pubspec = (ROOT / 'pubspec.yaml').read_text()
version = re.search(r'^version:\s*(\S+)', pubspec, re.M).group(1)
api = os.environ.get('D2F_API_BASE_URL', 'https://d2f-api-production.up.railway.app')
if not api.startswith('https://'):
    raise SystemExit('Release API origin must use HTTPS.')
with tempfile.TemporaryDirectory(prefix='d2f-android-release-') as directory:
    stage = Path(directory)
    for name in ['lib', 'assets', 'android']:
        shutil.copytree(ROOT / name, stage / name,
            ignore=shutil.ignore_patterns('.gradle', '.kotlin', 'build', '*.iml', 'GeneratedPluginRegistrant.java'))
    shutil.copy2(ROOT / 'pubspec.lock', stage / 'pubspec.lock')
    shutil.copy2(ROOT / 'analysis_options.yaml', stage / 'analysis_options.yaml')
    (stage / 'pubspec.yaml').write_text(re.sub(r'^  integration_test:\n    sdk: flutter\n', '', pubspec, flags=re.M))
    # Existing key.properties resolves this relative path from android/app.
    key = ROOT / '.local/d2f-release.jks'
    if key.exists():
        (stage / '.local').mkdir(mode=0o700)
        shutil.copy2(key, stage / '.local/d2f-release.jks')
        (stage / '.local/d2f-release.jks').chmod(0o600)
    subprocess.run([flutter, 'pub', 'get', '--offline'], cwd=stage, check=True)
    subprocess.run([flutter, 'build', 'apk', '--no-pub', '--release', '--split-per-abi',
        '--target-platform', 'android-arm64', '--dart-define=API_BASE_URL=' + api], cwd=stage, check=True)
    artifact = ROOT / 'output/apk' / f'D2F-Global-{version}-arm64-v8a.apk'
    artifact.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(stage / 'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk', artifact)
    digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
    artifact.with_suffix('.apk.sha256').write_text(f'{digest}  {artifact.relative_to(ROOT)}\n')
    print('Release APK:', artifact)
    print('SHA-256:', digest)
