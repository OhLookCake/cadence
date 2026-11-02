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
        for directory in [self.root, self.root.appendingPathComponent("runs"), self.root.appendingPathComponent("state")] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
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
    public func tasks() throws -> [ScheduledTask] {
        let url = root.appendingPathComponent("tasks.json")
        return FileManager.default.fileExists(atPath: url.path) ? try read([ScheduledTask].self, at: url) : []
    }
    public func save(_ task: ScheduledTask) throws {
        let lock = try FileLock(url: root.appendingPathComponent("tasks.lock")); defer { withExtendedLifetime(lock) {} }
        var all = try tasks()
        if let index = all.firstIndex(where: { $0.id == task.id }) { all[index] = task } else { all.append(task) }
        try write(all, at: root.appendingPathComponent("tasks.json"))
    }
    public func delete(_ id: UUID) throws {
        let lock = try FileLock(url: root.appendingPathComponent("tasks.lock")); defer { withExtendedLifetime(lock) {} }
        try write(tasks().filter { $0.id != id }, at: root.appendingPathComponent("tasks.json"))
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
