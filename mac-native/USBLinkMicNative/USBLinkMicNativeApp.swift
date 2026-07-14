import SwiftUI
import AppKit

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    var onTerminate: (() -> Void)?

    func applicationWillTerminate(_ notification: Notification) {
        onTerminate?()
    }
}

@main
struct USBLinkMicNativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(model)
                .frame(minWidth: 1080, minHeight: 680)
                .onAppear {
                    appDelegate.onTerminate = { model.stopRelayForTermination() }
                }
                .task {
                    await model.refresh()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("USB LinkMic") {
                Button("刷新状态") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button("全部停止") {
                    Task { await model.stopAll() }
                }
                .keyboardShortcut(".", modifiers: [.command])
            }
        }
    }
}
