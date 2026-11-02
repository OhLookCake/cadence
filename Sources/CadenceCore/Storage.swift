import Foundation
import Darwin

public final class FileLock {
    private let descriptor: Int32
    public init(url: URL, nonblocking: Bool = false) throws {
        descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CadenceError.message("Cannot open lock: \(url.path)") }
        guard flock(descriptor, LOCK_EX | (nonblocking ? LOCK_NB : 0)) == 0 else {
            close(descriptor)
            throw CadenceError.message("This task is already running.")
        }
        // Locks must not leak into child scripts.
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}

public final class CadenceStore {
    public let root: URL
    public init(root: URL? = nil) throws {
        self.root = root ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Cadence", isDirectory: true)
        for directory in [self.root, self.root.appendingPathComponent("runs"), self.root.appendingPathComponent("state"), self.root.appendingPathComponent("flows"), self.root.appendingPathComponent("metadata")] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try migrateLegacyTasks()
    }
    public func read<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(contentsOf: url))
    }
    public func write<T: Encodable>(_ value: T, at url: URL) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public var flowsDirectory: URL { root.appendingPathComponent("flows", isDirectory: true) }
    public func defaultConfigURL(_ id: UUID) -> URL { flowsDirectory.appendingPathComponent("\(id.uuidString.lowercased()).cadence.json") }
    private func metadataURL(_ id: UUID) -> URL { root.appendingPathComponent("metadata/\(id.uuidString).json") }

    public func catalog() throws -> FlowCatalog {
        let lock = try FileLock(url: root.appendingPathComponent("tasks.lock"))
        defer { withExtendedLifetime(lock) {} }
        return try catalogUnlocked()
    }
    public func tasks() throws -> [ScheduledTask] { try catalog().tasks }

    private func catalogUnlocked() throws -> FlowCatalog {
        let urls = try FileManager.default.contentsOfDirectory(at: flowsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "json" && !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var result = FlowCatalog()
        var candidates: [(ScheduledTask, URL)] = []
        for url in urls {
            do {
                let config = try FlowConfig.decode(Data(contentsOf: url))
                guard let id = config.id else { throw CadenceError.message("A managed config needs an id. Use Import Config to assign one.") }
                var task = config.task()
                // An enabled definition must be executable. Paused, incomplete UI drafts remain editable.
                if task.enabled { try task.validate() }
                var metadata: FlowMetadata
                if FileManager.default.fileExists(atPath: metadataURL(id).path) {
                    metadata = try read(FlowMetadata.self, at: metadataURL(id))
                    let previousRevision = metadata.revision
                    if metadata.schedule != task.schedule || (!metadata.enabled && task.enabled) {
                        metadata.revision = UUID(); metadata.activatedAt = Date()
                    }
                    let changed = metadata.schedule != task.schedule || metadata.enabled != task.enabled
                    metadata.schedule = task.schedule; metadata.enabled = task.enabled
                    // A revision change also needs to be persisted if the schedule was changed.
                    if changed || metadata.revision != previousRevision { try write(metadata, at: metadataURL(id)) }
                } else {
                    metadata = FlowMetadata(task: task)
                    try write(metadata, at: metadataURL(id))
                }
                task.scheduleRevision = metadata.revision; task.scheduleActivatedAt = metadata.activatedAt; task.createdAt = metadata.createdAt
                candidates.append((task, url))
            } catch { result.issues.append(ConfigIssue(url: url, message: error.localizedDescription)) }
        }
        let grouped = Dictionary(grouping: candidates, by: { $0.0.id })
        for (_, group) in grouped {
            if group.count > 1 {
                for (_, url) in group { result.issues.append(ConfigIssue(url: url, message: "Duplicate flow id. Each config must have a unique id.")) }
            } else if let (task, url) = group.first {
                result.tasks.append(task); result.files[task.id] = url
            }
        }
        result.tasks.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return result
    }

    public func save(_ task: ScheduledTask, expecting expected: ScheduledTask? = nil, schema: String? = nil) throws {
        let lock = try FileLock(url: root.appendingPathComponent("tasks.lock"))
        defer { withExtendedLifetime(lock) {} }
        let catalog = try catalogUnlocked()
        if let expected, catalog.tasks.first(where: { $0.id == task.id }) != expected {
            throw CadenceError.message("The config changed on disk while you were editing. Reload from file before saving to avoid overwriting those changes.")
        }
        let url = catalog.files[task.id] ?? defaultConfigURL(task.id)
        if catalog.files[task.id] == nil && FileManager.default.fileExists(atPath: url.path) {
            throw CadenceError.message("The existing config is invalid. Fix it before saving this task.")
        }
        let existingSchema = catalog.files[task.id].flatMap { try? FlowConfig.decode(Data(contentsOf: $0)).schema }
        try FlowConfig.encode(task, schema: schema ?? existingSchema).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try write(FlowMetadata(task: task), at: metadataURL(task.id))
    }

    @discardableResult public func importConfig(at url: URL) throws -> ScheduledTask {
        let config = try FlowConfig.decode(Data(contentsOf: url))
        var task = config.task(assignedID: UUID())
        task.enabled = false
        try task.validate()
        try save(task, schema: config.schema)
        guard let imported = try tasks().first(where: { $0.id == task.id }) else { throw CadenceError.message("The imported config could not be loaded.") }
        return imported
    }
    public func exportConfig(_ task: ScheduledTask, to url: URL) throws {
        try FlowConfig.encode(task).write(to: url, options: .atomic)
    }
    public func delete(_ id: UUID) throws {
        let lock = try FileLock(url: root.appendingPathComponent("tasks.lock"))
        defer { withExtendedLifetime(lock) {} }
        let catalog = try catalogUnlocked()
        if let url = catalog.files[id] { try FileManager.default.removeItem(at: url) }
    }
    private func migrateLegacyTasks() throws {
        let legacy = root.appendingPathComponent("tasks.json")
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        let lock = try FileLock(url: root.appendingPathComponent("tasks.lock"))
        defer { withExtendedLifetime(lock) {} }
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        for task in try read([ScheduledTask].self, at: legacy) {
            let url = defaultConfigURL(task.id)
            if !FileManager.default.fileExists(atPath: url.path) {
                try FlowConfig.encode(task).write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                try write(FlowMetadata(task: task), at: metadataURL(task.id))
            }
        }
        let archive = root.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: legacy, to: archive.appendingPathComponent("tasks-\(UUID().uuidString).json"))
    }
    public func stateURL(_ id: UUID) -> URL { root.appendingPathComponent("state/\(id.uuidString).json") }
    public func lockURL(_ id: UUID) -> URL { root.appendingPathComponent("state/\(id.uuidString).lock") }
    public func cancelURL(_ id: UUID) -> URL { root.appendingPathComponent("state/\(id.uuidString).cancel") }
    public func runDirectory(_ id: UUID) -> URL { root.appendingPathComponent("runs/\(id.uuidString)") }
    public func saveRun(_ record: RunRecord) throws {
        let dir = runDirectory(record.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try write(record, at: dir.appendingPathComponent("run.json"))
    }
    public func runs() throws -> [RunRecord] {
        let dirs = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("runs"), includingPropertiesForKeys: nil)
        return dirs.compactMap { try? read(RunRecord.self, at: $0.appendingPathComponent("run.json")) }.sorted { $0.startedAt > $1.startedAt }
    }
    public func log(_ id: UUID) -> String {
        let url = runDirectory(id).appendingPathComponent("output.log")
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "No output yet." }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 250000 ? size - 250000 : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        return (size > 250000 ? "[Showing the last 250 KB. Open the run folder for full output.]\n" : "") + String(decoding: data, as: UTF8.self)
    }
    public func cancel(_ id: UUID) throws { try Data().write(to: cancelURL(id), options: .atomic) }
}

public enum LaunchAgent {
    public static func managedIDs() throws -> Set<UUID> {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let prefix = "local.cadence.task."
        return Set(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).compactMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == "plist", name.hasPrefix(prefix) else { return nil }
            return UUID(uuidString: String(name.dropFirst(prefix.count)))
        })
    }
    public static func label(_ id: UUID) -> String { "local.cadence.task.\(id.uuidString.lowercased())" }
    public static func url(_ id: UUID) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label(id)).plist")
    }
    public static func definition(task: ScheduledTask, runner: URL, root: URL) -> [String: Any] {
        ["Label": label(task.id), "ProgramArguments": [runner.path, "--task", task.id.uuidString, "--data-dir", root.path],
         "RunAtLoad": true,
         // Calendar triggers coalesce on wake; the durable cursor decides what to replay.
         "StartCalendarInterval": (0..<60).map { ["Minute": $0] },
         "ProcessType": "Background", "LimitLoadToSessionType": "Aqua",
         "StandardOutPath": root.appendingPathComponent("agent.log").path,
         "StandardErrorPath": root.appendingPathComponent("agent-error.log").path,
         "EnvironmentVariables": ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"]]
    }
    @discardableResult
    public static func control(_ args: [String], allowFailure: Bool = false) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/launchctl"); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        let result = String(decoding: data, as: UTF8.self)
        if p.terminationStatus != 0 && !allowFailure { throw CadenceError.message("launchctl \(args.first ?? ""): \(result)") }
        return result
    }
    public static func installed(_ id: UUID) -> Bool {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["print", "gui/\(getuid())/\(label(id))"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
    }
    public static func sync(task: ScheduledTask, runner: URL, root: URL) throws {
        // Do not unload an executing agent. The runner re-reads enabled/revision between occurrences.
        do {
            let lock = try FileLock(url: root.appendingPathComponent("state/\(task.id.uuidString).lock"), nonblocking: true)
            defer { withExtendedLifetime(lock) {} }
            if task.enabled && !FileManager.default.isExecutableFile(atPath: runner.path) { throw CadenceError.message("Runner missing. Rebuild the application bundle.") }
            try remove(task.id)
            guard task.enabled else { return }
            let plist = try PropertyListSerialization.data(fromPropertyList: definition(task: task, runner: runner, root: root), format: .xml, options: 0)
            try FileManager.default.createDirectory(at: url(task.id).deletingLastPathComponent(), withIntermediateDirectories: true)
            try plist.write(to: url(task.id), options: .atomic)
        }
        // RunAtLoad may start the worker before bootstrap returns. Release its execution lock first.
        _ = try control(["bootstrap", "gui/\(getuid())", url(task.id).path])
    }
    public static func remove(_ id: UUID) throws {
        if installed(id) { _ = try control(["bootout", "gui/\(getuid())/\(label(id))"]) }
        if FileManager.default.fileExists(atPath: url(id).path) { try FileManager.default.removeItem(at: url(id)) }
    }
}
