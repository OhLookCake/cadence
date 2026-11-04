import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CadenceCore

struct EditorField: View {
    let title: String
    @Binding var text: String
    var monospaced = false
    var placeholder = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.cadenceFieldLabel).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField(placeholder, text: $text).textFieldStyle(.roundedBorder)
                .font(monospaced ? .system(size: 14, design: .monospaced) : .system(size: 15))
                .accessibilityLabel(title)
        }
    }
}
struct EditorPicker<Selection: Hashable, Options: View>: View {
    let title: String
    @Binding var selection: Selection
    var width: CGFloat = 320
    @ViewBuilder var options: () -> Options
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.cadenceFieldLabel).foregroundStyle(.secondary)
            Picker(title, selection: $selection, content: options)
                .labelsHidden().pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(title)
        }.frame(maxWidth: width, alignment: .leading)
    }
}
struct DurationField: View {
    let title: String
    @Binding var seconds: Int
    var inline = false
    var body: some View {
        Group {
            if inline {
                HStack(spacing: 8) {
                    Text(title).font(.cadenceFieldLabel).foregroundStyle(.secondary)
                    valueField
                }.fixedSize()
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    Text(title).font(.cadenceFieldLabel).foregroundStyle(.secondary)
                    valueField
                }.frame(maxWidth: 260, alignment: .leading)
            }
        }.font(.cadenceCallout)
    }
    var valueField: some View {
        HStack(spacing: 8) {
            TextField("", value: $seconds, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder).frame(width: 80)
                .labelsHidden().accessibilityLabel(title + " in seconds")
            Text("seconds").foregroundStyle(.secondary)
        }
    }
}
struct CodeField: View {
    @Binding var text: String
    var height: CGFloat = 140
    var label = "Text"
    var monospaced = true
    var placeholder = ""
    @Environment(\.isEnabled) private var isEnabled
    @State private var resizedHeight: CGFloat?
    @GestureState private var resizeTranslation: CGFloat = 0
    private let minimumHeight: CGFloat = 60
    private var editorHeight: CGFloat { max(minimumHeight, (resizedHeight ?? height) + resizeTranslation) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text).scrollContentBackground(.hidden).accessibilityLabel(label)
                if text.isEmpty && !placeholder.isEmpty {
                    Text(placeholder).foregroundStyle(.tertiary).padding(.horizontal, 5).padding(.top, 8)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }.padding(.horizontal, 8).padding(.top, 8)
            HStack {
                Spacer()
                resizeHandle
            }.padding(.horizontal, 6).padding(.bottom, 3)
        }
            .font(monospaced ? .system(size: 14, design: .monospaced) : .system(size: 15))
            .frame(height: editorHeight)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)).allowsHitTesting(false))
    }
    private var resizeHandle: some View {
        Image(systemName: "line.3.horizontal").font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary).frame(width: 30, height: 16).contentShape(Rectangle())
            .help("Drag up or down to resize")
            .onHover { hovering in
                if hovering && isEnabled { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
            }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .updating($resizeTranslation) { value, translation, _ in translation = value.translation.height }
                .onEnded { value in resizedHeight = max(minimumHeight, (resizedHeight ?? height) + value.translation.height) },
                including: isEnabled ? .all : .none)
            .accessibilityElement()
            .accessibilityLabel("Resize " + label)
            .accessibilityValue("\(Int(editorHeight)) points high")
            .accessibilityAdjustableAction { direction in
                guard isEnabled else { return }
                switch direction {
                case .increment: resizedHeight = (resizedHeight ?? height) + 20
                case .decrement: resizedHeight = max(minimumHeight, (resizedHeight ?? height) - 20)
                @unknown default: break
                }
            }
    }
}
struct ScheduleFields: View {
    @Binding var task: ScheduledTask
    var time: Binding<Date> {
        Binding(get: { task.schedule.calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: task.schedule.hour, minute: task.schedule.minute)) ?? Date() },
                set: { date in task.schedule.hour = task.schedule.calendar.component(.hour, from: date); task.schedule.minute = task.schedule.calendar.component(.minute, from: date) })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Frequency", selection: $task.schedule.kind) {
                ForEach(ScheduleKind.allCases) { kind in Text(kind.title).tag(kind) }
            }
            if task.schedule.kind == .interval || task.schedule.kind == .everyDays {
                HStack {
                    Text("Every").fixedSize(); Spacer()
                    TextField("", value: $task.schedule.every, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder).frame(width: 70).accessibilityLabel("Repeat interval")
                    Text(task.schedule.kind == .interval ? "minutes" : "days").fixedSize()
                }
            }
            if task.schedule.kind != .interval && task.schedule.kind != .once {
                DatePicker("At", selection: time, displayedComponents: .hourAndMinute).environment(\.timeZone, task.schedule.calendar.timeZone)
            }
            if task.schedule.kind == .weekly {
                HStack(spacing: 4) {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                        Button(["S", "M", "T", "W", "T", "F", "S"][day - 1]) {
                            toggleDay(day)
                        }.buttonStyle(.bordered).controlSize(.small)
                            .tint(task.schedule.weekdays.contains(day) ? .cadence : .secondary)
                            .background(task.schedule.weekdays.contains(day) ? Color.cadence.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 5))
                            .accessibilityLabel(["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][day - 1])
                            .help(["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][day - 1])
                    }
                }
            }
            if task.schedule.kind == .once || task.schedule.kind == .interval {
                DatePicker(task.schedule.kind == .once ? "Run at" : "Starting at", selection: $task.schedule.anchor)
                    .environment(\.timeZone, task.schedule.calendar.timeZone)
            }
            if task.schedule.kind == .everyDays {
                DatePicker("Starting on", selection: $task.schedule.anchor, displayedComponents: .date).environment(\.timeZone, task.schedule.calendar.timeZone)
            }
            Text("Uses this Mac’s local time, including daylight-saving changes. Checks run each minute.").font(.cadenceCaption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    func toggleDay(_ day: Int) {
        var days = task.schedule.weekdays
        if days.contains(day) { days.removeAll { $0 == day } } else { days.append(day) }
        task.schedule.weekdays = days
    }
}
struct MissedRunFields: View {
    @Binding var task: ScheduledTask
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("On return", selection: $task.missedPolicy) {
                ForEach(MissedPolicy.allCases) { policy in Text(policy.title).tag(policy) }
            }
            Text(task.missedPolicy.detail).font(.cadenceCaption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if task.missedPolicy == .all { Stepper("Up to \(task.catchUpLimit) runs per check", value: $task.catchUpLimit, in: 1...100).font(.cadenceCaption) }
            if task.missedPolicy == .skip { DurationField(title: "Grace period", seconds: $task.graceSeconds) }
            Text("Runs of this task never overlap. Re-enabling a paused task or changing its schedule starts from now.").font(.cadenceCaption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
struct ScheduleConfiguration: View {
    @Binding var task: ScheduledTask
    @Binding var missedRunsExpanded: Bool
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 32) {
                ScheduleFields(task: $task).frame(minWidth: 330, maxWidth: .infinity, alignment: .leading)
                missedRuns.frame(minWidth: 330, maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 24) {
                ScheduleFields(task: $task)
                Divider()
                missedRuns
            }
        }
    }
    var missedRuns: some View {
        DisclosureGroup(isExpanded: $missedRunsExpanded) {
            MissedRunFields(task: $task).padding(.top, 14)
        } label: {
            Label("Missed runs", systemImage: "arrow.trianglehead.clockwise").font(.system(size: 14, weight: .semibold))
        }
    }
}

struct WorkingDirectoryFields: View {
    @Binding var task: ScheduledTask
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom, spacing: 10) {
                EditorField(title: "Working directory", text: $task.workingDirectory, monospaced: true)
                Button("Choose…") {
                    let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url { task.workingDirectory = url.path }
                }.fixedSize()
            }
        }
    }
}
struct EnvironmentFields: View {
    @Binding var task: ScheduledTask
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Environment variables · one KEY=value per line").font(.cadenceCaption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            CodeField(text: $task.environment, height: 75, label: "Environment variables")
            Text("PATH includes Homebrew and system tools. Values are stored in the local task definition.").font(.cadenceCaption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct WorkflowEditor: View {
    @Binding var task: ScheduledTask
    @Environment(\.isEnabled) private var isEnabled
    @AppStorage private var expanded: Bool
    @AppStorage private var collapsedStepIDs: String
    private var collapsedSteps: Set<UUID> { Set(collapsedStepIDs.split(separator: ",").compactMap { UUID(uuidString: String($0)) }) }
    init(task: Binding<ScheduledTask>) {
        _task = task
        let key = task.wrappedValue.id.uuidString
        _expanded = AppStorage(wrappedValue: true, "cadence.section.\(key).workflow")
        _collapsedStepIDs = AppStorage(wrappedValue: "", "cadence.section.\(key).steps")
    }
    @State private var targetedInsertion: Int?
    private var referenceIssue: String? {
        do { try WorkflowReferences.validate(task); return nil }
        catch { return error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Button { expanded.toggle() } label: {
                        HStack(spacing: 10) {
                            Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 15, weight: .semibold))
                            Text("Workflow").font(.system(size: 24, weight: .semibold, design: .rounded))
                            Text("\(task.steps.count) steps").font(.cadenceCaption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(expanded ? "Collapse Workflow" : "Expand Workflow")
                }
                Spacer()
                addMenu
            }
            if expanded {
            if let issue = referenceIssue {
                Label(issue, systemImage: "exclamationmark.triangle")
                    .font(.cadenceCallout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            dropTarget(0, minimumHeight: 4) { Color.clear.frame(height: 4) }
            ForEach($task.steps) { $step in
                let index = task.steps.firstIndex(where: { $0.id == step.id }) ?? 0
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        WorkflowDragHandle(transfer: WorkflowStepTransfer(taskID: task.id, stepID: step.id),
                                           title: "\(index + 1). \(step.name)", enabled: isEnabled)
                            .frame(width: 18, height: 28)
                        Button { toggleStep(step.id) } label: {
                            HStack(spacing: 10) {
                                Text(String(format: "%02d", index + 1)).font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color.cadence).frame(width: 30, height: 30)
                                    .background(Color.cadence.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(step.name).font(.cadenceStepTitle)
                                    Label(step.kind.title, systemImage: step.kind.symbol).font(.cadenceCaption).foregroundStyle(.secondary)
                                }
                                if step.runIf != nil { Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(Color.cadence).help("This step has a run condition") }
                                Spacer(minLength: 0)
                                Image(systemName: collapsedSteps.contains(step.id) ? "chevron.right" : "chevron.down")
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .help(collapsedSteps.contains(step.id) ? "Expand step" : "Collapse step")
                            .accessibilityLabel((collapsedSteps.contains(step.id) ? "Expand " : "Collapse ") + step.name)
                        HStack(spacing: 4) {
                            Button { move(step.id, -1) } label: {
                                Image(systemName: "arrow.up").frame(width: 28, height: 28)
                            }.disabled(index == 0).help("Move up").accessibilityLabel("Move " + step.name + " up")
                            Button { move(step.id, 1) } label: {
                                Image(systemName: "arrow.down").frame(width: 28, height: 28)
                            }.disabled(index == task.steps.count - 1).help("Move down").accessibilityLabel("Move " + step.name + " down")
                            Button(role: .destructive) { task.steps.removeAll { $0.id == step.id } } label: {
                                Image(systemName: "trash").frame(width: 28, height: 28)
                            }.help("Delete step").accessibilityLabel("Delete " + step.name)
                        }
                    }.buttonStyle(.borderless).padding(16)
                    if !collapsedSteps.contains(step.id) {
                        Divider()
                        StepFields(step: $step, earlierSteps: Array(task.steps.prefix(index)), llmAPIKey: ModelChoices.apiKey(in: task.environment))
                            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12)).allowsHitTesting(false))
                if index < task.steps.count - 1 { dropTarget(index + 1) { WorkflowConnector() } }
            }
            if task.steps.isEmpty { Text("Add a step to define what this task does.").foregroundStyle(.secondary).padding(.vertical, 15) }
            dropTarget(task.steps.count) { WorkflowBoundary(title: "End", symbol: "checkmark") }
            addMenu
            }
        }.padding(20).frame(maxWidth: 880, alignment: .leading)
            .background(Color.cadence.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.cadence.opacity(0.15)).allowsHitTesting(false))
    }
    var addMenu: some View {
        Menu { ForEach(StepKind.allCases) { kind in Button { task.steps.append(TaskStep.make(kind)); expanded = true } label: { Label(kind.title, systemImage: kind.symbol) } } } label: {
            Label("Add Step", systemImage: "plus")
        }.fixedSize()
    }
    func move(_ id: UUID, _ direction: Int) {
        guard let index = task.steps.firstIndex(where: { $0.id == id }), task.steps.indices.contains(index + direction) else { return }
        task.steps.swapAt(index, index + direction)
    }
    func toggleStep(_ id: UUID) {
        var ids = collapsedSteps
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        collapsedStepIDs = ids.map(\.uuidString).sorted().joined(separator: ",")
    }
    func dropTarget<Content: View>(_ insertion: Int, minimumHeight: CGFloat = 30, @ViewBuilder content: () -> Content) -> some View {
        content().frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading)
            .padding(.vertical, 4).contentShape(Rectangle())
            .background(targetedInsertion == insertion ? Color.cadence.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottom) {
                if targetedInsertion == insertion { Rectangle().fill(Color.cadence).frame(height: 3).allowsHitTesting(false) }
            }
            .onDrop(of: [.cadenceWorkflowStep], isTargeted: Binding(get: { targetedInsertion == insertion }, set: { targeted in
                if targeted && isEnabled { targetedInsertion = insertion }
                else if targetedInsertion == insertion { targetedInsertion = nil }
            })) { providers in
                targetedInsertion = nil
                guard isEnabled, providers.count == 1, let provider = providers.first else { return false }
                provider.loadDataRepresentation(forTypeIdentifier: UTType.cadenceWorkflowStep.identifier) { data, _ in
                    guard let data, let item = try? JSONDecoder().decode(WorkflowStepTransfer.self, from: data) else { return }
                    Task { @MainActor in
                        guard isEnabled, item.taskID == task.id else { return }
                        WorkflowOrder.move(item.stepID, in: &task.steps, toInsertion: insertion)
                    }
                }
                return true
            }
            .accessibilityLabel(insertion == task.steps.count ? "Drop step at end" : "Drop step before step \(insertion + 1)")
    }
}
struct WorkflowBoundary: View {
    let title: String
    let symbol: String
    var body: some View {
        Label(title.uppercased(), systemImage: symbol).font(.system(size: 12, weight: .semibold))
            .tracking(1.5).foregroundStyle(Color.cadence).padding(.leading, 24)
    }
}
struct WorkflowConnector: View {
    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Rectangle().fill(Color.cadence.opacity(0.5)).frame(width: 2, height: 10)
                Image(systemName: "arrow.down").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.cadence)
                Rectangle().fill(Color.cadence.opacity(0.5)).frame(width: 2, height: 10)
            }.frame(width: 34)
            Text("THEN").font(.system(size: 11, weight: .medium)).tracking(1.5).foregroundStyle(.secondary)
        }.padding(.leading, 20).accessibilityLabel("Then run the next step")
    }
}
struct StepFields: View {
    @Binding var step: TaskStep
    var earlierSteps: [TaskStep] = []
    var llmAPIKey = ""
    @State private var codexModels: [String] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            EditorField(title: "Step name", text: $step.name)
            EditorPicker(title: "Step type", selection: Binding(get: { step.kind }, set: { kind in
                let id = step.id, key = step.key; let condition = step.runIf
                step = TaskStep.make(kind); step.id = id; step.key = key; step.runIf = condition
            })) {
                ForEach(StepKind.allCases) { kind in Text(kind.title).tag(kind) }
            }
            primaryInput
            VStack(alignment: .leading, spacing: 7) {
                EditorField(title: "Result name (optional)", text: $step.key, monospaced: true, placeholder: "report_summary")
                    .frame(maxWidth: 280, alignment: .leading)
                    .help("Start with a lowercase letter. Use lowercase letters, digits, and underscores, up to 40 characters. Keep this name stable when renaming the step.")
                Text("Lets later steps reuse this output by name.")
                    .font(.cadenceCaption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            toolSettings
            if earlierSteps.contains(where: { !$0.key.isEmpty }) || step.runIf != nil {
                Divider()
                RunConditionFields(condition: $step.runIf, earlierSteps: earlierSteps)
            }
            Divider()
            HStack(spacing: 24) {
                DurationField(title: durationTitle, seconds: $step.timeoutSeconds, inline: true)
                Spacer(minLength: 0)
                Toggle("Continue after failure", isOn: $step.continueOnFailure)
                    .toggleStyle(.checkbox).font(.cadenceCallout).fixedSize()
                    .help(step.kind == .question
                          ? "Cancelling or timing out always stops the workflow."
                          : "Run later steps after a failure. The overall run still reports failure.")
            }
        }.frame(maxWidth: 720, alignment: .leading)
    }
    var referenceMenu: some View {
        Menu {
            ForEach(earlierSteps.filter { !$0.key.isEmpty }) { source in
                Menu("\(source.name) · \(source.key)") {
                    ForEach(["output", "output_file", "status"], id: \.self) { field in
                        let reference = step.kind == .shell ? "$TASK_STEP_\(source.key.uppercased())_\(field.uppercased())" : "{{steps.\(source.key).\(field)}}"
                        Button(reference) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(reference, forType: .string)
                        }
                    }
                }
            }
        } label: { Label("Copy result reference", systemImage: "doc.on.doc") }
        .fixedSize().controlSize(.small).help("Copy an earlier result to paste into this input. Quote environment variables in shell commands.")
    }
    var durationTitle: String {
        switch step.kind { case .question: return "Wait for an answer"; case .response: return "Dismiss after"; default: return "Timeout" }
    }
    func hint(_ text: String) -> some View {
        Text(text).font(.cadenceCaption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    func textInput(_ title: String, label: String, height: CGFloat = 140, help: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 14, weight: .medium))
                Spacer(minLength: 12)
                if earlierSteps.contains(where: { !$0.key.isEmpty }) { referenceMenu }
            }
            CodeField(text: $step.body, height: height, label: label)
            hint(help)
        }
    }
    @ViewBuilder var primaryInput: some View {
        switch step.kind {
        case .shell:
            textInput("Command · /bin/zsh", label: "Inline shell command", help: "Use quoted variables such as \"$TASK_SCHEDULED_DATE\". Commands run literally in /bin/zsh.")
        case .script:
            VStack(alignment: .leading, spacing: 14) {
                fileField("Script file or executable", text: $step.scriptPath, script: true)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Arguments").font(.system(size: 14, weight: .medium))
                        Spacer(minLength: 12)
                        if earlierSteps.contains(where: { !$0.key.isEmpty }) { referenceMenu }
                    }
                    CodeField(text: $step.arguments, height: 85, label: "Script arguments")
                    hint("One argument per line, without shell quotes. The script path is supplied automatically. Variables such as {{input}} are supported.")
                }
            }
        case .codex:
            textInput("Prompt", label: "Codex prompt", help: "Uses your Codex CLI login. Include {{previous_output}} or an earlier result to provide context.")
        case .localLLM:
            textInput("Prompt", label: "Local LLM prompt", help: "Include {{previous_output}} or an earlier result to provide context. Each step sends a separate request.")
        case .question:
            textInput("Question", label: "Question text", height: 85, help: "The answer becomes {{input}} and {{previous_output}}, or $TASK_INPUT in commands.")
        case .response:
            textInput("Message", label: "Response message", height: 85, help: "Displays up to 6,000 characters. The previous output stays available to the next step.")
        case .saveFile:
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom, spacing: 10) {
                    EditorField(title: "Destination file", text: $step.outputPath, monospaced: true)
                    Button("Choose…", action: chooseDestination).fixedSize()
                }.frame(maxWidth: 560, alignment: .leading)
                textInput("Content", label: "File content", help: "{{previous_output}} saves the full preceding result. Replaces the destination file; its folder must exist. Relative paths use the working directory.")
            }
        }
    }
    @ViewBuilder var toolSettings: some View {
        switch step.kind {
        case .codex:
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Text("Codex settings").font(.system(size: 14, weight: .medium))
                fileField("Codex executable", text: $step.executable, script: false)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) { modelField.frame(minWidth: 220); sandboxField.frame(minWidth: 220) }
                    VStack(alignment: .leading, spacing: 14) { modelField; sandboxField }
                }
                hint("Workspace write allows changes in the working directory. Background runs cannot request approvals.")
            }.task { codexModels = ModelChoices.codex() }
        case .localLLM:
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Text("Model connection").font(.system(size: 14, weight: .medium))
                LocalModelConnectionFields(model: $step.model, endpoint: $step.endpoint, apiKey: llmAPIKey)
                hint("Works with Ollama, LM Studio, and compatible servers. Optional API key: CADENCE_LLM_API_KEY in Environment.")
            }
        case .script:
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                fileField("Interpreter (optional)", text: $step.executable, script: false)
                hint("Leave empty to execute the file directly. Use /bin/zsh for shell scripts or your uv environment’s .venv/bin/python for Python.")
            }
        default: EmptyView()
        }
    }
    var modelField: some View {
        EditorComboField(title: "Model (optional)", text: $step.model, choices: codexModels, placeholder: "Use CLI default")
            .frame(maxWidth: 280, alignment: .leading)
    }
    var sandboxField: some View {
        EditorPicker(title: "Sandbox", selection: $step.sandbox, width: 240) {
            Text("Read only").tag("read-only"); Text("Workspace write").tag("workspace-write")
        }
    }
    func fileField(_ title: String, text: Binding<String>, script: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            EditorField(title: title, text: text, monospaced: true)
            Button("Choose…") { chooseFile(script: script) }.fixedSize()
        }.frame(maxWidth: 560, alignment: .leading)
    }
    func chooseDestination() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = (step.outputPath as NSString).lastPathComponent
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        step.outputPath = url.path
    }
    func chooseFile(script: Bool) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if script {
            step.scriptPath = url.path
            step.executable = ["sh", "zsh", "bash"].contains(url.pathExtension.lowercased()) ? "/bin/zsh" : ""
        } else { step.executable = url.path }
    }
}

struct RunConditionFields: View {
    @Binding var condition: StepCondition?
    let earlierSteps: [TaskStep]
    var namedSteps: [TaskStep] { earlierSteps.filter { !$0.key.isEmpty } }
    var current: Binding<StepCondition> {
        Binding(get: { condition ?? StepCondition(step: namedSteps.first?.key ?? "") }, set: { condition = $0 })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Run only when…", isOn: Binding(get: { condition != nil }, set: { enabled in
                condition = enabled ? StepCondition(step: namedSteps.first?.key ?? "") : nil
            }))
            .toggleStyle(.checkbox).font(.cadenceCallout).disabled(namedSteps.isEmpty && condition == nil)
            if let selected = condition {
                EditorPicker(title: "Earlier result", selection: current.step, width: 440) {
                    if !namedSteps.contains(where: { $0.key == selected.step }) {
                        Text(selected.step.isEmpty ? "Choose an earlier result" : "Missing or later: \(selected.step)").tag(selected.step)
                    }
                    ForEach(namedSteps) { source in Text("\(source.name) · \(source.key)").tag(source.key) }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        checkField(selected).frame(minWidth: 160)
                        operatorField(selected).frame(minWidth: 240)
                    }
                    VStack(alignment: .leading, spacing: 12) { checkField(selected); operatorField(selected) }
                }
                if selected.operation.needsValue {
                    if selected.field == .status {
                        EditorPicker(title: "Value", selection: current.value) {
                            ForEach(StepResultStatus.conditionValues) { status in Text(status.rawValue.capitalized).tag(status.rawValue) }
                        }
                    } else {
                        EditorField(title: "Compare with (case-sensitive text)", text: current.value)
                            .frame(maxWidth: 440, alignment: .leading)
                    }
                }
                Text(selected.field == .output
                     ? "Empty checks ignore whitespace. If the earlier step failed or was skipped, this output condition is false. Skipping preserves the previous output."
                     : "A failed step must allow continuation for later steps to check its status. Skipped results have status skipped.")
                    .font(.cadenceCaption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if namedSteps.isEmpty {
                Text("Give an earlier step a result name to add a condition here.").font(.cadenceCaption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: 560, alignment: .leading)
    }
    func checkField(_ selected: StepCondition) -> some View {
        EditorPicker(title: "Check", selection: Binding(get: { selected.field }, set: { field in
            var updated = selected; updated.field = field
            if !field.operators.contains(updated.operation) { updated.operation = .equals }
            updated.value = field == .status ? "succeeded" : ""
            condition = updated
        }), width: 180) {
            ForEach(ConditionField.allCases) { field in Text(field.title).tag(field) }
        }
    }
    func operatorField(_ selected: StepCondition) -> some View {
        EditorPicker(title: "Condition", selection: current.operation, width: 260) {
            ForEach(selected.field.operators) { operation in Text(operation.title).tag(operation) }
        }
    }
}
