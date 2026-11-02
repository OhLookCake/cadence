import Foundation
import CadenceCore

final class CadenceCoreTests: CheckCase {
    func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func temporaryStore() throws -> CadenceStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CadenceTests-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try CadenceStore(root: root)
    }
    func intervalTask() -> ScheduledTask {
        var task = ScheduledTask(); task.schedule.kind = .interval; task.schedule.every = 60
        task.schedule.anchor = date("2026-11-01T00:00:00Z")
        return task
    }
    func testLatestCoalescesBacklog() throws {
        var task = intervalTask(); task.missedPolicy = .latest
        let plan = try Planner.plan(task: task, nextDue: task.schedule.anchor, now: date("2026-11-01T05:20:00Z"))
        XCTAssertEqual(plan.dates, [date("2026-11-01T05:00:00Z")]); XCTAssertEqual(plan.omitted, 5)
        XCTAssertEqual(plan.nextDue, date("2026-11-01T06:00:00Z"))
    }
    func testReplayKeepsUnclaimedBacklog() throws {
        var task = intervalTask(); task.missedPolicy = .all; task.catchUpLimit = 2
        let plan = try Planner.plan(task: task, nextDue: task.schedule.anchor, now: date("2026-11-01T05:20:00Z"))
        XCTAssertEqual(plan.dates, [date("2026-11-01T00:00:00Z"), date("2026-11-01T01:00:00Z")])
        XCTAssertEqual(plan.nextDue, date("2026-11-01T02:00:00Z")); XCTAssertEqual(plan.omitted, 0)
    }
    func testSkipHonorsGrace() throws {
        var task = intervalTask(); task.missedPolicy = .skip; task.graceSeconds = 90
        let missed = try Planner.plan(task: task, nextDue: task.schedule.anchor, now: date("2026-11-01T05:02:00Z"))
        XCTAssertTrue(missed.dates.isEmpty); XCTAssertEqual(missed.omitted, 6)
        let inTime = try Planner.plan(task: task, nextDue: task.schedule.anchor, now: date("2026-11-01T05:01:00Z"))
        XCTAssertEqual(inTime.dates, [date("2026-11-01T05:00:00Z")])
    }
    func testVeryLargeIntervalBacklog() throws {
        var task = intervalTask(); task.schedule.every = 1
        let plan = try Planner.plan(task: task, nextDue: task.schedule.anchor, now: task.schedule.anchor.addingTimeInterval(60 * 2_000_000))
        XCTAssertEqual(plan.omitted, 2_000_000); XCTAssertEqual(plan.dates.count, 1)
    }
    func testThursdayAndEveryTwoDays() {
        var schedule = TaskSchedule(); schedule.kind = .weekly; schedule.weekdays = [5]; schedule.timeZone = "Europe/London"; schedule.hour = 9
        XCTAssertEqual(schedule.next(after: date("2026-11-02T10:00:00Z")), date("2026-11-05T09:00:00Z"))
        schedule.kind = .everyDays; schedule.every = 2; schedule.anchor = date("2026-10-23T09:00:00Z")
        XCTAssertEqual(schedule.next(after: date("2026-10-24T12:00:00Z")), date("2026-10-25T09:00:00Z"))
    }
    func testCalendarDayAcrossDSTAndRepeatedHour() {
        var schedule = TaskSchedule(); schedule.timeZone = "Europe/London"; schedule.hour = 9
        XCTAssertEqual(schedule.next(after: date("2026-10-24T08:00:00Z")), date("2026-10-25T09:00:00Z"))
        schedule.hour = 1; schedule.minute = 30
        let first = schedule.next(after: date("2026-10-24T23:00:00Z"))!
        XCTAssertEqual(first, date("2026-10-25T00:30:00Z"))
        XCTAssertEqual(schedule.next(after: first), date("2026-10-26T01:30:00Z"))
    }
    func testMissingHourMovesForward() {
        var schedule = TaskSchedule(); schedule.timeZone = "Europe/London"; schedule.hour = 1; schedule.minute = 30
        XCTAssertEqual(schedule.next(after: date("2026-03-29T00:00:00Z")), date("2026-03-29T01:00:00Z"))
    }
    func testOneOffFinishes() throws {
        var task = ScheduledTask(); task.schedule.kind = .once; task.schedule.anchor = date("2026-11-01T09:00:00Z")
        let plan = try Planner.plan(task: task, nextDue: task.schedule.anchor, now: date("2026-11-02T09:00:00Z"))
        XCTAssertEqual(plan.dates.count, 1); XCTAssertNil(plan.nextDue)
    }
    func testParametersAreSinglePassAndTimeZoneAware() {
        var context = StepContext(now: date("2026-11-02T00:30:00Z"), scheduled: date("2026-11-01T00:30:00Z"), timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        context.input = "$(touch /tmp/not-executed) {{date}}"
        XCTAssertEqual(context.expand("{{date}} / {{scheduled_date}}"), "2026-11-01 / 2026-10-31")
        XCTAssertEqual(context.expand("{{input}}"), context.input)
    }
    func testManualSequencePreservesScheduleAndDoesNotInjectInput() throws {
        let store = try temporaryStore()
        var task = ScheduledTask(); task.name = "Sequence test"; task.workingDirectory = store.root.path
        task.environment = "EXAMPLE=$(printf injected)"
        task.steps[0].body = "printf '%s' \"$EXAMPLE\""
        var second = TaskStep(); second.body = "printf '%s' \"$TASK_PREVIOUS_OUTPUT\""; second.outputPath = "answer.txt"
        task.steps.append(second); try store.save(task)
        try TaskRunner.run(store: store, id: task.id, manual: true)
        let runs = try store.runs(); XCTAssertEqual(runs.count, 1); XCTAssertEqual(runs.first?.status, .succeeded)
        XCTAssertEqual(try String(contentsOf: store.root.appendingPathComponent("answer.txt")), "$(printf injected)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.stateURL(task.id).path))
    }
    func testFailureStopsSequenceAndContinueStillReportsFailure() throws {
        let store = try temporaryStore(); var task = ScheduledTask(); task.workingDirectory = store.root.path
        task.steps[0].body = "exit 7"
        var second = TaskStep(); second.body = "touch second-ran"; task.steps.append(second)
        try store.save(task); try TaskRunner.run(store: store, id: task.id, manual: true)
        XCTAssertEqual(try store.runs().first?.status, .failed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("second-ran").path))
        task.steps[0].continueOnFailure = true; try store.save(task); try TaskRunner.run(store: store, id: task.id, manual: true)
        XCTAssertEqual(try store.runs().first?.status, .failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("second-ran").path))
    }
    func testScheduleClaimAndNoDuplicate() throws {
        let store = try temporaryStore(); var task = intervalTask(); task.enabled = true
        task.scheduleActivatedAt = Date().addingTimeInterval(-7200); task.schedule.anchor = task.scheduleActivatedAt; task.missedPolicy = .latest
        try store.save(task)
        try TaskRunner.run(store: store, id: task.id, manual: false)
        let first = try store.runs().filter { $0.status == .succeeded }.count
        try TaskRunner.run(store: store, id: task.id, manual: false)
        XCTAssertEqual(first, 1); XCTAssertEqual(try store.runs().filter { $0.status == .succeeded }.count, 1)
    }
    func testTimeoutAndExclusiveLock() throws {
        let store = try temporaryStore(); var task = ScheduledTask(); task.steps[0].body = "sleep 10"; task.steps[0].timeoutSeconds = 1
        try store.save(task)
        let lock = try FileLock(url: store.lockURL(task.id), nonblocking: true)
        XCTAssertThrowsError(try FileLock(url: store.lockURL(task.id), nonblocking: true))
        withExtendedLifetime(lock) {}
        // Use a different task while the first lock is held.
        task.id = UUID(); try store.save(task)
        let start = Date(); try TaskRunner.run(store: store, id: task.id, manual: true)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5); XCTAssertEqual(try store.runs().first?.status, .failed)
        XCTAssertTrue(try store.runs().first?.message.contains("timed out") == true)
    }
    func testLaunchAgentIsCalendarBasedAndUsesSafeArguments() throws {
        let task = ScheduledTask()
        let plist = LaunchAgent.definition(task: task, runner: URL(fileURLWithPath: "/a path/runner"), root: URL(fileURLWithPath: "/data path"))
        XCTAssertEqual((plist["StartCalendarInterval"] as? [[String: Int]])?.count, 60)
        XCTAssertEqual((plist["ProgramArguments"] as? [String])?.first, "/a path/runner")
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
    }
    func testSkipCanRunMultipleRecentOccurrences() throws {
        var task = intervalTask(); task.schedule.every = 1; task.missedPolicy = .skip; task.graceSeconds = 90
        let plan = try Planner.plan(task: task, nextDue: task.schedule.anchor, now: date("2026-11-01T00:05:15Z"))
        XCTAssertEqual(plan.dates, [date("2026-11-01T00:04:00Z"), date("2026-11-01T00:05:00Z")])
        XCTAssertEqual(plan.omitted, 4)
    }
    func testLargeOutputCanBeChainedThroughFile() throws {
        let store = try temporaryStore(); var task = ScheduledTask(); task.workingDirectory = store.root.path
        task.steps[0].body = "head -c 1200000 /dev/zero | tr '\\0' a"
        var second = TaskStep(); second.body = "wc -c < \"$TASK_PREVIOUS_OUTPUT_FILE\""; second.outputPath = "size.txt"; task.steps.append(second)
        try store.save(task); try TaskRunner.run(store: store, id: task.id, manual: true)
        XCTAssertEqual(try store.runs().first?.status, .succeeded)
        XCTAssertEqual(try String(contentsOf: store.root.appendingPathComponent("size.txt")).trimmingCharacters(in: .whitespacesAndNewlines), "1200000")
    }
    func testCodexCLIContract() throws {
        let store = try temporaryStore(); let executable = store.root.appendingPathComponent("codex-fixture")
        let script = """
        #!/bin/zsh
        [[ "$1" == exec ]] || exit 41
        while (( $# )); do
          case "$1" in
            --output-last-message) answer="$2"; shift 2;;
            --sandbox) [[ "$2" == read-only ]] || exit 42; shift 2;;
            *) shift;;
          esac
        done
        cat > "$answer"
        print 'progress output'
        """
        try Data(script.utf8).write(to: executable); try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        var task = ScheduledTask(); task.workingDirectory = store.root.path
        task.steps[0].kind = .codex; task.steps[0].executable = executable.path; task.steps[0].body = "Literal $(echo not-executed) {{scheduled_date}}"; task.steps[0].outputPath = "answer.txt"
        try store.save(task); try TaskRunner.run(store: store, id: task.id, manual: true)
        XCTAssertEqual(try store.runs().first?.status, .succeeded)
        XCTAssertTrue(try String(contentsOf: store.root.appendingPathComponent("answer.txt")).hasPrefix("Literal $(echo not-executed) "))
    }
    func testCancellationStopsRemainingSteps() throws {
        let store = try temporaryStore(); var task = ScheduledTask(); task.workingDirectory = store.root.path
        task.steps[0].body = "sleep 20"
        var next = TaskStep(); next.body = "touch should-not-run"; task.steps.append(next)
        try store.save(task)
        let id = task.id, group = DispatchGroup(); group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            for _ in 0..<100 {
                if (try? store.runs().contains(where: { $0.taskID == id && $0.status == .running })) == true { Thread.sleep(forTimeInterval: 0.2); try? store.cancel(id); return }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        let start = Date(); try TaskRunner.run(store: store, id: id, manual: true)
        _ = group.wait(timeout: .now() + 5)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        XCTAssertEqual(try store.runs().first?.status, .cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("should-not-run").path))
    }
    func testRealLocalLLM() throws {
        guard let model = ProcessInfo.processInfo.environment["CADENCE_TEST_MODEL"] else { throw XCTSkip("Set CADENCE_TEST_MODEL to check a running local server.") }
        let store = try temporaryStore(); var task = ScheduledTask(); task.workingDirectory = store.root.path
        task.steps[0].kind = .localLLM; task.steps[0].model = model; task.steps[0].timeoutSeconds = 60
        task.steps[0].body = "Reply with just CADENCE_OK. /no_think"; task.steps[0].outputPath = "answer.txt"
        try store.save(task); try TaskRunner.run(store: store, id: task.id, manual: true)
        XCTAssertEqual(try store.runs().first?.status, .succeeded)
        XCTAssertFalse(try String(contentsOf: store.root.appendingPathComponent("answer.txt")).isEmpty)
        if let run = try store.runs().first, run.status != .succeeded { print(store.log(run.id)) }
    }
    func testLaunchdRoundTrip() throws {
        guard ProcessInfo.processInfo.environment["CADENCE_LAUNCHD_TEST"] == "1" else { throw XCTSkip("Set CADENCE_LAUNCHD_TEST=1 for a real, temporary launchd registration.") }
        let store = try temporaryStore(); var task = ScheduledTask(); task.name = "Cadence launchd smoke test"; task.enabled = true
        task.schedule.kind = .once; task.schedule.anchor = Date().addingTimeInterval(-30); task.scheduleActivatedAt = Date().addingTimeInterval(-60)
        task.steps[0].body = "printf 'launchd-ok'"; task.steps[0].outputPath = store.root.appendingPathComponent("launchd-result.txt").path
        try store.save(task)
        let runner = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CADENCE_TEST_RUNNER"] ?? FileManager.default.currentDirectoryPath + "/.build/debug/CadenceRunner")
        defer { try? LaunchAgent.remove(task.id) }
        try LaunchAgent.sync(task: task, runner: runner, root: store.root)
        XCTAssertTrue(LaunchAgent.installed(task.id))
        let result = store.root.appendingPathComponent("launchd-result.txt")
        for _ in 0..<100 { if FileManager.default.fileExists(atPath: result.path) { break }; Thread.sleep(forTimeInterval: 0.1) }
        if !FileManager.default.fileExists(atPath: result.path) {
            print("Agent error: " + ((try? String(contentsOf: store.root.appendingPathComponent("agent-error.log"))) ?? "none"))
            print((try? LaunchAgent.control(["print", "gui/\(getuid())/\(LaunchAgent.label(task.id))"])) ?? "Cannot inspect agent")
        }
        XCTAssertEqual(try String(contentsOf: result), "launchd-ok")
        XCTAssertEqual(try store.runs().first(where: { $0.status == .succeeded })?.taskID, task.id)
        try LaunchAgent.remove(task.id); XCTAssertFalse(LaunchAgent.installed(task.id))
    }
}
