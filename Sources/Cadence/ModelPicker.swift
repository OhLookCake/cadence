import SwiftUI
import AppKit

struct EditorComboField: View {
    let title: String
    @Binding var text: String
    let choices: [String]
    var placeholder = ""
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.cadenceFieldLabel).foregroundStyle(.secondary)
            EditableComboBox(text: $text, choices: choices, placeholder: placeholder,
                             title: title, monospaced: monospaced)
                .frame(height: 28)
        }
    }
}

/// A native combo box keeps the dropdown, keyboard navigation, and custom input in one control.
struct EditableComboBox: NSViewRepresentable {
    @Binding var text: String
    let choices: [String]
    var placeholder = ""
    let title: String
    var monospaced = false
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSComboBox {
        let combo = NSComboBox()
        combo.isEditable = true
        combo.completes = false
        combo.hasVerticalScroller = true
        combo.numberOfVisibleItems = 8
        combo.delegate = context.coordinator
        combo.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return combo
    }
    func updateNSView(_ combo: NSComboBox, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updating = true
        defer { context.coordinator.updating = false }
        if combo.objectValues as? [String] != choices {
            combo.removeAllItems()
            combo.addItems(withObjectValues: choices)
        }
        if combo.stringValue != text { combo.stringValue = text }
        combo.placeholderString = placeholder
        combo.font = monospaced ? .monospacedSystemFont(ofSize: 14, weight: .regular) : .systemFont(ofSize: 15)
        combo.isEnabled = isEnabled
        combo.setAccessibilityLabel(title)
    }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: EditableComboBox
        var updating = false
        init(_ parent: EditableComboBox) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard !updating, let combo = notification.object as? NSComboBox else { return }
            parent.text = combo.stringValue
        }
        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard !updating, let combo = notification.object as? NSComboBox,
                  parent.choices.indices.contains(combo.indexOfSelectedItem) else { return }
            let value = parent.choices[combo.indexOfSelectedItem]
            combo.stringValue = value
            parent.text = value
        }
    }
}

enum ModelChoices {
    static func codex() -> [String] {
        struct Cache: Decodable {
            struct Model: Decodable { let slug: String; let visibility: String? }
            let models: [Model]
        }
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        guard let data = try? Data(contentsOf: home.appendingPathComponent("models_cache.json")),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return [] }
        var seen = Set<String>()
        return cache.models.filter { $0.visibility != "hide" && !$0.slug.isEmpty && seen.insert($0.slug).inserted }.map(\.slug)
    }

    static func apiKey(in environment: String) -> String {
        var key = ProcessInfo.processInfo.environment["CADENCE_LLM_API_KEY"] ?? ""
        for line in environment.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 && parts[0] == "CADENCE_LLM_API_KEY" { key = String(parts[1]) }
        }
        return key
    }

    static func local(endpoint: String, apiKey: String) async throws -> [String] {
        struct Response: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        guard var url = URLComponents(string: endpoint), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil,
              url.path.hasSuffix("/chat/completions") else { throw URLError(.badURL) }
        url.path = String(url.path.dropLast("/chat/completions".count)) + "/models"
        url.fragment = nil
        guard let modelsURL = url.url else { throw URLError(.badURL) }
        var request = URLRequest(url: modelsURL, timeoutInterval: 5)
        if !apiKey.isEmpty { request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization") }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return Array(Set(try JSONDecoder().decode(Response.self, from: data).data.map(\.id).filter { !$0.isEmpty })).sorted()
    }
}

struct LocalModelConnectionFields: View {
    @Binding var model: String
    @Binding var endpoint: String
    var apiKey = ""
    @State private var models: [String] = []
    @State private var loading = false
    @State private var unavailable = false
    @State private var refresh = 0
    private struct Request: Equatable { let endpoint: String; let apiKey: String; let refresh: Int }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 10) {
                EditorComboField(title: "Model", text: $model, choices: models, placeholder: "Choose or enter a model")
                    .frame(maxWidth: 280, alignment: .leading)
                Button { refresh += 1 } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh available models").accessibilityLabel("Refresh available models")
                    .disabled(loading)
                if loading { ProgressView().controlSize(.small).padding(.bottom, 3) }
            }
            EditorComboField(title: "Chat completions URL", text: $endpoint,
                             choices: ["http://localhost:11434/v1/chat/completions", "http://localhost:1234/v1/chat/completions"],
                             monospaced: true)
                .frame(maxWidth: 560, alignment: .leading)
            if unavailable {
                Text("No models available from this server. Enter a model name or check the connection.")
                    .font(.cadenceCaption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: Request(endpoint: endpoint, apiKey: apiKey, refresh: refresh)) {
            models = []; unavailable = false; loading = true
            do {
                try await Task.sleep(for: .milliseconds(300))
                let choices = try await ModelChoices.local(endpoint: endpoint, apiKey: apiKey)
                try Task.checkCancellation()
                models = choices; unavailable = choices.isEmpty; loading = false
            } catch {
                guard !Task.isCancelled else { return }
                unavailable = true; loading = false
            }
        }
    }
}
