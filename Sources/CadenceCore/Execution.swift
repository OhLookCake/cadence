import Foundation
import Darwin

public protocol WorkflowDialogs {
    func ask(message: String, title: String, timeout: Int) throws -> String
    func show(message: String, title: String, timeout: Int) throws
}
public struct WorkflowCancelled: LocalizedError {
    public init() {}
    public var errorDescription: String? { "Question cancelled or expired; remaining steps were not run." }
}

public struct StepContext {
    public let now: Date
    public let scheduled: Date
    public let timeZone: TimeZone
    public var input = ""
    public var previous = ""
    public var previousFile = ""
    public var results: [String: NamedStepResult] = [:]
    public init(now: Date, scheduled: Date, timeZone: TimeZone) { self.now = now; self.scheduled = scheduled; self.timeZone = timeZone }
    public var values: [String: String] {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = timeZone; formatter.dateFormat = "yyyy-MM-dd"
        let iso = ISO8601DateFormatter()
        return ["date": formatter.string(from: now), "timestamp": iso.string(from: now), "unix": String(Int(now.timeIntervalSince1970)),
                "scheduled_date": formatter.string(from: scheduled), "scheduled_timestamp": iso.string(from: scheduled), "input": input, "previous_output": previous, "previous_output_file": previousFile]
    }
    public func expand(_ text: String) -> String {
        // A single pass prevents user input containing another placeholder from being expanded again.
        let regex = try! NSRegularExpression(pattern: #"\{\{([a-z_]+|steps\.[a-z][a-z0-9_]{0,39}\.(?:output|output_file|status))\}\}"#)
        let original = text as NSString
        let baseValues = values
        var result = text
        for match in regex.matches(in: text, range: NSRange(location: 0, length: original.length)).reversed() {
            let name = original.substring(with: match.range(at: 1))
            let value: String?
            if name.hasPrefix("steps.") {
                let parts = name.split(separator: ".").map(String.init)
                value = (results[parts[1]] ?? NamedStepResult(status: .pending)).value(parts[2])
            } else { value = baseValues[name] }
            if let value, let range = Range(match.range, in: result) { result.replaceSubrange(range, with: value) }
        }
        return result
    }
    public func environment(task: ScheduledTask) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for line in task.environment.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 { env[String(parts[0])] = expand(String(parts[1])) }
        }
        for (key, value) in values {
            // macOS limits exec's combined arguments and environment. Full output is available as a file.
            env["TASK_" + key.uppercased()] = key == "previous_output" ? String(value.suffix(16000)) : value
        }
        // Share a byte budget across named outputs so adding references does not exhaust exec's environment.
        let resultBudget = min(16000, 48000 / max(1, results.values.filter { !$0.output.isEmpty }.count))
        for (key, result) in results {
            let prefix = "TASK_STEP_" + key.uppercased()
            var bytes = result.output.utf8.suffix(resultBudget)
            // A byte limit must not split the first Unicode scalar in the retained suffix.
            while let first = bytes.first, first & 0xC0 == 0x80 { bytes = bytes.dropFirst() }
            env[prefix + "_OUTPUT"] = String(decoding: bytes, as: UTF8.self)
            env[prefix + "_OUTPUT_FILE"] = result.outputFile
            env[prefix + "_STATUS"] = result.status.rawValue
        }
        env["TASK_ID"] = task.id.uuidString
        return env
    }
}

public final class StepExecutor {
    let store: CadenceStore
    let task: ScheduledTask
    let run: RunRecord
    let logURL: URL
    let dialogs: WorkflowDialogs?
    public init(store: CadenceStore, task: ScheduledTask, run: RunRecord, dialogs: WorkflowDialogs? = nil) {
        self.store = store; self.task = task; self.run = run
        self.dialogs = dialogs
        logURL = store.runDirectory(run.id).appendingPathComponent("output.log")
    }
    func append(_ text: String) {
        if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            _ = try? handle.seekToEnd(); try? handle.write(contentsOf: Data(text.utf8)); try? handle.close()
        }
    }
    public var cancelled: Bool { FileManager.default.fileExists(atPath: store.cancelURL(task.id).path) }
    func stopTree(_ process: Process) {
        // Take a process-tree snapshot before terminating the parent, while descendants still have their original PPID.
        let ps = Process(); ps.executableURL = URL(fileURLWithPath: "/bin/ps"); ps.arguments = ["-axo", "pid=,ppid="]
        let pipe = Pipe(); ps.standardOutput = pipe; ps.standardError = FileHandle.nullDevice
        var descendants: [Int32] = []
        if (try? ps.run()) != nil {
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self); ps.waitUntilExit()
            let pairs = output.split(separator: "\n").compactMap { line -> (Int32, Int32)? in
                let fields = line.split(whereSeparator: { $0.isWhitespace })
                guard fields.count == 2, let pid = Int32(fields[0]), let ppid = Int32(fields[1]) else { return nil }; return (pid, ppid)
            }
            var parents: Set<Int32> = [process.processIdentifier]
            while true {
                let next = pairs.filter { parents.contains($0.1) && !parents.contains($0.0) }.map { $0.0 }
                if next.isEmpty { break }; descendants.append(contentsOf: next); parents.formUnion(next)
            }
        }
        for pid in descendants.reversed() { kill(pid, SIGTERM) }
        if process.isRunning { process.terminate() }
        Thread.sleep(forTimeInterval: 0.3)
        for pid in descendants.reversed() { kill(pid, SIGKILL) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
    func process(executable: String, arguments: [String], environment: [String: String], timeout: Int, stem: String, stdin: String? = nil) throws -> (Int32, String) {
        if cancelled { throw CadenceError.message("Cancelled by user.") }
        let directory = store.runDirectory(run.id)
        let stdout = directory.appendingPathComponent("\(stem).stdout")
        let stderr = directory.appendingPathComponent("\(stem).stderr")
        FileManager.default.createFile(atPath: stdout.path, contents: nil); FileManager.default.createFile(atPath: stderr.path, contents: nil)
        let out = try FileHandle(forWritingTo: stdout), err = try FileHandle(forWritingTo: stderr)
        defer { try? out.close(); try? err.close() }
        let workingDirectory = URL(fileURLWithPath: (task.workingDirectory as NSString).expandingTildeInPath)
        let expandedExecutable = (executable as NSString).expandingTildeInPath
        let p = Process()
        p.executableURL = expandedExecutable.hasPrefix("/") ? URL(fileURLWithPath: expandedExecutable) : workingDirectory.appendingPathComponent(expandedExecutable)
        p.arguments = arguments; p.environment = environment
        p.currentDirectoryURL = workingDirectory
        p.standardOutput = out; p.standardError = err; p.standardInput = FileHandle.nullDevice
        let byteCount = arguments.reduce(0) { $0 + $1.utf8.count + 1 } + environment.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count + 2 }
        guard byteCount < 200000 else { throw CadenceError.message("Arguments and environment exceed macOS process limits. Pass large data through files, using TASK_PREVIOUS_OUTPUT_FILE or {{previous_output_file}}.") }
        var inputHandle: FileHandle?
        if let stdin {
            let url = directory.appendingPathComponent("\(stem).stdin")
            try Data(stdin.utf8).write(to: url, options: .atomic)
            inputHandle = try FileHandle(forReadingFrom: url); p.standardInput = inputHandle
        }
        defer { try? inputHandle?.close() }
        try p.run()
        let start = Date()
        var stopped: String?
        while p.isRunning {
            if cancelled { stopped = "Cancelled by user." }
            else if Date().timeIntervalSince(start) >= Double(timeout) { stopped = "Step timed out after \(timeout) seconds." }
            if stopped != nil { stopTree(p); break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        p.waitUntilExit()
        // Keep the original files in full, but bound memory used by chained outputs and the UI.
        func tail(_ url: URL) -> String {
            guard let h = try? FileHandle(forReadingFrom: url) else { return "" }; defer { try? h.close() }
            let size = (try? h.seekToEnd()) ?? 0; try? h.seek(toOffset: size > 1000000 ? size - 1000000 : 0)
            return String(decoding: (try? h.readToEnd()) ?? Data(), as: UTF8.self)
        }
        let output = tail(stdout), errors = tail(stderr)
        append(output + (errors.isEmpty ? "" : "\n[stderr]\n" + errors) + "\n")
        if let stopped { throw CadenceError.message(stopped) }
        return (p.terminationStatus, output)
    }
    func ask(_ step: TaskStep, index: Int, context: StepContext) throws -> String {
        let message = context.expand(step.body)
        if let dialogs { return try dialogs.ask(message: message, title: task.name, timeout: step.timeoutSeconds) }
        let script = """
        on run argv
            set answer to display dialog (item 1 of argv) with title (item 2 of argv) default answer "" buttons {"Cancel", "Continue"} default button "Continue" cancel button "Cancel" giving up after (item 3 of argv as integer)
            if gave up of answer then error "Question timed out" number -128
            return text returned of answer
        end run
        """
        let (code, answer) = try process(executable: "/usr/bin/osascript", arguments: ["-e", script, message, task.name, String(step.timeoutSeconds)], environment: context.environment(task: task), timeout: step.timeoutSeconds + 5, stem: "step-\(index + 1)-question")
        guard code == 0 else { throw WorkflowCancelled() }
        return answer.trimmingCharacters(in: .newlines)
    }
    func showResponse(_ step: TaskStep, index: Int, context: StepContext) throws -> String {
        let message = context.expand(step.body)
        if let dialogs { try dialogs.show(message: message, title: task.name, timeout: step.timeoutSeconds); return message }
        let script = """
        on run argv
            display dialog (item 1 of argv) with title (item 2 of argv) buttons {"OK"} default button "OK" giving up after (item 3 of argv as integer)
        end run
        """
        let (code, _) = try process(executable: "/usr/bin/osascript", arguments: ["-e", script, String(message.suffix(6000)), task.name, String(step.timeoutSeconds)], environment: context.environment(task: task), timeout: step.timeoutSeconds + 5, stem: "step-\(index + 1)-response")
        guard code == 0 else { throw CadenceError.message("Could not display the response.") }
        return message
    }
    public func execute(_ step: TaskStep, index: Int, context: StepContext) throws -> String {
        append("\n━━ Step \(index + 1): \(step.name) · \(step.kind.title) ━━\n")
        let env = context.environment(task: task)
        let stem = "step-\(index + 1)"
        var code: Int32 = 0, output = ""
        switch step.kind {
        case .shell:
            // Never interpolate user input or LLM output into shell source. Pass values in the environment.
            (code, output) = try process(executable: "/bin/zsh", arguments: ["-c", step.body], environment: env, timeout: step.timeoutSeconds, stem: stem)
        case .script:
            let expanded = (context.expand(step.scriptPath) as NSString).expandingTildeInPath
            let path = expanded.hasPrefix("/") ? expanded : URL(fileURLWithPath: (task.workingDirectory as NSString).expandingTildeInPath).appendingPathComponent(expanded).path
            let args = step.arguments.components(separatedBy: "\n").filter { !$0.isEmpty }.map(context.expand)
            (code, output) = try process(executable: step.executable.isEmpty ? path : step.executable, arguments: (step.executable.isEmpty ? [] : [path]) + args, environment: env, timeout: step.timeoutSeconds, stem: stem)
        case .question: output = try ask(step, index: index, context: context)
        case .response: output = try showResponse(step, index: index, context: context)
        case .codex:
            let answer = store.runDirectory(run.id).appendingPathComponent("\(stem).answer.txt")
            var args = ["exec", "--skip-git-repo-check", "--color", "never", "--sandbox", step.sandbox, "--output-last-message", answer.path]
            if !step.model.isEmpty { args += ["--model", step.model] }
            args.append("-")
            (code, output) = try process(executable: step.executable, arguments: args, environment: env, timeout: step.timeoutSeconds, stem: stem, stdin: context.expand(step.body))
            if let final = try? String(contentsOf: answer, encoding: .utf8) { output = final }
        case .localLLM:
            guard let url = URL(string: step.endpoint) else { throw CadenceError.message("Invalid LLM endpoint.") }
            let payload: [String: Any] = ["model": step.model, "messages": [["role": "user", "content": context.expand(step.body)]], "stream": false]
            let request = store.runDirectory(run.id).appendingPathComponent("\(stem).request.json")
            try JSONSerialization.data(withJSONObject: payload).write(to: request, options: .atomic)
            var args = ["--silent", "--show-error", "--fail-with-body", "--max-time", String(step.timeoutSeconds), "-H", "Content-Type: application/json", "--data-binary", "@" + request.path, url.absoluteString]
            // Authentication is optional for local servers; avoid putting credentials in process arguments.
            if let token = env["CADENCE_LLM_API_KEY"], !token.isEmpty {
                let config = store.runDirectory(run.id).appendingPathComponent("\(stem).curl.conf")
                guard !token.contains("\n"), !token.contains("\r") else { throw CadenceError.message("Invalid API key.") }
                let escaped = token.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                try Data("header = \"Authorization: Bearer \(escaped)\"\n".utf8).write(to: config, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
                args = ["--config", config.path] + args
                defer { try? FileManager.default.removeItem(at: config) }
                (code, output) = try process(executable: "/usr/bin/curl", arguments: args, environment: env, timeout: step.timeoutSeconds + 2, stem: stem)
            } else { (code, output) = try process(executable: "/usr/bin/curl", arguments: args, environment: env, timeout: step.timeoutSeconds + 2, stem: stem) }
            if code == 0 {
                guard let data = output.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = object["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any], let content = message["content"] as? String else {
                    throw CadenceError.message("LLM response has no choices[0].message.content.")
                }
                output = content
            }
        }
        guard code == 0 else { throw CadenceError.message("Step \(index + 1) exited with status \(code). See its output in the run folder.") }
        let canonicalOutput = store.runDirectory(run.id).appendingPathComponent("\(stem).output.txt")
        if step.kind == .shell || step.kind == .script {
            try FileManager.default.copyItem(at: store.runDirectory(run.id).appendingPathComponent("\(stem).stdout"), to: canonicalOutput)
        } else { try Data(output.utf8).write(to: canonicalOutput, options: .atomic) }
        if !step.outputPath.isEmpty {
            let path = (context.expand(step.outputPath) as NSString).expandingTildeInPath
            let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL(fileURLWithPath: (task.workingDirectory as NSString).expandingTildeInPath).appendingPathComponent(path)
            try Data(output.utf8).write(to: url, options: .atomic)
            append("Saved output to \(url.path)\n")
        }
        return output
    }
}

public enum TaskRunner {
    public static func run(store: CadenceStore, id: UUID, manual: Bool, dialogs: WorkflowDialogs? = nil) throws {
        let lock = try FileLock(url: store.lockURL(id), nonblocking: true)
        defer { withExtendedLifetime(lock) {} }
        guard let task = try store.tasks().first(where: { $0.id == id }) else { throw CadenceError.message("Task no longer exists.") }
        guard task.enabled || manual else { return }
        try task.validate()
        try? FileManager.default.removeItem(at: store.cancelURL(id))
        // A previous worker died after claiming the occurrence. Do not repeat unknown side effects.
        for var record in try store.runs() where record.taskID == id && record.status == .running {
            record.status = .interrupted; record.finishedAt = Date(); record.message = "Runner stopped unexpectedly. This occurrence was claimed and will not replay automatically."
            if var results = record.stepResults {
                for index in results.indices where results[index].status == .running { results[index].status = .interrupted }
                record.stepResults = results
            }
            try store.saveRun(record)
        }
        let now = Date()
        var state: TaskState
        if FileManager.default.fileExists(atPath: store.stateURL(id).path) {
            state = try store.read(TaskState.self, at: store.stateURL(id))
            if state.revision != task.scheduleRevision { state = TaskState(revision: task.scheduleRevision, nextDue: task.schedule.next(after: task.scheduleActivatedAt.addingTimeInterval(-1))) }
        } else { state = TaskState(revision: task.scheduleRevision, nextDue: task.schedule.next(after: task.scheduleActivatedAt.addingTimeInterval(-1))) }
        let plan = manual ? DuePlan(dates: [now], nextDue: state.nextDue, omitted: 0) : try Planner.plan(task: task, nextDue: state.nextDue, now: now)
        if !manual && plan.omitted > 0 {
            var skipped = RunRecord(task: task, scheduledAt: state.nextDue ?? now, manual: false)
            skipped.status = .skipped; skipped.finishedAt = now; skipped.message = "\(plan.omitted) occurrence(s) \(task.missedPolicy == .latest ? "coalesced into the latest run" : "outside the grace period")."
            try store.saveRun(skipped)
        }
        if plan.dates.isEmpty && !manual { state.nextDue = plan.nextDue; try store.write(state, at: store.stateURL(id)); return }
        for scheduled in plan.dates {
            guard let current = try store.tasks().first(where: { $0.id == id }), manual || (current.enabled && current == task) else { break }
            if FileManager.default.fileExists(atPath: store.cancelURL(id).path) { break }
            var record = RunRecord(task: task, scheduledAt: scheduled, manual: manual); record.pid = getpid(); record.stepResults = []
            try store.saveRun(record)
            if !manual {
                state.nextDue = task.missedPolicy == .latest ? plan.nextDue : task.schedule.next(after: scheduled)
                // Claim before side effects; guarantees no automatic duplicate after a crash.
                try store.write(state, at: store.stateURL(id))
            }
            let executor = StepExecutor(store: store, task: task, run: record, dialogs: dialogs)
            var context = StepContext(now: Date(), scheduled: scheduled, timeZone: task.schedule.calendar.timeZone)
            for step in task.steps where !step.key.isEmpty { context.results[step.key] = NamedStepResult(status: .pending) }
            var failures: [String] = []
            var completed = 0, skipped = 0
            do {
                for (index, step) in task.steps.enumerated() {
                    if executor.cancelled { throw CadenceError.message("Cancelled by user.") }
                    if let condition = step.runIf, !condition.matches(context.results[condition.step]) {
                        let source = context.results[condition.step]?.status.rawValue ?? "missing"
                        let reason = "Condition was false: \(condition.summary) (source status: \(source))."
                        executor.append("\n━━ Step \(index + 1): \(step.name) · Skipped ━━\n\(reason)\n")
                        record.stepResults?.append(StepRunRecord(step: step, status: .skipped, message: reason))
                        if !step.key.isEmpty { context.results[step.key] = NamedStepResult(status: .skipped) }
                        skipped += 1
                        try store.saveRun(record)
                        continue
                    }
                    let resultIndex = record.stepResults?.count ?? 0
                    record.stepResults?.append(StepRunRecord(step: step, status: .running))
                    try store.saveRun(record)
                    do {
                        let output = try executor.execute(step, index: index, context: context)
                        let outputFile = store.runDirectory(record.id).appendingPathComponent("step-\(index + 1).output.txt").path
                        if !step.key.isEmpty { context.results[step.key] = NamedStepResult(status: .succeeded, output: output, outputFile: outputFile) }
                        if step.kind == .question { context.input = output }
                        if step.kind != .response {
                            context.previous = output
                            context.previousFile = outputFile
                        }
                        record.stepResults?[resultIndex].status = .succeeded
                        completed += 1
                        try store.saveRun(record)
                    }
                    catch {
                        executor.append("ERROR: \(error.localizedDescription)\n")
                        let status: StepResultStatus = executor.cancelled || error is WorkflowCancelled ? .cancelled : .failed
                        if !step.key.isEmpty { context.results[step.key] = NamedStepResult(status: status) }
                        record.stepResults?[resultIndex].status = status
                        record.stepResults?[resultIndex].message = error.localizedDescription
                        try store.saveRun(record)
                        if !step.continueOnFailure || executor.cancelled || error is WorkflowCancelled { throw error }
                        failures.append(error.localizedDescription); context.previous = ""; context.previousFile = ""
                    }
                }
                record.status = failures.isEmpty ? .succeeded : .failed
                record.message = failures.isEmpty ? (skipped == 0 ? "All \(task.steps.count) step(s) completed." : "\(completed) step(s) completed; \(skipped) skipped.") : failures.joined(separator: "\n")
            } catch {
                record.status = executor.cancelled || error is WorkflowCancelled ? .cancelled : .failed
                record.message = error.localizedDescription; executor.append("\n\(record.message)\n")
            }
            record.finishedAt = Date(); try store.saveRun(record)
            if executor.cancelled { break }
        }
    }
}
