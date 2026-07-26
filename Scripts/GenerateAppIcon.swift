#!/usr/bin/env swift
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

func renderIcon(size: Int) -> CGImage? {
    let s = CGFloat(size)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let margin = s * 0.06
    let corner = s * 0.22
    let rect = CGRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
    let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    // Amber → deep orange (power / energy)
    let colors = [
        CGColor(srgbRed: 0.72, green: 0.28, blue: 0.05, alpha: 1),
        CGColor(srgbRed: 0.92, green: 0.48, blue: 0.10, alpha: 1),
        CGColor(srgbRed: 0.98, green: 0.68, blue: 0.18, alpha: 1),
        CGColor(srgbRed: 0.65, green: 0.22, blue: 0.04, alpha: 1),
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 0.35, 0.7, 1]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }

    if let highlight = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22),
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0),
        ] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(
            highlight,
            start: CGPoint(x: rect.midX, y: rect.maxY),
            end: CGPoint(x: rect.midX, y: rect.midY),
            options: []
        )
    }

    ctx.restoreGState()

    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.92, blue: 0.75, alpha: 0.45))
    ctx.setLineWidth(max(1.0, s * 0.012))
    ctx.addPath(path)
    ctx.strokePath()

    drawBolt(in: ctx, size: s, bounds: rect)
    return ctx.makeImage()
}

func drawBolt(in ctx: CGContext, size s: CGFloat, bounds: CGRect) {
    let cx = bounds.midX
    let cy = bounds.midY
    let scale = s * 0.001

    // Classic lightning bolt polygon (normalized around center)
    let points: [(CGFloat, CGFloat)] = [
        (0.12, 0.42),
        (-0.18, -0.02),
        (0.02, -0.02),
        (-0.14, -0.42),
        (0.18, 0.02),
        (-0.02, 0.02),
    ]

    ctx.beginPath()
    for (i, p) in points.enumerated() {
        let x = cx + p.0 * s * 0.55
        let y = cy + p.1 * s * 0.55
        if i == 0 {
            ctx.move(to: CGPoint(x: x, y: y))
        } else {
            ctx.addLine(to: CGPoint(x: x, y: y))
        }
    }
    ctx.closePath()

    // Soft shadow
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -s * 0.015),
        blur: s * 0.04,
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35)
    )
    ctx.setFillColor(CGColor(srgbRed: 1, green: 0.98, blue: 0.92, alpha: 0.95))
    ctx.fillPath()
    ctx.restoreGState()

    // Re-path and fill (shadow path was consumed)
    ctx.beginPath()
    for (i, p) in points.enumerated() {
        let x = cx + p.0 * s * 0.55
        let y = cy + p.1 * s * 0.55
        if i == 0 {
            ctx.move(to: CGPoint(x: x, y: y))
        } else {
            ctx.addLine(to: CGPoint(x: x, y: y))
        }
    }
    ctx.closePath()
    ctx.setFillColor(CGColor(srgbRed: 1, green: 0.98, blue: 0.92, alpha: 0.95))
    ctx.fillPath()

    _ = scale
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "GenerateAppIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to write \(url.lastPathComponent)"])
    }
}

func writeICNS(images: [(Int, CGImage)], to url: URL) throws {
    // Build iconset and run iconutil
    let iconset = url.deletingLastPathComponent().appendingPathComponent("AppIcon.iconset")
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    let names: [Int: String] = [
        16: "icon_16x16.png",
        32: "diana.k@example.org",
        64: "ivan.p@example.net",
        128: "icon_128x128.png",
        256: "wendy.h@example.net",
        512: "icon_256x256.png",
        1024: "icon_512x512.png",
    ]
    // Also standard 512@2x naming
    let extra: [Int: String] = [
        32: "icon_32x32.png",
        256: "icon_256x256.png",
        512: "icon_512x512.png",
        1024: "walt.e@example.net",
    ]

    for (size, image) in images {
        if let name = names[size] {
            try writePNG(image, to: iconset.appendingPathComponent(name))
        }
        if let name = extra[size] {
            try writePNG(image, to: iconset.appendingPathComponent(name))
        }
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset.path, "-o", url.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "GenerateAppIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
    }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512, 1024]
var rendered: [(Int, CGImage)] = []
for size in sizes {
    guard let image = renderIcon(size: size) else {
        fputs("Failed to render \(size)px icon\n", stderr)
        exit(1)
    }
    rendered.append((size, image))
}

if let big = rendered.last?.1 {
    try writePNG(big, to: assets.appendingPathComponent("AppIcon-1024.png"))
}

try writeICNS(images: rendered, to: assets.appendingPathComponent("AppIcon.icns"))
print("Wrote Assets/AppIcon.icns and AppIcon-1024.png")
