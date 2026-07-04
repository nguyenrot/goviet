// Sinh icon GõViệt bằng CoreGraphics — vẽ vector ở từng cỡ pixel nên không mờ.
// Thiết kế: squircle đỏ gradient (chuẩn lưới Big Sur 824/1024), chữ "Gõ" trắng
// SF Rounded, riêng dấu ngã tô vàng (gợi màu cờ).
//
// Chạy:  swift scripts/make-icon.swift <thư-mục-ra>.iconset
// Rồi:   iconutil -c icns <thư-mục-ra>.iconset -o macos/Resources/AppIcon.icns

import AppKit
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let redTop = color(0xE8453C)
let redBottom = color(0xA8150C)
let white = color(0xFFFFFF)
let yellow = color(0xFFD60A)

func roundedFont(size: CGFloat) -> CTFont {
    let base = NSFont.systemFont(ofSize: size, weight: .heavy)
    if let desc = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: desc, size: size) {
        return f
    }
    return base
}

func makeLine(_ str: String, font: CTFont, fill: CGColor) -> CTLine {
    let attrs = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: fill] as CFDictionary
    return CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, str as CFString, attrs))
}

func draw(px: Int, in ctx: CGContext) {
    let s = CGFloat(px) / 1024
    ctx.clear(CGRect(x: 0, y: 0, width: px, height: px))

    // Squircle 824pt giữa canvas 1024pt, có bóng đổ nhẹ.
    let rect = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = CGPath(
        roundedRect: rect, cornerWidth: 184 * s, cornerHeight: 184 * s, transform: nil
    )
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 30 * s, color: color(0x000000, 0.3))
    ctx.addPath(squircle)
    ctx.setFillColor(redBottom)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [redTop, redBottom] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY),
        options: []
    )
    ctx.restoreGState()

    // Chữ "Gõ": đo mực thật (image bounds) để căn giữa, ép rộng ~62% squircle.
    let probe = roundedFont(size: 100)
    ctx.textPosition = .zero
    let probeWidth = CTLineGetImageBounds(makeLine("Gõ", font: probe, fill: white), ctx).width
    let font = roundedFont(size: 100 * (rect.width * 0.62) / probeWidth)

    let whiteLine = makeLine("Gõ", font: font, fill: white)
    ctx.textPosition = .zero
    let ink = CTLineGetImageBounds(whiteLine, ctx)
    // Căn giữa dọc theo thân chữ (cap height) — dấu ngã lơ lửng phía trên
    // không tính vào, nếu không khối chữ nhìn bị tụt xuống.
    let capHeight = CTFontGetCapHeight(font)
    let origin = CGPoint(
        x: rect.midX - ink.midX,
        y: rect.midY - capHeight / 2
    )
    ctx.textPosition = origin
    CTLineDraw(whiteLine, ctx)

    // Tô vàng dấu ngã: vẽ lại "Gõ" màu vàng, clip vùng phía trên x-height và
    // bên phải chữ G — vùng đó chỉ có mỗi dấu ngã.
    let gAdvance = CGFloat(CTLineGetTypographicBounds(makeLine("G", font: font, fill: white), nil, nil, nil))
    let tildeZone = CGRect(
        x: origin.x + gAdvance,
        y: origin.y + CTFontGetXHeight(font) * 1.02,
        width: rect.width,
        height: rect.height
    )
    ctx.saveGState()
    ctx.clip(to: tildeZone)
    ctx.textPosition = origin
    CTLineDraw(makeLine("Gõ", font: font, fill: yellow), ctx)
    ctx.restoreGState()
}

func writePNG(px: Int, to url: URL) {
    let ctx = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    draw(px: px, in: ctx)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

for (name, px) in [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
] {
    writePNG(px: px, to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("✓ iconset: \(outDir)")
