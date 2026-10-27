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
                .foregroundStyle(
                    LinearGradient(colors: [Color(red: 0.36, green: 0.56, blue: 0.99),
                                            Color(red: 0.08, green: 0.30, blue: 0.92)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            Image(systemName: "lock.fill")
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(.white)
                .offset(y: size * 0.03)
        }
        .frame(width: size * 0.86, height: size)
    }
}

struct WidgetContent: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    private var ink: Color { scheme == .dark ? .white : Color(red: 0.063, green: 0.094, blue: 0.157) }
    private var muted: Color { scheme == .dark ? .white.opacity(0.56) : Color(red: 0.40, green: 0.44, blue: 0.52) }
    private var faint: Color { scheme == .dark ? .white.opacity(0.34) : Color(red: 0.60, green: 0.64, blue: 0.72) }
    private var accent: Color { scheme == .dark ? Color(red: 0.62, green: 0.73, blue: 1.0) : Color(red: 0.114, green: 0.333, blue: 0.941) }
    private var soft: Color { scheme == .dark ? Color(red: 0.09, green: 0.14, blue: 0.23) : Color(red: 0.91, green: 0.95, blue: 1.0) }

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    WidgetShield(size: 27)
                    Text("EasyLock")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ink)
                        .tracking(0.1)
                }

                Spacer(minLength: 2)

                if let count = entry.count {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(count)")
                            .font(.system(size: 34, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(ink)
                        Text("项")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(muted)
                    }
                    Text("保险箱记录")
                        .font(.system(size: 10))
                        .foregroundStyle(muted)
                    if let updated = entry.updated {
                        Text(updated, style: .time)
                            .font(.system(size: 9))
                            .foregroundStyle(faint)
                    }
                } else {
                    Text("你的文件\n由你上锁")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(ink)
                        .lineSpacing(2)
                    Text("打开 EasyLock")
                        .font(.system(size: 9.5))
                        .foregroundStyle(muted)
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
                if scheme == .dark {
                    LinearGradient(colors: [Color(red: 0.075, green: 0.098, blue: 0.145),
                                            Color(red: 0.035, green: 0.043, blue: 0.063)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                } else {
                    LinearGradient(colors: [.white, Color(red: 0.925, green: 0.957, blue: 1.0)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                RadialGradient(colors: [Color(red: 0.114, green: 0.333, blue: 0.941).opacity(scheme == .dark ? 0.20 : 0.10), .clear],
                               center: .topLeading, startRadius: 4, endRadius: 280)
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
                    .foregroundStyle(accent.opacity(0.38))
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(soft, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(accent.opacity(0.14), lineWidth: 1)
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
