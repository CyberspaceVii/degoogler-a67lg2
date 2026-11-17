#!/usr/bin/env python3
"""Build the read-only package helper and a reproducible, standalone module ZIP."""
import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
sdk = Path(os.environ.get('ANDROID_SDK_ROOT', '/opt/android-sdk'))
android = Path(os.environ.get('ANDROID_JAR', str(sdk / 'platforms/android-37.0/android.jar')))
d8 = os.environ.get('D8', str(sdk / 'build-tools/37.0.0/d8'))
with tempfile.TemporaryDirectory(prefix='package-probe-') as directory:
    work = Path(directory)
    subprocess.run([os.environ.get('JAVAC', 'javac'), '--release', '11', '-classpath', str(android),
                    '-d', str(work), str(ROOT / 'source/PackageProbe.java')], check=True)
    dex = work / 'dex'
    dex.mkdir()
    subprocess.run([d8, '--min-api', '28', '--lib', str(android), '--output', str(dex),
                    str(work / 'PackageProbe.class')], check=True)
    payload = (dex / 'classes.dex').read_bytes()
    (ROOT / 'package-probe.dex').write_bytes(payload)
files = ['module.prop', 'customize.sh', 'configure.sh', 'lib.sh', 'service.sh', 'uninstall.sh',
         'targets.txt', 'trusted-signers.txt', 'package-probe.dex', 'README.md', 'CHANGELOG.md', 'VALIDATION.md', 'LICENSE']
if (ROOT / 'post-fs-data.sh').exists():
    files.append('post-fs-data.sh')
args.output.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(args.output, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for name in sorted(files):
        info = zipfile.ZipInfo(name, (2026, 11, 17, 0, 0, 0))
        info.external_attr = (0o100755 if name.endswith('.sh') else 0o100644) << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, (ROOT / name).read_bytes(), compresslevel=9)
print(hashlib.sha256(args.output.read_bytes()).hexdigest(), args.output)
