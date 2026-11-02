import SwiftUI
import AppKit
import CadenceCore

@MainActor final class AppModel: ObservableObject {
    let store: CadenceStore
    @Published var tasks: [ScheduledTask] = []
    @Published var runs: [RunRecord] = []
    @Published var selection: UUID?
    @Published var drafts: [UUID: ScheduledTask] = [:]
    var draftBases: [UUID: ScheduledTask] = [:]
    @Published var configFiles: [UUID: URL] = [:]
    @Published var configIssues: [ConfigIssue] = []
    @Published var registrationIssues: [String] = []
    @Published var error: String?
    @Published var agentIDs: Set<UUID> = []
    @Published var launched: Set<UUID> = []
    @Published var activeIDs: Set<UUID> = []
    private var timer: Timer?
    private var refreshCount = 0
    var runner: URL { Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("CadenceRunner") }
    init() {
        do { store = try CadenceStore() } catch { fatalError("Cannot open Cadence storage: \(error)") }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }
    func refresh(force: Bool = false) {
        if force { refreshCount = 0 }
        do {
            let catalog = try store.catalog()
            let changed = catalog.tasks != tasks
            tasks = catalog.tasks; configFiles = catalog.files; configIssues = catalog.issues
            runs = try store.runs()
            activeIDs = Set(tasks.filter { task in
                do { let lock = try FileLock(url: store.lockURL(task.id), nonblocking: true); withExtendedLifetime(lock) {}; return false }
                catch { return true }
            }.map(\.id))
            if changed || refreshCount % 5 == 0 { reconcileAgents() }
            refreshCount += 1
        } catch { self.error = error.localizedDescription }
    }
    private func reconcileAgents() {
        var issues: [String] = []
        do {
            let managed = try LaunchAgent.managedIDs()
            let enabled = Set(tasks.filter(\.enabled).map(\.id))
            for id in managed.subtracting(enabled) {
                // External edits never interrupt a currently executing occurrence.
                guard let lock = try? FileLock(url: store.lockURL(id), nonblocking: true) else { continue }
                defer { withExtendedLifetime(lock) {} }
                do { try LaunchAgent.remove(id) } catch { issues.append(error.localizedDescription) }
            }
            for task in tasks where task.enabled && !LaunchAgent.installed(task.id) && !activeIDs.contains(task.id) {
                do { try LaunchAgent.sync(task: task, runner: runner, root: store.root) }
                catch { issues.append("\(task.name): \(error.localizedDescription)") }
            }
            agentIDs = Set(tasks.filter { LaunchAgent.installed($0.id) }.map(\.id))
        } catch { issues.append(error.localizedDescription) }
        registrationIssues = issues
    }
    func isRunning(_ task: ScheduledTask) -> Bool {
        launched.contains(task.id) || activeIDs.contains(task.id)
    }
    func nextDue(_ task: ScheduledTask) -> Date? {
        if let state = try? store.read(TaskState.self, at: store.stateURL(task.id)), state.revision == task.scheduleRevision { return state.nextDue }
        return task.schedule.next(after: task.scheduleActivatedAt.addingTimeInterval(-1))
    }
    func create(_ kind: StepKind = .shell) {
        var task = ScheduledTask(); task.name = "New task"; task.steps = [TaskStep.make(kind)]
        do { try store.save(task); selection = task.id; refresh() }
        catch { self.error = error.localizedDescription }
    }
    func save(_ edited: ScheduledTask, expecting base: ScheduledTask? = nil) throws {
        var task = edited
        try task.validate()
        if let old = tasks.first(where: { $0.id == task.id }) {
            if isRunning(old) { throw CadenceError.message("Stop the current run before changing this task.") }
            if old.schedule != task.schedule || (!old.enabled && task.enabled) {
                task.scheduleRevision = UUID(); task.scheduleActivatedAt = Date()
            }
        } else { task.scheduleActivatedAt = Date() }
        // Persist first: an agent never sees a half-written definition.
        try store.save(task, expecting: base ?? tasks.first(where: { $0.id == task.id }))
        selection = task.id
        do { try LaunchAgent.sync(task: task, runner: runner, root: store.root) }
        catch {
            refreshCount = 0; refresh()
            throw CadenceError.message("Task saved, but launchd registration failed: \(error.localizedDescription) Use Repair schedule in the task menu.")
        }
        refreshCount = 0; refresh()
    }
    func toggle(_ task: ScheduledTask) {
        var copy = task; copy.enabled.toggle()
        do { try save(copy) } catch { self.error = error.localizedDescription }
    }
    func duplicate(_ task: ScheduledTask) {
        var copy = task; copy.id = UUID(); copy.name += " copy"; copy.enabled = false; copy.createdAt = Date(); copy.scheduleRevision = UUID()
        do { try store.save(copy); selection = copy.id; refresh() } catch { self.error = error.localizedDescription }
    }
    func remove(_ task: ScheduledTask) {
        do {
            guard !isRunning(task) else { throw CadenceError.message("Stop this task before deleting it.") }
            let lock = try FileLock(url: store.lockURL(task.id), nonblocking: true)
            defer { withExtendedLifetime(lock) {} }
            try LaunchAgent.remove(task.id); try store.delete(task.id)
            drafts.removeValue(forKey: task.id)
            draftBases.removeValue(forKey: task.id)
            if selection == task.id { selection = nil }; refreshCount = 0; refresh()
        } catch { self.error = error.localizedDescription }
    }
    func repair(_ task: ScheduledTask) {
        do { try LaunchAgent.sync(task: task, runner: runner, root: store.root); refreshCount = 0; refresh() }
        catch { self.error = error.localizedDescription }
    }
    func runNow(_ task: ScheduledTask) {
        do {
            guard drafts[task.id] == nil else { throw CadenceError.message("Save your changes before running this task.") }
            guard !isRunning(task) else { throw CadenceError.message("This task is already running.") }
            let p = Process(); p.executableURL = runner
            p.arguments = ["--task", task.id.uuidString, "--manual", "--data-dir", store.root.path]
            let errors = store.root.appendingPathComponent("manual-\(task.id).log")
            FileManager.default.createFile(atPath: errors.path, contents: nil)
            let handle = try FileHandle(forWritingTo: errors); p.standardError = handle; p.standardOutput = handle
            p.terminationHandler = { [weak self] process in
                try? handle.close()
                Task { @MainActor in
                    self?.launched.remove(task.id); self?.refresh()
                    if process.terminationStatus != 0 {
                        self?.error = (try? String(contentsOf: errors, encoding: .utf8)) ?? "The runner could not start."
                    }
                }
            }
            launched.insert(task.id)
            do { try p.run() } catch { launched.remove(task.id); try? handle.close(); throw error }
        } catch { self.error = error.localizedDescription }
    }
    func cancel(_ task: ScheduledTask) {
        do { try store.cancel(task.id) } catch { self.error = error.localizedDescription }
    }
    func exportTasks() {
        guard let task = tasks.first(where: { $0.id == selection }) else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = task.name.replacingOccurrences(of: "/", with: "-") + ".cadence.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.exportConfig(task, to: url) } catch { self.error = error.localizedDescription }
    }
    func importTasks() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        do {
            for url in panel.urls {
                let data = try Data(contentsOf: url)
                if (try? JSONSerialization.jsonObject(with: data)) is [Any] {
                    // Continue accepting exports from the previous aggregate format.
                    for var task in try store.read([ScheduledTask].self, at: url) {
                        task.id = UUID(); task.enabled = false; task.scheduleRevision = UUID()
                        try task.validate(); try store.save(task); selection = task.id
                    }
                } else { selection = try store.importConfig(at: url).id }
            }
            refreshCount = 0; refresh()
        } catch { self.error = error.localizedDescription }
    }
    func editConfig(_ url: URL) {
        let editor = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            if let error { Task { @MainActor in self?.error = error.localizedDescription } }
        }
    }
}
