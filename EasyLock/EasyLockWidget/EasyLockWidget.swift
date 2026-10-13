import SwiftUI
import WidgetKit

struct Entry: TimelineEntry { let date: Date; let count: Int?; let updated: Date? }
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, count: nil, updated: nil) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(context.isPreview ? placeholder(in: context) : read()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) { completion(Timeline(entries: [read()], policy: .after(.now.addingTimeInterval(900)))) }
    private func read() -> Entry {
        struct Snapshot: Decodable { let count: Int?; let updated: Date }
        guard let group = Bundle.main.object(forInfoDictionaryKey: "EasyLockWidgetGroup") as? String,
              let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group),
              let data = try? Data(contentsOf: directory.appendingPathComponent("summary.json")),
              let summary = try? JSONDecoder().decode(Snapshot.self, from: data),
              summary.count.map({ $0 >= 0 }) ?? true else { return Entry(date: .now, count: nil, updated: nil) }
        return Entry(date: .now, count: summary.count, updated: summary.updated)
    }
}
struct WidgetContent: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 9) {
                Label("EasyLock", systemImage: "heart.circle").font(.headline)
                Spacer(minLength: 4)
                if let count = entry.count {
                    Text("\(count)").font(.system(size: 32, weight: .semibold, design: .rounded))
                    Text("保险箱记录").font(.caption).foregroundStyle(.secondary)
                    if let updated = entry.updated { Text(updated, style: .time).font(.caption2).foregroundStyle(.secondary) }
                } else {
                    Text("你的隐私\n由你掌握").font(.title3.weight(.medium))
                    Text("打开保险箱").font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if family == .systemMedium {
                VStack(alignment: .leading, spacing: 15) {
                    Link(destination: URL(string: "easylock://add-file")!) { Label("添加文件", systemImage: "doc.badge.plus") }
                    Link(destination: URL(string: "easylock://add-folder")!) { Label("添加文件夹", systemImage: "folder.badge.plus") }
                    Link(destination: URL(string: "easylock://settings")!) { Label("安全设置", systemImage: "slider.horizontal.3") }
                }.font(.callout)
            }
        }.widgetURL(URL(string: "easylock://library"))
        .containerBackground(for: .widget) { LinearGradient(colors: [Color(red: 0.34, green: 0.47, blue: 0.84).opacity(0.08), Color(red: 0.76, green: 0.43, blue: 0.70).opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing) }
    }
}
@main struct EasyLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EasyLockQuickAccess", provider: Provider()) { WidgetContent(entry: $0) }
            .configurationDisplayName("EasyLock 快捷管理")
            .description("打开保险箱或添加文件。可在应用设置中选择显示记录数量，不显示文件名称和内容。")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
