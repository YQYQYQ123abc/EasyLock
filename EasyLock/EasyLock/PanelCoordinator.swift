import Foundation
import Observation

/// Serializes presentation and waits for the actual dismissal callback, not a timer.
@MainActor @Observable final class PanelCoordinator {
    enum Panel: String, Identifiable { case encrypt, decrypt, results, passwordApp, help, passwordChange, recoverySetup, notice; var id: String { rawValue } }
    private(set) var presented: Panel?
    private(set) var current: Panel?
    private(set) var dismissing = false
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []
    var occupied: Bool { current != nil || dismissing }
    func reconcile(_ requested: [Panel]) {
        guard !dismissing else { return }
        if let current {
            if !requested.contains(current) { dismiss() }
        } else if let next = requested.first {
            current = next; presented = next
        }
    }
    func dismiss() {
        guard current != nil else { return }
        dismissing = true; presented = nil
    }
    @discardableResult func didDismiss() -> Panel? {
        let old = current
        presented = nil; current = nil; dismissing = false
        let pending = waiters; waiters = []
        pending.forEach { $0.resume() }
        return old
    }
    func closeAndWait() async {
        guard occupied else { return }
        dismiss()
        await withCheckedContinuation { waiters.append($0) }
    }
}
