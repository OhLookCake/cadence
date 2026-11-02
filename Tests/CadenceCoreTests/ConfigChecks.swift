import Foundation
import CadenceCore

extension CadenceCoreTests {
    func testOneConfigPerFlowAndExternalEdit() throws {
        let store = try temporaryStore()
        var first = ScheduledTask(); first.name = "First flow"
        var second = ScheduledTask(); second.name = "Second flow"
        try store.save(first); try store.save(second)
        XCTAssertEqual(try store.catalog().files.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("tasks.json").path))
        let firstURL = try store.catalog().files[first.id]!
        let original = try store.tasks().first(where: { $0.id == first.id })!
        var edited = original; edited.name = "Edited outside Cadence"; edited.steps[0].body = "printf changed"
        try store.exportConfig(edited, to: firstURL)
        let refreshed = try store.tasks().first(where: { $0.id == first.id })!
        XCTAssertEqual(refreshed.name, edited.name); XCTAssertEqual(refreshed.steps[0].body, "printf changed")
        XCTAssertEqual(refreshed.scheduleRevision, original.scheduleRevision)
        XCTAssertEqual(try store.tasks().first(where: { $0.id == second.id })?.name, second.name)
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: firstURL)) as! [String: Any]
        XCTAssertNil(raw["scheduleRevision"]); XCTAssertNil(raw["scheduleActivatedAt"]); XCTAssertNil(raw["createdAt"])
    }
    func testMinimalConfigImportAndStableStepIDs() throws {
        let store = try temporaryStore()
        let data = Data(#"""
        {
          "version": 1,
          "$schema": "https://example.invalid/cadence.schema.json",
          "name": "Handwritten report",
          "description": "Created in a text editor",
          "enabled": true,
          "schedule": {"kind": "daily", "hour": 8, "minute": 30, "timeZone": "Europe/London"},
          "steps": [{"kind": "shell", "body": "printf report"}]
        }
        """#.utf8)
        let source = store.root.appendingPathComponent("import.json")
        try data.write(to: source)
        let imported = try store.importConfig(at: source)
        XCTAssertFalse(imported.enabled); XCTAssertEqual(imported.name, "Handwritten report")
        XCTAssertEqual(imported.notes, "Created in a text editor")
        XCTAssertEqual(imported.schedule.hour, 8); XCTAssertEqual(imported.schedule.minute, 30)
        XCTAssertEqual(imported.steps.first?.body, "printf report")
        XCTAssertEqual(try FlowConfig.decode(Data(contentsOf: store.defaultConfigURL(imported.id))).schema, "https://example.invalid/cadence.schema.json")
        try store.save(imported, expecting: imported)
        XCTAssertEqual(try FlowConfig.decode(Data(contentsOf: store.defaultConfigURL(imported.id))).schema, "https://example.invalid/cadence.schema.json")
        XCTAssertEqual(try store.tasks().first?.steps.map(\.id), imported.steps.map(\.id))
        // A managed handwritten file may also omit step IDs; polling must not manufacture new ones.
        let managed = store.defaultConfigURL(imported.id)
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: managed)) as! [String: Any]
        object["steps"] = [["kind": "shell", "body": "printf edited"]]
        try JSONSerialization.data(withJSONObject: object).write(to: managed, options: .atomic)
        XCTAssertEqual(try store.tasks().first?.steps.map(\.id), try store.tasks().first?.steps.map(\.id))
        let another = try store.importConfig(at: source)
        XCTAssertFalse(imported.id == another.id)
        XCTAssertEqual(try store.tasks().count, 2)
    }
    func testInvalidConfigIsolatedAndConflictsPreserved() throws {
        let store = try temporaryStore(); var task = ScheduledTask(); task.name = "Valid flow"
        try store.save(task)
        let base = try store.tasks().first!
        let url = try store.catalog().files[task.id]!
        var external = base; external.notes = "External change"
        try store.exportConfig(external, to: url)
        var stale = base; stale.notes = "Unsaved UI change"
        XCTAssertThrowsError(try store.save(stale, expecting: base))
        XCTAssertEqual(try store.tasks().first?.notes, "External change")
        let broken = store.flowsDirectory.appendingPathComponent("broken.cadence.json")
        try Data("{ invalid JSON".utf8).write(to: broken)
        let catalog = try store.catalog()
        XCTAssertEqual(catalog.tasks.count, 1); XCTAssertEqual(catalog.issues.count, 1)
        XCTAssertEqual(catalog.issues.first?.url.resolvingSymlinksInPath(), broken.resolvingSymlinksInPath())
        let unknown = Data(#"{"name":"Typo","schedule":{"kind":"daily"},"steps":[],"enabledd":true}"#.utf8)
        XCTAssertThrowsError(try FlowConfig.decode(unknown))
        try Data("broken".utf8).write(to: url, options: .atomic)
        XCTAssertThrowsError(try store.save(stale, expecting: external))
        XCTAssertEqual(try String(contentsOf: url), "broken")
    }
    func testExternalScheduleChangeResetsCursorRevision() throws {
        let store = try temporaryStore(); let task = ScheduledTask()
        try store.save(task)
        let base = try store.tasks().first!
        var external = base; external.schedule.hour = 17
        try store.exportConfig(external, to: store.defaultConfigURL(task.id))
        let revised = try store.tasks().first!
        XCTAssertFalse(revised.scheduleRevision == base.scheduleRevision)
        XCTAssertEqual(revised.schedule.hour, 17)
        XCTAssertEqual(try store.tasks().first?.scheduleRevision, revised.scheduleRevision)
        var enabled = revised; enabled.enabled = true
        try store.exportConfig(enabled, to: store.defaultConfigURL(task.id))
        let active = try store.tasks().first!
        XCTAssertFalse(active.scheduleRevision == revised.scheduleRevision)
    }
    func testDuplicateConfigIDsFailClosed() throws {
        let store = try temporaryStore(); let task = ScheduledTask(); try store.save(task)
        try store.exportConfig(task, to: store.flowsDirectory.appendingPathComponent("duplicate.json"))
        let catalog = try store.catalog()
        XCTAssertTrue(catalog.tasks.isEmpty); XCTAssertEqual(catalog.issues.count, 2)
    }
    func testLegacyCatalogMigrationPreservesHistory() throws {
        let original = try temporaryStore(); var task = ScheduledTask()
        task.name = "Existing flow"; task.createdAt = date("2026-11-01T12:00:00Z")
        task.scheduleActivatedAt = date("2026-11-01T12:00:00Z")
        try original.write([task], at: original.root.appendingPathComponent("tasks.json"))
        var run = RunRecord(task: task, scheduledAt: task.createdAt, manual: true); run.status = .succeeded
        try original.saveRun(run)
        let cursor = TaskState(revision: task.scheduleRevision, nextDue: date("2026-11-03T09:00:00Z"))
        try original.write(cursor, at: original.stateURL(task.id))
        let migrated = try CadenceStore(root: original.root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: migrated.root.appendingPathComponent("tasks.json").path))
        XCTAssertEqual(try migrated.tasks().first?.id, task.id)
        XCTAssertEqual(try migrated.tasks().first?.scheduleRevision, task.scheduleRevision)
        XCTAssertEqual(try migrated.tasks().first?.createdAt, task.createdAt)
        XCTAssertEqual(try migrated.runs().first?.id, run.id)
        XCTAssertEqual(try migrated.read(TaskState.self, at: migrated.stateURL(task.id)).nextDue, cursor.nextDue)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: migrated.root.appendingPathComponent("legacy").path).count, 1)
        _ = try CadenceStore(root: original.root)
        XCTAssertEqual(try migrated.tasks().count, 1)
    }
    func testRunnerReadsExternallyEditedDefinition() throws {
        let store = try temporaryStore(); var task = ScheduledTask()
        task.workingDirectory = store.root.path
        task.steps[0].body = "printf old"; task.steps[0].outputPath = "answer.txt"
        try store.save(task)
        var external = try store.tasks().first!
        external.steps[0].body = "printf new"
        try store.exportConfig(external, to: store.defaultConfigURL(task.id))
        try TaskRunner.run(store: store, id: task.id, manual: true)
        XCTAssertEqual(try store.runs().first?.status, .succeeded)
        XCTAssertEqual(try String(contentsOf: store.root.appendingPathComponent("answer.txt")), "new")
    }
}

extension CadenceCoreTests {
    func testConfigRoundTripAllKinds() throws {
        let store = try temporaryStore(); var task = ScheduledTask(); task.workingDirectory = store.root.path
        task.steps = StepKind.allCases.map { TaskStep.make($0) }
        for index in task.steps.indices {
            if task.steps[index].kind == .script {
                task.steps[index].scriptPath = "/bin/echo"; task.steps[index].executable = ""
                task.steps[index].arguments = "literal 'quoted' value\n{{input}}"
            }
            if task.steps[index].kind == .localLLM { task.steps[index].model = "test-model" }
        }
        try task.validate()
        let data = try FlowConfig.encode(task)
        let decoded = try FlowConfig.decode(data).task()
        XCTAssertEqual(decoded.steps, task.steps)
        let raw = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let kinds = (raw["steps"] as! [[String: Any]]).map { $0["kind"] as! String }
        XCTAssertTrue(kinds.contains("userInput")); XCTAssertTrue(kinds.contains("alert"))
        let exampleURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Examples/daily-report.cadence.json")
        if FileManager.default.fileExists(atPath: exampleURL.path) {
            let example = try store.importConfig(at: exampleURL)
            XCTAssertEqual(example.steps.map(\.kind), [.shell, .response])
        }
    }
}
