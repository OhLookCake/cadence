# Conditional workflows: design and implementation plan

## Behavior

Cadence keeps its ordered workflow. Each step optionally supplies a stable `key`
(shown as **Result name**) independent of its display name. Keys are unique within
a task and match `[a-z][a-z0-9_]{0,39}`. Existing steps default to no key and no
condition.

Later steps can reference `{{steps.fetch.output}}`,
`{{steps.fetch.output_file}}`, and `{{steps.fetch.status}}`. Shell source stays
literal; the equivalent variables are `$TASK_STEP_FETCH_OUTPUT`,
`$TASK_STEP_FETCH_OUTPUT_FILE`, and `$TASK_STEP_FETCH_STATUS`. Expansion stays
single-pass. Output files contain the full result; inline output is bounded as
before. Named shell outputs share a bounded environment budget.

An optional `runIf` object selects an earlier result by key, a field (`output`
or `status`), an operator, and a literal comparison value. Output operators are
`isEmpty`, `isNotEmpty`, `equals`, `notEquals`, `contains`, and `notContains`.
Empty checks ignore whitespace; text comparisons are exact and case-sensitive.
Status supports `equals` and `notEquals` against `succeeded`, `failed`, `skipped`,
or `cancelled`. There is one condition per step; multiple consecutive steps can
share it. An output condition on a source that did not succeed is always false.

False conditions record a skipped step with a reason, perform no side effects,
and preserve the current input and previous output. Skipped/failed results have
empty output/file references and retain their status. Existing stop/continue and
cancellation rules still apply. A failed step needs continue-on-failure enabled
before a later status condition can handle it. Skipping does not fail a run.

Saving validates keys, conditions, and named references before execution.
References in per-step templated fields must target earlier steps; shell source
is not interpreted as a template. Shared environment values may reference any
existing key and are reevaluated before each step: an unreached result has empty
output/file and status `pending`. Renaming a display name is harmless; editing a
result name requires updating its references. Reordering/deleting steps cannot
silently create broken or forward references.

Version 1 config gains optional `key` and `runIf` fields. Strict unknown-field
checks include the condition object. Run records gain optional step outcomes so
old history remains readable. The history sheet shows step statuses and skip
reasons alongside its existing log.

## Plan

1. Add the condition/reference types, validation, backward-compatible config
   encoding, schema, and durable step outcomes.
2. Add single-pass named result expansion, safe shell variables, condition
   evaluation, skipped-step handling, and accurate final summaries to the runner.
3. Add result names, condition controls, reference-copy menus, and visible step
   outcomes to the existing native editor/history UI.
4. Document the format and behavior; add a runnable conditional example.
5. Test config round trips, legacy compatibility, invalid references, every
   operator, success/failure/skip chains, cancellation, single-pass substitution,
   shell injection resistance, full output files, and repeated runs.
6. Run all checks, build the release app, exercise the editor and both branches
   of a workflow in the app, and correct any discovered problems.

## Acceptance criteria

- Old configs and history load without migration or behavior changes.
- A later step can reuse an earlier result across intervening and skipped steps.
- Both empty/nonempty branches and continued-failure status branches work.
- Invalid references fail before any workflow command runs.
- Skipped steps create no output files or external effects and are clearly
  identified in history.
- Templates and environment variables treat results as data, including text
  containing shell syntax or other placeholders.
- Editing, saving, reopening, and running the new controls works in the built app.

## Verification completed

- `zsh scripts/check.sh`: 42 passed, zero failures. The existing optional live
  model and real launchd checks were skipped.
- `zsh scripts/build-app.sh`: release bundle built and signed successfully.
- The release check executable passed its conditional-process test against the
  runner packaged inside `dist/Cadence.app`.
- Native UI checks covered import, output/status selection, literal text
  comparisons, save/reopen, both empty and nonempty branches, step status/skip
  display, and rejection of a dependency moved before its source. Revert restored
  the valid workflow. A final empty-branch run also passed in the rebuilt bundle.
- Review/testing corrected Unicode truncation at environment byte boundaries,
  rejection of unfinished references, and a test that assumed second-resolution
  history timestamps uniquely ordered two rapid runs.
- The imported conditional example remains paused with its default input
  restored, ready to inspect in the app.
