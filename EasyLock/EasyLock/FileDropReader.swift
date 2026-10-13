import Foundation
import UniformTypeIdentifiers

/// Loads only original file URLs, never a provider's temporary file copy.
@MainActor
final class FileDropReader {
    private var results: [Int: URL] = [:]
    private var remaining: Int
    private var failures = 0
    private let completion: @MainActor ([URL], Int) -> Void

    private init(count: Int, completion: @escaping @MainActor ([URL], Int) -> Void) {
        remaining = count
        self.completion = completion
    }

    @discardableResult
    static func begin(_ providers: [NSItemProvider], completion: @escaping @MainActor ([URL], Int) -> Void) -> Bool {
        let candidates = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !candidates.isEmpty else { return false }
        let reader = FileDropReader(count: candidates.count, completion: completion)
        // Begin each load synchronously within onDrop; deferring the request loses drag access.
        for (index, provider) in candidates.enumerated() {
            _ = provider.loadObject(ofClass: NSURL.self) { item, _ in
                let url = item as? URL
                Task { @MainActor in reader.finished(index: index, url: url) }
            }
        }
        return true
    }

    private func finished(index: Int, url: URL?) {
        if let url, url.isFileURL { results[index] = url } else { failures += 1 }
        remaining -= 1
        if remaining == 0 {
            var seen = Set<URL>()
            let urls = results.keys.sorted().compactMap { results[$0] }.filter { seen.insert($0.standardizedFileURL).inserted }
            completion(urls, failures)
        }
    }
}
