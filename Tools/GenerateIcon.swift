import AppKit

private let outputPath = CommandLine.arguments.dropFirst().first ?? "Resources/QuickCopy.iconset"
private let outputURL = URL(fileURLWithPath: outputPath)
private let fileManager = FileManager.default

try? fileManager.removeItem(at: outputURL)
try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)

private struct IconSize {
    let name: String
    let pixels: Int
}

private let sizes = [
    IconSize(name: "icon_16x16.png", pixels: 16),
    IconSize(name: "icon_16x16@2x.png", pixels: 32),
    IconSize(name: "icon_32x32.png", pixels: 32),
    IconSize(name: "icon_32x32@2x.png", pixels: 64),
    IconSize(name: "icon_128x128.png", pixels: 128),
    IconSize(name: "icon_128x128@2x.png", pixels: 256),
    IconSize(name: "icon_256x256.png", pixels: 256),
    IconSize(name: "icon_256x256@2x.png", pixels: 512),
    IconSize(name: "icon_512x512.png", pixels: 512),
    IconSize(name: "icon_512x512@2x.png", pixels: 1024)
]

for size in sizes {
    let image = drawIcon(pixelSize: size.pixels)
    let url = outputURL.appendingPathComponent(size.name)
    try writePNG(image, to: url)
}

private func drawIcon(pixelSize: Int) -> NSImage {
    let length = CGFloat(pixelSize)
    let rect = NSRect(x: 0, y: 0, width: length, height: length)
    let image = NSImage(size: rect.size)

    image.lockFocus()

    let background = NSBezierPath(
        roundedRect: rect.insetBy(dx: length * 0.055, dy: length * 0.055),
        xRadius: length * 0.215,
        yRadius: length * 0.215
    )
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.05, green: 0.36, blue: 0.42, alpha: 1),
        NSColor(calibratedRed: 0.07, green: 0.48, blue: 0.58, alpha: 1)
    ])
    gradient?.draw(in: background, angle: 315)

    NSColor(calibratedWhite: 1, alpha: 0.18).setStroke()
    background.lineWidth = max(1, length * 0.018)
    background.stroke()

    let pageRect = NSRect(
        x: length * 0.245,
        y: length * 0.205,
        width: length * 0.51,
        height: length * 0.61
    )
    let page = NSBezierPath(
        roundedRect: pageRect,
        xRadius: length * 0.07,
        yRadius: length * 0.07
    )
    NSColor(calibratedRed: 0.96, green: 0.98, blue: 0.96, alpha: 1).setFill()
    page.fill()

    NSColor(calibratedRed: 0.04, green: 0.26, blue: 0.31, alpha: 0.22).setStroke()
    page.lineWidth = max(1, length * 0.012)
    page.stroke()

    let fold = NSBezierPath()
    fold.move(to: NSPoint(x: pageRect.maxX - length * 0.145, y: pageRect.maxY))
    fold.line(to: NSPoint(x: pageRect.maxX, y: pageRect.maxY - length * 0.145))
    fold.line(to: NSPoint(x: pageRect.maxX - length * 0.145, y: pageRect.maxY - length * 0.145))
    fold.close()
    NSColor(calibratedRed: 0.82, green: 0.91, blue: 0.88, alpha: 1).setFill()
    fold.fill()

    let lineColor = NSColor(calibratedRed: 0.09, green: 0.39, blue: 0.45, alpha: 0.32)
    lineColor.setFill()
    for index in 0..<3 {
        let y = pageRect.maxY - length * (0.26 + CGFloat(index) * 0.12)
        let line = NSBezierPath(
            roundedRect: NSRect(
                x: pageRect.minX + length * 0.105,
                y: y,
                width: pageRect.width - length * 0.21,
                height: length * 0.032
            ),
            xRadius: length * 0.018,
            yRadius: length * 0.018
        )
        line.fill()
    }

    let badgeRect = NSRect(
        x: length * 0.565,
        y: length * 0.155,
        width: length * 0.27,
        height: length * 0.27
    )
    let badge = NSBezierPath(ovalIn: badgeRect)
    NSColor(calibratedRed: 0.98, green: 0.79, blue: 0.24, alpha: 1).setFill()
    badge.fill()

    NSColor(calibratedRed: 0.08, green: 0.25, blue: 0.28, alpha: 1).setStroke()
    let check = NSBezierPath()
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    check.lineWidth = max(2, length * 0.035)
    check.move(to: NSPoint(x: badgeRect.minX + badgeRect.width * 0.27, y: badgeRect.midY))
    check.line(to: NSPoint(x: badgeRect.minX + badgeRect.width * 0.44, y: badgeRect.minY + badgeRect.height * 0.34))
    check.line(to: NSPoint(x: badgeRect.minX + badgeRect.width * 0.74, y: badgeRect.minY + badgeRect.height * 0.67))
    check.stroke()

    image.unlockFocus()
    return image
}

private func writePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw CocoaError(.fileWriteUnknown)
    }

    try pngData.write(to: url)
}
