#!/usr/bin/env python3
"""Check shipping app/extension entitlements and accidental license-client inclusion."""
import pathlib
import plistlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1]).resolve()
assert app.is_dir() and app.suffix == '.app', 'Provide a built EasyLock.app'
bundles = [app, *sorted((app / 'Contents/PlugIns').glob('*.appex'))]
assert len(bundles) == 4, 'Expected the app and three extensions'
for bundle in bundles:
    raw = subprocess.check_output(['codesign', '-d', '--entitlements', ':-', str(bundle)], stderr=subprocess.DEVNULL)
    entitlements = plistlib.loads(raw)
    assert entitlements.get('com.apple.security.app-sandbox'), f'Sandbox missing: {bundle.name}'
    for key in ('com.apple.security.network.client', 'com.apple.security.network.server'):
        assert not entitlements.get(key), f'Network permission present: {bundle.name}'
    manifest_path = bundle / 'Contents/Resources/PrivacyInfo.xcprivacy'
    assert manifest_path.is_file(), f'Privacy manifest missing: {bundle.name}'
    manifest = plistlib.loads(manifest_path.read_bytes())
    assert manifest.get('NSPrivacyTracking') is False
    assert manifest.get('NSPrivacyTrackingDomains') == []
    assert manifest.get('NSPrivacyCollectedDataTypes') == []
    expected = {
        'EasyLock.app': {'FileTimestamp': {'C617.1', '3B52.1'}, 'SystemBootTime': {'35F9.1'},
                         'DiskSpace': {'E174.1', '85F4.1'}, 'UserDefaults': {'CA92.1'}},
        'EasyLockPreview.appex': {'FileTimestamp': {'3B52.1'}},
        'EasyLockThumbnail.appex': {'FileTimestamp': {'3B52.1'}},
        'EasyLockWidget.appex': {},
    }[bundle.name]
    declarations = manifest['NSPrivacyAccessedAPITypes']
    actual = {entry['NSPrivacyAccessedAPIType']: set(entry['NSPrivacyAccessedAPITypeReasons']) for entry in declarations}
    assert len(actual) == len(declarations), f'Duplicate privacy categories: {bundle.name}'
    assert actual == {'NSPrivacyAccessedAPICategory' + key: value for key, value in expected.items()}, f'Privacy declarations differ: {bundle.name}'
    if bundle == app:
        policy = bundle / 'Contents/Resources/PrivacyPolicy.txt'
        assert policy.is_file() and '免费离线版' in policy.read_text(), 'Bundled privacy policy missing'
    info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
    executable = bundle / 'Contents/MacOS' / info['CFBundleExecutable']
    symbols = subprocess.check_output(['nm', '-a', str(executable)], stderr=subprocess.DEVNULL)
    for marker in (b'LicenseStore', b'LicenseView', b'RejectLicenseRedirects', b'URLSession'):
        assert marker not in symbols, f'Unexpected network/license symbol {marker!r}: {bundle.name}'
    print(f'PASS offline build: {bundle.name}')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print('PASS bundle signature integrity (does not establish distribution signing or notarization)')
