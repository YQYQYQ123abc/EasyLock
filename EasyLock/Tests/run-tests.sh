#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
engine_sources=(EasyLock/FileMetadata.swift EasyLock/LockEngine.swift EasyLock/LockTransactions.swift EasyLock/OperationControl.swift EasyLock/StreamArchive.swift EasyLock/TransactionRecovery.swift EasyLock/SpacePreflight.swift EasyLock/RecoveryKey.swift EasyLock/RestoreCopy.swift EasyLock/PasswordCredential.swift)
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/easylock-validation.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
for suite in EngineTests InPlaceTests MetadataPolicyTests StreamRecoveryTests ReleaseSafetyTests; do
  xcrun swiftc -module-cache-path /tmp/EasyLock-module-cache "${engine_sources[@]}" "Tests/$suite.swift" -o "$work_dir/$suite"
  "$work_dir/$suite"
done
xcrun swiftc -module-cache-path /tmp/EasyLock-module-cache EasyLock/FileRenameMonitor.swift Tests/RenameMonitorTests.swift -o "$work_dir/RenameMonitorTests"
"$work_dir/RenameMonitorTests"

xcrun swiftc -module-cache-path /tmp/EasyLock-module-cache EasyLock/FileDropReader.swift Tests/FileDropTests.swift -o "$work_dir/FileDropTests"
"$work_dir/FileDropTests"

xcrun swiftc -module-cache-path /tmp/EasyLock-module-cache EasyLock/AutoLockController.swift Tests/AutoLockTests.swift -o "$work_dir/AutoLockTests"
"$work_dir/AutoLockTests"

xcrun swiftc -module-cache-path /tmp/EasyLock-module-cache PreviewShared/LockedPreview.swift Tests/PreviewPrivacyTests.swift -o "$work_dir/PreviewPrivacyTests"
"$work_dir/PreviewPrivacyTests"
xcrun swiftc -module-cache-path /tmp/EasyLock-module-cache EasyLock/ExternalFileRequests.swift Tests/ExternalFileRequestsTests.swift -o "$work_dir/ExternalFileRequestsTests"
"$work_dir/ExternalFileRequestsTests"

xcrun swiftc -module-cache-path /tmp/EasyLock-module-cache EasyLock/LicenseReceipt.swift Tests/LicenseReceiptTests.swift -o "$work_dir/LicenseReceiptTests"
"$work_dir/LicenseReceiptTests"

xcrun swiftc -module-cache-path /tmp/EasyLock-module-cache EasyLock/SensitiveClipboard.swift Tests/SensitiveClipboardTests.swift -o "$work_dir/SensitiveClipboardTests"
"$work_dir/SensitiveClipboardTests"

xcrun swiftc -module-cache-path /tmp/EasyLock-module-cache EasyLock/PanelCoordinator.swift Tests/PanelCoordinatorTests.swift -o "$work_dir/PanelCoordinatorTests"
"$work_dir/PanelCoordinatorTests"
