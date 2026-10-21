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

private struct WidgetShield: View {
    var size: CGFloat = 34
    var body: some View {
        ZStack {
            Image(systemName: "shield.fill")
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(.white)
            Image(systemName: "lock.fill")
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(.black.opacity(0.88))
                .offset(y: size * 0.03)
        }
        .frame(width: size * 0.86, height: size)
    }
}

struct WidgetContent: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    WidgetShield(size: 27)
                    Text("EasyLock")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .tracking(0.1)
                }

                Spacer(minLength: 2)

                if let count = entry.count {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(count)")
                            .font(.system(size: 34, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text("项")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Text("保险箱记录")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                    if let updated = entry.updated {
                        Text(updated, style: .time)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.32))
                    }
                } else {
                    Text("你的文件\n由你上锁")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .lineSpacing(2)
                    Text("打开 EasyLock")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if family == .systemMedium {
                VStack(alignment: .leading, spacing: 12) {
                    widgetLink("添加文件", symbol: "doc.badge.plus", url: "easylock://add-file")
                    widgetLink("添加文件夹", symbol: "folder.badge.plus", url: "easylock://add-folder")
                    widgetLink("安全设置", symbol: "slider.horizontal.3", url: "easylock://settings")
                }
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .widgetURL(URL(string: "easylock://library"))
        .containerBackground(for: .widget) {
            ZStack {
                Color(red: 0.043, green: 0.043, blue: 0.049)
                RadialGradient(colors: [Color.white.opacity(0.115), .clear],
                               center: .topLeading, startRadius: 4, endRadius: 260)
                LinearGradient(colors: [.clear, Color.black.opacity(0.30)],
                               startPoint: .center, endPoint: .bottom)
            }
        }
    }

    private func widgetLink(_ title: String, symbol: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 16)
                Text(title)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white.opacity(0.28))
            }
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
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
