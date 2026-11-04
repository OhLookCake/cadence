# Cadence task configs: instructions for LLM agents

Use this document to create or edit Cadence task configuration files from a user's request. A task is one schedule plus an ordered workflow of steps. The public format is **version 1, UTF-8 JSON**, named after the workflow with underscores replacing spaces, such as `Daily_report.cadence.json`. JSON comments, trailing commas, and unknown fields are not supported.

The [JSON Schema](docs/flow.schema.json) describes the file structure. [FlowConfig.swift](Sources/CadenceCore/FlowConfig.swift) implements decoding and serialization; [Models.swift](Sources/CadenceCore/Models.swift) supplies defaults, validation, and schedule arithmetic; [Execution.swift](Sources/CadenceCore/Execution.swift) defines execution and substitution. Consult those files if this guide and the implementation diverge. The [user-facing format guide](docs/flow-config.md) explains import and reload behavior.

## Creating and editing files

1. Read the existing config before editing. Preserve the task `id`, existing step IDs, workflow order, enabled state, and settings outside the requested change. Do not replace an existing task with an imported copy: importing assigns a new task identity.
2. For a new importable config, omit the top-level `id` and use `"enabled": false`. Cadence assigns an ID and always imports tasks paused. Step IDs can be omitted in a new file; when adding steps to an existing managed file, prefer fresh UUIDs for the new steps and preserve all existing IDs.
3. For a new file placed directly in the managed `flows/` directory, generate a unique top-level UUID. Never put two files with the same task ID there; both are rejected. Files without a task ID cannot load as managed tasks. Use the workflow name with underscores for the filename. Cadence renames managed files to match their name on reload, adding numeric suffixes for collisions; recheck the current path after changing a workflow name.
4. Use explicit schedule values for the interval, weekdays, and anchor where applicable. Schedules use the Mac’s local time zone. Ask for missing information that materially changes the requested behavior, such as an unknown script location. Do not invent installed models, executable paths, credentials, or script contents.
5. Write complete valid JSON, using only the fields below. Unless asked for a patch or explanation, deliver an actual `.cadence.json` file when filesystem access is available, or one complete JSON object otherwise. Explain dependencies and whether validation was structural or performed by Cadence.

Managed configs live at:

```text
~/Library/Application Support/Cadence/flows/<Workflow_name>.cadence.json
```

For an importable file, use **File → Import Config…**, then edit the managed copy shown in the task's **Config file** section. Import copies the definition; later edits to the original import source do not update the task.

With Cadence open, external edits reload within about three seconds. Unsaved UI drafts are protected against overwriting external edits; use **Reload from file** or **Revert** to load the disk version. Open Cadence after adding a new managed config or enabling an unregistered task so it can register the schedule. Existing registered jobs read current definitions on their next check. A running occurrence keeps the definition it started with.

Do not edit `metadata/`, `state/`, `runs/`, LaunchAgent plists, or the legacy `tasks.json` catalog to change a task. Runtime fields such as `createdAt`, `scheduleRevision`, and `scheduleActivatedAt` do not belong in a config. The public description field is `description`, not the internal Swift property `notes`.

## Top-level fields

| Field | Type | Requirement / default |
| --- | --- | --- |
| `$schema` | string | Optional editor schema reference. Use a path or URL that actually resolves from the target file; it does not replace Cadence validation. |
| `version` | integer | Use `1`; omitted means `1`. Other versions are rejected. |
| `id` | UUID string | Required in managed files; optional on import. Preserve when editing. |
| `name` | string | Required; must contain non-whitespace text. |
| `description` | string | Optional; default `""`. |
| `enabled` | boolean | Default `false`. Preserve on edits unless asked to change activation. |
| `workingDirectory` | string | Default `"~"`. Must name an existing directory. Prefer an absolute or `~/…` path. |
| `environment` | string | Default `""`. Newline-separated `KEY=value` entries, **not a JSON object**. |
| `schedule` | object | Required; see below. |
| `missedPolicy` | string | `"skip"`, `"latest"` (default), or `"all"`. |
| `catchUpLimit` | integer | `1`–`100`; default `5`. Batch size per check for `all`; remaining occurrences stay queued. |
| `graceSeconds` | integer | `0`–`3600`; default `90`. For `skip`, older occurrences are skipped. |
| `steps` | array of objects | Required, at least one. Executes in array order. |

`latest` runs only the most recent missed occurrence. `all` replays oldest first. Schedule edits and re-enabling reset scheduling from the next observation; paused time is not backfilled. Command and description edits preserve the schedule cursor. Manual runs do not advance that cursor. Scheduling uses a roughly one-minute launchd check; interval units are minutes, not seconds. Cadence does not wake or power on the Mac.

## Schedule object

| Field | Type | Rule / default |
| --- | --- | --- |
| `kind` | string | Required: `daily`, `weekly`, `everyDays`, `interval`, or `once`. |
| `timeZone` | string | Legacy field: accepted but ignored. Omit it from new configs; all schedules use the Mac’s local time zone. |
| `hour` | integer | `0`–`23`; default `9`. Used by daily, weekly, and everyDays. |
| `minute` | integer | `0`–`59`; default `0`. Used by daily, weekly, and everyDays. |
| `weekdays` | array of integers | Sunday=`1`, Monday=`2`, … Saturday=`7`. Default `[2,3,4,5,6]`. For weekly, supply a nonempty list without duplicates. |
| `every` | integer | `1`–`10000`; default `2`. Days for everyDays, minutes for interval. Always specify for those kinds. |
| `anchor` | string | ISO 8601 timestamp with a zone, e.g. `2027-01-04T09:00:00Z`. Required for everyDays, interval, and once. Prefer whole seconds. |

Calendar schedules use the Mac’s local time zone and retain their wall-clock time across daylight saving changes. Missing times move forward; repeated times run once. For `everyDays`, the anchor's **local calendar date on the Mac** sets the day cadence, while `hour` and `minute` set the execution time. For `interval`, the anchor is the first timestamp and subsequent occurrences are fixed elapsed intervals. For `once`, the anchor is the exact execution timestamp. Supply a future timestamp for a newly created one-time task; an old anchor does not request an immediate run.

These are interchangeable `schedule` objects, not complete task files. The anchor dates are examples; choose dates matching the user's request.

```json
{"kind": "daily", "hour": 9, "minute": 0}
```

```json
{"kind": "weekly", "weekdays": [2, 4, 6], "hour": 18, "minute": 30}
```

```json
{"kind": "everyDays", "every": 3, "anchor": "2027-01-04T00:00:00Z", "hour": 9, "minute": 0}
```

```json
{"kind": "interval", "every": 30, "anchor": "2027-01-04T09:00:00Z"}
```

```json
{"kind": "once", "anchor": "2027-01-04T09:00:00Z"}
```

## Workflow steps

Every step should specify `kind`. All kinds except `script` require a nonempty `body`; `script` requires a nonempty `scriptPath`. Use only common fields and fields relevant to that kind.

| Common field | Type | Rule / default |
| --- | --- | --- |
| `id` | UUID string | Optional, unique within the task. Preserve existing values. Omitted IDs are derived from task identity and array position until saved. |
| `name` | string | Optional display label; defaults to the step kind's title. |
| `key` | string | Optional stable result name, unique in the task; `[a-z][a-z0-9_]{0,39}`. Independent of the display name. |
| `runIf` | object | Optional condition on an earlier named result; see below. Omitted means unconditional. |
| `timeoutSeconds` | integer | `1`–`86400`; default `600`, except userInput=`300`, alert=`120`. |
| `continueOnFailure` | boolean | Default `false`. If true, later steps may run after failure, but the overall run still fails. |
| `outputPath` | string | Required for `saveFile`. Relative to workingDirectory; supports `~` and placeholders. Replaces the destination atomically; its parent directory must already exist. Legacy use on other kinds is still accepted; generate a separate `saveFile` step instead. |

### Conditions and named results

A step with `"key": "fetch"` exposes `{{steps.fetch.output}}`,
`{{steps.fetch.output_file}}`, and `{{steps.fetch.status}}` to later steps.
Shell source uses quoted `$TASK_STEP_FETCH_OUTPUT`,
`$TASK_STEP_FETCH_OUTPUT_FILE`, and `$TASK_STEP_FETCH_STATUS` instead. These work
across intervening steps. Keep keys stable when editing display names. Named
references in per-step templated fields must refer to earlier steps; validation
rejects missing keys, duplicates, and forward references after reordering.

`runIf` contains required `step` (the earlier key) and `operator`, optional
`field` (`output` by default, or `status`), and optional literal string `value`
(default empty). Output operators are `isEmpty`, `isNotEmpty`, `equals`,
`notEquals`, `contains`, and `notContains`. Empty checks ignore whitespace;
other comparisons are exact and case-sensitive. There is no regex, expression
evaluation, or template expansion in the comparison value. Status permits only
`equals`/`notEquals` and a value of `succeeded`, `failed`, `skipped`, or
`cancelled`.

```json
{"kind":"alert","body":"{{steps.fetch.output}}","runIf":{"step":"fetch","field":"output","operator":"isNotEmpty"}}
```

False conditions skip only their step, preserving `input`, `previous_output`,
and `previous_output_file`. Skips appear explicitly in history. Output checks
against failed/skipped sources are always false, including negative/empty
checks; use status to handle these cases. Failed/skipped named results have
empty output/file values. An alert's named output is its rendered message.
Failed source steps need `continueOnFailure: true` to reach later handlers, and
the overall run still fails. Cancellation stops everything, including status
handlers. Do not invent jump, else, or graph fields: repeat a condition on each
step in a branch. See [the full example](Examples/Conditional_report_example.cadence.json).

### shell

`body` is literal source passed to `/bin/zsh -c`, without login-shell configuration. Cadence does **not** substitute `{{…}}` in shell source. Use quoted `$TASK_…` environment variables for runtime values. Avoid evaluating user input or model output as shell code.

```json
{"kind": "shell", "name": "Report", "body": "./report.sh --date \"$TASK_SCHEDULED_DATE\"", "timeoutSeconds": 600}
```

### script

`scriptPath` is a script or executable file. `executable` selects its interpreter (default `/bin/zsh`); set it to `""` to run the file directly, which requires an executable file and appropriate shebang where relevant. Relative script and interpreter paths resolve against workingDirectory. A bare interpreter name does not request PATH lookup: use an absolute or working-directory-relative path.

`arguments` should be an array of strings, one argument per element. The script path is supplied automatically before these arguments when an interpreter is used. Arguments are passed directly without shell parsing: do not add shell quotes around values, and do not expect `$VAR`, globs, pipes, or command substitution to expand. Each argument must be newline-free. Empty argument entries are discarded before template expansion, so do not rely on literal empty entries. The older newline-separated string form is readable, but generate arrays.

For Python, use the interpreter from an existing uv-managed project environment; manage any Python environments with uv.

```json
{
  "kind": "script",
  "name": "Python report",
  "scriptPath": "scripts/report.py",
  "executable": ".venv/bin/python",
  "arguments": ["--date", "{{scheduled_date}}", "--input", "{{input}}"]
}
```

### codex

`body` is the prompt. Set `executable` to the actual installed Codex CLI path. If omitted, Cadence chooses `/opt/homebrew/bin/codex` when executable, otherwise `/usr/local/bin/codex`; verify rather than assuming either exists. `model` is optional (empty uses the CLI default). `sandbox` is `read-only` (default) or `workspace-write`.

Cadence runs `codex exec` in workingDirectory, sends the prompt via stdin, and captures the final message for following steps. An existing CLI login is required; interactive approvals are unavailable. Do not add invented config fields for CLI flags.

```json
{"kind": "codex", "executable": "/opt/homebrew/bin/codex", "sandbox": "read-only", "body": "Summarize this report:\n{{previous_output}}", "timeoutSeconds": 900}
```

### localLLM

Requires `body` and a nonempty installed `model` name. `endpoint` defaults to `http://localhost:11434/v1/chat/completions`; supply a full HTTP(S) chat-completions URL. Cadence sends a non-streaming request with one user message and reads `choices[0].message.content`. Each step makes a separate request; include earlier output explicitly to pass context. Optional bearer authentication comes from `CADENCE_LLM_API_KEY` in the task environment. No custom generation-parameter fields are supported.

```json
{"kind": "localLLM", "model": "your-installed-model", "endpoint": "http://localhost:11434/v1/chat/completions", "body": "Summarize:\n{{previous_output}}"}
```

Replace `your-installed-model` with the user's actual model before using this step.

### userInput and alert

`userInput.body` asks a question at that position in the workflow. Its answer becomes both `input` and `previous_output`. Another question replaces the current `input`. Cancellation or expiration stops remaining steps even with `continueOnFailure: true`.

`alert.body` displays a message and preserves the previous output for subsequent steps. Dialogs require an interactive logged-in desktop. Alerts display the last 6,000 characters; use files for longer results. Legacy kind names `question` and `response` are readable; generate `userInput` and `alert`. Do not add task-level interaction fields.

```json
{"kind": "userInput", "body": "What should the report focus on?", "timeoutSeconds": 300}
```

```json
{"kind": "alert", "body": "{{previous_output}}", "timeoutSeconds": 120}
```

### saveFile

Requires nonempty `body` content and `outputPath`. Add it after the producing step, using `{{previous_output}}` or an earlier named result. Its result is the saved content. Whole output references save the full canonical file, including large process output; custom text expands the usual placeholders. The parent directory must exist. Relative paths resolve against workingDirectory; existing files are replaced atomically.

```json
{"kind": "saveFile", "name": "Save report", "body": "{{previous_output}}", "outputPath": "report-{{scheduled_date}}.txt"}
```

## Runtime values and environment

Placeholders expand in prompts, alert messages, script paths, script arguments, environment **values**, and output paths. They do not expand in shell source, workingDirectory, executable, model, endpoint, names, or descriptions. Expansion is a single pass; unknown placeholders remain literal. Arbitrary environment variables do not become `{{…}}` placeholders.

| Placeholder | Shell environment variable | Meaning |
| --- | --- | --- |
| `{{date}}` | `TASK_DATE` | Actual run date in the Mac’s local time zone, `YYYY-MM-DD`. |
| `{{timestamp}}` | `TASK_TIMESTAMP` | Actual run start, ISO 8601 UTC. |
| `{{unix}}` | `TASK_UNIX` | Actual run start as Unix seconds. |
| `{{scheduled_date}}` | `TASK_SCHEDULED_DATE` | Original occurrence date in the Mac’s local time zone; use for catch-up reports. |
| `{{scheduled_timestamp}}` | `TASK_SCHEDULED_TIMESTAMP` | Original occurrence timestamp, ISO 8601 UTC. |
| `{{input}}` | `TASK_INPUT` | Most recent question answer; initially empty. |
| `{{previous_output}}` | `TASK_PREVIOUS_OUTPUT` | Previous step's captured result; initially empty. Alerts preserve it; continued failures clear it. |
| `{{previous_output_file}}` | `TASK_PREVIOUS_OUTPUT_FILE` | Run-folder file containing the previous captured result; initially empty. |
| None | `TASK_ID` | Stable task UUID. |

Shell/script results are stdout; LLM results are captured response text. Alerts and skipped steps preserve the preceding result. A failed step allowed to continue clears previous_output and previous_output_file. Use named references to reuse other earlier results; their output_file is Cadence's canonical run-folder file, not the optional outputPath destination.

Prompts and substitutions receive up to the last 1 MB of process output; `TASK_PREVIOUS_OUTPUT` carries its last 16,000 characters. The previous-output file contains full shell/script stdout or the captured response. For large data, pass the file path and have the next tool read it. Do not assume `outputPath` is the file exposed by `previous_output_file`; Cadence also maintains a canonical result file in the run folder.

Named output conditions inspect the same captured result. Named shell output
variables are capped at 16,000 UTF-8 bytes each and share a 48,000-byte budget;
prefer output files for large results. Environment values may reference any
existing result key; they are reevaluated before each step. Before a named step
is reached, its output/file are empty and its status is `pending`. Unknown or
malformed `steps` references are validation errors, unlike unknown ordinary
placeholders, which remain literal.

Environment keys must match `[A-Za-z_][A-Za-z0-9_]*`; the `TASK_` prefix is reserved. Values are literal strings with placeholder expansion, without shell parsing: do not use `export`, shell quotes, `$HOME`, or command substitutions expecting evaluation. Separate entries with JSON `\n` escapes:

```json
{"environment": "REPORT_DATE={{scheduled_date}}\nREPORT_STYLE=concise"}
```

The runner supplies PATH `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`, which environment entries can override. Shell startup files are not loaded. Configs and exports store environment values in plaintext; use existing script/Keychain arrangements for secrets rather than inventing a secret-reference syntax.

## Complete importable example

This example needs no external scripts or models. It starts paused, asks for input, formats it using quoted shell variables, and shows the result. Enable it after import when ready.

```json
{
  "version": 1,
  "name": "Weekday focus reminder",
  "description": "Ask for today's focus and show a dated reminder.",
  "enabled": false,
  "workingDirectory": "~",
  "environment": "",
  "schedule": {
    "kind": "weekly",
    "weekdays": [2, 3, 4, 5, 6],
    "hour": 9,
    "minute": 0
  },
  "missedPolicy": "latest",
  "catchUpLimit": 5,
  "graceSeconds": 90,
  "steps": [
    {
      "kind": "userInput",
      "name": "Ask for focus",
      "body": "What is your focus for {{scheduled_date}}?",
      "timeoutSeconds": 300
    },
    {
      "kind": "shell",
      "name": "Format reminder",
      "body": "printf 'Focus for %s: %s\\n' \"$TASK_SCHEDULED_DATE\" \"$TASK_INPUT\"",
      "timeoutSeconds": 30,
      "continueOnFailure": false
    },
    {
      "kind": "alert",
      "name": "Show reminder",
      "body": "{{previous_output}}",
      "timeoutSeconds": 120
    }
  ]
}
```

## Validate before delivery

- Parse as strict JSON and check against [flow.schema.json](docs/flow.schema.json) when a schema validator is available. Schema checks do not confirm existing directories, installed tools/models, or execution permissions.
- Check the field tables above, nonempty steps and bodies, UUID uniqueness, numeric bounds, weekday numbering, and anchor timestamps. Confirm the requested local time matches the anchor's offset where an anchor represents an exact instant.
- Confirm workingDirectory exists; check referenced scripts, interpreters, executables, output parents, and local model availability where accessible. State anything unverified. Config acceptance alone does not prove those tools can run.
- Review shell quoting and JSON escaping. For a newline in a prompt use JSON `\n`; for a literal backslash-n passed to `printf`, use JSON `\\n`. Use scheduled dates for backlog work.
- For an existing file, review the diff to ensure only requested behavior changed. Write atomically where supported; do not clobber concurrent changes.
- Cadence import/load performs decoding and task validation and reports file-specific errors. The runner has no validate-only flag; running it executes the task. Do not execute a task merely to validate its format. When changing this repository's config implementation, run `zsh scripts/check.sh`; this is the repository check suite, not a validator for an arbitrary config path.

## Example user requests

> Read README-for-LLMs.md and create a paused importable config that runs my existing ~/Projects/reports/scripts/report.py with ~/Projects/reports/.venv/bin/python every weekday at 08:30 Europe/London. Use ~/Projects/reports as workingDirectory, pass --date with the scheduled date, and show stdout in an alert. Save it as weekday-report.cadence.json.

> Read README-for-LLMs.md and edit the managed config at [path]. Change its schedule to Tuesdays and Thursdays at 18:00 Europe/London. Preserve its task ID, step IDs, enabled state, and workflow. Validate the JSON and summarize the diff without running the task.
