import AppKit
import CoreGraphics

let size = 1024
let output = CommandLine.arguments[1]
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let s = CGFloat(size)
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

// Background: diagonal violet to coral.
let background = CGGradient(colorsSpace: space, colors: [color(0x4B2BE0), color(0x9A3BE8), color(0xFF5A6E)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

// Soft glow top-left.
let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: s * 0.25, y: s * 0.8), startRadius: 0, endCenter: CGPoint(x: s * 0.25, y: s * 0.8), endRadius: s * 0.6, options: [])

// Flowing ribbons across the lower half.
func ribbon(baseline: CGFloat, amplitude: CGFloat, thickness: CGFloat, phase: CGFloat, alpha: CGFloat) {
    let path = CGMutablePath()
    let steps = 120
    var top: [CGPoint] = [], bottom: [CGPoint] = []
    for i in 0...steps {
        let x = s * CGFloat(i) / CGFloat(steps)
        let t = CGFloat(i) / CGFloat(steps) * .pi * 2 + phase
        let y = baseline + sin(t) * amplitude
        let w = thickness * (0.55 + 0.45 * sin(t * 0.5 + 1))
        top.append(CGPoint(x: x, y: y + w / 2)); bottom.append(CGPoint(x: x, y: y - w / 2))
    }
    path.addLines(between: top)
    path.addLines(between: bottom.reversed())
    path.closeSubpath()
    ctx.addPath(path)
    ctx.setFillColor(color(0xFFFFFF, alpha))
    ctx.fillPath()
}
ribbon(baseline: s * 0.30, amplitude: s * 0.06, thickness: s * 0.10, phase: 0.0, alpha: 0.10)
ribbon(baseline: s * 0.24, amplitude: s * 0.07, thickness: s * 0.07, phase: 1.2, alpha: 0.14)
ribbon(baseline: s * 0.18, amplitude: s * 0.05, thickness: s * 0.05, phase: 2.4, alpha: 0.18)

// Rounded play triangle, optically centered.
let cx = s * 0.53, cy = s * 0.54, r = s * 0.25
let a = CGPoint(x: cx - r * 0.8, y: cy + r)
let b = CGPoint(x: cx - r * 0.8, y: cy - r)
let c = CGPoint(x: cx + r * 1.0, y: cy)
let tri = CGMutablePath()
let corner = s * 0.06
tri.move(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2))
tri.addArc(tangent1End: b, tangent2End: c, radius: corner)
tri.addArc(tangent1End: c, tangent2End: a, radius: corner)
tri.addArc(tangent1End: a, tangent2End: b, radius: corner)
tri.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.05, color: color(0x2A0A6B, 0.45))
ctx.addPath(tri)
ctx.setFillColor(color(0xFFFFFF))
ctx.fillPath()
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote", output)
