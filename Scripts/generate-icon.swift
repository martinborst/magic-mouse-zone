import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon-1024.png"
let size: CGFloat = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size),
    pixelsHigh: Int(size),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Could not create bitmap\n", stderr)
    exit(1)
}

rep.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
    exit(1)
}
NSGraphicsContext.current = context
context.imageInterpolation = .high
context.shouldAntialias = true
context.cgContext.setShouldAntialias(true)
context.cgContext.setAllowsAntialiasing(true)

let canvas = NSRect(x: 0, y: 0, width: size, height: size)
NSColor.clear.setFill()
canvas.fill(using: .copy)

// Apple macOS app icons use a squircle (superellipse), not a square
// and not a simple rounded rectangle.
let squircle = superellipse(in: canvas.insetBy(dx: 1, dy: 1), n: 5)

NSGraphicsContext.current?.saveGraphicsState()
squircle.addClip()

let bgGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.93, green: 0.95, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 0.76, green: 0.83, blue: 0.91, alpha: 1)
])
bgGradient?.draw(in: canvas, angle: -90)

let mouseWidth: CGFloat = 420
let mouseHeight: CGFloat = 730
let mouseRect = NSRect(
    x: (size - mouseWidth) / 2,
    y: (size - mouseHeight) / 2 - 12,
    width: mouseWidth,
    height: mouseHeight
)
let mousePath = NSBezierPath(roundedRect: mouseRect, xRadius: 150, yRadius: 150)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
shadow.shadowBlurRadius = 42
shadow.shadowOffset = NSSize(width: 0, height: -18)
NSGraphicsContext.current?.saveGraphicsState()
shadow.set()
NSColor.white.setFill()
mousePath.fill()
NSGraphicsContext.current?.restoreGraphicsState()

let mouseGradient = NSGradient(colors: [
    NSColor(calibratedWhite: 0.99, alpha: 1),
    NSColor(calibratedWhite: 0.88, alpha: 1)
])
mouseGradient?.draw(in: mousePath, angle: -90)

NSColor.black.withAlphaComponent(0.10).setStroke()
mousePath.lineWidth = 3
mousePath.stroke()

let zoneInsetX: CGFloat = 128
let zoneInsetTop: CGFloat = 70
let zoneInsetBottom: CGFloat = 90
let zoneRect = NSRect(
    x: mouseRect.minX + zoneInsetX,
    y: mouseRect.minY + zoneInsetBottom,
    width: mouseRect.width - zoneInsetX * 2,
    height: mouseRect.height - zoneInsetTop - zoneInsetBottom
)
let zonePath = NSBezierPath(roundedRect: zoneRect, xRadius: 36, yRadius: 36)
NSColor(calibratedRed: 0.10, green: 0.48, blue: 1.0, alpha: 0.38).setFill()
zonePath.fill()
NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.98, alpha: 0.95).setStroke()
zonePath.lineWidth = 8
zonePath.stroke()

let portRect = NSRect(
    x: mouseRect.midX - 48,
    y: mouseRect.minY + 36,
    width: 96,
    height: 16
)
NSColor.black.withAlphaComponent(0.10).setFill()
NSBezierPath(roundedRect: portRect, xRadius: 8, yRadius: 8).fill()

NSGraphicsContext.current?.restoreGraphicsState()

NSColor.white.withAlphaComponent(0.42).setStroke()
squircle.lineWidth = 3
squircle.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Could not encode PNG\n", stderr)
    exit(1)
}

let url = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: url)
print("Wrote \(outputPath)")

func superellipse(in rect: NSRect, n: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let steps = 360
    let a = rect.width / 2
    let b = rect.height / 2
    let cx = rect.midX
    let cy = rect.midY
    let p = 2 / n
    for i in 0...steps {
        let theta = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let cosT = Foundation.cos(theta)
        let sinT = Foundation.sin(theta)
        let x = cx + a * copysign(pow(abs(cosT), p), cosT)
        let y = cy + b * copysign(pow(abs(sinT), p), sinT)
        let point = NSPoint(x: x, y: y)
        if i == 0 {
            path.move(to: point)
        } else {
            path.line(to: point)
        }
    }
    path.close()
    return path
}

