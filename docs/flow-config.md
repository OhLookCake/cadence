# Flow configuration files

Each task is backed by exactly one UTF-8 JSON file:

~~~text
~/Library/Application Support/Cadence/flows/<task UUID>.cadence.json
~~~

This is the source of truth. UI saves update the file atomically. Files can be renamed within the flows folder; keep the **id** unchanged to retain identity, history, and schedule state. Do not keep two files with the same ID in that folder.

Use **Edit Config File** to open the task's file in TextEdit, or **Show in Finder** to use your preferred editor. With Cadence open, edits appear within three seconds. New or enabled configs are registered with launchd; disabled or removed configs are unregistered after any active occurrence finishes. Already registered jobs read the latest config on their next check even with the UI closed. Open Cadence after adding a new file or enabling a previously unregistered task.

## Create or import

**File → Import Config…** accepts one or more JSON files. Imports get new task IDs and start paused, even if the source says enabled. The source file is copied into the managed folder; subsequent edits should target the managed file shown on the task. **Export Config…** exports one task in the same format.

[This example](../Examples/daily-report.cadence.json) can be imported as written. IDs are optional on import. Managed files require a task ID; imports and UI saves supply it. Handwritten steps may omit IDs and get stable identities when loaded.

~~~json
{
  "version": 1,
  "name": "Daily report",
  "description": "Generate a report at 09:00.",
  "enabled": false,
  "workingDirectory": "~",
  "schedule": {
    "kind": "daily",
    "hour": 9,
    "minute": 0,
    "timeZone": "Europe/London"
  },
  "missedPolicy": "latest",
  "steps": [
    {
      "kind": "shell",
      "body": "./report.sh --date \"$TASK_SCHEDULED_DATE\"",
      "timeoutSeconds": 600
    }
  ]
}
~~~

The optional **$schema** key can point your editor to [flow.schema.json](flow.schema.json) for completion and validation. Unknown keys, wrong types, unsupported versions, duplicate IDs, and malformed JSON produce file-specific errors. Invalid enabled tasks do not execute; valid neighboring tasks remain usable.

If a file changes while the UI has unsaved edits, Cadence keeps the draft and prevents overwriting the external change. **Reload from file** or **Revert** replaces the draft with the current file.

## Top-level fields

| Field | Meaning / default |
| --- | --- |
| version | 1 |
| id | Stable UUID; optional on import |
| name | Required task name |
| description | Optional description |
| enabled | false |
| workingDirectory | ~; absolute and home-relative paths supported |
| environment | String with one KEY=value per line, separated by \n |
| schedule | Required schedule object |
| missedPolicy | skip, latest (default), or all |
| catchUpLimit | 1–100; default 5 |
| graceSeconds | 0–3,600; default 90 |
| steps | Ordered list of steps |

## Schedules

Each schedule has **kind** and an optional IANA **timeZone** identifier (default: the Mac's current zone). Generated configs include explicit values so they remain stable across launches.

| Kind | Fields |
| --- | --- |
| daily | hour (default 9), minute (default 0) |
| weekly | hour, minute, weekdays: Sunday=1 through Saturday=7 |
| everyDays | every (days), anchor (ISO 8601 timestamp), hour, minute |
| interval | every (minutes), anchor (ISO 8601 timestamp) |
| once | anchor (ISO 8601 timestamp) |

An anchor is required for everyDays, interval, and once, for example **2026-11-03T09:00:00Z**. Changing a schedule or re-enabling a task starts scheduling from the next observation. Editing commands or descriptions preserves its cursor.

## Steps

Common optional fields: **id**, **name**, **timeoutSeconds**, **continueOnFailure**, **outputPath**. Timeouts range from 1 to 86,400 seconds. Output files are replaced atomically; their parent folders must exist.

| Kind | Fields |
| --- | --- |
| shell | Required body: literal /bin/zsh commands |
| script | Required scriptPath; optional executable interpreter (default /bin/zsh, empty string for direct execution); arguments array |
| codex | Required body prompt; optional executable, model, sandbox |
| localLLM | Required body prompt and installed model; optional endpoint |
| userInput | Required body prompt; default timeout 300 seconds |
| alert | Required body message; default timeout 120 seconds |

The older question and response kind names remain readable; new files use userInput and alert. Script arguments also accept the older newline-separated string format. The script path is passed automatically:

~~~json
{
  "kind": "script",
  "scriptPath": "scripts/report.sh",
  "executable": "/bin/zsh",
  "arguments": ["--date", "{{scheduled_date}}", "--input", "{{input}}"]
}
~~~

For Python, select your uv project's .venv/bin/python as the interpreter. Relative script and interpreter paths resolve against workingDirectory.

Arguments, prompts, messages, and output paths support {{date}}, {{timestamp}}, {{unix}}, {{scheduled_date}}, {{scheduled_timestamp}}, {{input}}, {{previous_output}}, and {{previous_output_file}}. Inline commands use quoted TASK_ environment variables instead of template substitution.

## Migration and runtime data

The previous tasks.json catalog is migrated automatically to individual files. IDs, enabled states, history, and existing schedule cursors are retained. The original catalog is archived under legacy after conversion succeeds.

Runtime metadata stays in metadata/, occurrence cursors in state/, and logs/history in runs/. These are not config files. Deleting a task removes its config and launchd registration while retaining history. A running occurrence uses the definition it started with; file edits take effect on the next occurrence without interrupting commands already running.
