import SwiftUI

struct TimeZonePicker: View {
    @Binding var selection: String
    @State private var presented = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Time zone").font(.caption).foregroundStyle(.secondary)
            Button { presented = true } label: {
                HStack {
                    Text(selection.replacingOccurrences(of: "_", with: " ")).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }.frame(maxWidth: .infinity).contentShape(Rectangle())
            }.buttonStyle(.bordered).accessibilityLabel("Choose time zone")
                .popover(isPresented: $presented, arrowEdge: .bottom) {
                    TimeZoneSearch(selection: $selection) { presented = false }
                }
        }
    }
}

private struct TimeZoneSearch: View {
    @Binding var selection: String
    let close: () -> Void
    @State private var query = ""
    @State private var highlighted: String?
    @FocusState private var searchFocused: Bool
    private static let identifiers = Array(Set(TimeZone.knownTimeZoneIdentifiers + ["UTC", TimeZone.current.identifier])).sorted()
    var matches: [String] {
        let words = query.replacingOccurrences(of: "_", with: " ").split(whereSeparator: \.isWhitespace).map(String.init)
        return Self.identifiers.filter { identifier in
            let label = identifier.replacingOccurrences(of: "_", with: " ")
            return words.allSatisfy { label.localizedCaseInsensitiveContains($0) }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a time zone").font(.headline)
            TextField("Filter by city or region", text: $query).textFieldStyle(.roundedBorder)
                .focused($searchFocused).accessibilityLabel("Filter time zones")
                .onSubmit { chooseHighlighted() }
                .onKeyPress(.downArrow) { advance(1); return .handled }
                .onKeyPress(.upArrow) { advance(-1); return .handled }
            if matches.isEmpty {
                Text("No matching time zones").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 260)
            } else {
                ScrollViewReader { proxy in
                    List(selection: $highlighted) {
                        ForEach(matches, id: \.self) { identifier in
                            HStack {
                                Text(identifier.replacingOccurrences(of: "_", with: " "))
                                Spacer()
                                if selection == identifier { Image(systemName: "checkmark").foregroundStyle(Color.cadence) }
                                Text(offset(identifier)).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }.contentShape(Rectangle()).tag(identifier).id(identifier)
                                .onTapGesture { choose(identifier) }
                        }
                    }.listStyle(.plain)
                        .onChange(of: highlighted) { _, value in if let value { proxy.scrollTo(value) } }
                }.frame(height: 285)
            }
        }.padding(18).frame(width: 460)
            .onAppear { highlighted = selection; searchFocused = true }
            .onChange(of: query) { _, _ in highlighted = matches.first }
            .onExitCommand { close() }
    }
    func offset(_ identifier: String) -> String {
        let seconds = TimeZone(identifier: identifier)?.secondsFromGMT() ?? 0
        let minutes = abs(seconds) / 60
        return String(format: "UTC%@%02d:%02d", seconds < 0 ? "−" : "+", minutes / 60, minutes % 60)
    }
    func advance(_ direction: Int) {
        let zones = matches
        guard !zones.isEmpty else { return }
        let index = highlighted.flatMap { zones.firstIndex(of: $0) } ?? 0
        highlighted = zones[max(0, min(zones.count - 1, index + direction))]
    }
    func chooseHighlighted() { if let value = highlighted, matches.contains(value) { choose(value) } }
    func choose(_ identifier: String) { selection = identifier; close() }
}
