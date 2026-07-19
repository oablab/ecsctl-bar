// Generate ecsctl Bar app icon: dark bg + fleet status rows (green dot + bar).
import AppKit
import CoreGraphics

func drawIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError() }

    let s = size
    let inset = s * 0.10
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225

    // Background: GitHub-dark navy gradient
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.clip()
    let colors = [
        CGColor(red: 0x1C / 255, green: 0x27 / 255, blue: 0x33 / 255, alpha: 1),
        CGColor(red: 0x0D / 255, green: 0x11 / 255, blue: 0x17 / 255, alpha: 1),
    ] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.minY),
                           options: [])

    // Fleet rows: status dot + name bar
    let green = CGColor(red: 0x3F / 255, green: 0xB9 / 255, blue: 0x50 / 255, alpha: 1)
    let red = CGColor(red: 0xF8 / 255, green: 0x51 / 255, blue: 0x49 / 255, alpha: 1)
    let fg = CGColor(red: 0xC9 / 255, green: 0xD1 / 255, blue: 0xD9 / 255, alpha: 0.92)
    let dim = CGColor(red: 0xC9 / 255, green: 0xD1 / 255, blue: 0xD9 / 255, alpha: 0.45)

    let contentX = rect.minX + rect.width * 0.17
    let contentW = rect.width * 0.66
    let dotR = rect.height * 0.042
    let barH = rect.height * 0.055
    let gap = rect.height * 0.145
    var y = rect.maxY - rect.height * 0.26

    let rows: [(CGColor, CGFloat, CGColor)] = [
        (green, 0.88, fg),
        (green, 0.68, dim),
        (green, 0.80, fg),
        (red,   0.58, dim),
        (green, 0.74, fg),
    ]
    for (dot, wf, barColor) in rows {
        // status dot
        ctx.setFillColor(dot)
        ctx.fillEllipse(in: CGRect(x: contentX, y: y - dotR + barH / 2,
                                   width: dotR * 2, height: dotR * 2))
        // name bar
        ctx.setFillColor(barColor)
        let barX = contentX + dotR * 2 + rect.width * 0.05
        ctx.addPath(CGPath(roundedRect: CGRect(x: barX, y: y, width: contentW * wf, height: barH),
                           cornerWidth: barH * 0.5, cornerHeight: barH * 0.5, transform: nil))
        ctx.fillPath()
        y -= gap
    }

    img.unlockFocus()
    return img
}

let sizes: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

for (px, name) in sizes {
    let img = drawIcon(size: CGFloat(px))
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { continue }
    rep.size = NSSize(width: px, height: px)
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("iconset written to \(outDir)")
