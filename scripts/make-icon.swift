// Draws the M’AND app icon at 1024×1024 and writes it as a PNG.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    // macOS icon grid: 824 pt body centred in a 1024 canvas.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.14, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.26, alpha: 1),
               ending: NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.12, alpha: 1))?
        .draw(in: shape, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: 400, weight: .regular)
        .applying(.init(paletteColors: [.white, NSColor(calibratedRed: 0.36, green: 0.84, blue: 0.62, alpha: 1)]))
    if let symbol = NSImage(systemSymbolName: "laptopcomputer.and.iphone", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let symbolSize = symbol.size
        let scale = min(560 / symbolSize.width, 560 / symbolSize.height)
        let drawn = NSSize(width: symbolSize.width * scale, height: symbolSize.height * scale)
        symbol.draw(in: NSRect(x: (size - drawn.width) / 2, y: (size - drawn.height) / 2 - 10,
                               width: drawn.width, height: drawn.height))
    }
    return true
}

guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Could not render icon\n".utf8))
    exit(1)
}
try png.write(to: URL(fileURLWithPath: output))
