import Foundation

public enum ScheduleKind: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, everyDays, interval, once
    public var id: String { rawValue }
    public var title: String {
        switch self { case .daily: return "Daily"; case .weekly: return "Days of the week"
        case .everyDays: return "Every N days"; case .interval: return "Every N minutes"; case .once: return "Once" }
    }
}

public struct TaskSchedule: Codable, Equatable {
    public var kind: ScheduleKind = .daily
    public var hour = 9
    public var minute = 0
    public var weekdays: [Int] = [2, 3, 4, 5, 6]
    public var every = 2
    public var anchor = Date()
    public var timeZone = TimeZone.current.identifier
    public init() {}
    public var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: timeZone) ?? .current
        return c
    }
    public func formatted(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE d MMM yyyy 'at' HH:mm zzz"
        return formatter.string(from: date)
    }
    public func next(after date: Date) -> Date? {
        let c = calendar
        if kind == .once { return anchor > date ? anchor : nil }
        if kind == .interval {
            let seconds = Double(max(1, every)) * 60
            if date < anchor { return anchor }
            return anchor.addingTimeInterval((floor(date.timeIntervalSince(anchor) / seconds) + 1) * seconds)
        }
        if kind == .daily {
            return c.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute, second: 0), matchingPolicy: .nextTime, repeatedTimePolicy: .first)
        }
        // Iterate local calendar days, so an every-two-days schedule stays at its wall-clock time across DST.
        let first = c.startOfDay(for: date)
        let origin = c.startOfDay(for: anchor)
        for offset in 0...3700 {
            guard let day = c.date(byAdding: .day, value: offset, to: first),
                  let candidate = c.date(bySettingHour: hour, minute: minute, second: 0, of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward), candidate > date else { continue }
            if kind == .weekly && weekdays.contains(c.component(.weekday, from: day)) { return candidate }
            if kind == .everyDays {
                let days = c.dateComponents([.day], from: origin, to: day).day ?? -1
                if days >= 0 && days % max(1, every) == 0 { return candidate }
            }
        }
        return nil
    }
    public var summary: String {
        let time = String(format: "%02d:%02d", hour, minute)
        switch kind {
        case .daily: return "Every day at \(time)"
        case .weekly:
            let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            return weekdays.sorted().map { names[max(0, min(6, $0 - 1))] }.joined(separator: ", ") + " at \(time)"
        case .everyDays: return "Every \(every) days at \(time)"
        case .interval: return "Every \(every) minutes"
        case .once: return "Once · " + formatted(anchor)
        }
    }
}

public enum MissedPolicy: String, Codable, CaseIterable, Identifiable {
    case skip, latest, all
    public var id: String { rawValue }
    public var title: String {
        switch self { case .skip: return "Skip missed runs"; case .latest: return "Run the latest only"; case .all: return "Replay missed runs in order" }
    }
    public var detail: String {
        switch self {
        case .skip: return "Only run occurrences within the grace period. Older occurrences are recorded as skipped."
        case .latest: return "On wake or login, run the most recent occurrence. Coalesce older occurrences into it."
        case .all: return "Replay oldest first, up to the batch limit per check. The rest stay queued for the next check."
        }
    }
}
public enum StepKind: String, Codable, CaseIterable, Identifiable {
    case shell, script, codex, localLLM, question, response
    public var id: String { rawValue }
    public var title: String {
        switch self { case .shell: return "Inline command"; case .script: return "Script file / executable"; case .codex: return "Codex CLI"; case .localLLM: return "Local LLM (HTTP)"; case .question: return "User input"; case .response: return "Show alert" }
    }
    public var symbol: String {
        switch self { case .shell: return "terminal"; case .script: return "doc.text"; case .codex: return "sparkles"; case .localLLM: return "cpu"; case .question: return "bubble.left.and.text.bubble.right"; case .response: return "text.bubble" }
    }
}
public struct TaskStep: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var name = "Step"
    public var kind: StepKind = .shell
    public var body = "printf 'Task completed at %s\\n' \"$TASK_TIMESTAMP\""
    public var executable = "/bin/zsh"
    public var scriptPath = ""
    public var arguments = ""
    public var model = ""
    public var endpoint = "http://localhost:11434/v1/chat/completions"
    public var sandbox = "read-only"
    public var outputPath = ""
    public var timeoutSeconds = 600
    public var continueOnFailure = false
    public init() {}
    enum CodingKeys: String, CodingKey {
        case id, name, kind, body, executable, scriptPath, arguments, model, endpoint, sandbox, outputPath, timeoutSeconds, continueOnFailure
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? id
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? name
        kind = try c.decodeIfPresent(StepKind.self, forKey: .kind) ?? kind
        if (kind == .question && name == "Ask a question") || (kind == .response && name == "Show response") { name = kind.title }
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? body
        executable = try c.decodeIfPresent(String.self, forKey: .executable) ?? executable
        scriptPath = try c.decodeIfPresent(String.self, forKey: .scriptPath) ?? ""
        arguments = try c.decodeIfPresent(String.self, forKey: .arguments) ?? arguments
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? model
        endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint) ?? endpoint
        sandbox = try c.decodeIfPresent(String.self, forKey: .sandbox) ?? sandbox
        outputPath = try c.decodeIfPresent(String.self, forKey: .outputPath) ?? outputPath
        timeoutSeconds = try c.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? timeoutSeconds
        continueOnFailure = try c.decodeIfPresent(Bool.self, forKey: .continueOnFailure) ?? continueOnFailure
        if kind == .script && !c.contains(.scriptPath) {
            // Preserve the exact invocation of older executable steps.
            scriptPath = executable; executable = ""
        }
    }
    public static func make(_ kind: StepKind) -> TaskStep {
        var step = TaskStep(); step.kind = kind; step.name = kind.title
        switch kind {
        case .shell: break
        case .script: step.body = ""
        case .codex:
            step.executable = FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/codex") ? "/opt/homebrew/bin/codex" : "/usr/local/bin/codex"
            step.body = "Summarize this for {{scheduled_date}}:\n{{previous_output}}"
        case .localLLM: step.body = "Summarize this:\n{{previous_output}}"
        case .question: step.body = "What would you like to provide?"; step.timeoutSeconds = 300
        case .response: step.body = "{{previous_output}}"; step.timeoutSeconds = 120
        }
        return step
    }
}
public struct ScheduledTask: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var name = "Untitled task"
    public var notes = ""
    public var enabled = false
    public var schedule = TaskSchedule()
    public var missedPolicy: MissedPolicy = .latest
    public var catchUpLimit = 5
    public var graceSeconds = 90
    public var workingDirectory = FileManager.default.homeDirectoryForCurrentUser.path
    public var environment = ""
    public var steps: [TaskStep] = [TaskStep()]
    public var createdAt = Date()
    public var scheduleRevision = UUID()
    public var scheduleActivatedAt = Date()
    public init() {}
    enum CodingKeys: String, CodingKey {
        case id, name, notes, enabled, schedule, missedPolicy, catchUpLimit, graceSeconds, workingDirectory, environment, steps, createdAt, scheduleRevision, scheduleActivatedAt
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? notes
        enabled = try c.decode(Bool.self, forKey: .enabled)
        schedule = try c.decode(TaskSchedule.self, forKey: .schedule)
        missedPolicy = try c.decode(MissedPolicy.self, forKey: .missedPolicy)
        catchUpLimit = try c.decode(Int.self, forKey: .catchUpLimit)
        graceSeconds = try c.decode(Int.self, forKey: .graceSeconds)
        workingDirectory = try c.decode(String.self, forKey: .workingDirectory)
        environment = try c.decode(String.self, forKey: .environment)
        steps = try c.decode([TaskStep].self, forKey: .steps)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        scheduleRevision = try c.decode(UUID.self, forKey: .scheduleRevision)
        scheduleActivatedAt = try c.decode(Date.self, forKey: .scheduleActivatedAt)
        struct LegacyInteraction: Decodable { var question: String?; var showResult: Bool?; var promptTimeoutSeconds: Int? }
        let legacy = try LegacyInteraction(from: decoder)
        if let question = legacy.question, !question.isEmpty {
            var step = TaskStep.make(.question); var bytes = id.uuid; bytes.15 ^= 0xA1
            step.id = UUID(uuid: bytes); step.body = question; step.timeoutSeconds = legacy.promptTimeoutSeconds ?? 300
            steps.insert(step, at: 0)
        }
        if legacy.showResult == true {
            var step = TaskStep.make(.response); var bytes = id.uuid; bytes.15 ^= 0xB2
            step.id = UUID(uuid: bytes); steps.append(step)
        }
    }
    public func validate() throws {
        func require(_ condition: Bool, _ message: String) throws { if !condition { throw CadenceError.message(message) } }
        try require(!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Give the task a name.")
        try require(!steps.isEmpty, "Add at least one step.")
        try require(TimeZone(identifier: schedule.timeZone) != nil, "Choose a valid time zone identifier.")
        try require((0...23).contains(schedule.hour) && (0...59).contains(schedule.minute), "Choose a valid time.")
        try require((1...10000).contains(schedule.every), "The repeat interval must be between 1 and 10,000.")
        try require(schedule.kind != .weekly || !schedule.weekdays.isEmpty, "Select at least one weekday.")
        try require((1...100).contains(catchUpLimit) && (0...3600).contains(graceSeconds), "Check the catch-up limit and grace period.")
        var directory: ObjCBool = false
        try require(FileManager.default.fileExists(atPath: (workingDirectory as NSString).expandingTildeInPath, isDirectory: &directory) && directory.boolValue, "The working directory does not exist.")
        for line in environment.split(separator: "\n") where !line.isEmpty {
            let key = String(line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)[0])
            try require(line.contains("=") && key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil && !key.hasPrefix("TASK_"), "Environment entries must be KEY=value; TASK_ names are reserved.")
        }
        for step in steps {
            try require((1...86400).contains(step.timeoutSeconds), "Step timeout must be 1–86,400 seconds.")
            if step.kind != .script { try require(!step.body.isEmpty, "A command, prompt, or message is empty.") }
            if step.kind == .script { try require(!step.scriptPath.isEmpty, "Choose a script file or executable.") }
            if step.kind == .codex { try require(!step.executable.isEmpty, "Specify the Codex executable.") }
            if step.kind == .localLLM {
                try require(!step.model.isEmpty, "Enter the local model name.")
                try require(URL(string: step.endpoint)?.host != nil && ["http", "https"].contains(URL(string: step.endpoint)?.scheme ?? ""), "Enter a complete HTTP endpoint.")
            }
        }
    }
}

public struct TaskState: Codable {
    public var revision: UUID
    public var nextDue: Date?
    public init(revision: UUID, nextDue: Date?) { self.revision = revision; self.nextDue = nextDue }
}
public enum RunStatus: String, Codable { case running, succeeded, failed, cancelled, skipped, interrupted }
public struct RunRecord: Codable, Identifiable {
    public var id = UUID()
    public var taskID: UUID
    public var taskName: String
    public var scheduledAt: Date
    public var startedAt = Date()
    public var finishedAt: Date?
    public var status: RunStatus = .running
    public var message = ""
    public var manual = false
    public var pid: Int32 = 0
    public init(task: ScheduledTask, scheduledAt: Date, manual: Bool) {
        taskID = task.id; taskName = task.name; self.scheduledAt = scheduledAt; self.manual = manual
    }
}
public enum CadenceError: LocalizedError {
    case message(String)
    public var errorDescription: String? { switch self { case .message(let message): return message } }
}

public struct DuePlan {
    public var dates: [Date]
    public var nextDue: Date?
    public var omitted: Int
}
public enum Planner {
    public static func plan(task: ScheduledTask, nextDue: Date?, now: Date) throws -> DuePlan {
        guard let first = nextDue, first <= now else { return DuePlan(dates: [], nextDue: nextDue, omitted: 0) }
        // Fixed intervals can have years of backlog: compute without enumerating every minute.
        if task.schedule.kind == .interval {
            let interval = Double(max(1, task.schedule.every)) * 60
            let count = Int(floor(now.timeIntervalSince(first) / interval)) + 1
            let newest = first.addingTimeInterval(Double(count - 1) * interval)
            let future = first.addingTimeInterval(Double(count) * interval)
            switch task.missedPolicy {
            case .latest: return DuePlan(dates: [newest], nextDue: future, omitted: count - 1)
            case .skip:
                let available = Double(task.graceSeconds) - now.timeIntervalSince(newest)
                let recentCount = available >= 0 ? min(count, Int(floor(available / interval)) + 1) : 0
                let dates = (0..<recentCount).reversed().map { newest.addingTimeInterval(-Double($0) * interval) }
                return DuePlan(dates: dates, nextDue: future, omitted: count - dates.count)
            case .all:
                let n = min(count, task.catchUpLimit)
                return DuePlan(dates: (0..<n).map { first.addingTimeInterval(Double($0) * interval) }, nextDue: first.addingTimeInterval(Double(n) * interval), omitted: 0)
            }
        }
        var dates: [Date] = [], cursor: Date? = first, total = 0
        while let due = cursor, due <= now {
            total += 1
            guard total <= 100000 else { throw CadenceError.message("Backlog exceeds 100,000 occurrences. Edit the schedule to reset its cursor.") }
            switch task.missedPolicy {
            case .all: dates.append(due)
            case .latest: dates = [due]
            case .skip: if now.timeIntervalSince(due) <= Double(task.graceSeconds) { dates.append(due) }
            }
            cursor = task.schedule.next(after: due)
            if task.missedPolicy == .all && dates.count >= task.catchUpLimit { break }
        }
        return DuePlan(dates: dates, nextDue: cursor, omitted: task.missedPolicy == .all ? 0 : total - dates.count)
    }
}
