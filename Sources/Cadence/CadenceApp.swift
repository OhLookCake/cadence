import SwiftUI
import AppKit

@main struct CadenceApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model).font(.cadenceBody)
                .disclosureGroupStyle(CadenceDisclosureStyle())
                .frame(minWidth: 1020, minHeight: 720)
                .tint(Color.cadence)
        }
        .defaultSize(width: 1360, height: 900)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Workflow…") { model.create() }.keyboardShortcut("n")
                Button("Import Config…") { model.importTasks() }
            }
            CommandMenu("Workflow") {
                Button("Run Now") { if let task = model.tasks.first(where: { $0.id == model.selection }) { model.runNow(task) } }.keyboardShortcut("r").disabled(model.selection == nil)
                Button("Refresh") { model.refresh(force: true) }.keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Open Data Folder") { NSWorkspace.shared.open(model.store.root) }
            }
        }
        Settings { PreferencesView().environmentObject(model).font(.cadenceBody) }
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
    static let cadence = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.38, green: 0.73, blue: 0.67, alpha: 1)
            : NSColor(srgbRed: 0.17, green: 0.43, blue: 0.40, alpha: 1)
    })
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let subdued = Color.secondary
}

struct PreferencesView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Section("Scheduling") {
                Text("Workflows run through per-user launchd agents while you are logged in. You can close this app; enabled schedules keep running.")
                Text("Checks run each minute and on wake or login. The app does not wake or power on your Mac. Prompts require an interactive desktop.").foregroundStyle(.secondary)
                LabeledContent("Registered schedules", value: "\(model.agentIDs.count)")
            }
            Section("Local data") {
                Text(model.store.root.path).font(.cadenceCaption.monospaced()).textSelection(.enabled)
                Button("Open Data Folder") { NSWorkspace.shared.open(model.store.root) }
                Button("Import Config…") { model.importTasks() }
                Text("Definitions, environment values, prompts and output are stored locally. Run history remains after deleting a workflow.").font(.cadenceCaption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding().frame(width: 540, height: 420)
    }
}
