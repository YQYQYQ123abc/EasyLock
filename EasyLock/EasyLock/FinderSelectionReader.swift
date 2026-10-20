import AppKit

/// Finder Services may provide modern file URLs or the legacy filenames list.
enum FinderSelectionReader {
    static let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    static func urls(from pasteboard: NSPasteboard) -> [URL] {
        var values = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if let paths = pasteboard.propertyList(forType: filenamesType) as? [String] {
            values += paths.filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0) }
        }
        var seen = Set<URL>()
        return values.filter { $0.isFileURL && seen.insert($0.standardizedFileURL).inserted }
    }
}
