import Foundation

@main struct PanelCoordinatorTests {
    @MainActor static func main() async {
        let panels = PanelCoordinator()
        panels.reconcile([.encrypt, .help, .decrypt])
        precondition(panels.presented == .encrypt)
        // A second request must not replace the sheet already visible.
        panels.reconcile([.help, .encrypt, .decrypt])
        precondition(panels.presented == .encrypt)
        panels.reconcile([.help, .decrypt])
        precondition(panels.presented == nil && panels.occupied)
        // Dismissal animation has not finished; do not present the next panel yet.
        panels.reconcile([.results, .help, .decrypt])
        precondition(panels.presented == nil)
        precondition(panels.didDismiss() == .encrypt)
        panels.reconcile([.results, .help, .decrypt])
        precondition(panels.presented == .results)
        var resumed = false
        let work = Task { await panels.closeAndWait(); resumed = true }
        await Task.yield()
        precondition(!resumed && panels.occupied)
        panels.reconcile([.help])
        precondition(panels.presented == nil)
        panels.didDismiss()
        await work.value
        precondition(resumed && !panels.occupied)
        panels.reconcile([.passwordChange])
        panels.reconcile([.notice, .passwordChange])
        precondition(panels.presented == .passwordChange) // Error stays inline in the active form.
        panels.reconcile([.notice])
        precondition(panels.presented == nil)
        panels.didDismiss(); panels.reconcile([.notice])
        precondition(panels.presented == .notice)
        panels.reconcile([]); panels.didDismiss()
        // Locking removes all requests and drains presentation only after dismissal.
        panels.reconcile([.passwordChange, .recoverySetup])
        panels.reconcile([])
        precondition(panels.dismissing)
        panels.didDismiss(); panels.reconcile([])
        precondition(!panels.occupied)
        await panels.closeAndWait()
        panels.didDismiss() // Idempotent close/window disappearance callback.
        precondition(!panels.occupied)
        print("PASS: exclusive panels, stable active presentation, dismissal barrier, deferred work, session clearing and repeated close")
    }
}
