import Foundation

/// Shared cancellation is checked only before the transaction's commit boundary.
final class OperationControl: @unchecked Sendable {
    struct Update: Sendable {
        let phase: String
        let completed: Int64
        let total: Int64
    }
    private let lock = NSLock()
    private var cancelled = false
    private var lastReport = Date.distantPast
    private var lastPhase = ""
    let report: @Sendable (Update) -> Void
    init(report: @escaping @Sendable (Update) -> Void = { _ in }) { self.report = report }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func check() throws { if isCancelled { throw CancellationError() } }
    func update(_ phase: String, _ completed: Int64 = 0, _ total: Int64 = 0) {
        lock.lock()
        let now = Date()
        let emit = phase != lastPhase || now.timeIntervalSince(lastReport) > 0.12 || completed == total
        if emit { lastPhase = phase; lastReport = now }
        lock.unlock()
        if emit { report(Update(phase: phase, completed: completed, total: total)) }
    }
}
