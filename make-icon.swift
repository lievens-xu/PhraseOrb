import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let s = CGFloat(pixels)
        let path = NSBezierPath(roundedRect: NSRect(x: s * 0.07, y: s * 0.07, width: s * 0.86, height: s * 0.86), xRadius: s * 0.22, yRadius: s * 0.22)
        NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.77, blue: 0.67, alpha: 1),
                   ending: NSColor(calibratedRed: 0.02, green: 0.42, blue: 0.43, alpha: 1))!.draw(in: path, angle: -55)
        let bubble = NSBezierPath(roundedRect: NSRect(x: s * 0.24, y: s * 0.34, width: s * 0.52, height: s * 0.38), xRadius: s * 0.10, yRadius: s * 0.10)
        NSColor.white.setFill(); bubble.fill()
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: s * 0.35, y: s * 0.38))
        tail.line(to: NSPoint(x: s * 0.35, y: s * 0.23))
        tail.line(to: NSPoint(x: s * 0.51, y: s * 0.38))
        tail.close(); tail.fill()
        NSColor(calibratedRed: 0.04, green: 0.52, blue: 0.48, alpha: 1).setFill()
        for x in [0.36, 0.47, 0.58] {
            NSBezierPath(ovalIn: NSRect(x: s * x, y: s * 0.50, width: s * 0.055, height: s * 0.055)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
    }
}
