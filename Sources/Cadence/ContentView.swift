import SwiftUI
import AppKit
import CadenceCore

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var search = ""
    @State private var filter = "All tasks"
    var filtered: [ScheduledTask] {
        model.tasks.filter { task in
            (search.isEmpty || task.name.localizedCaseInsensitiveContains(search) || task.notes.localizedCaseInsensitiveContains(search)) &&
            (filter == "All tasks" || (filter == "Enabled" ? task.enabled : !task.enabled))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 26, weight: .medium)).foregroundStyle(Color.cadence)
                    VStack(alignment: .leading, spacing: 3) { Text("Cadence").font(.headline); Text("LOCAL AUTOMATION").font(.system(size: 9, weight: .semibold, design: .rounded)).tracking(1.6).foregroundStyle(.secondary) }
                }.padding(.horizontal, 18).padding(.vertical, 22)
                Button { model.selection = nil } label: {
                    HStack { Label("Overview", systemImage: "square.grid.2x2"); Spacer(); Text("\(model.tasks.count)").foregroundStyle(.secondary) }.padding(10)
                }.buttonStyle(.plain).background(model.selection == nil ? Color.cadence.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 12)
                HStack { Text("TASKS").font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary); Spacer(); Menu { ForEach(["All tasks", "Enabled", "Paused"], id: \.self) { value in Button(value) { filter = value } } } label: { Image(systemName: "line.3.horizontal.decrease") }.menuStyle(.borderlessButton).fixedSize() }.padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 10)
                TextField("Find a task", text: $search).textFieldStyle(.roundedBorder).padding(.horizontal, 14).padding(.bottom, 8)
                List(selection: $model.selection) {
                    ForEach(filtered) { task in
                        HStack(spacing: 10) {
                            Image(systemName: task.steps.first?.kind.symbol ?? "terminal").foregroundStyle(task.enabled ? Color.cadence : .secondary).frame(width: 22)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text(task.schedule.summary).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Circle().fill(model.isRunning(task) ? .orange : (task.enabled ? Color.cadence : Color.secondary.opacity(0.35))).frame(width: 6, height: 6)
                        }.padding(.vertical, 6).tag(task.id)
                            .contextMenu { Button("Open Task") { model.selection = task.id }; Button("Run Now") { model.runNow(task) }; Button("Duplicate…") { model.duplicate(task) } }
                    }
                }.listStyle(.sidebar)
                Divider().padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 7) {
                    Label("Powered by launchd", systemImage: "desktopcomputer").font(.caption).foregroundStyle(.secondary)
                    Text("Runs locally, even with this window closed.").font(.system(size: 10)).foregroundStyle(.tertiary)
                }.padding(20)
            }.navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 320)
        } detail: {
            if let task = model.tasks.first(where: { $0.id == model.selection }) { TaskDetailView(task: task).id(task.id) }
            else { DashboardView() }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { model.create() } label: { Label("New Task", systemImage: "plus") }.help("New Task (⌘N)") }
        }
        .alert("Cadence", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
    }
}

struct CadenceCard<Content: View>: View {
    var title: String
    var symbol: String
    @State private var expanded = true
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { expanded.toggle() } label: {
                HStack {
                    Label(title.uppercased(), systemImage: symbol).font(.system(size: 10, weight: .semibold)).tracking(1.2)
                    Spacer()
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 11, weight: .semibold))
                }.foregroundStyle(.secondary).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel((expanded ? "Collapse " : "Expand ") + title)
            if expanded { content }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.055)).allowsHitTesting(false))
    }
}
struct StatusBadge: View {
    let title: String
    let color: Color
    var body: some View { Text(title).font(.system(size: 10, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 5).background(color.opacity(0.1), in: Capsule()).foregroundStyle(color) }
}
struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    var upcoming: [(ScheduledTask, Date)] { model.tasks.filter(\.enabled).compactMap { task in model.nextDue(task).map { (task, $0) } }.sorted { $0.1 < $1.1 } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased()).font(.system(size: 10, weight: .medium)).tracking(1.5).foregroundStyle(.secondary)
                        Text("Your Mac, on schedule.").font(.system(size: 32, weight: .semibold, design: .rounded))
                        Text("Scripts, workflows, and AI. In their own time.").font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "clock.badge.checkmark").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(Color.cadence).padding(.trailing, 10)
                }.padding(.top, 12)
                HStack(spacing: 14) {
                    metric("Enabled", value: model.tasks.filter(\.enabled).count, symbol: "calendar", color: .cadence)
                    metric("Running", value: model.tasks.filter { model.isRunning($0) }.count, symbol: "play.circle", color: .orange)
                    metric("Completed today", value: model.runs.filter { $0.status == .succeeded && Calendar.current.isDateInToday($0.startedAt) }.count, symbol: "checkmark.circle", color: .cadence)
                }
                if model.tasks.isEmpty {
                    VStack(spacing: 16) {
                        ZStack { Circle().fill(Color.cadence.opacity(0.08)).frame(width: 88, height: 88); Image(systemName: "calendar.badge.plus").font(.system(size: 35, weight: .light)).foregroundStyle(Color.cadence) }
                        Text("A little less to remember.").font(.system(size: 23, weight: .medium, design: .rounded))
                        Text("Set up a task once. Choose when it runs, what it does,\nand how it catches up when your Mac is away.").multilineTextAlignment(.center).foregroundStyle(.secondary).lineSpacing(4)
                        Button("Create your first task") { model.create() }.buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 4)
                    }.frame(maxWidth: .infinity).padding(.vertical, 40).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                } else {
                    CadenceCard(title: "Coming up", symbol: "calendar") {
                        if upcoming.isEmpty { Text("No enabled schedules. Enable a task to put it on the calendar.").foregroundStyle(.secondary) }
                        ForEach(upcoming.prefix(6), id: \.0.id) { task, date in
                            Button { model.selection = task.id } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: task.steps.first?.kind.symbol ?? "terminal").foregroundStyle(Color.cadence).frame(width: 30)
                                    VStack(alignment: .leading, spacing: 5) { Text(task.name).fontWeight(.medium); Text(task.schedule.summary).font(.caption).foregroundStyle(.secondary) }
                                    Spacer(); Text(date, style: .relative).font(.caption).foregroundStyle(.secondary); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }.padding(.vertical, 6)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 13) {
                    Text("START WITH A STEP").font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) { ForEach(StepKind.allCases) { kind in
                        Button { model.create(kind) } label: {
                            VStack(alignment: .leading, spacing: 12) { Image(systemName: kind.symbol).font(.system(size: 20, weight: .light)).foregroundStyle(Color.cadence); Text(kind.title).font(.system(size: 12, weight: .medium)); Text(templateDescription(kind)).font(.system(size: 10)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, minHeight: 82, alignment: .leading).padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    } }
                }
                HStack { Image(systemName: "moon.zzz"); Text("Missed a window? Each task decides whether to skip, catch up once, or replay its backlog.") }.font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(32).frame(maxWidth: 1100)
        }.navigationTitle("Overview").background(Color.canvas)
    }
    func metric(_ title: String, value: Int, symbol: String, color: Color) -> some View {
        HStack { VStack(alignment: .leading, spacing: 7) { Text("\(value)").font(.system(size: 29, weight: .medium, design: .rounded)); Text(title).font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer(); Image(systemName: symbol).font(.system(size: 23, weight: .light)).foregroundStyle(color) }.padding(20).frame(maxWidth: .infinity).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13))
    }
    func templateDescription(_ kind: StepKind) -> String {
        switch kind { case .shell: return "A command or snippet"; case .script: return "Your existing scripts"; case .codex: return "An agent in your workspace"; case .localLLM: return "Ollama, LM Studio & more"; case .question: return "Ask for input along the way"; case .response: return "Display a result or message" }
    }
}

struct TaskDetailView: View {
    @EnvironmentObject var model: AppModel
    let task: ScheduledTask
    @State private var draft: ScheduledTask
    @State private var selectedRun: RunRecord?
    @State private var confirmDelete = false
    @State private var showAllRuns = false
    @State private var missedRunsExpanded = true
    init(task: ScheduledTask) { self.task = task; _draft = State(initialValue: task) }
    var dirty: Bool { draft != task }
    var taskRuns: [RunRecord] { model.runs.filter { $0.taskID == task.id } }
    var previews: [Date] {
        var dates: [Date] = [], cursor = Date()
        for _ in 0..<3 { guard let next = draft.schedule.next(after: cursor) else { break }; dates.append(next); cursor = next }
        return dates
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if task.enabled && !model.agentIDs.contains(task.id) {
                    HStack { Label("Schedule is not registered with launchd.", systemImage: "exclamationmark.triangle"); Spacer(); Button("Repair") { model.repair(task) } }
                        .font(.caption).padding(12).background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                Group {
                    CadenceCard(title: "Schedule", symbol: "calendar") {
                        ScheduleConfiguration(task: $draft, missedRunsExpanded: $missedRunsExpanded)
                    }
                    CadenceCard(title: "Next occurrences", symbol: "clock") {
                        if previews.isEmpty { Text("No future occurrences for this schedule.").font(.caption).foregroundStyle(.secondary) }
                        ForEach(previews, id: \.self) { date in Text(draft.schedule.formatted(date)).font(.caption.monospaced()) }
                        if !draft.enabled { Text("Schedule preview · task is paused").font(.caption).foregroundStyle(.secondary) }
                    }
                    WorkflowEditor(task: $draft)
                    CadenceCard(title: "Working directory", symbol: "folder") { WorkingDirectoryFields(task: $draft) }
                    CadenceCard(title: "Environment", symbol: "terminal") { EnvironmentFields(task: $draft) }
                }.disabled(model.isRunning(task))
                CadenceCard(title: "Available variables", symbol: "curlybraces") {
                    Text("{{date}}  {{timestamp}}  {{unix}}\n{{scheduled_date}}  {{scheduled_timestamp}}\n{{input}}  {{previous_output}}  {{previous_output_file}}")
                        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    Text("Use placeholders in script arguments, prompts, messages, and output paths. Inline commands use quoted $TASK_DATE, $TASK_SCHEDULED_DATE, $TASK_INPUT, $TASK_PREVIOUS_OUTPUT and the corresponding TASK_ variables. For large output, read $TASK_PREVIOUS_OUTPUT_FILE.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                CadenceCard(title: "Run history (\(taskRuns.count))", symbol: "clock.arrow.circlepath") {
                    if taskRuns.isEmpty { Text("No runs yet. Save this task, then run it now or enable its schedule.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(Array(taskRuns.prefix(showAllRuns ? 250 : 5))) { run in runRow(run) }
                    if taskRuns.count > 5 { Button(showAllRuns ? "Show recent runs" : "Show more history") { showAllRuns.toggle() } }
                }
            }.padding(28).frame(maxWidth: 1100)
        }.navigationTitle(task.name).background(Color.canvas)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Text(dirty ? "Unsaved changes" : "All changes saved").font(.caption).foregroundStyle(dirty ? Color.orange : .secondary)
                    Spacer()
                    Button("Revert") { draft = task }.disabled(!dirty)
                    Button("Save Changes") { save() }.buttonStyle(.borderedProminent).keyboardShortcut("s")
                        .disabled(!dirty || model.isRunning(task))
                }.padding(.horizontal, 28).padding(.vertical, 14).background(.bar)
            }
            .onAppear { draft = model.drafts[task.id] ?? task }
            .onChange(of: draft) { _, value in model.drafts[task.id] = value == task ? nil : value }
            .onChange(of: task) { old, new in if draft == old { draft = new } }
            .sheet(item: $selectedRun) { run in RunLogView(run: run).environmentObject(model) }
            .confirmationDialog("Delete \(task.name)?", isPresented: $confirmDelete) {
                Button("Delete Task", role: .destructive) { model.remove(task) }
            } message: { Text("Its launchd schedule will be removed. Existing run history and output files will be retained.") }
    }
    var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                StatusBadge(title: model.isRunning(task) ? "Running" : (task.enabled ? "Enabled" : "Paused"),
                            color: model.isRunning(task) ? .orange : (task.enabled ? .cadence : .secondary))
                Text("\(draft.steps.count) steps").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("Enable schedule", isOn: $draft.enabled).toggleStyle(.switch).fixedSize().disabled(model.isRunning(task))
            }
            VStack(alignment: .leading, spacing: 8) {
                Label("Task name", systemImage: "pencil").font(.caption).foregroundStyle(.secondary)
                TextField("Name this task", text: $draft.name)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .textFieldStyle(.plain).padding(12)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.18)).allowsHitTesting(false))
                    .accessibilityLabel("Task name")
            }.disabled(model.isRunning(task))
            VStack(alignment: .leading, spacing: 8) {
                Label("Description", systemImage: "text.alignleft").font(.caption).foregroundStyle(.secondary)
                TextField("Describe what this task does…", text: $draft.notes, axis: .vertical)
                    .lineLimit(2...5).font(.system(size: 13)).textFieldStyle(.plain).padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.18)).allowsHitTesting(false))
                    .accessibilityLabel("Task description")
            }.disabled(model.isRunning(task))
            HStack {
                Button { model.runNow(task) } label: { Label("Run Now", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).disabled(dirty || model.isRunning(task)).help(dirty ? "Save changes before running" : "Run this task now")
                if model.isRunning(task) { Button("Stop", role: .destructive) { model.cancel(task) } }
                Text("Edit any field below, then save.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Duplicate") { model.duplicate(task) }.disabled(dirty)
                    Button("Repair Schedule") { model.repair(task) }
                    Button("Show LaunchAgent") { NSWorkspace.shared.selectFile(LaunchAgent.url(task.id).path, inFileViewerRootedAtPath: "") }
                    Divider()
                    Button("Delete Task…", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis") }.fixedSize()
            }
        }.padding(.top, 12)
    }
    func save() {
        do {
            try model.save(draft)
            draft = model.tasks.first(where: { $0.id == task.id }) ?? draft
            model.drafts.removeValue(forKey: task.id)
        } catch { model.error = error.localizedDescription }
    }
    func runRow(_ run: RunRecord) -> some View {
        Button { selectedRun = run } label: {
            HStack(spacing: 14) {
                Image(systemName: statusSymbol(run.status)).foregroundStyle(statusColor(run.status)).frame(width: 24)
                VStack(alignment: .leading, spacing: 5) {
                    Text(run.startedAt.formatted(date: .abbreviated, time: .standard)).font(.system(size: 12, weight: .medium))
                    Text(run.message.isEmpty ? "Running…" : run.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if run.manual { Text("Manual").font(.caption).foregroundStyle(.secondary) }
                StatusBadge(title: run.status.rawValue.capitalized, color: statusColor(run.status))
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }.padding(.vertical, 5)
        }.buttonStyle(.plain)
    }
}
func statusColor(_ status: RunStatus) -> Color {
    switch status { case .succeeded: return .cadence; case .running: return .orange; case .failed, .interrupted: return .red; case .cancelled, .skipped: return .secondary }
}
func statusSymbol(_ status: RunStatus) -> String {
    switch status { case .succeeded: return "checkmark.circle"; case .running: return "arrow.trianglehead.2.clockwise.rotate.90"; case .failed, .interrupted: return "exclamationmark.circle"; case .cancelled: return "xmark.circle"; case .skipped: return "forward.end.circle" }
}
struct RunLogView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let run: RunRecord
    var current: RunRecord { model.runs.first(where: { $0.id == run.id }) ?? run }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(run.taskName).font(.title2.bold()); Spacer(); StatusBadge(title: current.status.rawValue.capitalized, color: statusColor(current.status)); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Scheduled: \(run.scheduledAt.formatted(date: .abbreviated, time: .standard))  ·  Started: \(run.startedAt.formatted(date: .abbreviated, time: .standard))").font(.caption).foregroundStyle(.secondary)
            Text(current.message).font(.callout).textSelection(.enabled)
            ScrollView([.horizontal, .vertical]) { Text(model.store.log(run.id)).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(16) }.background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            HStack { Text("Full stdout and stderr are saved separately for each step.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Open Run Folder") { NSWorkspace.shared.open(model.store.runDirectory(run.id)) } }
        }.padding(24).frame(width: 850, height: 600)
    }
}
