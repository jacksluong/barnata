// Renders Resources/AppIcon.icns from code, so no image assets are committed by hand.
// Run through Scripts/make-icon.sh, which wraps this and calls iconutil.
import AppKit
import Foundation

let canvas: CGFloat = 1024

/// Apple's icon grid: the shape fills 824 of the 1024 canvas
let plateInset: CGFloat = 100
let plateRadius = (canvas - 2 * plateInset) / 2
let squircleExponent: CGFloat = 5.8

let topColor = NSColor(srgbRed: 0.435, green: 0.482, blue: 1.0, alpha: 1)
let bottomColor = NSColor(srgbRed: 0.180, green: 0.192, blue: 0.573, alpha: 1)
let keyColor = NSColor.white
let accentColor = NSColor(srgbRed: 1.0, green: 0.820, blue: 0.400, alpha: 1)

/// A superellipse, which is the continuous-corner shape macOS icons use
func squirclePath(center: CGPoint, radius: CGFloat, exponent: CGFloat, steps: Int = 1440) -> CGPath {
    let path = CGMutablePath()
    let power = 2 / exponent
    for step in 0...steps {
        let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let cosine = cos(angle)
        let sine = sin(angle)
        let x = center.x + radius * copysign(pow(abs(cosine), power), cosine)
        let y = center.y + radius * copysign(pow(abs(sine), power), sine)
        if step == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

/// Three rows of keys over a spacebar, with one key picked out to stand for the active layer
func keyboardRects() -> [(rect: CGRect, isAccent: Bool)] {
    let key: CGFloat = 70
    let gap: CGFloat = 20
    let columns = 7
    let width = CGFloat(columns) * key + CGFloat(columns - 1) * gap
    let rows = 4
    let height = CGFloat(rows) * key + CGFloat(rows - 1) * gap
    let originX = (canvas - width) / 2
    let topY = (canvas + height) / 2 - key

    var result: [(CGRect, Bool)] = []
    for row in 0..<3 {
        let y = topY - CGFloat(row) * (key + gap)
        for column in 0..<columns {
            let x = originX + CGFloat(column) * (key + gap)
            result.append((CGRect(x: x, y: y, width: key, height: key), row == 1 && column == 2))
        }
    }

    // Spacebar row: one key, the bar, one key
    let y = topY - 3 * (key + gap)
    let barWidth = width - 2 * (key + gap)
    result.append((CGRect(x: originX, y: y, width: key, height: key), false))
    result.append((CGRect(x: originX + key + gap, y: y, width: barWidth, height: key), false))
    result.append((CGRect(x: originX + width - key, y: y, width: key, height: key), false))
    return result
}

func render(size: Int) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { fatalError("cannot make a \(size)px bitmap") }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let graphics = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("cannot make a context") }
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext

    let scale = CGFloat(size) / canvas
    context.scaleBy(x: scale, y: scale)
    context.setShouldAntialias(true)

    let plate = squirclePath(
        center: CGPoint(x: canvas / 2, y: canvas / 2),
        radius: plateRadius,
        exponent: squircleExponent
    )

    context.saveGState()
    context.addPath(plate)
    context.clip()
    let colors = [bottomColor.cgColor, topColor.cgColor] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: plateInset),
            end: CGPoint(x: 0, y: canvas - plateInset),
            options: []
        )
    }
    context.restoreGState()

    // Keys sit slightly above the plate, so a soft shadow keeps them legible on the gradient
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: NSColor.black.withAlphaComponent(0.28).cgColor)
    for (rect, isAccent) in keyboardRects() {
        let path = CGPath(roundedRect: rect, cornerWidth: 18, cornerHeight: 18, transform: nil)
        context.addPath(path)
        context.setFillColor(isAccent ? accentColor.cgColor : keyColor.cgColor)
        context.fillPath()
    }
    context.restoreGState()

    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("cannot encode png") }
    return data
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
    exit(1)
}

let iconset = URL(fileURLWithPath: arguments[1])
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// iconutil expects exactly these names
let outputs: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

var cache: [Int: Data] = [:]
for (name, size) in outputs {
    let data = cache[size] ?? {
        let rendered = render(size: size)
        cache[size] = rendered
        return rendered
    }()
    try data.write(to: iconset.appending(path: name))
}
