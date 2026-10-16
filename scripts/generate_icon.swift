import AppKit

let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let pixels = size * factor
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let icon = NSBezierPath(roundedRect: CGRect(x: 72, y: 72, width: 880, height: 880), xRadius: 200, yRadius: 200)
        let gradient = NSGradient(starting: NSColor(srgbRed: 0.49, green: 0.45, blue: 0.94, alpha: 1),
                                  ending: NSColor(srgbRed: 0.29, green: 0.31, blue: 0.73, alpha: 1))!
        gradient.draw(in: icon, angle: -55)
        NSColor.white.withAlphaComponent(0.2).setStroke(); icon.lineWidth = 4; icon.stroke()
        let lines = NSBezierPath()
        for endpoint in [CGPoint(x: 285, y: 710), CGPoint(x: 748, y: 710), CGPoint(x: 748, y: 318)] {
            lines.move(to: CGPoint(x: 480, y: 510))
            lines.curve(to: endpoint, controlPoint1: CGPoint(x: endpoint.x, y: 510), controlPoint2: CGPoint(x: 480, y: endpoint.y))
        }
        NSColor.white.withAlphaComponent(0.72).setStroke(); lines.lineWidth = 23; lines.lineCapStyle = .round; lines.stroke()
        for rect in [CGRect(x: 382, y: 437, width: 210, height: 146), CGRect(x: 195, y: 664, width: 178, height: 102),
                     CGRect(x: 661, y: 664, width: 178, height: 102), CGRect(x: 661, y: 267, width: 178, height: 102)] {
            NSColor.white.setFill(); NSBezierPath(roundedRect: rect, xRadius: 29, yRadius: 29).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = factor == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output + "/icon_\(size)x\(size)\(suffix).png"))
    }
}
