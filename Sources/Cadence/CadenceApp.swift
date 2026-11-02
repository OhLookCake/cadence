import SwiftUI
import AppKit

@main struct CadenceApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model)
                .frame(minWidth: 1020, minHeight: 720)
                .tint(Color.cadence)
        }
        .defaultSize(width: 1220, height: 820)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task…") { model.create() }.keyboardShortcut("n")
                Button("Import Tasks…") { model.importTasks() }
                Button("Export Tasks…") { model.exportTasks() }.disabled(model.tasks.isEmpty)
            }
            CommandMenu("Task") {
                Button("Run Now") { if let task = model.tasks.first(where: { $0.id == model.selection }) { model.runNow(task) } }.keyboardShortcut("r").disabled(model.selection == nil)
                Button("Refresh") { model.refresh() }.keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Open Data Folder") { NSWorkspace.shared.open(model.store.root) }
            }
        }
        Settings { PreferencesView().environmentObject(model) }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { sender.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil) }; return true
    }
}
extension Color {
    static let cadence = Color(red: 0.17, green: 0.43, blue: 0.40)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let subdued = Color.secondary
}

struct PreferencesView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Section("Scheduling") {
                Text("Tasks run through per-user launchd agents while you are logged in. You can close this app; enabled schedules keep running.")
                Text("Checks run each minute and on wake or login. The app does not wake or power on your Mac. Prompts require an interactive desktop.").foregroundStyle(.secondary)
                LabeledContent("Registered schedules", value: "\(model.agentIDs.count)")
            }
            Section("Local data") {
                Text(model.store.root.path).font(.caption.monospaced()).textSelection(.enabled)
                Button("Open Data Folder") { NSWorkspace.shared.open(model.store.root) }
                HStack { Button("Export Tasks…") { model.exportTasks() }; Button("Import Tasks…") { model.importTasks() } }
                Text("Definitions, environment values, prompts and output are stored locally. Run history remains after deleting a task. Exported definitions include environment values.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding().frame(width: 540, height: 420)
    }
}
