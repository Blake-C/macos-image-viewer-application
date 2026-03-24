#!/usr/bin/env swift
// Generates AppIcon.icns for ImageViewer
import AppKit
import CoreGraphics

func drawIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { img.unlockFocus(); return img }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.22

    // Rounded rect clip
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    // Gradient background: deep blue-purple
    let colors = [
        CGColor(red: 0.13, green: 0.18, blue: 0.38, alpha: 1),
        CGColor(red: 0.22, green: 0.10, blue: 0.42, alpha: 1)
    ] as CFArray
    let locs: [CGFloat] = [0, 1]
    let space = CGColorSpaceCreateDeviceRGB()
    if let grad = CGGradient(colorsSpace: space, colors: colors, locations: locs) {
        ctx.drawLinearGradient(grad,
            start: CGPoint(x: 0, y: size),
            end:   CGPoint(x: size, y: 0),
            options: [])
    }

    // Subtle inner glow ring
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.07))
    ctx.setLineWidth(size * 0.015)
    ctx.strokePath()

    // --- Camera body ---
    let pad  = size * 0.18
    let camW = size - pad * 2
    let camH = camW * 0.66
    let camX = pad
    let camY = (size - camH) / 2 - size * 0.02
    let camR = size * 0.07

    // Viewfinder bump
    let bumpW = camW * 0.28
    let bumpH = camH * 0.20
    let bumpX = camX + camW * 0.5 - bumpW / 2
    let bumpY = camY + camH - bumpH * 0.5
    let bumpPath = CGMutablePath()
    bumpPath.addRoundedRect(in: CGRect(x: bumpX, y: bumpY, width: bumpW, height: bumpH),
                            cornerWidth: bumpH * 0.4, cornerHeight: bumpH * 0.4)

    // Camera body
    let bodyPath = CGMutablePath()
    bodyPath.addRoundedRect(in: CGRect(x: camX, y: camY, width: camW, height: camH),
                            cornerWidth: camR, cornerHeight: camR)

    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
    ctx.addPath(bumpPath)
    ctx.addPath(bodyPath)
    ctx.fillPath()

    // Lens outer circle
    let lensR  = camH * 0.34
    let lensX  = camX + camW * 0.5
    let lensY  = camY + camH * 0.48
    ctx.setFillColor(CGColor(red: 0.17, green: 0.22, blue: 0.42, alpha: 1))
    ctx.addEllipse(in: CGRect(x: lensX - lensR, y: lensY - lensR, width: lensR*2, height: lensR*2))
    ctx.fillPath()

    // Lens mid ring
    let lensR2 = lensR * 0.75
    ctx.setFillColor(CGColor(red: 0.12, green: 0.16, blue: 0.34, alpha: 1))
    ctx.addEllipse(in: CGRect(x: lensX - lensR2, y: lensY - lensR2, width: lensR2*2, height: lensR2*2))
    ctx.fillPath()

    // Lens inner glass
    let lensR3 = lensR * 0.50
    if let lensGrad = CGGradient(colorsSpace: space,
        colors: [CGColor(red: 0.45, green: 0.62, blue: 0.95, alpha: 1),
                 CGColor(red: 0.18, green: 0.30, blue: 0.70, alpha: 1)] as CFArray,
        locations: [0, 1]) {
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: lensX - lensR3, y: lensY - lensR3, width: lensR3*2, height: lensR3*2))
        ctx.clip()
        ctx.drawRadialGradient(lensGrad,
            startCenter: CGPoint(x: lensX - lensR3*0.2, y: lensY + lensR3*0.2), startRadius: 0,
            endCenter:   CGPoint(x: lensX, y: lensY), endRadius: lensR3,
            options: [.drawsAfterEndLocation])
        ctx.restoreGState()
    }

    // Lens specular highlight
    let specR = lensR3 * 0.35
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.40))
    ctx.addEllipse(in: CGRect(x: lensX - lensR3*0.55 - specR/2,
                              y: lensY + lensR3*0.40 - specR/2,
                              width: specR, height: specR))
    ctx.fillPath()

    img.unlockFocus()
    return img
}

// Sizes required for a macOS .iconset
let sizes: [(Int, String)] = [
    (16,   "icon_16x16"),
    (32,   "icon_16x16@2x"),
    (32,   "icon_32x32"),
    (64,   "icon_32x32@2x"),
    (128,  "icon_128x128"),
    (256,  "icon_128x128@2x"),
    (256,  "icon_256x256"),
    (512,  "icon_256x256@2x"),
    (512,  "icon_512x512"),
    (1024, "icon_512x512@2x"),
]

let iconsetDir = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetDir,
     withIntermediateDirectories: true)

for (px, name) in sizes {
    let img  = drawIcon(size: CGFloat(px))
    let path = "\(iconsetDir)/\(name).png"
    guard let tiff = img.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to write \(path)"); continue
    }
    try! png.write(to: URL(fileURLWithPath: path))
    print("Wrote \(path)")
}

print("Done. Run:  iconutil -c icns AppIcon.iconset")
