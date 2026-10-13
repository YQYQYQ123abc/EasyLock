#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/easylock-sandbox-validation.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
app_dir="$work_dir/EasyLockSandboxTests.app"
mkdir -p "$app_dir/Contents/MacOS"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.easylock.sandbox-regression</string>
<key>CFBundleExecutable</key><string>SandboxTests</string>
<key>LSFileQuarantineEnabled</key><true/>
</dict></plist>
PLIST
cat > "$work_dir/entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
</dict></plist>
PLIST
xcrun swiftc -module-cache-path /tmp/EasyLock-module-cache EasyLock/FileMetadata.swift EasyLock/LockEngine.swift EasyLock/LockTransactions.swift EasyLock/OperationControl.swift EasyLock/StreamArchive.swift EasyLock/TransactionRecovery.swift EasyLock/SpacePreflight.swift EasyLock/RecoveryKey.swift EasyLock/RestoreCopy.swift EasyLock/PasswordCredential.swift Tests/SandboxQuarantineTests.swift -o "$app_dir/Contents/MacOS/SandboxTests"
codesign --force --sign - --entitlements "$work_dir/entitlements.plist" "$app_dir"
"$app_dir/Contents/MacOS/SandboxTests"
