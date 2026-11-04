import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension UTType {
    static let cadenceWorkflowStep = UTType(exportedAs: "local.cadence.workflow-step")
}

struct WorkflowStepTransfer: Codable {
    let taskID: UUID
    let stepID: UUID
}

/// Use AppKit's dragging session so the grip works inside editable SwiftUI cards and scroll views.
struct WorkflowDragHandle: NSViewRepresentable {
    let transfer: WorkflowStepTransfer
    let title: String
    let enabled: Bool
    func makeNSView(context: Context) -> StepGripView { StepGripView() }
    func updateNSView(_ view: StepGripView, context: Context) {
        view.transfer = transfer; view.title = title; view.dragEnabled = enabled
        view.toolTip = "Drag to reorder step"
        view.setAccessibilityLabel("Drag \(title) to reorder")
        view.needsDisplay = true
    }
}

final class StepGripView: NSView, NSDraggingSource {
    var transfer: WorkflowStepTransfer?
    var title = ""
    var dragEnabled = true
    private var mouseDownPoint: NSPoint?
    private var dragging = false
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true); setAccessibilityRole(.image)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { if dragEnabled { addCursorRect(bounds, cursor: .openHand) } }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.withAlphaComponent(dragEnabled ? 1 : 0.3).setStroke()
        let path = NSBezierPath(); path.lineWidth = 1.5; path.lineCapStyle = .round
        for offset in [-4.0, 0, 4] {
            path.move(to: NSPoint(x: 6, y: bounds.midY + offset))
            path.line(to: NSPoint(x: bounds.width - 6, y: bounds.midY + offset))
        }
        path.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
    }
    override func mouseUp(with event: NSEvent) { mouseDownPoint = nil }
    override func mouseDragged(with event: NSEvent) {
        guard dragEnabled, !dragging, let start = mouseDownPoint, let transfer else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) >= 3, let data = try? JSONEncoder().encode(transfer) else { return }
        let item = NSPasteboardItem()
        item.setData(data, forType: NSPasteboard.PasteboardType(UTType.cadenceWorkflowStep.identifier))
        let dragged = NSDraggingItem(pasteboardWriter: item)
        dragged.setDraggingFrame(NSRect(x: 0, y: 0, width: 240, height: 36), contents: preview())
        dragging = true
        let session = beginDraggingSession(with: [dragged], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? [.move, .copy] : []
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragging = false; mouseDownPoint = nil
    }
    private func preview() -> NSImage {
        let image = NSImage(size: NSSize(width: 240, height: 36))
        image.lockFocus()
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 240, height: 36), xRadius: 8, yRadius: 8).fill()
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(in: NSRect(x: 12, y: 9, width: 216, height: 20),
                                withAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph])
        image.unlockFocus()
        return image
    }
}
