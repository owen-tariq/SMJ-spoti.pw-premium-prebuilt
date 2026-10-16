# SPDX-License-Identifier: MIT
"""Verify that the two pre-existing files we edited came from the reusable GPL snapshot.
This is a provenance check for these two files, NOT a licence audit of the entire fork.
"""
import subprocess
from pathlib import Path

GPL_BASE = 'a08b38b9e293f0893e92ff7a9b7b9d92f903431a'
FORK_BASE = '8f4342e2f219ed64e4a0bed938f64595c5bd70d1'
FILES = (
    'tweak/Sources/Redesigned/Kit/SGRTokens.m',
    'tweak/Sources/Redesigned/Kit/SGRAppearanceSettings.m',
)


def blob(ref, path):
    return subprocess.check_output(['git', 'show', f'{ref}:{path}'])


license_text = blob(GPL_BASE, 'LICENSE')
assert b'GNU GENERAL PUBLIC LICENSE' in license_text
assert b'Version 3' in license_text
for path in FILES:
    original = blob(GPL_BASE, path)
    assert original == blob(FORK_BASE, path), f'Pre-edit provenance mismatch: {path}'
    assert Path(path).read_text().startswith('// SPDX-License-Identifier: GPL-3.0-only')
    print(f'GPL snapshot matches pre-edit fork file: {path}')
print('Two-file provenance check passed; the whole fork has NOT been relicensed.')
