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
                    VStack(alignment: .leading, spacing: 3) { Text("Cadence").font(.headline); Text("ON THIS MAC").font(.system(size: 9, weight: .semibold, design: .rounded)).tracking(1.6).foregroundStyle(.secondary) }
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
                VStack(spacing: 8) {
                    Button { model.create() } label: {
                        Label("New Task", systemImage: "plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .help("New Task (⌘N)")
                    Button { model.importTasks() } label: {
                        Label("Import Config…", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .help("Create paused tasks from JSON config files. You can also drop files onto the sidebar.")
                }
                .controlSize(.large)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                Divider().padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 7) {
                    Label("Powered by launchd", systemImage: "desktopcomputer").font(.caption).foregroundStyle(.secondary)
                    Text("Runs locally, even with this window closed.").font(.system(size: 10)).foregroundStyle(.tertiary)
                }.padding(20)
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard !urls.isEmpty, urls.allSatisfy(\.isFileURL) else { return false }
                model.importTasks(from: urls)
                return true
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 280)
        } detail: {
            VStack(spacing: 0) {
            if !model.configIssues.isEmpty || !model.registrationIssues.isEmpty { ConfigHealthBanner() }
            if let task = model.tasks.first(where: { $0.id == model.selection }) { TaskDetailView(task: task).id(task.id) }
            else { DashboardView() }
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.importTasks() } label: { Label("Import Config…", systemImage: "square.and.arrow.down") }
                    .help("Import JSON config files as new paused tasks")
            }
            ToolbarItem(placement: .primaryAction) { Button { model.create() } label: { Label("New Task", systemImage: "plus") }.buttonStyle(.borderedProminent).help("New Task (⌘N)") }
        }
        .alert("Cadence", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
    }
}

struct CadenceCard<Content: View>: View {
    var title: String
    var symbol: String
    var summary: String?
    @AppStorage private var expanded: Bool
    var content: Content
    init(title: String, symbol: String, storageKey: String? = nil, summary: String? = nil,
         initiallyExpanded: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title; self.symbol = symbol; self.summary = summary; self.content = content()
        _expanded = AppStorage(wrappedValue: initiallyExpanded, "cadence.section.\(storageKey ?? title)")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 9) {
                    Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Color.cadence).frame(width: 18)
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 8)
                    if !expanded, let summary { Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }.contentShape(Rectangle()).padding(.vertical, 2)
            }.buttonStyle(.plain).accessibilityLabel((expanded ? "Collapse " : "Expand ") + title)
            if expanded { content }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.09)).allowsHitTesting(false))
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
                        Text("Your task workspace").font(.system(size: 32, weight: .semibold, design: .rounded))
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
                        Button("Create your first task") { model.create() }.buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 4)
                        Button("Import Config…") { model.importTasks() }.buttonStyle(.bordered).controlSize(.large)
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
                            VStack(alignment: .leading, spacing: 12) { Image(systemName: kind.symbol).font(.system(size: 20, weight: .light)).foregroundStyle(Color.cadence); Text(kind.title).font(.system(size: 12, weight: .medium)) }.frame(maxWidth: .infinity, minHeight: 82, alignment: .leading).padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    } }
                }
            }.padding(28).frame(maxWidth: 1760).frame(maxWidth: .infinity)
        }.navigationTitle("Overview").background(Color.canvas)
    }
    func metric(_ title: String, value: Int, symbol: String, color: Color) -> some View {
        HStack { VStack(alignment: .leading, spacing: 7) { Text("\(value)").font(.system(size: 29, weight: .medium, design: .rounded)); Text(title).font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer(); Image(systemName: symbol).font(.system(size: 23, weight: .light)).foregroundStyle(color) }.padding(20).frame(maxWidth: .infinity).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13))
    }
}

struct TaskDetailView: View {
    @EnvironmentObject var model: AppModel
    let task: ScheduledTask
    @State private var draft: ScheduledTask
    @State private var baseTask: ScheduledTask
    @State private var selectedRun: RunRecord?
    @State private var confirmDelete = false
    @State private var showAllRuns = false
    @State private var missedRunsExpanded = true

    init(task: ScheduledTask) {
        self.task = task
        _draft = State(initialValue: task); _baseTask = State(initialValue: task)
    }
    var dirty: Bool { draft != task }
    var conflict: Bool { dirty && baseTask != task }
    var running: Bool { model.isRunning(task) }
    var taskRuns: [RunRecord] { model.runs.filter { $0.taskID == task.id } }
    var nextOccurrence: Date? { dirty ? draft.schedule.next(after: Date()) : model.nextDue(task) }
    var previews: [Date] {
        var dates: [Date] = [], cursor = Date()
        for _ in 0..<3 { guard let next = draft.schedule.next(after: cursor) else { break }; dates.append(next); cursor = next }
        return dates
    }
    func sectionKey(_ key: String) -> String { "\(task.id.uuidString).\(key)" }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 1120
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if conflict { conflictBanner }
                    if task.enabled && !model.agentIDs.contains(task.id) { registrationBanner }
                    CadenceCard(title: "Schedule", symbol: "calendar", storageKey: sectionKey("schedule"), summary: draft.schedule.summary) {
                        ScheduleConfiguration(task: $draft, missedRunsExpanded: $missedRunsExpanded).disabled(running)
                    }
                    if wide {
                        HStack(alignment: .top, spacing: 24) {
                            primaryColumn.frame(maxWidth: .infinity, alignment: .topLeading)
                            contextColumn.frame(width: 320, alignment: .topLeading)
                        }
                    } else {
                        primaryColumn
                        contextColumn
                    }
                }
                .padding(wide ? 32 : 24)
                .frame(maxWidth: 1760)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
        }
        .navigationTitle(task.name).background(Color.canvas)
        .onAppear { baseTask = model.draftBases[task.id] ?? task; draft = model.drafts[task.id] ?? task }
        .onChange(of: draft) { _, value in
            model.drafts[task.id] = value == task ? nil : value
            model.draftBases[task.id] = value == task ? nil : baseTask
            if value == task { baseTask = task }
        }
        .onChange(of: task) { old, new in if draft == old { baseTask = new; draft = new } }
        .sheet(item: $selectedRun) { run in RunLogView(run: run).environmentObject(model) }
        .confirmationDialog("Delete \(task.name)?", isPresented: $confirmDelete) {
            Button("Delete Task", role: .destructive) { model.remove(task) }
        } message: { Text("Its config and launchd schedule will be removed. Run history and output files will be retained.") }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 18) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 25, weight: .medium)).foregroundStyle(Color.cadence)
                    .frame(width: 52, height: 52).background(Color.cadence.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 22)
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Task name").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        TextField("Name this task", text: $draft.name)
                            .font(.system(size: 22, weight: .semibold)).textFieldStyle(.roundedBorder)
                            .controlSize(.large).accessibilityLabel("Task name")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        TextField("Describe what this task does…", text: $draft.notes, axis: .vertical)
                            .lineLimit(2...4).font(.system(size: 13)).textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Task description")
                    }
                }.disabled(running)
            }
            HStack(spacing: 14) {
                Button { model.runNow(task) } label: { Label("Run Now", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(dirty || running)
                    .help(dirty ? "Save changes before running" : "Run this task now")
                if running { Button("Stop", role: .destructive) { model.cancel(task) } }
                StatusBadge(title: running ? "Running" : (task.enabled ? "Enabled" : "Paused"),
                            color: running ? .orange : (task.enabled ? .cadence : .secondary))
                Text("\(draft.steps.count) steps").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Toggle("Enable schedule", isOn: $draft.enabled).toggleStyle(.switch).fixedSize().disabled(running)
                Menu {
                    if let url = model.configFiles[task.id] { Button("Edit Config File…") { model.editConfig(url) } }
                    Button("Export Config…") { model.exportTasks() }.disabled(dirty)
                    Button("Duplicate") { model.duplicate(task) }.disabled(dirty)
                    Button("Repair Schedule") { model.repair(task) }
                    Button("Show LaunchAgent") { NSWorkspace.shared.selectFile(LaunchAgent.url(task.id).path, inFileViewerRootedAtPath: "") }
                    Divider()
                    Button("Delete Task…", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis").frame(width: 20, height: 20) }.fixedSize().help("Task actions")
            }
        }
    }

    var primaryColumn: some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkflowEditor(task: $draft).disabled(running)
            CadenceCard(title: "Run history", symbol: "clock.arrow.circlepath", storageKey: sectionKey("history"), summary: "\(taskRuns.count) runs") {
                if taskRuns.isEmpty {
                    Label("No runs yet. Enable its schedule or run this task now.", systemImage: "clock")
                        .font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
                }
                ForEach(Array(taskRuns.prefix(showAllRuns ? 250 : 5))) { run in
                    runRow(run)
                    if run.id != taskRuns.prefix(showAllRuns ? 250 : 5).last?.id { Divider() }
                }
                if taskRuns.count > 5 { Button(showAllRuns ? "Show recent runs" : "Show more history") { showAllRuns.toggle() } }
            }
        }
    }
    var contextColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            CadenceCard(title: "Next occurrence", symbol: "clock", storageKey: sectionKey("next")) {
                if let next = nextOccurrence {
                    Text(draft.schedule.formatted(next)).font(.system(size: 15, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                    if !draft.enabled { StatusBadge(title: "Preview · paused", color: .secondary) }
                    else if next < Date() { StatusBadge(title: "Catch-up pending", color: .orange) }
                    else { Text(next, style: .relative).font(.caption).foregroundStyle(.secondary) }
                    Divider()
                    ForEach(Array(previews.dropFirst()), id: \.self) { date in
                        Text(draft.schedule.formatted(date)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                } else { Text("No future occurrences").font(.callout).foregroundStyle(.secondary) }
            }
            CadenceCard(title: "Working directory", symbol: "folder", storageKey: sectionKey("directory")) {
                WorkingDirectoryFields(task: $draft).disabled(running)
            }
            CadenceCard(title: "Environment", symbol: "terminal", storageKey: sectionKey("environment"), initiallyExpanded: false) {
                EnvironmentFields(task: $draft).disabled(running)
            }
            if let url = model.configFiles[task.id] { configCard(url) }
            CadenceCard(title: "Available variables", symbol: "curlybraces", storageKey: sectionKey("variables"), initiallyExpanded: false) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(["date", "timestamp", "unix", "scheduled_date", "scheduled_timestamp", "input", "previous_output", "previous_output_file"], id: \.self) { name in
                        Text("{{\(name)}}").font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled).padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
                Text("Use variables in arguments, prompts, alerts, and output paths. Inline commands use quoted TASK_ environment variables.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    func configCard(_ url: URL) -> some View {
        CadenceCard(title: "Config file", symbol: "doc.text", storageKey: sectionKey("config")) {
            Label("JSON · version 1", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
            Text(url.lastPathComponent).font(.system(size: 11, design: .monospaced))
                .lineLimit(1).truncationMode(.middle).help(url.path).textSelection(.enabled)
            HStack {
                Button { model.editConfig(url) } label: { Label("Edit File…", systemImage: "square.and.pencil") }
                Spacer()
                Menu {
                    Button("Show in Finder") { NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "") }
                    Button("Export Config…") { model.exportTasks() }.disabled(dirty)
                } label: { Image(systemName: "ellipsis") }.fixedSize().help("Config file actions")
            }
        }
    }
    var saveBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                Label(dirty ? "Unsaved changes" : "Saved to config file", systemImage: dirty ? "circle.fill" : "checkmark.circle")
                    .font(.caption).foregroundStyle(dirty ? Color.orange : .secondary)
                Spacer()
                Button("Revert") { reloadFromDisk() }.disabled(!dirty)
                Button("Save Changes") { save() }.buttonStyle(.borderedProminent).keyboardShortcut("s")
                    .disabled(!dirty || running || conflict)
            }.padding(.horizontal, 24).padding(.vertical, 12)
                .frame(maxWidth: 1760).frame(maxWidth: .infinity)
        }.background(.bar)
    }
    var conflictBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("The config changed on disk. Reload it before saving this draft.").font(.callout)
            Spacer()
            Button("Reload from file") { reloadFromDisk() }
        }.padding(14).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
    var registrationBanner: some View {
        HStack {
            Label("Schedule is not registered with launchd.", systemImage: "exclamationmark.triangle")
            Spacer(); Button("Repair") { model.repair(task) }
        }.font(.caption).padding(12).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
    func save() {
        do {
            try model.save(draft, expecting: baseTask)
            draft = model.tasks.first(where: { $0.id == task.id }) ?? draft; baseTask = draft
            model.drafts.removeValue(forKey: task.id); model.draftBases.removeValue(forKey: task.id)
        } catch { model.error = error.localizedDescription }
    }
    func reloadFromDisk() {
        baseTask = task; draft = task
        model.drafts.removeValue(forKey: task.id); model.draftBases.removeValue(forKey: task.id)
    }
    func runRow(_ run: RunRecord) -> some View {
        Button { selectedRun = run } label: {
            HStack(spacing: 12) {
                Image(systemName: statusSymbol(run.status)).font(.system(size: 18)).foregroundStyle(statusColor(run.status)).frame(width: 24)
                VStack(alignment: .leading, spacing: 5) {
                    Text(run.startedAt.formatted(date: .abbreviated, time: .standard)).font(.system(size: 12, weight: .medium))
                    Text(run.message.isEmpty ? "Running…" : run.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 10)
                if run.manual { Text("Manual").font(.caption).foregroundStyle(.secondary) }
                StatusBadge(title: run.status.rawValue.capitalized, color: statusColor(run.status))
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }.padding(.vertical, 6).contentShape(Rectangle())
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
