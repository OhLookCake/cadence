import Foundation

// Dependency-free verification harness: works with Command Line Tools, without Xcode's XCTest framework.
var assertionFailures = 0
func failure(_ message: String, file: StaticString, line: UInt) {
    assertionFailures += 1; print("  FAIL \(file):\(line): \(message)")
}
func XCTAssertEqual<T: Equatable>(_ actual: @autoclosure () throws -> T, _ expected: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { let a = try actual(), b = try expected(); if a != b { failure("\(a) != \(b)", file: file, line: line) } } catch { failure(error.localizedDescription, file: file, line: line) }
}
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    do { if try !value() { failure("Expected true", file: file, line: line) } } catch { failure(error.localizedDescription, file: file, line: line) }
}
func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(try !value(), file: file, line: line) }
func XCTAssertNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { if value != nil { failure("Expected nil", file: file, line: line) } }
func XCTAssertLessThan<T: Comparable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) { if actual >= expected { failure("\(actual) is not less than \(expected)", file: file, line: line) } }
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression(); failure("Expected an error", file: file, line: line) } catch {}
}
struct XCTSkip: Error { let message: String; init(_ message: String) { self.message = message } }
class CheckCase {
    var teardown: [() -> Void] = []
    func addTeardownBlock(_ block: @escaping () -> Void) { teardown.append(block) }
    func cleanup() { for block in teardown.reversed() { block() }; teardown = [] }
}
let checks: [(String, (CadenceCoreTests) -> () throws -> Void)] = [
    ("Schedules follow local time and accept legacy zones", CadenceCoreTests.testSchedulesFollowLocalTimeAndIgnoreLegacyZone),
    ("Save to file content, references, and full output", CadenceCoreTests.testSaveFileStepContentReferencesAndLargeOutput),
    ("Save to file validation and failure", CadenceCoreTests.testSaveFileValidationAndFailure),
    ("Config names follow workflows and preserve identity", CadenceCoreTests.testConfigNamesFollowWorkflowsAndPreserveIdentity),
    ("Config name collisions and safe filenames", CadenceCoreTests.testConfigNameCollisionsAndSafeFilenames),
    ("Conditional config and old history", CadenceCoreTests.testConditionalConfigAndOldHistory),
    ("Conditional reference validation", CadenceCoreTests.testConditionalReferenceValidation),
    ("Every condition operator", CadenceCoreTests.testEveryConditionOperator),
    ("Conditional branches preserve previous output", CadenceCoreTests.testConditionalBranchesAndPreviousOutput),
    ("Named results are single-pass across step kinds", CadenceCoreTests.testNamedResultsAreSinglePassAndSafeAcrossKinds),
    ("Continued failure and skipped status branches", CadenceCoreTests.testContinuedFailureAndSkippedStatusBranches),
    ("Invalid references stop before side effects", CadenceCoreTests.testInvalidReferencesStopBeforeSideEffects),
    ("Large named outputs and environment budget", CadenceCoreTests.testLargeNamedOutputAndEnvironmentBudget),
    ("Conditional question cancellation", CadenceCoreTests.testConditionalQuestionCancellation),
    ("Conditional runner process and skipped chain", CadenceCoreTests.testConditionalRunnerProcessAndAllLaterStepsSkipped),
    ("All workflow kinds round trip through config", CadenceCoreTests.testConfigRoundTripAllKinds),
    ("One config per flow and external edits", CadenceCoreTests.testOneConfigPerFlowAndExternalEdit),
    ("Handwritten config import and stable IDs", CadenceCoreTests.testMinimalConfigImportAndStableStepIDs),
    ("Invalid config isolation and edit conflicts", CadenceCoreTests.testInvalidConfigIsolatedAndConflictsPreserved),
    ("External schedule edits reset revisions", CadenceCoreTests.testExternalScheduleChangeResetsCursorRevision),
    ("Duplicate config IDs fail closed", CadenceCoreTests.testDuplicateConfigIDsFailClosed),
    ("Legacy config migration preserves history", CadenceCoreTests.testLegacyCatalogMigrationPreservesHistory),
    ("Runner reads external config edits", CadenceCoreTests.testRunnerReadsExternallyEditedDefinition),
    ("Workflow drag reorder boundaries", CadenceCoreTests.testWorkflowReorder),
    ("Legacy interaction migration", CadenceCoreTests.testLegacyInteractionsMigrateOnceWithStableIDs),
    ("Legacy script invocation migration", CadenceCoreTests.testLegacyExecutableKeepsExactArguments),
    ("File scripts and inline commands", CadenceCoreTests.testFileScriptsAndInlineCommandsCoexist),
    ("Questions and responses in workflow order", CadenceCoreTests.testQuestionsAndResponsesAnywhereInWorkflow),
    ("Question cancellation stops remaining steps", CadenceCoreTests.testQuestionCancellationStopsLaterSteps),
    ("Latest coalesces backlog", CadenceCoreTests.testLatestCoalescesBacklog),
    ("Replay retains queued work", CadenceCoreTests.testReplayKeepsUnclaimedBacklog),
    ("Skip honors grace period", CadenceCoreTests.testSkipHonorsGrace),
    ("Large interval backlog", CadenceCoreTests.testVeryLargeIntervalBacklog),
    ("Weekdays and every N days", CadenceCoreTests.testThursdayAndEveryTwoDays),
    ("DST and repeated hour", CadenceCoreTests.testCalendarDayAcrossDSTAndRepeatedHour),
    ("Missing hour moves forward", CadenceCoreTests.testMissingHourMovesForward),
    ("One-off schedule", CadenceCoreTests.testOneOffFinishes),
    ("Safe time-zone parameters", CadenceCoreTests.testParametersAreSinglePassAndTimeZoneAware),
    ("Sequence and literal environment", CadenceCoreTests.testManualSequencePreservesScheduleAndDoesNotInjectInput),
    ("Failure and continuation", CadenceCoreTests.testFailureStopsSequenceAndContinueStillReportsFailure),
    ("Durable claim prevents duplicate", CadenceCoreTests.testScheduleClaimAndNoDuplicate),
    ("Timeout and exclusive lock", CadenceCoreTests.testTimeoutAndExclusiveLock),
    ("LaunchAgent definition", CadenceCoreTests.testLaunchAgentIsCalendarBasedAndUsesSafeArguments),
    ("Skip preserves recent occurrences", CadenceCoreTests.testSkipCanRunMultipleRecentOccurrences),
    ("Large output passes through files", CadenceCoreTests.testLargeOutputCanBeChainedThroughFile),
    ("Codex CLI invocation contract", CadenceCoreTests.testCodexCLIContract),
    ("Cancellation stops remaining steps", CadenceCoreTests.testCancellationStopsRemainingSteps),
    ("Real local LLM request", CadenceCoreTests.testRealLocalLLM),
    ("Real launchd round trip", CadenceCoreTests.testLaunchdRoundTrip)
]
var passed = 0, skipped = 0
for (name, check) in checks where CommandLine.arguments.count < 2 || name.localizedCaseInsensitiveContains(CommandLine.arguments[1]) {
    let test = CadenceCoreTests(); let before = assertionFailures
    do { try check(test)(); if assertionFailures == before { print("PASS \(name)"); passed += 1 } }
    catch let skip as XCTSkip { print("SKIP \(name): \(skip.message)"); skipped += 1 }
    catch { assertionFailures += 1; print("FAIL \(name): \(error)") }
    test.cleanup()
}
print("\(passed) passed, \(skipped) skipped, \(assertionFailures) failures")
exit(assertionFailures == 0 ? 0 : 1)
