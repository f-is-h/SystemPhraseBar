import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: 1)
}
func drawIcon() {
    let base = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200)
    NSGradient(starting: color(249, 141, 83), ending: color(227, 91, 57))!.draw(in: base, angle: -90)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.13)
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.shadowBlurRadius = 28
    shadow.set()
    color(255, 251, 241).setFill()
    NSBezierPath(roundedRect: NSRect(x: 225, y: 225, width: 574, height: 574), xRadius: 105, yRadius: 105).fill()
    NSGraphicsContext.restoreGraphicsState()
    color(58, 56, 54).setFill()
    NSBezierPath(roundedRect: NSRect(x: 327, y: 613, width: 190, height: 42), xRadius: 21, yRadius: 21).fill()
    NSBezierPath(roundedRect: NSRect(x: 327, y: 369, width: 294, height: 42), xRadius: 21, yRadius: 21).fill()
    let arrow = NSBezierPath()
    arrow.lineWidth = 37
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 618, y: 634))
    arrow.line(to: NSPoint(x: 676, y: 634))
    arrow.line(to: NSPoint(x: 676, y: 509))
    arrow.line(to: NSPoint(x: 541, y: 509))
    arrow.move(to: NSPoint(x: 582, y: 551))
    arrow.line(to: NSPoint(x: 540, y: 509))
    arrow.line(to: NSPoint(x: 582, y: 467))
    color(230, 103, 65).setStroke()
    arrow.stroke()
}
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(pixels)/1024)
        transform.concat()
        drawIcon()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    }
}
