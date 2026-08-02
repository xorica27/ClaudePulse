import AppKit
import Foundation

// `swift generate-dmg-background.swift out.png 680 420` runs this file through
// the interpreter, and swift-frontend leaves its own entire invocation in
// CommandLine.arguments with the script's arguments appended after a trailing
// `--`. Reading arguments[1] therefore picks up a compiler flag rather than the
// output path. Slice from the last `--` so the arguments are the same whether
// this file is interpreted or compiled.
let arguments: [String] = {
    if let separator = CommandLine.arguments.lastIndex(of: "--") {
        return Array(CommandLine.arguments[(separator + 1)...])
    }
    return Array(CommandLine.arguments.dropFirst())
}()

guard arguments.count == 1 || arguments.count == 3 else {
    fputs("Usage: generate-dmg-background.swift <output.png> [width height]\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: arguments[0])
// package-dmg.sh passes the installer window size so the background can never
// drift out of sync with it.
let width = arguments.count == 3 ? Double(arguments[1]) ?? 680 : 680
let height = arguments.count == 3 ? Double(arguments[2]) ?? 420 : 420
let size = NSSize(width: width, height: height)
let image = NSImage(size: size)

let centerStyle = NSMutableParagraphStyle()
centerStyle.alignment = .center

func drawCentered(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
    text.draw(
        in: rect,
        withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: centerStyle
        ]
    )
}

image.lockFocus()

let bounds = NSRect(origin: .zero, size: size)
NSColor(calibratedRed: 0.965, green: 0.968, blue: 0.976, alpha: 1).setFill()
bounds.fill()

let topLine = NSBezierPath()
topLine.lineWidth = 1
NSColor(calibratedWhite: 1, alpha: 0.75).setStroke()
topLine.move(to: NSPoint(x: 0, y: height - 1))
topLine.line(to: NSPoint(x: width, y: height - 1))
topLine.stroke()

drawCentered(
    "Drag to install",
    rect: NSRect(x: (width - 360) / 2, y: height - 75, width: 360, height: 24),
    font: NSFont.systemFont(ofSize: 16, weight: .medium),
    color: NSColor(calibratedRed: 0.22, green: 0.24, blue: 0.28, alpha: 1)
)

// Finder positions the icons from the top-left; this canvas draws from the
// bottom-left, so the arrow sits at (height - iconY) to line up with them.
let arrowY = height - 198
let arrowCenterX = width / 2
let arrowColor = NSColor(calibratedRed: 1, green: 0.16, blue: 0.25, alpha: 0.95)
arrowColor.setStroke()

let arrowPath = NSBezierPath()
arrowPath.lineWidth = 7
arrowPath.lineCapStyle = .round
arrowPath.lineJoinStyle = .round
arrowPath.move(to: NSPoint(x: arrowCenterX - 55, y: arrowY))
arrowPath.line(to: NSPoint(x: arrowCenterX + 55, y: arrowY))
arrowPath.stroke()

let arrowHead = NSBezierPath()
arrowHead.lineWidth = 7
arrowHead.lineCapStyle = .round
arrowHead.lineJoinStyle = .round
arrowHead.move(to: NSPoint(x: arrowCenterX + 30, y: arrowY + 25))
arrowHead.line(to: NSPoint(x: arrowCenterX + 55, y: arrowY))
arrowHead.line(to: NSPoint(x: arrowCenterX + 30, y: arrowY - 25))
arrowHead.stroke()

drawCentered(
    "ClaudePulse stays local and reads Claude app data only.",
    rect: NSRect(x: (width - 500) / 2, y: 40, width: 500, height: 18),
    font: NSFont.systemFont(ofSize: 11, weight: .regular),
    color: NSColor(calibratedRed: 0.53, green: 0.55, blue: 0.6, alpha: 1)
)

image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not render DMG background.\n", stderr)
    exit(1)
}

try pngData.write(to: outputURL)
