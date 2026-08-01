import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate-dmg-background.swift <output.png>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 680, height: 420)
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
topLine.move(to: NSPoint(x: 0, y: 419))
topLine.line(to: NSPoint(x: 680, y: 419))
topLine.stroke()

drawCentered(
    "Drag to install",
    rect: NSRect(x: 160, y: 345, width: 360, height: 24),
    font: NSFont.systemFont(ofSize: 16, weight: .medium),
    color: NSColor(calibratedRed: 0.22, green: 0.24, blue: 0.28, alpha: 1)
)

let arrowColor = NSColor(calibratedRed: 1, green: 0.16, blue: 0.25, alpha: 0.95)
arrowColor.setStroke()

let arrowPath = NSBezierPath()
arrowPath.lineWidth = 7
arrowPath.lineCapStyle = .round
arrowPath.lineJoinStyle = .round
arrowPath.move(to: NSPoint(x: 285, y: 222))
arrowPath.line(to: NSPoint(x: 395, y: 222))
arrowPath.stroke()

let arrowHead = NSBezierPath()
arrowHead.lineWidth = 7
arrowHead.lineCapStyle = .round
arrowHead.lineJoinStyle = .round
arrowHead.move(to: NSPoint(x: 370, y: 247))
arrowHead.line(to: NSPoint(x: 395, y: 222))
arrowHead.line(to: NSPoint(x: 370, y: 197))
arrowHead.stroke()

drawCentered(
    "ClaudePulse stays local and reads Claude app data only.",
    rect: NSRect(x: 90, y: 40, width: 500, height: 18),
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
