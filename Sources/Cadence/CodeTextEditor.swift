import SwiftUI
import AppKit

/// Hide scrollbars when the text fits, including with macOS's “Always” scrollbar setting.
struct CodeTextEditor: NSViewRepresentable {
    @Binding var text: String
    let label: String
    var monospaced = true
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        let editor = scrollView.documentView as! NSTextView
        editor.drawsBackground = false
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.delegate = context.coordinator
        context.coordinator.editor = editor
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        let editor = scrollView.documentView as! NSTextView
        if editor.string != text {
            editor.string = text
            editor.undoManager?.removeAllActions()
        }
        let font = monospaced ? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular) : .systemFont(ofSize: 15)
        if editor.font != font { editor.font = font }
        editor.textColor = isEnabled ? .textColor : .disabledControlTextColor
        editor.insertionPointColor = .textColor
        editor.isEditable = isEnabled
        editor.setAccessibilityLabel(label)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeTextEditor
        weak var editor: NSTextView?
        private let history = UndoManager()

        init(_ parent: CodeTextEditor) {
            self.parent = parent
            super.init()
            for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
                NotificationCenter.default.addObserver(self, selector: #selector(historyDidChange), name: name, object: history)
            }
        }
        deinit { NotificationCenter.default.removeObserver(self) }

        func undoManager(for view: NSTextView) -> UndoManager? { history }

        // Native undo/redo can change the text without calling textDidChange.
        @objc private func historyDidChange(_ notification: Notification) {
            guard let editor else { return }
            parent.text = editor.string
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}
