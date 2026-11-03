import Foundation

public enum ConditionField: String, Codable, CaseIterable, Identifiable {
    case output, status
    public var id: String { rawValue }
    public var title: String { self == .output ? "Output" : "Status" }
    public var operators: [ConditionOperator] { self == .output ? ConditionOperator.allCases : [.equals, .notEquals] }
}

public enum ConditionOperator: String, Codable, CaseIterable, Identifiable {
    case isEmpty, isNotEmpty, equals, notEquals, contains, notContains
    public var id: String { rawValue }
    public var needsValue: Bool { self != .isEmpty && self != .isNotEmpty }
    public var title: String {
        switch self {
        case .isEmpty: return "is empty"
        case .isNotEmpty: return "is not empty"
        case .equals: return "equals"
        case .notEquals: return "does not equal"
        case .contains: return "contains"
        case .notContains: return "does not contain"
        }
    }
}

public struct StepCondition: Codable, Equatable {
    public var step: String
    public var field: ConditionField = .output
    public var operation: ConditionOperator = .isNotEmpty
    public var value = ""
    enum CodingKeys: String, CodingKey { case step, field, value; case operation = "operator" }
    public init(step: String, field: ConditionField = .output, operation: ConditionOperator = .isNotEmpty, value: String = "") {
        self.step = step; self.field = field; self.operation = operation; self.value = value
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        step = try c.decode(String.self, forKey: .step)
        field = try c.decodeIfPresent(ConditionField.self, forKey: .field) ?? .output
        operation = try c.decode(ConditionOperator.self, forKey: .operation)
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
    }
    public var summary: String {
        "\(step).\(field.rawValue) \(operation.title)" + (operation.needsValue ? " \(String(reflecting: value))" : "")
    }
    public func matches(_ result: NamedStepResult?) -> Bool {
        guard let result else { return false }
        if field == .output && result.status != .succeeded { return false }
        let text = field == .output ? result.output : result.status.rawValue
        switch operation {
        case .isEmpty: return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .isNotEmpty: return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .equals: return text == value
        case .notEquals: return text != value
        case .contains: return text.contains(value)
        case .notContains: return !text.contains(value)
        }
    }
}

public enum StepResultStatus: String, Codable, CaseIterable, Identifiable {
    case pending, running, succeeded, failed, skipped, cancelled, interrupted
    public var id: String { rawValue }
    public static var conditionValues: [Self] { [.succeeded, .failed, .skipped, .cancelled] }
}

public struct NamedStepResult {
    public var status: StepResultStatus
    public var output: String
    public var outputFile: String
    public init(status: StepResultStatus, output: String = "", outputFile: String = "") {
        self.status = status; self.output = output; self.outputFile = outputFile
    }
    func value(_ field: String) -> String {
        switch field { case "output": return output; case "output_file": return outputFile; case "status": return status.rawValue; default: return "" }
    }
}

public struct StepRunRecord: Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var key: String
    public var status: StepResultStatus
    public var message: String
    public init(step: TaskStep, status: StepResultStatus, message: String = "") {
        id = step.id; name = step.name; key = step.key; self.status = status; self.message = message
    }
}

public enum WorkflowReferences {
    public static func validKey(_ key: String) -> Bool {
        key.range(of: #"\A[a-z][a-z0-9_]{0,39}\z"#, options: .regularExpression) != nil
    }
    static let referencePattern = try! NSRegularExpression(pattern: #"\{\{\s*steps\b[\s\S]*?(?:\}\}|$)"#)
    static func keys(in text: String) throws -> [String] {
        let original = text as NSString
        return try referencePattern.matches(in: text, range: NSRange(location: 0, length: original.length)).map { match in
            let token = original.substring(with: match.range)
            let parts = String(token.dropFirst(2).dropLast(2)).split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard token.hasSuffix("}}"), parts.count == 3, parts[0] == "steps", validKey(parts[1]), ["output", "output_file", "status"].contains(parts[2]) else {
                throw CadenceError.message("Invalid result reference \(token). Use {{steps.result_name.output}}, output_file, or status.")
            }
            return parts[1]
        }
    }
    public static func validate(_ task: ScheduledTask) throws {
        var available: Set<String> = []
        for step in task.steps where !step.key.isEmpty {
            guard validKey(step.key) else { throw CadenceError.message("Result name \(String(reflecting: step.key)) must start with a lowercase letter and contain only lowercase letters, digits, or underscores (up to 40 characters).") }
            guard available.insert(step.key).inserted else { throw CadenceError.message("Result name \(step.key) is used more than once. Give each result a unique name.") }
        }
        for key in try keys(in: task.environment) where !available.contains(key) {
            throw CadenceError.message("Environment refers to missing result \(key).")
        }
        var earlier: Set<String> = []
        for (index, step) in task.steps.enumerated() {
            let location = "Step \(index + 1) (\(step.name))"
            if let condition = step.runIf {
                guard earlier.contains(condition.step) else { throw CadenceError.message("\(location): Run if must select an earlier named result; \(condition.step.isEmpty ? "no result is selected" : condition.step + " is missing or comes later").") }
                guard condition.field.operators.contains(condition.operation) else { throw CadenceError.message("\(location): Status conditions support equals or does not equal.") }
                if condition.field == .status && !StepResultStatus.conditionValues.map(\.rawValue).contains(condition.value) {
                    throw CadenceError.message("\(location): Choose succeeded, failed, skipped, or cancelled for a status condition.")
                }
            }
            var templated = [step.outputPath]
            if step.kind == .script { templated += [step.scriptPath, step.arguments] }
            else if step.kind != .shell { templated.append(step.body) }
            for text in templated {
                for key in try keys(in: text) where !earlier.contains(key) {
                    throw CadenceError.message("\(location) refers to result \(key), which is missing or does not come before this step.")
                }
            }
            if !step.key.isEmpty { earlier.insert(step.key) }
        }
    }
}
