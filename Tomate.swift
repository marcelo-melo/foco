import CoreGraphics
import Foundation

/// Forma do tomate (coordenadas com y para baixo), usada no ícone, na janela e na barra de menus.
enum Tomate {
    static func corpo(in r: CGRect) -> CGPath {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        let path = CGMutablePath()
        path.move(to: p(0.5, 0.17))
        path.addCurve(to: p(0.76, 0.09), control1: p(0.57, 0.10), control2: p(0.66, 0.08))
        path.addCurve(to: p(1.0, 0.53), control1: p(0.93, 0.11), control2: p(1.0, 0.30))
        path.addCurve(to: p(0.5, 1.0), control1: p(1.0, 0.83), control2: p(0.76, 1.0))
        path.addCurve(to: p(0.0, 0.53), control1: p(0.24, 1.0), control2: p(0.0, 0.83))
        path.addCurve(to: p(0.24, 0.09), control1: p(0.0, 0.30), control2: p(0.07, 0.11))
        path.addCurve(to: p(0.5, 0.17), control1: p(0.34, 0.08), control2: p(0.43, 0.10))
        path.closeSubpath()
        return path
    }

    static func folhas(in r: CGRect) -> CGPath {
        let c = CGPoint(x: r.midX, y: r.minY + 0.17 * r.height)
        let w = r.width
        let path = CGMutablePath()
        let specs: [(Double, CGFloat)] = [(200, 0.25), (155, 0.19), (340, 0.25), (25, 0.19), (95, 0.08)]
        for (ang, len) in specs {
            let a = ang * .pi / 180
            let d = CGPoint(x: cos(a), y: sin(a))
            let tip = CGPoint(x: c.x + d.x * len * w, y: c.y + d.y * len * w)
            let mid = CGPoint(x: (c.x + tip.x) / 2, y: (c.y + tip.y) / 2)
            let n = CGPoint(x: -d.y * 0.055 * w, y: d.x * 0.055 * w)
            path.move(to: c)
            path.addQuadCurve(to: tip, control: CGPoint(x: mid.x + n.x, y: mid.y + n.y))
            path.addQuadCurve(to: c, control: CGPoint(x: mid.x - n.x, y: mid.y - n.y))
            path.closeSubpath()
        }
        return path
    }

    static func cabo(in r: CGRect) -> CGPath {
        let w = 0.05 * r.width
        return CGPath(roundedRect: CGRect(x: r.midX - w / 2, y: r.minY, width: w, height: 0.18 * r.height),
                      cornerWidth: w / 2, cornerHeight: w / 2, transform: nil)
    }
}
