# Cadence

A native SwiftUI macOS app for scheduling local workflows with launchd. Requires macOS 14 or later. No third-party packages.

## Open the app

The built app is at **[dist/Cadence.app](dist/Cadence.app)**. Open it in Finder, or run:

```sh
open "dist/Cadence.app"
```

Keep the app at a stable path once you enable schedules: launchd points to its bundled runner. If you move the app, open the new copy and choose **Repair Schedule** for each enabled task. The app manages its own tasks; it does not modify or import unrelated existing LaunchAgents.

## Tasks

Create a task with **⌘N** or a starter button. Its overview is directly editable: name, notes, schedule, workflow, working directory, and environment all appear on the same page. Use **Save Changes** (⌘S) to apply edits, or **Revert** to discard them. Unsaved edits remain available when switching between tasks. Save before using **Run Now**. Tasks start paused; enable the schedule when ready.

| Feature | Behavior |
| --- | --- |
| Daily | At a chosen wall-clock time |
| Selected weekdays | Any combination, including every Thursday |
| Every N days | Calendar days from an anchor date, at a chosen time |
| Every N minutes | Fixed elapsed intervals from an anchor timestamp |
| Once | One scheduled timestamp |
| Skip missed runs | Discard occurrences older than the grace period; default 90 seconds |
| Latest only | Coalesce the backlog into its most recent occurrence |
| Replay backlog | Oldest first, with a configurable per-check batch limit; remaining work stays queued |
| User input | Ask for input anywhere in the workflow; cancellation or timeout stops remaining steps |
| Show alert | Display a message or an earlier result anywhere in the workflow |

Calendar schedules use the task’s explicit time zone. Choose from the time-zone list; type a city or region to filter, then click a result or use the arrow keys and Return. Missing DST times move forward; repeated times run once. The editor previews upcoming occurrences. Editing a schedule or re-enabling a task resets scheduling from now. Paused time is not backfilled. Manual runs do not change the schedule cursor.

## Steps

- **Shell command:** literal code passed to `/bin/zsh -c`. Use quoted `$TASK_…` variables. Login-shell configuration is not loaded.
- **Script file / executable:** select an existing file with **Choose File…**. Specify an optional interpreter, such as `/bin/zsh` or your uv project’s `.venv/bin/python`; leave it empty to run an executable file directly. The script path is passed automatically, followed by one argument per line, without shell parsing. Relative script and interpreter paths resolve against the task’s working directory. Inline commands and file scripts can coexist in the same workflow.
- **Codex CLI:** `codex exec`, using an existing CLI login, the task’s working directory, optional model, and read-only or workspace-write sandbox. Prompts go through stdin; the final message is captured with `--output-last-message`. Interactive approvals are unavailable. No paid Codex call was made during verification; the CLI argument/stdin/output contract was tested with a local fixture.
- **Local LLM:** an HTTP chat-completions endpoint, defaulting to `http://localhost:11434/v1/chat/completions`. Works with servers that implement `choices[0].message.content`, including compatible Ollama and LM Studio configurations. Set the installed model name explicitly. Optional bearer authentication uses `CADENCE_LLM_API_KEY` from the task’s environment.
- **User input:** displays a text-entry dialog at that point in the sequence. Its answer becomes both `{{input}}` and `{{previous_output}}` for following steps. Multiple questions are supported; `{{input}}` contains the most recent answer. Cancel or timeout stops remaining steps even when continue on failure is enabled. Earlier completed steps are retained.
- **Show alert:** displays literal text with variables, defaulting to `{{previous_output}}`. It preserves the previous output for later steps. Each response has its own dismissal timeout. The dialog displays the last 6,000 characters; the step’s captured output remains in the run folder.
- **Save to file:** choose a destination and content, defaulting to `{{previous_output}}`. A whole previous or named output reference saves the full captured file, including large process results. Custom text supports the same variables as prompts. Relative paths use the working directory; the destination folder must exist. Existing files are replaced atomically.

Model fields offer editable dropdowns: Codex uses the CLI's cached model list, and local LLM steps list models from the selected server. You can also type a custom model name or connection URL. Leave the Codex model empty to use its CLI default. Drag the handle at the bottom right of any multiline text box to make it taller or shorter.

Questions, responses, and file saves use the same add, edit, reorder, remove, and per-step execution controls as other steps. Existing task-level question/result settings automatically load as a question at the beginning and a response at the end. Saved definitions use only workflow steps. A failure stops later steps unless that failed step is configured to continue.

### Conditions and earlier results

Give a step an optional **Result name**, such as `fetch` or `summary`, to reuse its output later. This is separate from its display name. Result names start with a lowercase letter and contain lowercase letters, digits, or underscores, up to 40 characters; each must be unique in the task. The **Copy earlier result reference** menu supplies the right syntax for the current step type.

| Earlier result | Arguments, prompts, messages, output paths | Shell variable |
| --- | --- | --- |
| Captured output | `{{steps.fetch.output}}` | `$TASK_STEP_FETCH_OUTPUT` |
| Full result file | `{{steps.fetch.output_file}}` | `$TASK_STEP_FETCH_OUTPUT_FILE` |
| Step status | `{{steps.fetch.status}}` | `$TASK_STEP_FETCH_STATUS` |

Enable **Run only when…** to check an earlier named result. Output conditions support empty/nonempty, equals/does not equal, and contains/does not contain. Empty checks ignore whitespace; other comparisons use literal, case-sensitive text. A status condition checks succeeded, failed, skipped, or cancelled. To reach a later failure-handling step, enable continuation on the failed source step. Cancellation still stops the workflow.

A false condition skips only that step, leaving `input` and `previous_output` unchanged. History shows each reached step's status and the reason for a skip. Output conditions on failed or skipped sources are false, including empty and negative checks; use status conditions to handle those cases. Failed/skipped results have empty output and file references. An alert has its own named result while continuing to preserve `previous_output`.

Template references and conditions must target earlier steps. Save rejects missing names and forward template references after reordering/removal; update references when changing a result name. Existing workflows run unconditionally until you add conditions. See the [importable conditional example](Examples/Conditional_report_example.cadence.json) and [config details](docs/flow-config.md#conditions-and-named-results).

Output comparisons and template references use the captured result (up to the last 1 MB for process output). Named shell output variables contain at most the last 16,000 UTF-8 bytes each and share a 48,000-byte budget; use their full output files for larger data. Shared environment values may use named references and are expanded afresh before each step. Unreached results have empty output/file and status `pending`.

Each step has a timeout and a continue-after-failure switch. Add a **Save to file** step wherever a result should be written to disk. Legacy per-step output paths still execute for compatibility. Any failed step makes the final run status failed, even if later steps continue successfully. Different tasks run concurrently; a single task never overlaps with itself, including manual runs. **Stop** requests cancellation, terminating the active process and its ordinary descendants. Detached processes that intentionally reparent themselves are outside this guarantee.

### Parameters

| Placeholder in arguments, prompts, environment values, output paths | Shell environment | Meaning |
| --- | --- | --- |
| `{{date}}` | `TASK_DATE` | Actual run date, `YYYY-MM-DD` in the task’s time zone |
| `{{timestamp}}` | `TASK_TIMESTAMP` | Actual run start, ISO 8601 UTC |
| `{{unix}}` | `TASK_UNIX` | Unix timestamp in seconds |
| `{{scheduled_date}}` | `TASK_SCHEDULED_DATE` | Date of the original scheduled occurrence |
| `{{scheduled_timestamp}}` | `TASK_SCHEDULED_TIMESTAMP` | Original scheduled timestamp, ISO 8601 UTC |
| `{{input}}` | `TASK_INPUT` | Most recent question-step answer |
| `{{previous_output}}` | `TASK_PREVIOUS_OUTPUT` | Previous step’s answer/stdout |
| `{{previous_output_file}}` | `TASK_PREVIOUS_OUTPUT_FILE` | Path to the previous step’s saved output |
| — | `TASK_ID` | Stable task UUID |

For a catch-up report, use the **scheduled** date:

```sh
./report.sh --date "$TASK_SCHEDULED_DATE"
```

Shell source does not expand `{{…}}` placeholders. Answers and model output enter shell steps through environment variables to avoid evaluating them as shell code. Script arguments are passed directly. Placeholder expansion is a single pass.

Prompts can consume up to the last 1 MB of prior output. The shell environment carries its last 16,000 characters to stay below macOS process limits. For larger data, read `TASK_PREVIOUS_OUTPUT_FILE`. That file contains full stdout for shell/script steps and the captured response for LLM steps. Full raw stdout/stderr remain in each run folder. UI log previews show the last 250 KB.

## Background operation

Each enabled task has a LaunchAgent at:

```text
~/Library/LaunchAgents/local.cadence.task.<uuid>.plist
```

The agent invokes the bundled runner on a one-minute calendar pulse and on load/login. Calendar triggers resume on wake. The runner uses a persisted cursor to compute missed occurrences, including across shutdown and login; it does not rely on launchd to preserve a backlog. You can close or quit the UI without disabling schedules.

This version runs as the logged-in user. It does not power on or wake the Mac, run at the login screen, or bypass macOS privacy permissions. Questions need an interactive desktop and expire after the configured timeout. File access follows the account’s macOS permissions; background tools may need their usual access to protected folders.

Before side effects, each occurrence is claimed durably. If the runner crashes or is killed, its claimed occurrence is not automatically retried, because it might already have changed files or made a request. A subsequent run marks stale running records as interrupted. Inspect history and rerun manually if appropriate. This favors avoiding duplicate side effects; it is not an exactly-once guarantee.

**Repair Schedule** reinstalls an enabled task’s LaunchAgent. Registration failures are shown in the UI. Tasks cannot be edited or deleted during an active run. The launchd registration badge refreshes every 15 seconds. Agent diagnostics are stored in `agent.log` and `agent-error.log` in the data folder.

## Storage & portability

```text
~/Library/Application Support/Cadence/
  flows/<Workflow_name>.cadence.json  One editable config per task
  metadata/                 Schedule activation metadata
  legacy/                   Archived pre-migration catalog
  state/                  Durable schedule cursors, locks, cancellation requests
  runs/<run UUID>/         Run metadata, stdout, stderr, inputs, and captured answers
```

Definitions are written atomically under a file lock. The data root is private to the user. Environment values, prompts, question answers, and outputs are local plaintext; exported definitions include environment values. Use your scripts and Keychain for secrets when possible. Log retention is manual in this version; there is no automatic history deletion.

**File → Import Config…** creates paused tasks from individual JSON files. **Export Config…** exports the selected task in the same format. The task’s **Config file** section opens its source file for editing. External edits reload automatically, with protection for unsaved UI changes. See [the format and examples](docs/flow-config.md), or give an LLM agent [README-for-LLMs.md](README-for-LLMs.md) to create or edit task configs. Deleting a task removes its schedule and config while retaining history.

## Build & verify

```sh
zsh scripts/build-app.sh
zsh scripts/check.sh
```

The scripts use the installed macOS 26.5 SDK when available, avoiding the incomplete SwiftUI macro support in this machine’s default command-line macOS 27 SDK. The standalone check executable requires only Command Line Tools, rather than Xcode’s XCTest framework. The build generates an icon and ad-hoc signs the app locally; it is not notarized for distribution to other Macs.

For an actual temporary launchd registration and optional local-model request:

```sh
CADENCE_LAUNCHD_TEST=1 zsh scripts/check.sh
CADENCE_LAUNCHD_TEST=1 CADENCE_TEST_MODEL=qwen3.5:9b zsh scripts/check.sh
```

Checks use temporary data directories. The launchd check removes its test agent after completion. They cover schedule arithmetic, DST, missed-run policies, durable claims, process timeouts, exclusive execution, parameter handling, output chaining, conditions and named references, skipped-step history, failure behavior, the Codex invocation contract, and launchd integration. The optional model check makes one local request with a short synthetic prompt.

## Implementation references

- [Apple: scheduling timed jobs with launchd](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/ScheduledJobs.html)
- [Official OpenAI documentation: Codex non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode)

The planner and file store are in `Sources/CadenceCore`; the separate runner is in `Sources/CadenceRunner`; the SwiftUI application is in `Sources/Cadence`.
