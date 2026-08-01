import AppKit

private struct Point {
    let x: CGFloat
    let y: CGFloat
}

private let canvas: CGFloat = 1254
private let menuCanvas = CGSize(width: 934, height: 648)

private let avatar: [Point] = [
    .init(x: 344, y: 303), .init(x: 909, y: 303), .init(x: 909, y: 365),
    .init(x: 971, y: 365), .init(x: 971, y: 574), .init(x: 1094, y: 574),
    .init(x: 1094, y: 710), .init(x: 971, y: 710), .init(x: 971, y: 835),
    .init(x: 909, y: 835), .init(x: 909, y: 951), .init(x: 849, y: 951),
    .init(x: 849, y: 835), .init(x: 788, y: 835), .init(x: 788, y: 951),
    .init(x: 728, y: 951), .init(x: 728, y: 835), .init(x: 526, y: 835),
    .init(x: 526, y: 951), .init(x: 466, y: 951), .init(x: 466, y: 835),
    .init(x: 405, y: 835), .init(x: 405, y: 951), .init(x: 344, y: 951),
    .init(x: 344, y: 835), .init(x: 282, y: 835), .init(x: 282, y: 710),
    .init(x: 160, y: 710), .init(x: 160, y: 575), .init(x: 282, y: 575),
    .init(x: 282, y: 365), .init(x: 344, y: 365)
]

private let pulse: [Point] = [
    .init(x: 909, y: 668), .init(x: 908, y: 648), .init(x: 806, y: 648),
    .init(x: 778, y: 591), .init(x: 753, y: 590), .init(x: 699, y: 726),
    .init(x: 640, y: 498), .init(x: 613, y: 499), .init(x: 559, y: 691),
    .init(x: 504, y: 575), .init(x: 481, y: 575), .init(x: 447, y: 648),
    .init(x: 345, y: 648), .init(x: 345, y: 675), .init(x: 463, y: 675),
    .init(x: 493, y: 613), .init(x: 543, y: 722), .init(x: 578, y: 722),
    .init(x: 627, y: 551), .init(x: 682, y: 764), .init(x: 714, y: 764),
    .init(x: 767, y: 628), .init(x: 790, y: 675), .init(x: 908, y: 675),
    .init(x: 909, y: 668)
]

private func makePath(_ points: [Point]) -> CGPath {
    let path = CGMutablePath()
    guard let first = points.first else { return path }
    path.move(to: CGPoint(x: first.x, y: first.y))
    points.dropFirst().forEach { path.addLine(to: CGPoint(x: $0.x, y: $0.y)) }
    path.closeSubpath()
    return path
}

private func drawColorIcon(in context: CGContext) {
    context.addPath(makePath(avatar))
    context.setFillColor(CGColor(red: 0.835, green: 0.451, blue: 0.322, alpha: 1))
    context.fillPath()

    context.addPath(makePath(pulse))
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fillPath()
}

private func drawTemplateIcon(in context: CGContext) {
    let combined = CGMutablePath()
    combined.addPath(makePath(avatar))
    combined.addPath(makePath(pulse))
    context.addPath(combined)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fillPath(using: .evenOdd)
}

private func writePNG(size: Int, url: URL, template: Bool = false) throws {
    guard let bitmap = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "ClaudePulseIcon", code: 1)
    }

    bitmap.clear(CGRect(x: 0, y: 0, width: size, height: size))
    bitmap.interpolationQuality = .high
    bitmap.setShouldAntialias(true)
    bitmap.translateBy(x: 0, y: CGFloat(size))
    let scale = CGFloat(size) / canvas
    bitmap.scaleBy(x: scale, y: -scale)

    if template {
        drawTemplateIcon(in: bitmap)
    } else {
        drawColorIcon(in: bitmap)
    }

    guard let image = bitmap.makeImage()
    else {
        throw NSError(domain: "ClaudePulseIcon", code: 2)
    }

    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ClaudePulseIcon", code: 2)
    }

    try data.write(to: url, options: .atomic)
}

private func writeTemplatePDF(url: URL) throws {
    var mediaBox = CGRect(origin: .zero, size: menuCanvas)
    guard let consumer = CGDataConsumer(url: url as CFURL),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
    else {
        throw NSError(domain: "ClaudePulseIcon", code: 3)
    }

    context.beginPDFPage(nil)
    context.translateBy(x: -160, y: menuCanvas.height + 303)
    context.scaleBy(x: 1, y: -1)
    drawTemplateIcon(in: context)
    context.endPDFPage()
    context.closePDF()
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Sources/ClaudePulse/Resources", isDirectory: true)
let docs = root.appendingPathComponent("docs", isDirectory: true)
let temporary = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("claudepulse-icon.iconset", isDirectory: true)

try? FileManager.default.removeItem(at: temporary)
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)

let iconFiles: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in iconFiles {
    try writePNG(size: size, url: temporary.appendingPathComponent(name))
}

try writePNG(size: 1024, url: docs.appendingPathComponent("claudepulse-icon.png"))
try writePNG(size: 256, url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("claudepulse-menu-template-preview.png"), template: true)
try writeTemplatePDF(url: resources.appendingPathComponent("ClaudePulseMenuTemplate.pdf"))

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c", "icns",
    temporary.path,
    "-o", resources.appendingPathComponent("ClaudePulse.icns").path
]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "ClaudePulseIcon", code: Int(process.terminationStatus))
}
