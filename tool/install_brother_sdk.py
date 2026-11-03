#!/usr/bin/env python3
"""Install the unchanged official Brother 4.13.2 Android redistributable.
The proprietary SDK binary is embedded in the APK, never included in source ZIPs.
"""
import argparse
import hashlib
import io
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / 'android/app/libs/BrotherPrintLibrary.aar'
SHA256 = 'def6bccc7415da38b771186d571757c0a44add5358b6dc7a1855fff77bced64e'
URL = 'https://download.brother.com/welcome/dlfp100900/bpsdkaall4132.zip'

def find_library(data, depth=0):
    if depth > 4: raise RuntimeError('Unexpected SDK archive structure.')
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        for entry in archive.infolist():
            if entry.filename.endswith('/libs/BrotherPrintLibrary.aar'):
                return archive.read(entry)
        for entry in archive.infolist():
            if entry.filename.lower().endswith('.zip') and 'bpsdka' in entry.filename.lower():
                found = find_library(archive.read(entry), depth+1)
                if found: return found
    return None

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--accept-brother-license', action='store_true', help='Confirm you reviewed and accept the official Brother SDK EULA in assets/licenses.')
    args = p.parse_args()
    if TARGET.exists() and hashlib.sha256(TARGET.read_bytes()).hexdigest() == SHA256:
        print('Brother SDK 4.13.2 is already installed and verified.')
    else:
        if not args.accept_brother_license:
            raise SystemExit('Review assets/licenses/Brother-SDK-EULA.txt, then pass --accept-brother-license.')
        with urllib.request.urlopen(URL, timeout=90) as response:
            archive = response.read(80_000_001)
        if len(archive)>80_000_000: raise SystemExit('Unexpected SDK download size.')
        data = find_library(archive)
        if data is None or hashlib.sha256(data).hexdigest() != SHA256:
            raise SystemExit('Official SDK checksum mismatch. No binary installed.')
        TARGET.parent.mkdir(parents=True, exist_ok=True)
        temporary = TARGET.with_suffix('.tmp')
        temporary.write_bytes(data)
        temporary.replace(TARGET)
        print('Installed verified Brother SDK 4.13.2 runtime.')
