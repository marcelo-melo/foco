import AppKit
let S = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
ctx.translateBy(x: 0, y: CGFloat(S)); ctx.scaleBy(x: 1, y: -1)   // y-down
let r = CGRect(x: 92, y: 90, width: 840, height: 840)
let red = CGColor(red: 0.90, green: 0.22, blue: 0.18, alpha: 1)
let green = CGColor(red: 0.25, green: 0.69, blue: 0.31, alpha: 1)
let darkGreen = CGColor(red: 0.18, green: 0.52, blue: 0.24, alpha: 1)
ctx.addPath(Tomato.body(in: r)); ctx.setFillColor(red); ctx.fillPath()
// flat white clock
let c = CGPoint(x: r.midX, y: r.minY + 0.60 * r.height), R = 0.25 * r.width
ctx.setStrokeColor(.white); ctx.setLineCap(.round); ctx.setLineWidth(44)
ctx.addArc(center: c, radius: R, startAngle: -.pi / 2, endAngle: .pi, clockwise: false); ctx.strokePath()
ctx.setLineWidth(40)
ctx.move(to: c); ctx.addLine(to: CGPoint(x: c.x, y: c.y - R * 0.6)); ctx.strokePath()
ctx.move(to: c); ctx.addLine(to: CGPoint(x: c.x + R * 0.45, y: c.y + R * 0.25)); ctx.strokePath()
ctx.addPath(Tomato.stem(in: r)); ctx.setFillColor(darkGreen); ctx.fillPath()
ctx.addPath(Tomato.leaves(in: r)); ctx.setFillColor(green); ctx.fillPath()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
