// Generates the app icon artwork at 1024×1024 as a PNG using CoreGraphics.
// Run:  swift Resources/make-icon.swift /tmp/icon_1024.png
// The .icns is then assembled from this PNG via sips + iconutil (see build-app.sh).
import CoreGraphics
import ImageIO
import Foundation

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/icon_1024.png"

let N = 1024
let n = CGFloat(N)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: N, height: N, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no context")
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}

// macOS-style rounded square with a small transparent margin.
let inset: CGFloat = n * 0.085
let rect = CGRect(x: inset, y: inset, width: n - 2 * inset, height: n - 2 * inset)
let radius = rect.width * 0.2237
let rr = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Soft drop shadow for the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -n * 0.012), blur: n * 0.03,
              color: color(0, 0, 0, 0.35))
ctx.addPath(rr)
ctx.setFillColor(color(0.06, 0.09, 0.25))
ctx.fillPath()
ctx.restoreGState()

// Clip to the tile and paint the gradient + highlights + curve.
ctx.saveGState()
ctx.addPath(rr)
ctx.clip()

// Vertical gradient: deep indigo (top) -> royal blue -> cyan (bottom).
let bgColors = [color(0.063, 0.090, 0.247),
                color(0.141, 0.278, 0.839),
                color(0.122, 0.714, 0.847)] as CFArray
let bgGrad = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0.0, 0.55, 1.0])!
ctx.drawLinearGradient(bgGrad,
                       start: CGPoint(x: rect.midX, y: rect.maxY),
                       end: CGPoint(x: rect.midX, y: rect.minY),
                       options: [])

// Top-left glossy highlight.
let hiCenter = CGPoint(x: rect.minX + rect.width * 0.30, y: rect.maxY - rect.height * 0.20)
let hiGrad = CGGradient(colorsSpace: cs,
                        colors: [color(1, 1, 1, 0.22), color(1, 1, 1, 0)] as CFArray,
                        locations: [0, 1])!
ctx.drawRadialGradient(hiGrad, startCenter: hiCenter, startRadius: 0,
                       endCenter: hiCenter, endRadius: rect.width * 0.75, options: [])

// Helper: point from fractions within the tile (fy measured from the TOP).
func P(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
    CGPoint(x: rect.minX + fx * rect.width, y: rect.maxY - fy * rect.height)
}

let baseF: CGFloat = 0.70   // baseline (axis) height fraction from top
let topF: CGFloat = 0.30    // passband flat-top fraction from top

// Faint frequency grid.
ctx.setLineWidth(n * 0.004)
ctx.setStrokeColor(color(1, 1, 1, 0.10))
for fx in stride(from: CGFloat(0.22), through: 0.78, by: 0.14) {
    ctx.move(to: P(fx, 0.22)); ctx.addLine(to: P(fx, baseF))
}
ctx.strokePath()

// Baseline / frequency axis.
ctx.setLineWidth(n * 0.007)
ctx.setStrokeColor(color(1, 1, 1, 0.38))
ctx.move(to: P(0.13, baseF)); ctx.addLine(to: P(0.87, baseF))
ctx.strokePath()

// Band-pass response curve (the "mesa": skirt up, flat passband, skirt down).
let A = P(0.16, baseF)
let B = P(0.34, baseF)
let C = P(0.42, topF)
let D = P(0.58, topF)
let E = P(0.66, baseF)
let F = P(0.84, baseF)

let curve = CGMutablePath()
curve.move(to: A)
curve.addLine(to: B)
curve.addCurve(to: C, control1: P(0.39, baseF), control2: P(0.39, topF))
curve.addLine(to: D)
curve.addCurve(to: E, control1: P(0.61, topF), control2: P(0.61, baseF))
curve.addLine(to: F)

// Filled passband area under the curve.
let area = curve.mutableCopy()!
area.addLine(to: A)
area.closeSubpath()
ctx.addPath(area)
ctx.setFillColor(color(1, 1, 1, 0.16))
ctx.fillPath()

// Glowing curve stroke.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: n * 0.03, color: color(0.55, 0.95, 1.0, 0.9))
ctx.addPath(curve)
ctx.setStrokeColor(color(1, 1, 1, 0.98))
ctx.setLineWidth(n * 0.030)
ctx.setLineJoin(.round)
ctx.setLineCap(.round)
ctx.strokePath()
ctx.restoreGState()

// Passband corner markers.
for p in [C, D] {
    let r = n * 0.014
    ctx.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
}
ctx.setFillColor(color(1, 1, 1, 1))
ctx.fillPath()

ctx.restoreGState()

// Subtle inner rim for definition.
ctx.saveGState()
ctx.addPath(rr)
ctx.setStrokeColor(color(1, 1, 1, 0.16))
ctx.setLineWidth(n * 0.006)
ctx.strokePath()
ctx.restoreGState()

// Write PNG.
guard let image = ctx.makeImage() else { fatalError("no image") }
let url = URL(fileURLWithPath: outPath)
let type: CFString
#if canImport(UniformTypeIdentifiers)
type = UTType.png.identifier as CFString
#else
type = "public.png" as CFString
#endif
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
    fatalError("no destination")
}
CGImageDestinationAddImage(dest, image, nil)
if CGImageDestinationFinalize(dest) {
    print("wrote \(outPath)")
} else {
    fatalError("write failed")
}
