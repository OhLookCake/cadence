import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent("Cadence.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform(); transform.scale(by: factor); transform.concat()
        let box = NSBezierPath(roundedRect: NSRect(x: 74, y: 74, width: 876, height: 876), xRadius: 200, yRadius: 200)
        NSGradient(starting: NSColor(red: 0.24, green: 0.56, blue: 0.51, alpha: 1), ending: NSColor(red: 0.08, green: 0.29, blue: 0.29, alpha: 1))!.draw(in: box, angle: -60)
        let ring = NSBezierPath(ovalIn: NSRect(x: 250, y: 250, width: 524, height: 524)); ring.lineWidth = 32; NSColor.white.withAlphaComponent(0.9).setStroke(); ring.stroke()
        let hands = NSBezierPath(); hands.move(to: NSPoint(x: 512, y: 695)); hands.line(to: NSPoint(x: 512, y: 512)); hands.line(to: NSPoint(x: 632, y: 442)); hands.lineWidth = 38; hands.lineCapStyle = .round; hands.stroke()
        let badge = NSBezierPath(ovalIn: NSRect(x: 657, y: 222, width: 165, height: 165)); NSColor(red: 0.86, green: 0.91, blue: 0.71, alpha: 1).setFill(); badge.fill()
        let check = NSBezierPath(); check.move(to: NSPoint(x: 696, y: 303)); check.line(to: NSPoint(x: 726, y: 273)); check.line(to: NSPoint(x: 783, y: 335)); check.lineWidth = 17; check.lineCapStyle = .round; check.lineJoinStyle = .round; NSColor(red: 0.1, green: 0.32, blue: 0.29, alpha: 1).setStroke(); check.stroke()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(filename))
    }
}
let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil"); process.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Cadence.icns").path]
try process.run(); process.waitUntilExit()
if process.terminationStatus != 0 { exit(1) }
try FileManager.default.removeItem(at: iconset)
