import SwiftUI

/// Deterministik sözde rastgele sayı (0...1): her kare aynı yıldız/küre konumları çıkar.
private func rnd(_ i: Int, _ k: Int) -> Double {
    let x = sin(Double(i &* 127 &+ k &* 311)) * 43758.5453
    return x - floor(x)
}

struct AnimationView: View {
    let kind: Kind
    var displayID: CGDirectDisplayID = 0
    @ObservedObject private var c = WallpaperController.shared

    var body: some View {
        // 30 fps sınırı + duraklatılınca zamanlayıcı tamamen durur (CPU ≈ 0)
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: c.effectivePaused || c.coveredScreens.contains(displayID))) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                switch kind {
                case .stars: drawStars(&g, size, t)
                case .particles: drawParticles(&g, size, t)
                default: drawWaves(&g, size, t)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func background(_ g: inout GraphicsContext, _ s: CGSize, _ top: Color, _ bottom: Color) {
        g.fill(Path(CGRect(origin: .zero, size: s)),
               with: .linearGradient(Gradient(colors: [top, bottom]),
                                     startPoint: .zero, endPoint: CGPoint(x: s.width * 0.3, y: s.height)))
    }

    // MARK: Yıldızlı gökyüzü
    private func drawStars(_ g: inout GraphicsContext, _ s: CGSize, _ t: Double) {
        background(&g, s, Color(red: 0.02, green: 0.03, blue: 0.12), Color(red: 0.16, green: 0.06, blue: 0.28))
        for i in 0..<240 {
            let r = 0.5 + rnd(i, 3) * 1.6
            let speed = 1.5 + r * 2.5
            var x = rnd(i, 1) * s.width + t * speed
            x = x.truncatingRemainder(dividingBy: s.width)
            let y = rnd(i, 2) * s.height
            let tw = 0.5 + 0.5 * sin(t * (0.6 + rnd(i, 4) * 2.2) + rnd(i, 5) * 6.28)
            let a = 0.25 + 0.75 * tw
            g.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                   with: .color(.white.opacity(a)))
        }
        // Kayan yıldız (her 8 sn'de bir)
        let cycle = 8.0
        let ph = t.truncatingRemainder(dividingBy: cycle)
        if ph < 1.1 {
            let k = Int(t / cycle)
            let p = ph / 1.1
            let sx = s.width * (0.2 + 0.6 * rnd(k, 7)), sy = s.height * (0.05 + 0.35 * rnd(k, 8))
            let dx = s.width * 0.18, dy = s.height * 0.12
            let head = CGPoint(x: sx + dx * p, y: sy + dy * p)
            let tail = CGPoint(x: head.x - dx * 0.35, y: head.y - dy * 0.35)
            var path = Path(); path.move(to: tail); path.addLine(to: head)
            g.stroke(path, with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(1 - p)]),
                                                 startPoint: tail, endPoint: head), lineWidth: 2)
        }
    }

    // MARK: Parıldayan küreler
    private func drawParticles(_ g: inout GraphicsContext, _ s: CGSize, _ t: Double) {
        background(&g, s, Color(red: 0.03, green: 0.07, blue: 0.16), Color(red: 0.07, green: 0.03, blue: 0.20))
        g.blendMode = .plusLighter
        for i in 0..<60 {
            let r = 25 + rnd(i, 1) * 90
            let speed = 12 + rnd(i, 2) * 30
            let travel = s.height + r * 2
            let y = s.height + r - (rnd(i, 3) * travel + t * speed).truncatingRemainder(dividingBy: travel)
            let x = rnd(i, 4) * s.width + sin(t * 0.25 + Double(i)) * 50
            let color = Color(hue: 0.5 + rnd(i, 5) * 0.4, saturation: 0.7, brightness: 1)
            let center = CGPoint(x: x, y: y)
            g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                   with: .radialGradient(Gradient(colors: [color.opacity(0.45), color.opacity(0)]),
                                         center: center, startRadius: 0, endRadius: r))
        }
    }

    // MARK: Gradyan dalgalar
    private func drawWaves(_ g: inout GraphicsContext, _ s: CGSize, _ t: Double) {
        background(&g, s, Color(red: 0.98, green: 0.45, blue: 0.40), Color(red: 0.30, green: 0.12, blue: 0.55))
        let layers: [(Double, Double, Double, Double, Color)] = [
            (0.55, 60, 0.0035, 0.45, Color(red: 1.0, green: 0.7, blue: 0.5)),
            (0.65, 50, 0.0045, -0.35, Color(red: 0.85, green: 0.35, blue: 0.65)),
            (0.75, 45, 0.0030, 0.30, Color(red: 0.45, green: 0.20, blue: 0.75)),
            (0.85, 35, 0.0050, -0.25, Color(red: 0.15, green: 0.10, blue: 0.40)),
        ]
        for (i, l) in layers.enumerated() {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: s.height))
            var x = 0.0
            while x <= s.width + 8 {
                let y = s.height * l.0 + l.1 * sin(x * l.2 + t * l.3 + Double(i) * 1.7)
                p.addLine(to: CGPoint(x: x, y: y))
                x += 8
            }
            p.addLine(to: CGPoint(x: s.width, y: s.height))
            p.closeSubpath()
            g.fill(p, with: .color(l.4.opacity(0.75)))
        }
    }
}
