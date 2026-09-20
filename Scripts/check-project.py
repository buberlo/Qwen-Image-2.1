from pathlib import Path
import json, plistlib
root = Path(__file__).resolve().parent.parent
manifest = json.loads((root / 'App/Resources/Models.json').read_text())
project = (root / 'QwenOffline.xcodeproj/project.pbxproj').read_text()
for resource in ('Models.json', 'NOTICES.txt'):
    assert f'{resource} in Resources' in project, f'{resource} missing from app bundle'
assert manifest['runtimeRevision'] in (root / 'Scripts/bootstrap.sh').read_text()
with (root / 'App/Info.plist').open('rb') as f:
    info = plistlib.load(f)
assert info['NSPhotoLibraryAddUsageDescription']
print('PASS: app resource membership, runtime pin, and Photos permission description')
