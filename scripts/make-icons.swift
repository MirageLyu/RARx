import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let output = root.appendingPathComponent("build/icons", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let navy = NSColor(srgbRed: 0.047, green: 0.129, blue: 0.188, alpha: 1)
let deepNavy = NSColor(srgbRed: 0.025, green: 0.075, blue: 0.110, alpha: 1)
let cream = NSColor(srgbRed: 0.957, green: 0.937, blue: 0.882, alpha: 1)
let creamDark = NSColor(srgbRed: 0.835, green: 0.800, blue: 0.718, alpha: 1)
let gold = NSColor(srgbRed: 0.976, green: 0.741, blue: 0.251, alpha: 1)
let goldDeep = NSColor(srgbRed: 0.886, green: 0.573, blue: 0.102, alpha: 1)
let teal = NSColor(srgbRed: 0.118, green: 0.471, blue: 0.545, alpha: 1)

func path(_ points: [NSPoint]) -> NSBezierPath {
    let p = NSBezierPath()
    guard let first = points.first else { return p }
    p.move(to: first)
    for point in points.dropFirst() { p.line(to: point) }
    p.close()
    p.lineJoinStyle = .round
    return p
}

func shadow(_ color: NSColor = NSColor.black.withAlphaComponent(0.28), blur: CGFloat = 36, y: CGFloat = -22) {
    let s = NSShadow()
    s.shadowColor = color
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: y)
    s.set()
}

func clearShadow() {
    NSShadow().set()
}

func drawStar(center: NSPoint, radius: CGFloat, color: NSColor) {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: center.x, y: center.y + radius))
    p.curve(to: NSPoint(x: center.x + radius, y: center.y),
            controlPoint1: NSPoint(x: center.x + radius * 0.15, y: center.y + radius * 0.15),
            controlPoint2: NSPoint(x: center.x + radius * 0.15, y: center.y + radius * 0.15))
    p.curve(to: NSPoint(x: center.x, y: center.y - radius),
            controlPoint1: NSPoint(x: center.x + radius * 0.15, y: center.y - radius * 0.15),
            controlPoint2: NSPoint(x: center.x + radius * 0.15, y: center.y - radius * 0.15))
    p.curve(to: NSPoint(x: center.x - radius, y: center.y),
            controlPoint1: NSPoint(x: center.x - radius * 0.15, y: center.y - radius * 0.15),
            controlPoint2: NSPoint(x: center.x - radius * 0.15, y: center.y - radius * 0.15))
    p.curve(to: NSPoint(x: center.x, y: center.y + radius),
            controlPoint1: NSPoint(x: center.x - radius * 0.15, y: center.y + radius * 0.15),
            controlPoint2: NSPoint(x: center.x - radius * 0.15, y: center.y + radius * 0.15))
    p.close()
    color.setFill()
    p.fill()
}

func drawAppIcon() {
    let background = NSBezierPath(
        roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
        xRadius: 188,
        yRadius: 188
    )
    let backgroundGradient = NSGradient(
        starting: NSColor(srgbRed: 0.071, green: 0.188, blue: 0.251, alpha: 1),
        ending: NSColor(srgbRed: 0.024, green: 0.075, blue: 0.110, alpha: 1)
    )!
    backgroundGradient.draw(in: background, angle: -68)

    NSGraphicsContext.saveGraphicsState()
    background.addClip()
    let glow = NSBezierPath(ovalIn: NSRect(x: 120, y: 390, width: 760, height: 760))
    NSGradient(
        starting: teal.withAlphaComponent(0.55),
        ending: teal.withAlphaComponent(0)
    )!.draw(in: glow, relativeCenterPosition: NSPoint(x: -0.2, y: -0.25))
    let topGlow = NSBezierPath(ovalIn: NSRect(x: 180, y: 650, width: 680, height: 360))
    NSGradient(
        starting: NSColor.white.withAlphaComponent(0.10),
        ending: NSColor.white.withAlphaComponent(0)
    )!.draw(in: topGlow, relativeCenterPosition: NSPoint(x: 0, y: 0.25))
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.13).setStroke()
    background.lineWidth = 2
    background.stroke()

    // Arrow rising out of the archive.
    NSGraphicsContext.saveGraphicsState()
    shadow(NSColor.black.withAlphaComponent(0.35), blur: 40, y: -28)
    let arrow = path([
        NSPoint(x: 468, y: 535),
        NSPoint(x: 468, y: 700),
        NSPoint(x: 376, y: 700),
        NSPoint(x: 512, y: 868),
        NSPoint(x: 648, y: 700),
        NSPoint(x: 556, y: 700),
        NSPoint(x: 556, y: 535)
    ])
    arrow.lineJoinStyle = .round
    NSGradient(starting: NSColor(srgbRed: 1.0, green: 0.851, blue: 0.435, alpha: 1),
               ending: goldDeep)!.draw(in: arrow, angle: -82)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shadow(NSColor.black.withAlphaComponent(0.34), blur: 34, y: -22)
    let lid = path([
        NSPoint(x: 512, y: 626),
        NSPoint(x: 776, y: 536),
        NSPoint(x: 512, y: 446),
        NSPoint(x: 248, y: 536)
    ])
    NSGradient(starting: NSColor.white, ending: creamDark)!.draw(in: lid, angle: -55)
    lid.lineWidth = 2
    navy.withAlphaComponent(0.24).setStroke()
    lid.stroke()
    NSGraphicsContext.restoreGraphicsState()

    let leftFace = path([
        NSPoint(x: 248, y: 536),
        NSPoint(x: 512, y: 446),
        NSPoint(x: 512, y: 246),
        NSPoint(x: 248, y: 336)
    ])
    cream.setFill()
    leftFace.fill()
    leftFace.lineWidth = 2
    navy.withAlphaComponent(0.20).setStroke()
    leftFace.stroke()

    let rightFace = path([
        NSPoint(x: 776, y: 536),
        NSPoint(x: 512, y: 446),
        NSPoint(x: 512, y: 246),
        NSPoint(x: 776, y: 336)
    ])
    NSGradient(starting: creamDark, ending: NSColor(srgbRed: 0.746, green: 0.706, blue: 0.612, alpha: 1))!
        .draw(in: rightFace, angle: -80)
    rightFace.lineWidth = 2
    navy.withAlphaComponent(0.20).setStroke()
    rightFace.stroke()

    let leftBand = path([
        NSPoint(x: 248, y: 405),
        NSPoint(x: 512, y: 315),
        NSPoint(x: 512, y: 362),
        NSPoint(x: 248, y: 452)
    ])
    gold.setFill()
    leftBand.fill()
    let rightBand = path([
        NSPoint(x: 776, y: 405),
        NSPoint(x: 512, y: 315),
        NSPoint(x: 512, y: 362),
        NSPoint(x: 776, y: 452)
    ])
    goldDeep.setFill()
    rightBand.fill()

    // Small archive clasp.
    let clasp = NSBezierPath(roundedRect: NSRect(x: 480, y: 452, width: 64, height: 54), xRadius: 12, yRadius: 12)
    goldDeep.setFill()
    clasp.fill()
    NSColor.white.withAlphaComponent(0.28).setStroke()
    clasp.lineWidth = 2
    clasp.stroke()

    drawStar(center: NSPoint(x: 704, y: 790), radius: 23, color: gold.withAlphaComponent(0.92))
    drawStar(center: NSPoint(x: 300, y: 735), radius: 15, color: cream.withAlphaComponent(0.78))
    drawStar(center: NSPoint(x: 758, y: 640), radius: 9, color: cream.withAlphaComponent(0.50))
}

func drawDocumentIcon() {
    let pageRect = NSRect(x: 206, y: 104, width: 612, height: 816)
    let page = NSBezierPath(roundedRect: pageRect, xRadius: 42, yRadius: 42)

    NSGraphicsContext.saveGraphicsState()
    shadow(NSColor.black.withAlphaComponent(0.30), blur: 34, y: -22)
    NSColor.white.setFill()
    page.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    page.addClip()
    NSGradient(starting: NSColor.white, ending: NSColor(srgbRed: 0.925, green: 0.918, blue: 0.894, alpha: 1))!
        .draw(in: pageRect, angle: -90)

    let header = NSBezierPath(rect: NSRect(x: 206, y: 842, width: 612, height: 78))
    NSGradient(starting: navy, ending: deepNavy)!.draw(in: header, angle: 0)
    NSGraphicsContext.restoreGraphicsState()

    // Folded corner.
    let fold = path([
        NSPoint(x: 696, y: 920),
        NSPoint(x: 818, y: 920),
        NSPoint(x: 818, y: 798)
    ])
    NSColor(srgbRed: 0.957, green: 0.851, blue: 0.596, alpha: 1).setFill()
    fold.fill()
    let foldShadow = path([
        NSPoint(x: 696, y: 920),
        NSPoint(x: 818, y: 798),
        NSPoint(x: 696, y: 798)
    ])
    NSColor(srgbRed: 0.894, green: 0.741, blue: 0.353, alpha: 1).setFill()
    foldShadow.fill()

    page.lineWidth = 2
    navy.withAlphaComponent(0.10).setStroke()
    page.stroke()

    let headline = "RAR"
    let headlineFont = NSFont.systemFont(ofSize: 174, weight: .heavy)
    let headlineAttributes: [NSAttributedString.Key: Any] = [
        .font: headlineFont,
        .foregroundColor: navy,
        .kern: 4
    ]
    let headlineSize = headline.size(withAttributes: headlineAttributes)
    headline.draw(
        at: NSPoint(x: (1024 - headlineSize.width) / 2, y: 478),
        withAttributes: headlineAttributes
    )

    let rule = NSBezierPath(roundedRect: NSRect(x: 404, y: 420, width: 216, height: 14), xRadius: 7, yRadius: 7)
    gold.setFill()
    rule.fill()

    // A compact extract arrow.
    NSGraphicsContext.saveGraphicsState()
    let arrow = path([
        NSPoint(x: 478, y: 250),
        NSPoint(x: 478, y: 332),
        NSPoint(x: 442, y: 332),
        NSPoint(x: 512, y: 402),
        NSPoint(x: 582, y: 332),
        NSPoint(x: 546, y: 332),
        NSPoint(x: 546, y: 250)
    ])
    NSGradient(starting: gold, ending: goldDeep)!.draw(in: arrow, angle: -82)
    NSGraphicsContext.restoreGraphicsState()

    let subtitle = "ARCHIVE"
    let subtitleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 27, weight: .semibold),
        .foregroundColor: NSColor(srgbRed: 0.38, green: 0.38, blue: 0.38, alpha: 1),
        .kern: 9
    ]
    let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
    subtitle.draw(
        at: NSPoint(x: (1024 - subtitleSize.width) / 2, y: 172),
        withAttributes: subtitleAttributes
    )
}

func renderPNG(size: Int, draw: () -> Void) -> Data {
    let rep = NSBitmapImageRep(
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
    )!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.cgContext.setShouldAntialias(true)
    context.cgContext.setAllowsAntialiasing(true)
    context.cgContext.scaleBy(x: CGFloat(size) / 1024.0, y: CGFloat(size) / 1024.0)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

struct IconSpec {
    let filename: String
    let points: Int
    let pixels: Int
}

let specs: [IconSpec] = [
    IconSpec(filename: "icon_16x16.png", points: 16, pixels: 16),
    IconSpec(filename: "icon_16x16@2x.png", points: 16, pixels: 32),
    IconSpec(filename: "icon_32x32.png", points: 32, pixels: 32),
    IconSpec(filename: "icon_32x32@2x.png", points: 32, pixels: 64),
    IconSpec(filename: "icon_128x128.png", points: 128, pixels: 128),
    IconSpec(filename: "icon_128x128@2x.png", points: 128, pixels: 256),
    IconSpec(filename: "icon_256x256.png", points: 256, pixels: 256),
    IconSpec(filename: "icon_256x256@2x.png", points: 256, pixels: 512),
    IconSpec(filename: "icon_512x512.png", points: 512, pixels: 512),
    IconSpec(filename: "icon_512x512@2x.png", points: 512, pixels: 1024)
]

func buildIcon(named name: String, draw: @escaping () -> Void) throws {
    let iconset = output.appendingPathComponent("\(name).iconset", isDirectory: true)
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for spec in specs {
        let data = renderPNG(size: spec.pixels, draw: draw)
        try data.write(to: iconset.appendingPathComponent(spec.filename))
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("\(name).icns").path]
    let pipe = Pipe()
    process.standardError = pipe
    process.standardOutput = pipe
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        let message = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        throw NSError(domain: "icons", code: Int(process.terminationStatus), userInfo: [
            NSLocalizedDescriptionKey: "iconutil failed: \(message)"
        ])
    }
}

try buildIcon(named: "AppIcon", draw: drawAppIcon)
try buildIcon(named: "RARFile", draw: drawDocumentIcon)
print("Icons written to \(output.path)")
