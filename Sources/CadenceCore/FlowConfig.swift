import Foundation

/// The public, versioned configuration format. Runtime cursors and registration state never live here.
public struct FlowConfig: Codable {
    public var schema: String?
    public var version = 1
    public var id: UUID?
    public var name: String
    public var notes = ""
    public var enabled = false
    public var schedule = TaskSchedule()
    public var missedPolicy: MissedPolicy = .latest
    public var catchUpLimit = 5
    public var graceSeconds = 90
    public var workingDirectory = "~"
    public var environment = ""
    public var steps: [TaskStep]
    private var missingStepIDs: Set<Int> = []
    enum CodingKeys: String, CodingKey {
        case version, id, name, enabled, schedule, missedPolicy, catchUpLimit, graceSeconds, workingDirectory, environment, steps
        case notes = "description"
        case schema = "$schema"
    }
    public init(task: ScheduledTask) {
        id = task.id; name = task.name; notes = task.notes; enabled = task.enabled
        schedule = task.schedule; missedPolicy = task.missedPolicy; catchUpLimit = task.catchUpLimit
        graceSeconds = task.graceSeconds; workingDirectory = task.workingDirectory
        environment = task.environment; steps = task.steps
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(String.self, forKey: .schema)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard version == 1 else { throw CadenceError.message("Unsupported config version \(version). Expected version 1.") }
        id = try c.decodeIfPresent(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        schedule = try c.decode(TaskSchedule.self, forKey: .schedule)
        missedPolicy = try c.decodeIfPresent(MissedPolicy.self, forKey: .missedPolicy) ?? .latest
        catchUpLimit = try c.decodeIfPresent(Int.self, forKey: .catchUpLimit) ?? 5
        graceSeconds = try c.decodeIfPresent(Int.self, forKey: .graceSeconds) ?? 90
        workingDirectory = try c.decodeIfPresent(String.self, forKey: .workingDirectory) ?? "~"
        environment = try c.decodeIfPresent(String.self, forKey: .environment) ?? ""
        var list = try c.nestedUnkeyedContainer(forKey: .steps)
        steps = []
        while !list.isAtEnd {
            let stepDecoder = try list.superDecoder()
            let fields = try stepDecoder.container(keyedBy: TaskStep.CodingKeys.self)
            if !fields.contains(.id) { missingStepIDs.insert(steps.count) }
            steps.append(try TaskStep(from: stepDecoder))
        }
        guard Set(steps.map(\.id)).count == steps.count else { throw CadenceError.message("Each step needs a unique id.") }
    }
    public func task(assignedID: UUID? = nil) -> ScheduledTask {
        var task = ScheduledTask()
        task.id = assignedID ?? id ?? task.id
        task.name = name; task.notes = notes; task.enabled = enabled; task.schedule = schedule
        task.missedPolicy = missedPolicy; task.catchUpLimit = catchUpLimit; task.graceSeconds = graceSeconds
        task.workingDirectory = workingDirectory; task.environment = environment; task.steps = steps
        // Handwritten steps may omit IDs. Derive stable identities until the next UI save supplies them.
        for index in missingStepIDs {
            var bytes = task.id.uuid
            bytes.12 ^= 0xC0
            bytes.13 ^= UInt8((index >> 16) & 255); bytes.14 ^= UInt8((index >> 8) & 255); bytes.15 ^= UInt8(index & 255)
            task.steps[index].id = UUID(uuid: bytes)
        }
        return task
    }
    public static func decode(_ data: Data) throws -> FlowConfig {
        // Reject typos instead of silently ignoring misspelled options in a handwritten config.
        func check(_ object: Any?, allowed: Set<String>, location: String) throws {
            guard let values = object as? [String: Any] else { return }
            let unknown = Set(values.keys).subtracting(allowed)
            if !unknown.isEmpty { throw CadenceError.message("Unknown field(s) in \(location): \(unknown.sorted().joined(separator: ", ")).") }
        }
        let raw = try JSONSerialization.jsonObject(with: data)
        try check(raw, allowed: Set(CodingKeys.allNames), location: "flow")
        if let object = raw as? [String: Any] {
            try check(object["schedule"], allowed: ["kind", "hour", "minute", "weekdays", "every", "anchor", "timeZone"], location: "schedule")
            if let steps = object["steps"] as? [Any] {
                for (index, step) in steps.enumerated() {
                    try check(step, allowed: ["id", "name", "kind", "body", "executable", "scriptPath", "arguments", "model", "endpoint", "sandbox", "outputPath", "timeoutSeconds", "continueOnFailure", "key", "runIf"], location: "step \(index + 1)")
                    if let fields = step as? [String: Any] {
                        try check(fields["runIf"], allowed: ["step", "field", "operator", "value"], location: "step \(index + 1) runIf")
                        let field = fields["kind"] as? String == "script" ? "scriptPath" : "body"
                        if fields[field] == nil { throw CadenceError.message("Missing \(field) in step \(index + 1).") }
                    }
                }
            }
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        do { return try decoder.decode(FlowConfig.self, from: data) }
        catch let error as DecodingError {
            switch error {
            case .keyNotFound(let key, let context):
                throw CadenceError.message("Missing \(key.stringValue) at \(context.codingPath.map(\.stringValue).joined(separator: ".")).")
            case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
                throw CadenceError.message("Invalid config at \(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)")
            @unknown default: throw error
            }
        }
    }
    public static func encode(_ task: ScheduledTask, schema: String? = nil) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var config = FlowConfig(task: task); config.schema = schema
        let data = try encoder.encode(config)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let common: Set<String> = ["id", "name", "kind", "timeoutSeconds", "continueOnFailure", "outputPath", "key", "runIf"]
        object["steps"] = (object["steps"] as! [[String: Any]]).enumerated().map { index, fields in
            let specific: Set<String>
            switch task.steps[index].kind {
            case .shell, .question, .response: specific = ["body"]
            case .script: specific = ["scriptPath", "executable", "arguments"]
            case .codex: specific = ["body", "executable", "model", "sandbox"]
            case .localLLM: specific = ["body", "endpoint", "model"]
            }
            var result = fields.filter { common.union(specific).contains($0.key) }
            if task.steps[index].key.isEmpty { result.removeValue(forKey: "key") }
            if task.steps[index].kind == .question { result["kind"] = "userInput" }
            if task.steps[index].kind == .response { result["kind"] = "alert" }
            if task.steps[index].kind == .script {
                result["arguments"] = task.steps[index].arguments.components(separatedBy: "\n").filter { !$0.isEmpty }
            }
            return result
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) + Data("\n".utf8)
    }
}
private extension FlowConfig.CodingKeys {
    static var allNames: [String] {
        ["$schema", "version", "id", "name", "description", "enabled", "schedule", "missedPolicy", "catchUpLimit", "graceSeconds", "workingDirectory", "environment", "steps"]
    }
}

public struct ConfigIssue: Identifiable {
    public var id: String { url.path }
    public let url: URL
    public let message: String
}
public struct FlowCatalog {
    public var tasks: [ScheduledTask] = []
    public var files: [UUID: URL] = [:]
    public var issues: [ConfigIssue] = []
}
struct FlowMetadata: Codable {
    var revision: UUID
    var activatedAt: Date
    var createdAt: Date
    var schedule: TaskSchedule
    var enabled: Bool
    init(task: ScheduledTask) {
        revision = task.scheduleRevision; activatedAt = task.scheduleActivatedAt; createdAt = task.createdAt
        schedule = task.schedule; enabled = task.enabled
    }
}
