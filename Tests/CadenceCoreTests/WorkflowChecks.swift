import Foundation
import CadenceCore

private final class RecordingDialogs: WorkflowDialogs {
    var questions: [String] = []
    var messages: [String] = []
    var answers: [String]
    var cancel = false
    init(_ answers: [String] = []) { self.answers = answers }
    func ask(message: String, title: String, timeout: Int) throws -> String {
        questions.append(message)
        if cancel { throw WorkflowCancelled() }
        guard !answers.isEmpty else { throw CadenceError.message("Unexpected question") }
        return answers.removeFirst()
    }
    func show(message: String, title: String, timeout: Int) throws { messages.append(message) }
}

extension CadenceCoreTests {
    func testLegacyInteractionsMigrateOnceWithStableIDs() throws {
        var task = ScheduledTask(); task.enabled = true
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var object = try JSONSerialization.jsonObject(with: encoder.encode(task)) as! [String: Any]
        object["question"] = "Original question"; object["showResult"] = true; object["promptTimeoutSeconds"] = 240
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let migrated = try decoder.decode(ScheduledTask.self, from: data)
        XCTAssertEqual(migrated.steps.map(\.kind), [.question, .shell, .response])
        XCTAssertEqual(migrated.steps.first?.body, "Original question")
        XCTAssertEqual(migrated.steps.first?.timeoutSeconds, 240)
        XCTAssertEqual(migrated.steps.map(\.id), try decoder.decode(ScheduledTask.self, from: data).steps.map(\.id))
        XCTAssertEqual(migrated.id, task.id)
        XCTAssertEqual(migrated.scheduleRevision, task.scheduleRevision)
        XCTAssertEqual(migrated.enabled, true)
        let saved = try encoder.encode(migrated)
        let newObject = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
        XCTAssertNil(newObject["question"]); XCTAssertNil(newObject["showResult"]); XCTAssertNil(newObject["promptTimeoutSeconds"])
        XCTAssertEqual(try decoder.decode(ScheduledTask.self, from: saved).steps, migrated.steps)
    }
    func testLegacyExecutableKeepsExactArguments() throws {
        let step = TaskStep.make(.script)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(step)) as! [String: Any]
        object.removeValue(forKey: "scriptPath")
        object["executable"] = "/bin/zsh"
        object["arguments"] = "/a path/report.sh\n{{scheduled_date}}"
        let migrated = try JSONDecoder().decode(TaskStep.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(migrated.scriptPath, "/bin/zsh")
        XCTAssertEqual(migrated.executable, "")
        XCTAssertEqual(migrated.arguments, "/a path/report.sh\n{{scheduled_date}}")
    }
    func testFileScriptsAndInlineCommandsCoexist() throws {
        let store = try temporaryStore()
        let directory = store.root.appendingPathComponent("scripts with spaces")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("zsh"), withDestinationURL: URL(fileURLWithPath: "/bin/zsh"))
        let script = directory.appendingPathComponent("report.sh")
        try Data("#!/bin/zsh\nprintf '%s|%s|%s' \"$TASK_PREVIOUS_OUTPUT\" \"$1\" \"$TASK_SCHEDULED_DATE\"\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: script.path)
        var task = ScheduledTask(); task.workingDirectory = store.root.path
        task.steps[0].body = "printf inline"
        var file = TaskStep.make(.script); file.scriptPath = "scripts with spaces/report.sh"; file.arguments = "a 'quoted' $(literal) value"; file.outputPath = "answer.txt"
        file.executable = "scripts with spaces/zsh"
        task.steps.append(file)
        try store.save(task); try TaskRunner.run(store: store, id: task.id, manual: true)
        XCTAssertEqual(try store.runs().first?.status, .succeeded)
        let answer = try String(contentsOf: store.root.appendingPathComponent("answer.txt"))
        XCTAssertTrue(answer.hasPrefix("inline|a 'quoted' $(literal) value|"))
        // The same selected file also supports direct execution, without an interpreter.
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        task.steps[1].executable = ""; try store.save(task)
        try TaskRunner.run(store: store, id: task.id, manual: true)
        XCTAssertEqual(try store.runs().first?.status, .succeeded)
        XCTAssertEqual(try String(contentsOf: store.root.appendingPathComponent("answer.txt")), answer)
    }
    func testQuestionsAndResponsesAnywhereInWorkflow() throws {
        let store = try temporaryStore(); var task = ScheduledTask(); task.workingDirectory = store.root.path
        var first = TaskStep.make(.shell); first.body = "printf before"
        var question = TaskStep.make(.question); question.body = "First: {{previous_output}}"
        var response = TaskStep.make(.response); response.body = "Answer: {{input}}"
        var next = TaskStep.make(.shell); next.body = "printf '%s|%s' \"$TASK_INPUT\" \"$TASK_PREVIOUS_OUTPUT\""
        var secondQuestion = TaskStep.make(.question); secondQuestion.body = "Next: {{previous_output}}"
        var secondResponse = TaskStep.make(.response); secondResponse.body = "Final: {{previous_output}}"
        task.steps = [first, question, response, next, secondQuestion, secondResponse]
        let answer = "A $(literal) {{date}}"
        let dialogs = RecordingDialogs([answer, "B"])
        try store.save(task); try TaskRunner.run(store: store, id: task.id, manual: true, dialogs: dialogs)
        XCTAssertEqual(try store.runs().first?.status, .succeeded)
        XCTAssertEqual(dialogs.questions, ["First: before", "Next: \(answer)|\(answer)"])
        XCTAssertEqual(dialogs.messages, ["Answer: \(answer)", "Final: B"])
        let run = try store.runs().first!
        XCTAssertEqual(try String(contentsOf: store.runDirectory(run.id).appendingPathComponent("step-2.output.txt")), answer)
        XCTAssertEqual(try String(contentsOf: store.runDirectory(run.id).appendingPathComponent("step-5.output.txt")), "B")
    }
    func testQuestionCancellationStopsLaterSteps() throws {
        let store = try temporaryStore(); var task = ScheduledTask(); task.workingDirectory = store.root.path
        var first = TaskStep.make(.shell); first.body = "touch before-question"
        var question = TaskStep.make(.question); question.continueOnFailure = true
        var last = TaskStep.make(.shell); last.body = "touch after-question"
        task.steps = [first, question, TaskStep.make(.response), last]
        let dialogs = RecordingDialogs(); dialogs.cancel = true
        try store.save(task); try TaskRunner.run(store: store, id: task.id, manual: true, dialogs: dialogs)
        XCTAssertEqual(try store.runs().first?.status, .cancelled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("before-question").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("after-question").path))
        XCTAssertTrue(dialogs.messages.isEmpty)
    }
}

extension CadenceCoreTests {
    func testWorkflowReorder() {
        let original = [TaskStep.make(.question), TaskStep.make(.shell), TaskStep.make(.response)]
        var steps = original
        XCTAssertTrue(WorkflowOrder.move(original[0].id, in: &steps, toInsertion: 3))
        XCTAssertEqual(steps.map(\.id), [original[1].id, original[2].id, original[0].id])
        XCTAssertTrue(WorkflowOrder.move(original[0].id, in: &steps, toInsertion: 0))
        XCTAssertEqual(steps, original)
        XCTAssertTrue(WorkflowOrder.move(original[1].id, in: &steps, toInsertion: 2))
        XCTAssertEqual(steps, original)
        XCTAssertTrue(WorkflowOrder.move(original[2].id, in: &steps, toInsertion: 1))
        XCTAssertEqual(steps.map(\.id), [original[0].id, original[2].id, original[1].id])
        let before = steps
        XCTAssertFalse(WorkflowOrder.move(UUID(), in: &steps, toInsertion: 0))
        XCTAssertFalse(WorkflowOrder.move(steps[0].id, in: &steps, toInsertion: -1))
        XCTAssertFalse(WorkflowOrder.move(steps[0].id, in: &steps, toInsertion: 4))
        XCTAssertEqual(steps, before)
        var empty: [TaskStep] = []
        XCTAssertFalse(WorkflowOrder.move(UUID(), in: &empty, toInsertion: 0))
    }
}
