import Foundation
import WidgetKit

/// Only an opt-in count is shared; never file names, paths, bookmarks or credentials.
enum WidgetSummary {
    struct Snapshot: Codable { let count: Int?; let updated: Date }
    static func publish(count: Int) {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "EasyLockWidgetGroup") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return }
        let url = container.appendingPathComponent("summary.json")
        let summary = Snapshot(count: UserDefaults.standard.bool(forKey: "widgetShowCount") ? max(0, count) : nil, updated: Date())
        do {
            try JSONEncoder().encode(summary).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            WidgetCenter.shared.reloadTimelines(ofKind: "EasyLockQuickAccess")
        } catch { /* Widget availability must never fail a file operation. */ }
    }
}
