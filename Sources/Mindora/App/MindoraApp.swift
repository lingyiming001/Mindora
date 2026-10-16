import SwiftUI

@main struct MindoraApp: App {
    @NSApplicationDelegateAdaptor(MindoraAppDelegate.self) private var appDelegate
    @StateObject private var workspace = WorkspaceStore.shared

    init() { AppPreferences.register() }

    var body: some Scene {
        Window("Mindora", id: "workspace") {
            WorkspaceView(workspace: workspace)
        }
        .defaultSize(width: 1180, height: 760)
        .commands { EditorCommands() }
        Settings { MindoraSettings() }
        Window("回收箱", id: "recycle-bin") { RecycleBinView() }.defaultSize(width: 720, height: 540)
        Window("键盘快捷键", id: "shortcuts") { ShortcutHelpView().padding(24).frame(width: 580, height: 620) }
    }
}

@MainActor final class MindoraAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { AppPreferences.applyAppearance() }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.last { WorkspaceStore.shared.openFile(url) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            _ = WorkspaceStore.shared.showFolder()
            WorkspaceStore.shared.presentWorkspace?()
        }
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        WorkspaceStore.shared.canCloseWindow() ? .terminateNow : .terminateCancel
    }
}

