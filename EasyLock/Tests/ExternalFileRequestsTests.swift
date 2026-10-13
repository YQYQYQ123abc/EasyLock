import Foundation

@main struct ExternalFileRequestsTests {
    @MainActor static func main() {
        let queue = ExternalFileRequests()
        let first = URL(fileURLWithPath: "/tmp/first.easylock")
        let second = URL(fileURLWithPath: "/tmp/second.txt")
        queue.enqueue([URL(string: "https://example.com")!], kind: .openEncrypted)
        precondition(queue.count == 0)
        queue.enqueue([first, first], kind: .openEncrypted)
        queue.enqueue([first], kind: .openEncrypted)
        queue.enqueue([second], kind: .finderSelection)
        precondition(queue.count == 2)
        // Requests remain queued before UI creation or while UI is busy.
        var received: [URL] = []
        queue.consumeNext { request in
            precondition(request.kind == .openEncrypted)
            received += request.urls
        }
        precondition(received == [first] && queue.count == 1)
        queue.consumeNext { request in
            precondition(request.kind == .finderSelection)
            received += request.urls
        }
        queue.consumeNext { _ in preconditionFailure("empty queue") }
        precondition(received == [first, second] && queue.count == 0)
        queue.enqueue([first], kind: .openEncrypted)
        precondition(queue.count == 1) // Later intentional reopening remains possible.
        queue.consumeNext { _ in }
        for invalid in ["easylock://decrypt", "easylock://add-file?path=/tmp/test", "https://library", "easylock://library/private", "easylock://user@settings"] {
            queue.enqueueShortcut(URL(string: invalid)!)
            precondition(queue.shortcut == nil)
        }
        for valid in ["library", "settings", "add-file", "add-folder"] {
            queue.enqueueShortcut(URL(string: "easylock://" + valid)!)
            precondition(queue.consumeShortcut() == valid && queue.shortcut == nil)
        }
        print("PASS: widget navigation allowlist and rejection of file paths/credentials/query actions")
        print("PASS: queued cold-start requests, ordering, deduplication, URL filtering and repeated opens")
    }
}
