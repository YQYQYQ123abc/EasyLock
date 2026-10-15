import SwiftUI

@main
struct EasyLockApp: App {
    @NSApplicationDelegateAdaptor(FinderService.self) private var appDelegate
    @State private var store = VaultStore()
    var body: some Scene {
        Window("EasyLock", id: "main") {
            ContentView(store: store)
                .modifier(MainWindowRegistration(delegate: appDelegate, preview: store.preview))

        }
        .defaultSize(width: 1060, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("添加文件…") { store.chooseSources() }
                    .keyboardShortcut("n").disabled(store.password.isEmpty || !store.canPresentPicker)
                Button("添加文件夹…") { store.chooseSources(foldersOnly: true) }
                    .keyboardShortcut("n", modifiers: [.command, .shift]).disabled(store.password.isEmpty || !store.canPresentPicker)
                Button("导入加密文件…") { store.importFiles() }.keyboardShortcut("o").disabled(!store.canPresentPicker)
            }
        }
    }
}

private struct MainWindowRegistration: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    let delegate: FinderService
    let preview: PrivatePreview
    func body(content: Content) -> some View {
        content.onAppear {
            delegate.openMainWindow = { openWindow(id: "main") }
            delegate.closePrivatePreview = {
                preview.close()
                while preview.busy { try? await Task.sleep(for: .milliseconds(50)) }
            }
        }
    }
}
