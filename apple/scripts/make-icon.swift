import AppKit
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let n = CGFloat(pixels)
        let base = NSRect(x: n * 0.08, y: n * 0.08, width: n * 0.84, height: n * 0.84)
        NSColor(calibratedRed: 0.22, green: 0.43, blue: 0.33, alpha: 1).setFill()
        NSBezierPath(roundedRect: base, xRadius: n * 0.19, yRadius: n * 0.19).fill()
        NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.89, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: n * 0.27, y: n * 0.21, width: n * 0.49, height: n * 0.60), xRadius: n * 0.055, yRadius: n * 0.055).fill()
        NSColor(calibratedRed: 0.79, green: 0.83, blue: 0.70, alpha: 1).setFill()
        NSRect(x: n * 0.32, y: n * 0.21, width: n * 0.018, height: n * 0.60).fill()
        NSColor(calibratedRed: 0.29, green: 0.48, blue: 0.36, alpha: 1).setFill()
        for y in [0.56, 0.45, 0.34] { NSBezierPath(roundedRect: NSRect(x: n * 0.40, y: n * y, width: n * 0.26, height: n * 0.025), xRadius: n * 0.01, yRadius: n * 0.01).fill() }
        NSColor(calibratedRed: 0.82, green: 0.61, blue: 0.29, alpha: 1).setFill()
        NSRect(x: n * 0.60, y: n * 0.66, width: n * 0.065, height: n * 0.15).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
