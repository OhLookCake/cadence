import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CadenceCore

struct EditorField: View {
    let title: String
    @Binding var text: String
    var monospaced = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("", text: $text).textFieldStyle(.roundedBorder)
                .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 13))
                .accessibilityLabel(title)
        }
    }
}
struct DurationField: View {
    let title: String
    @Binding var seconds: Int
    var body: some View {
        HStack(spacing: 10) {
            Text(title).fixedSize(horizontal: true, vertical: true)
            Spacer(minLength: 12)
            TextField("", value: $seconds, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                .frame(width: 90).labelsHidden().accessibilityLabel(title + " in seconds")
            Text("seconds").foregroundStyle(.secondary).fixedSize()
        }.font(.system(size: 12))
    }
}
struct CodeField: View {
    @Binding var text: String
    var height: CGFloat = 140
    var label = "Text"
    var body: some View {
        TextEditor(text: $text).font(.system(size: 12, design: .monospaced))
            .scrollContentBackground(.hidden).padding(8)
            .frame(height: height)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)).allowsHitTesting(false))
            .accessibilityLabel(label)
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
            TimeZonePicker(selection: $task.schedule.timeZone)
            Text("Calendar times follow this time zone, including daylight-saving changes. Checks run each minute.").font(.caption).foregroundStyle(.secondary)
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
            Text(task.missedPolicy.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if task.missedPolicy == .all { Stepper("Up to \(task.catchUpLimit) runs per check", value: $task.catchUpLimit, in: 1...100).font(.caption) }
            if task.missedPolicy == .skip { DurationField(title: "Grace period", seconds: $task.graceSeconds) }
            Text("Runs of this task never overlap. Re-enabling a paused task or changing its schedule starts from now.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
struct ScheduleConfiguration: View {
    @Binding var task: ScheduledTask
    @Binding var missedRunsExpanded: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            ScheduleFields(task: $task).frame(maxWidth: .infinity, alignment: .leading)
            DisclosureGroup(isExpanded: $missedRunsExpanded) {
                MissedRunFields(task: $task).padding(.top, 14)
            } label: {
                Label("Missed runs", systemImage: "arrow.trianglehead.clockwise").font(.system(size: 12, weight: .semibold))
            }.frame(maxWidth: .infinity, alignment: .leading)
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
            Text("All steps run from this directory.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
struct EnvironmentFields: View {
    @Binding var task: ScheduledTask
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Environment variables · one KEY=value per line").font(.caption).foregroundStyle(.secondary)
            CodeField(text: $task.environment, height: 75, label: "Environment variables")
            Text("PATH includes Homebrew and system tools. Values are stored in the local task definition.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct WorkflowEditor: View {
    @Binding var task: ScheduledTask
    @Environment(\.isEnabled) private var isEnabled
    @State private var expanded = true
    @State private var collapsedSteps: Set<UUID> = []
    @State private var targetedInsertion: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Button { expanded.toggle() } label: {
                        HStack(spacing: 10) {
                            Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 13, weight: .semibold))
                            Text("Workflow").font(.system(size: 22, weight: .semibold, design: .rounded))
                            Text("\(task.steps.count) steps").font(.caption).foregroundStyle(.secondary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(expanded ? "Collapse Workflow" : "Expand Workflow")
                    Text("Drag a step’s grip to a connector to reorder. Output flows from one step to the next.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                addMenu
            }
            if expanded {
            dropTarget(0) { WorkflowBoundary(title: "Start", symbol: "play.fill") }
            ForEach($task.steps) { $step in
                let index = task.steps.firstIndex(where: { $0.id == step.id }) ?? 0
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        WorkflowDragHandle(transfer: WorkflowStepTransfer(taskID: task.id, stepID: step.id),
                                           title: "\(index + 1). \(step.name)", enabled: isEnabled)
                            .frame(width: 28, height: 28)
                        Text(String(format: "%02d", index + 1)).font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white).frame(width: 34, height: 34).background(Color.cadence, in: Circle())
                        Image(systemName: step.kind.symbol).foregroundStyle(Color.cadence)
                        TextField("Step name", text: $step.name).font(.system(size: 16, weight: .medium)).textFieldStyle(.plain).accessibilityLabel("Step \(index + 1) name")
                        Spacer()
                        Button { toggleStep(step.id) } label: {
                            Image(systemName: collapsedSteps.contains(step.id) ? "chevron.right" : "chevron.down")
                        }.help(collapsedSteps.contains(step.id) ? "Expand step" : "Collapse step")
                            .accessibilityLabel((collapsedSteps.contains(step.id) ? "Expand " : "Collapse ") + step.name)
                        Button { move(step.id, -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0).help("Move step up")
                        Button { move(step.id, 1) } label: { Image(systemName: "arrow.down") }.disabled(index == task.steps.count - 1).help("Move step down")
                        Button(role: .destructive) { task.steps.removeAll { $0.id == step.id } } label: { Image(systemName: "trash") }.help("Remove step")
                    }.buttonStyle(.borderless)
                    if !collapsedSteps.contains(step.id) {
                        Divider().overlay(Color.cadence.opacity(0.15))
                        StepFields(step: $step)
                    }
                }.padding(20).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.cadence.opacity(0.35), lineWidth: 1.5).allowsHitTesting(false))
                if index < task.steps.count - 1 { dropTarget(index + 1) { WorkflowConnector() } }
            }
            if task.steps.isEmpty { Text("Add a step to define what this task does.").foregroundStyle(.secondary).padding(.vertical, 15) }
            dropTarget(task.steps.count) { WorkflowBoundary(title: "End", symbol: "checkmark") }
            addMenu
            }
        }.padding(20).background(Color.cadence.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
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
        if collapsedSteps.contains(id) { collapsedSteps.remove(id) } else { collapsedSteps.insert(id) }
    }
    func dropTarget<Content: View>(_ insertion: Int, @ViewBuilder content: () -> Content) -> some View {
        content().frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
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
        Label(title.uppercased(), systemImage: symbol).font(.system(size: 10, weight: .semibold))
            .tracking(1.5).foregroundStyle(Color.cadence).padding(.leading, 24)
    }
}
struct WorkflowConnector: View {
    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Rectangle().fill(Color.cadence.opacity(0.5)).frame(width: 2, height: 10)
                Image(systemName: "arrow.down").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.cadence)
                Rectangle().fill(Color.cadence.opacity(0.5)).frame(width: 2, height: 10)
            }.frame(width: 34)
            Text("THEN").font(.system(size: 9, weight: .medium)).tracking(1.5).foregroundStyle(.secondary)
        }.padding(.leading, 20).accessibilityLabel("Then run the next step")
    }
}
struct StepFields: View {
    @Binding var step: TaskStep
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Picker("Step type", selection: Binding(get: { step.kind }, set: { kind in
                let id = step.id; step = TaskStep.make(kind); step.id = id
            })) {
                ForEach(StepKind.allCases) { kind in Text(kind.title).tag(kind) }
            }.frame(maxWidth: 380)
            configuration
            Divider()
            DurationField(title: durationTitle, seconds: $step.timeoutSeconds)
            Toggle("Continue to the next step if this one fails", isOn: $step.continueOnFailure).font(.caption)
            if step.kind == .question {
                Text("Cancel or timeout stops the remaining workflow, even if continue on failure is enabled.").font(.caption).foregroundStyle(.secondary)
            }
            EditorField(title: "Save output to file (optional)", text: $step.outputPath, monospaced: true)
        }
    }
    var durationTitle: String {
        switch step.kind { case .question: return "Wait for an answer"; case .response: return "Dismiss after"; default: return "Timeout" }
    }
    @ViewBuilder var configuration: some View {
        switch step.kind {
        case .shell:
            Text("Command · /bin/zsh").font(.caption).foregroundStyle(.secondary)
            CodeField(text: $step.body, label: "Inline shell command")
            Text("Use quoted variables, such as ./report.sh --date \"$TASK_SCHEDULED_DATE\". Shell commands are executed literally.").font(.caption).foregroundStyle(.secondary)
        case .script:
            HStack(alignment: .bottom) {
                EditorField(title: "Script file or executable", text: $step.scriptPath, monospaced: true)
                Button("Choose File…") { chooseFile(script: true) }.fixedSize()
            }
            HStack(alignment: .bottom) {
                EditorField(title: "Interpreter (optional; leave empty to execute the file directly)", text: $step.executable, monospaced: true)
                Button("Choose…") { chooseFile(script: false) }.fixedSize()
            }
            Text("For shell scripts use /bin/zsh. For Python select your uv environment’s .venv/bin/python.").font(.caption).foregroundStyle(.secondary)
            Text("Arguments · one per line, without shell quoting").font(.caption).foregroundStyle(.secondary)
            CodeField(text: $step.arguments, height: 85, label: "Script arguments")
            Text("The script path is passed automatically. Arguments support {{scheduled_date}}, {{input}}, and the other variables below.").font(.caption).foregroundStyle(.secondary)
        case .codex:
            HStack(alignment: .bottom) {
                EditorField(title: "Codex executable", text: $step.executable, monospaced: true)
                Button("Choose…") { chooseFile(script: false) }.fixedSize()
            }
            EditorField(title: "Model (optional)", text: $step.model)
            Picker("Sandbox", selection: $step.sandbox) { Text("Read only").tag("read-only"); Text("Workspace write").tag("workspace-write") }.frame(maxWidth: 380)
            Text("Prompt").font(.caption).foregroundStyle(.secondary)
            CodeField(text: $step.body, label: "Codex prompt")
            Text("Uses your CLI login. Workspace write permits file changes in the working directory. Background runs cannot ask for command approvals.").font(.caption).foregroundStyle(.secondary)
        case .localLLM:
            EditorField(title: "Chat completions URL", text: $step.endpoint, monospaced: true)
            EditorField(title: "Model", text: $step.model)
            Text("Prompt").font(.caption).foregroundStyle(.secondary)
            CodeField(text: $step.body, label: "Local LLM prompt")
            Text("Uses an OpenAI-compatible server, such as Ollama or LM Studio. Optional authentication: CADENCE_LLM_API_KEY in the task environment.").font(.caption).foregroundStyle(.secondary)
        case .question:
            Text("Question").font(.caption).foregroundStyle(.secondary)
            CodeField(text: $step.body, height: 85, label: "Question text")
            Text("The answer becomes {{input}} and {{previous_output}} for later steps, or $TASK_INPUT and $TASK_PREVIOUS_OUTPUT in shell commands. Questions can include output from earlier steps.").font(.caption).foregroundStyle(.secondary)
        case .response:
            Text("Message").font(.caption).foregroundStyle(.secondary)
            CodeField(text: $step.body, height: 85, label: "Response message")
            Text("Use {{previous_output}} to show the preceding result, or write a message with variables. Showing a response preserves the previous output for the next step. Displays up to 6,000 characters.").font(.caption).foregroundStyle(.secondary)
        }
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
