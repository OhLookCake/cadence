import SwiftUI
import AppKit

struct ConfigHealthBanner: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Some workflow configs need attention", systemImage: "exclamationmark.triangle.fill").font(.cadenceCallout.weight(.medium))
            ForEach(model.configIssues.prefix(5)) { issue in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(issue.url.lastPathComponent).font(.cadenceCaption.monospaced())
                        Text(issue.message).font(.cadenceCaption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    Button("Edit File…") { model.editConfig(issue.url) }
                }
            }
            ForEach(model.registrationIssues.prefix(3), id: \.self) { Text($0).font(.cadenceCaption).foregroundStyle(.secondary) }
            HStack {
                Text("Invalid configs do not run. Other valid workflows remain available.").font(.cadenceCaption).foregroundStyle(.secondary)
                Spacer()
                Button("Open Config Folder") { NSWorkspace.shared.open(model.store.flowsDirectory) }
                Button("Refresh") { model.refresh(force: true) }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.1))
    }
}
