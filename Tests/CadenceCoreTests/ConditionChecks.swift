import Foundation
import CadenceCore

private final class ConditionDialogs: WorkflowDialogs {
    var messages: [String] = []
    var answers: [String] = []
    var cancel = false
    func ask(message: String, title: String, timeout: Int) throws -> String {
        if cancel { throw WorkflowCancelled() }
        return answers.removeFirst()
    }
    func show(message: String, title: String, timeout: Int) throws { messages.append(message) }
}

extension CadenceCoreTests {
    func testConditionalConfigAndOldHistory() throws {
        var task = ScheduledTask(); task.steps[0].key = "fetch"
        var next = TaskStep.make(.response); next.body = "{{steps.fetch.output}}"
        next.runIf = StepCondition(step: "fetch", field: .status, operation: .equals, value: "succeeded")
        task.steps.append(next)
        try task.validate()
        let data = try FlowConfig.encode(task)
        XCTAssertEqual(try FlowConfig.decode(data).task().steps, task.steps)
        let raw = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var fields = (raw["steps"] as! [[String: Any]])
        XCTAssertNil(fields[1]["key"])
        XCTAssertEqual((fields[1]["runIf"] as! [String: Any])["operator"] as? String, "equals")
        fields[1]["runIf"] = ["step": "fetch", "operator": "isNotEmpty", "typo": true]
        var invalid = raw; invalid["steps"] = fields
        XCTAssertThrowsError(try FlowConfig.decode(JSONSerialization.data(withJSONObject: invalid)))
        let old = Data(#"{"name":"Old","schedule":{"kind":"daily"},"steps":[{"kind":"shell","body":"true"}]}"#.utf8)
        let oldTask = try FlowConfig.decode(old).task()
        XCTAssertEqual(oldTask.steps[0].key, ""); XCTAssertNil(oldTask.steps[0].runIf)
        var record = RunRecord(task: task, scheduledAt: Date(), manual: true)
        record.stepResults = [StepRunRecord(step: task.steps[0], status: .skipped, message: "Condition was false")]
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(RunRecord.self, from: encoder.encode(record)).stepResults?.first?.status, .skipped)
        var oldRecord = try JSONSerialization.jsonObject(with: encoder.encode(record)) as! [String: Any]
        oldRecord.removeValue(forKey: "stepResults")
        XCTAssertNil(try decoder.decode(RunRecord.self, from: JSONSerialization.data(withJSONObject: oldRecord)).stepResults)
        let example = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Examples/conditional-report.cadence.json")
        try FlowConfig.decode(Data(contentsOf: example)).task().validate()
    }

    func testConditionalReferenceValidation() throws {
        var task = ScheduledTask(); task.steps[0].key = "fetch"
        var step = TaskStep.make(.response); step.body = "{{steps.fetch.output}} / {{steps.fetch.status}} / {{steps.fetch.output_file}}"
        step.key = "report"; step.runIf = StepCondition(step: "fetch")
        task.steps.append(step); try task.validate()
        // Display names are independent of references, and names may be repeated.
        task.steps[0].name = "Renamed"; task.steps[1].name = "Renamed"; try task.validate()
        var invalid = task; invalid.steps.reverse(); XCTAssertThrowsError(try invalid.validate())
        invalid = task; invalid.steps.removeFirst(); XCTAssertThrowsError(try invalid.validate())
        invalid = task; invalid.steps[1].key = "fetch"; XCTAssertThrowsError(try invalid.validate())
        for key in ["Has capitals", "1start", "has-dash", String(repeating: "a", count: 41), "x\n"] {
            invalid = task; invalid.steps[0].key = key; XCTAssertThrowsError(try invalid.validate())
        }
        for reference in ["{{steps.missing.output}}", "{{steps.report.output}}", "{{steps.fetch.typo}}", "{{ steps.fetch.output }}", "{{steps..output}}", "{{steps.fetch.output", "{{steps.fetch.outputxx", "{{steps.fetch.{{input}}}}"] {
            invalid = task; invalid.steps[1].body = reference; XCTAssertThrowsError(try invalid.validate())
        }
        invalid = task; invalid.steps[1].outputPath = "{{steps.report.output}}"; XCTAssertThrowsError(try invalid.validate())
        invalid = task; invalid.steps[1].runIf = StepCondition(step: "report"); XCTAssertThrowsError(try invalid.validate())
        invalid = task; invalid.steps[1].runIf = StepCondition(step: "fetch", field: .status, operation: .contains, value: "failed"); XCTAssertThrowsError(try invalid.validate())
        invalid = task; invalid.steps[1].runIf = StepCondition(step: "fetch", field: .status, operation: .equals, value: "typo"); XCTAssertThrowsError(try invalid.validate())
        invalid = task; invalid.environment = "VALUE={{steps.missing.output}}"; XCTAssertThrowsError(try invalid.validate())
        // Shell source remains literal, even if it contains placeholder-like text.
        invalid = task; invalid.steps[1].kind = .shell; invalid.steps[1].body = "printf '%s' '{{steps.missing.output}}'"; try invalid.validate()
    }

    func testEveryConditionOperator() {
        let result = NamedStepResult(status: .succeeded, output: "Hello 世界")
        let cases: [(ConditionOperator, String, Bool)] = [
            (.isEmpty, "", false), (.isNotEmpty, "", true), (.equals, "Hello 世界", true),
            (.equals, "hello 世界", false), (.notEquals, "hello 世界", true),
            (.contains, "世界", true), (.contains, "hello", false), (.notContains, "missing", true)
        ]
        for (operation, value, expected) in cases {
            XCTAssertEqual(StepCondition(step: "fetch", operation: operation, value: value).matches(result), expected)
        }
        XCTAssertTrue(StepCondition(step: "fetch", operation: .isEmpty).matches(NamedStepResult(status: .succeeded, output: " \n\t")))
        for status in StepResultStatus.allCases where status != .succeeded {
            for operation in ConditionOperator.allCases {
                XCTAssertFalse(StepCondition(step: "fetch", operation: operation, value: "anything").matches(NamedStepResult(status: status)))
            }
        }
        XCTAssertFalse(StepCondition(step: "fetch").matches(nil))
        XCTAssertTrue(StepCondition(step: "fetch", field: .status, operation: .equals, value: "skipped").matches(NamedStepResult(status: .skipped)))
        XCTAssertTrue(StepCondition(step: "fetch", field: .status, operation: .notEquals, value: "succeeded").matches(NamedStepResult(status: .failed)))
    }

    func testConditionalBranchesAndPreviousOutput() throws {
        let store = try temporaryStore(); var task = ScheduledTask(); task.workingDirectory = store.root.path
        task.steps[0].key = "fetch"; task.steps[0].body = "printf '%s' \"$PAYLOAD\""
        var positive = TaskStep.make(.shell); positive.key = "positive"; positive.body = "printf 'report:%s' \"$TASK_STEP_FETCH_OUTPUT\""; positive.outputPath = "positive.txt"
        positive.runIf = StepCondition(step: "fetch", operation: .isNotEmpty)
        var empty = TaskStep.make(.shell); empty.key = "empty"; empty.body = "printf no-changes"; empty.outputPath = "empty.txt"
        empty.runIf = StepCondition(step: "fetch", operation: .isEmpty)
        var final = TaskStep.make(.shell); final.body = "printf '%s|%s|%s|%s' \"$TASK_PREVIOUS_OUTPUT\" \"$TASK_STEP_FETCH_OUTPUT\" \"$TASK_STEP_POSITIVE_STATUS\" \"$TASK_STEP_EMPTY_STATUS\""; final.outputPath = "final.txt"
        task.steps += [positive, empty, final]
        for payload in ["Hello 世界", ""] {
            let earlierRunIDs = Set(try store.runs().map(\.id))
            task.environment = "PAYLOAD=\(payload)"; try store.save(task)
            try TaskRunner.run(store: store, id: task.id, manual: true)
            let run = try store.runs().first(where: { !earlierRunIDs.contains($0.id) })!
            XCTAssertEqual(run.status, .succeeded)
            XCTAssertEqual(run.stepResults?.map(\.status), payload.isEmpty ? [.succeeded, .skipped, .succeeded, .succeeded] : [.succeeded, .succeeded, .skipped, .succeeded])
            let expected = payload.isEmpty ? "no-changes||skipped|succeeded" : "report:\(payload)|\(payload)|succeeded|skipped"
            XCTAssertEqual(try String(contentsOf: store.root.appendingPathComponent("final.txt")), expected)
            let skippedIndex = payload.isEmpty ? 2 : 3
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.runDirectory(run.id).appendingPathComponent("step-\(skippedIndex).output.txt").path))
            XCTAssertTrue(store.log(run.id).contains("Condition was false"))
            XCTAssertTrue(run.message.contains("1 skipped"))
        }
    }

    func testNamedResultsAreSinglePassAndSafeAcrossKinds() throws {
        let store = try temporaryStore(); var task = ScheduledTask(); task.workingDirectory = store.root.path
        let payload = "世界 $(touch injected) `touch injected2` {{date}} {{steps.fetch.output}}"
        try Data(payload.utf8).write(to: store.root.appendingPathComponent("payload.txt"))
        task.environment = "FROM_RESULT={{steps.fetch.output}}\nSTATE={{steps.fetch.status}}"
        task.steps[0].key = "fetch"; task.steps[0].body = "cat payload.txt"
        var skipped = TaskStep.make(.question); skipped.key = "ask"; skipped.runIf = StepCondition(step: "fetch", operation: .isEmpty)
        let scriptURL = store.root.appendingPathComponent("echo argument.sh")
        try Data("printf '%s' \"$1\"\n".utf8).write(to: scriptURL)
        var script = TaskStep.make(.script); script.key = "copy"; script.scriptPath = "echo argument.sh"; script.arguments = "{{steps.fetch.output}}"; script.outputPath = "copy-{{steps.fetch.status}}.txt"
        var alert = TaskStep.make(.response); alert.key = "display"; alert.body = "{{steps.fetch.output}}|{{steps.ask.status}}|{{steps.ask.output_file}}"; alert.runIf = StepCondition(step: "ask", field: .status, operation: .equals, value: "skipped")
        var final = TaskStep.make(.shell); final.body = "printf '%s|%s|%s' \"$FROM_RESULT\" \"$STATE\" \"$TASK_PREVIOUS_OUTPUT\""; final.outputPath = "final.txt"
        task.steps += [skipped, script, alert, final]
        let dialogs = ConditionDialogs()
        try store.save(task); try TaskRunner.run(store: store, id: task.id, manual: true, dialogs: dialogs)
        XCTAssertEqual(try store.runs().first?.status, .succeeded)
        XCTAssertEqual(try String(contentsOf: store.root.appendingPathComponent("copy-succeeded.txt")), payload)
        XCTAssertEqual(dialogs.messages, ["\(payload)|skipped|"])
        XCTAssertEqual(try String(contentsOf: store.root.appendingPathComponent("final.txt")), "\(payload)|succeeded|\(payload)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("injected").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("injected2").path))
        let record = try store.runs().first!
        XCTAssertEqual(try String(contentsOf: store.runDirectory(record.id).appendingPathComponent("step-4.output.txt")), "\(payload)|skipped|")
    }

    func testContinuedFailureAndSkippedStatusBranches() throws {
        let store = try temporaryStore(); var task = ScheduledTask(); task.workingDirectory = store.root.path
        task.steps[0].key = "fetch"; task.steps[0].body = "printf partial; exit 7"; task.steps[0].continueOnFailure = true
        var outputCheck = TaskStep.make(.shell); outputCheck.key = "empty"; outputCheck.body = "touch should-not-run"; outputCheck.runIf = StepCondition(step: "fetch", operation: .isEmpty)
        var recovery = TaskStep.make(.shell); recovery.body = "printf '%s|%s|%s' \"$TASK_STEP_FETCH_STATUS\" \"$TASK_STEP_FETCH_OUTPUT\" \"$TASK_STEP_FETCH_OUTPUT_FILE\""; recovery.outputPath = "failure.txt"
        recovery.runIf = StepCondition(step: "fetch", field: .status, operation: .equals, value: "failed")
        var fallback = TaskStep.make(.shell); fallback.body = "touch fallback"; fallback.runIf = StepCondition(step: "empty", field: .status, operation: .equals, value: "skipped")
        task.steps += [outputCheck, recovery, fallback]
        try store.save(task); try TaskRunner.run(store: store, id: task.id, manual: true)
        let run = try store.runs().first!
        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.stepResults?.map(\.status), [.failed, .skipped, .succeeded, .succeeded])
        XCTAssertEqual(try String(contentsOf: store.root.appendingPathComponent("failure.txt")), "failed||")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("should-not-run").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("fallback").path))
    }

    func testInvalidReferencesStopBeforeSideEffects() throws {
        let store = try temporaryStore(); var task = ScheduledTask(); task.workingDirectory = store.root.path
        task.steps[0].body = "touch should-not-run"
        var next = TaskStep.make(.response); next.body = "{{steps.missing.output}}"; task.steps.append(next)
        try store.save(task)
        XCTAssertThrowsError(try TaskRunner.run(store: store, id: task.id, manual: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("should-not-run").path))
        XCTAssertTrue(try store.runs().isEmpty)
    }

    func testLargeNamedOutputAndEnvironmentBudget() throws {
        let store = try temporaryStore(); var task = ScheduledTask(); task.workingDirectory = store.root.path
        task.steps[0].key = "large"; task.steps[0].body = "head -c 1200000 /dev/zero | tr '\\0' x"
        var copy = TaskStep.make(.shell); copy.body = "wc -c < \"$TASK_STEP_LARGE_OUTPUT_FILE\""; copy.outputPath = "size.txt"
        task.steps.append(copy); try store.save(task); try TaskRunner.run(store: store, id: task.id, manual: true)
        XCTAssertEqual(try store.runs().first?.status, .succeeded)
        XCTAssertEqual(try String(contentsOf: store.root.appendingPathComponent("size.txt")).trimmingCharacters(in: .whitespacesAndNewlines), "1200000")
        var context = StepContext(now: Date(), scheduled: Date(), timeZone: .current)
        for index in 0..<30 { context.results["result_\(index)"] = NamedStepResult(status: .succeeded, output: String(repeating: "界", count: 20000)) }
        let environment = context.environment(task: ScheduledTask())
        let outputBytes = environment.filter { $0.key.hasPrefix("TASK_STEP_") && $0.key.hasSuffix("_OUTPUT") }.values.reduce(0) { $0 + $1.utf8.count }
        XCTAssertLessThan(outputBytes, 48001)
        XCTAssertFalse(environment.filter { $0.key.hasPrefix("TASK_STEP_") }.values.contains { $0.contains("\u{FFFD}") })
        // Environment references are reevaluated at each step and start pending.
        context.results["future"] = NamedStepResult(status: .pending)
        XCTAssertEqual(context.expand("{{steps.future.output}}|{{steps.future.status}}"), "|pending")
    }

    func testConditionalQuestionCancellation() throws {
        let store = try temporaryStore(); var task = ScheduledTask(); task.workingDirectory = store.root.path
        task.steps[0].key = "fetch"; task.steps[0].body = "printf ready"
        var question = TaskStep.make(.question); question.key = "answer"; question.continueOnFailure = true; question.runIf = StepCondition(step: "fetch")
        var final = TaskStep.make(.shell); final.body = "touch should-not-run"; final.runIf = StepCondition(step: "answer", field: .status, operation: .equals, value: "cancelled")
        task.steps += [question, final]
        let dialogs = ConditionDialogs(); dialogs.cancel = true
        try store.save(task); try TaskRunner.run(store: store, id: task.id, manual: true, dialogs: dialogs)
        let record = try store.runs().first!
        XCTAssertEqual(record.status, .cancelled)
        XCTAssertEqual(record.stepResults?.map(\.status), [.succeeded, .cancelled])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("should-not-run").path))
    }

    func testConditionalRunnerProcessAndAllLaterStepsSkipped() throws {
        guard let executable = ProcessInfo.processInfo.environment["CADENCE_TEST_RUNNER"] else { throw XCTSkip("Runner path is required") }
        let store = try temporaryStore(); var task = ScheduledTask(); task.workingDirectory = store.root.path
        task.steps[0].key = "fetch"; task.steps[0].body = "printf '  \\n'"
        var step = TaskStep.make(.shell); step.key = "report"; step.body = "touch should-not-run"; step.outputPath = "should-not-exist.txt"; step.runIf = StepCondition(step: "fetch")
        var chained = step; chained.id = UUID(); chained.key = "chained"; chained.runIf = StepCondition(step: "report", operation: .isEmpty)
        task.steps += [step, chained]; try store.save(task)
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--task", task.id.uuidString, "--manual", "--data-dir", store.root.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let record = try store.runs().first!
        XCTAssertEqual(record.status, .succeeded)
        XCTAssertEqual(record.stepResults?.map(\.status), [.succeeded, .skipped, .skipped])
        XCTAssertEqual(record.message, "1 step(s) completed; 2 skipped.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("should-not-run").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("should-not-exist.txt").path))
    }
}
