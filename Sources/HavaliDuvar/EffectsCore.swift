import SwiftUI

private func rnd(_ i: Int, _ k: Int) -> Double {
    let x = sin(Double(i &* 127 &+ k &* 311)) * 43758.5453
    return x - floor(x)
}

// MARK: - Ayarlar

/// Tek bir efekt: açık/kapalı + şiddet (0...1)
struct Eff: Codable, Equatable {
    var on: Bool
    var amount: Double
}

enum Particle: String, CaseIterable, Identifiable, Codable {
    case petals, sparkles, rain, snow, fireflies, embers
    var id: String { rawValue }
    var title: String {
        switch self {
        case .petals: "Sakura yaprakları"
        case .sparkles: "Parıltılar"
        case .rain: "Yağmur"
        case .snow: "Kar"
        case .fireflies: "Ateş böcekleri"
        case .embers: "Kıvılcımlar"
        }
    }
    var icon: String {
        switch self {
        case .petals: "leaf"
        case .sparkles: "sparkles"
        case .rain: "cloud.rain"
        case .snow: "snowflake"
        case .fireflies: "light.max"
        case .embers: "flame"
        }
    }
}

struct EffectConfig: Codable, Equatable {
    // Karakter
    var breathe = Eff(on: true, amount: 0.5)
    var wave = Eff(on: true, amount: 0.5)
    var sway = Eff(on: false, amount: 0.5)
    var float = Eff(on: false, amount: 0.5)
    var pulse = Eff(on: false, amount: 0.4)
    var jitter = Eff(on: false, amount: 0.3)
    var glitch = Eff(on: false, amount: 0.5)
    var glow = Eff(on: false, amount: 0.5)
    // Arka plan / sahne
    var parallax = Eff(on: true, amount: 0.5)
    var bgZoom = Eff(on: true, amount: 0.5)
    var hue = Eff(on: false, amount: 0.4)
    var vignette = Eff(on: true, amount: 0.4)
    var sweep = Eff(on: false, amount: 0.5)
    var grain = Eff(on: false, amount: 0.3)
    // Parçacıklar
    var particles: Set<Particle> = [.petals]
    var particleAmount = 0.5
    // Genel
    var speed = 1.0

    static var calm: EffectConfig {
        var c = EffectConfig()
        c.wave.amount = 0.25; c.breathe.amount = 0.4; c.speed = 0.7
        c.particles = [.petals]; c.particleAmount = 0.35
        return c
    }
    static var dynamic: EffectConfig {
        var c = EffectConfig()
        c.sway.on = true; c.float.on = true; c.glow.on = true; c.pulse.on = true; c.sweep.on = true
        c.wave.amount = 0.6; c.speed = 1.2
        c.particles = [.sparkles, .embers]; c.particleAmount = 0.6
        return c
    }
    static var cyber: EffectConfig {
        var c = EffectConfig()
        c.glitch = Eff(on: true, amount: 0.7); c.jitter = Eff(on: true, amount: 0.4)
        c.hue = Eff(on: true, amount: 0.7); c.grain = Eff(on: true, amount: 0.4)
        c.wave.on = false; c.sweep.on = true
        c.particles = [.rain]; c.particleAmount = 0.6; c.speed = 1.1
        return c
    }
    static var allOff: EffectConfig {
        var c = EffectConfig()
        for kp in [\EffectConfig.breathe, \.wave, \.parallax, \.bgZoom, \.vignette] { c[keyPath: kp].on = false }
        c.particles = []
        return c
    }
}

// MARK: - Sahne geneli efektler (karakterden bağımsız)

func drawScreenFX(_ g: inout GraphicsContext, _ s: CGSize, _ t: Double, _ cfg: EffectConfig) {
    let full = Path(CGRect(origin: .zero, size: s))

    if cfg.sweep.on {
        let ph = (t * 0.15).truncatingRemainder(dividingBy: 1.7) - 0.35
        let x0 = ph * s.width, bw = s.width * 0.2, skew = s.height * 0.3
        var p = Path()
        p.move(to: CGPoint(x: x0, y: 0)); p.addLine(to: CGPoint(x: x0 + bw, y: 0))
        p.addLine(to: CGPoint(x: x0 + bw - skew, y: s.height)); p.addLine(to: CGPoint(x: x0 - skew, y: s.height))
        p.closeSubpath()
        var c = g
        c.blendMode = .plusLighter
        c.fill(p, with: .linearGradient(
            Gradient(colors: [.clear, .white.opacity(0.18 * cfg.sweep.amount * 2), .clear]),
            startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x0 + bw, y: 0)))
    }

    if cfg.vignette.on {
        g.fill(full, with: .radialGradient(
            Gradient(colors: [.clear, .black.opacity(min(0.9, 0.9 * cfg.vignette.amount * 1.6))]),
            center: CGPoint(x: s.width / 2, y: s.height / 2),
            startRadius: min(s.width, s.height) * 0.3, endRadius: hypot(s.width, s.height) * 0.55))
    }

    drawParticles(&g, s, t, cfg)

    if cfg.grain.on {
        let seed = Int(t * 18)
        let n = Int(700 * cfg.grain.amount * 2)
        for i in 0..<n {
            let x = rnd(i, seed) * s.width, y = rnd(i, seed + 7) * s.height
            let light = rnd(i, seed + 13) > 0.5
            g.fill(Path(CGRect(x: x, y: y, width: 2, height: 2)),
                   with: .color((light ? Color.white : Color.black).opacity(0.14)))
        }
    }
}

// MARK: - Parçacıklar

func drawParticles(_ g: inout GraphicsContext, _ s: CGSize, _ t: Double, _ cfg: EffectConfig) {
    let mult = 0.3 + cfg.particleAmount * 1.4
    for kind in cfg.particles.sorted(by: { $0.rawValue < $1.rawValue }) {
        switch kind {
        case .petals:
            for i in 0..<Int(36 * mult) {
                let size = 6 + rnd(i, 3) * 9
                let x = (rnd(i, 1) * s.width + sin(t * 0.6 + Double(i)) * 40 + t * 18).truncatingRemainder(dividingBy: s.width)
                let y = (rnd(i, 2) * (s.height + 60) + t * (35 + rnd(i, 4) * 50)).truncatingRemainder(dividingBy: s.height + 60) - 30
                var c = g
                c.translateBy(x: x, y: y)
                c.rotate(by: .radians(t * (0.4 + rnd(i, 5)) + Double(i)))
                c.fill(Path(ellipseIn: CGRect(x: -size, y: -size * 0.55, width: size * 2, height: size * 1.1)),
                       with: .color(Color(red: 1, green: 0.72 + rnd(i, 6) * 0.15, blue: 0.82).opacity(0.85)))
            }
        case .sparkles:
            var c = g
            c.blendMode = .plusLighter
            for i in 0..<Int(70 * mult) {
                let x = rnd(i, 1) * s.width, y = rnd(i, 2) * s.height
                let tw = max(0, sin(t * (0.8 + rnd(i, 3) * 1.8) + rnd(i, 4) * 6.28))
                let r = (3 + rnd(i, 5) * 9) * tw
                if r < 0.5 { continue }
                var p = Path()
                p.move(to: CGPoint(x: x, y: y - r)); p.addLine(to: CGPoint(x: x + r * 0.2, y: y - r * 0.2))
                p.addLine(to: CGPoint(x: x + r, y: y)); p.addLine(to: CGPoint(x: x + r * 0.2, y: y + r * 0.2))
                p.addLine(to: CGPoint(x: x, y: y + r)); p.addLine(to: CGPoint(x: x - r * 0.2, y: y + r * 0.2))
                p.addLine(to: CGPoint(x: x - r, y: y)); p.addLine(to: CGPoint(x: x - r * 0.2, y: y - r * 0.2))
                p.closeSubpath()
                c.fill(p, with: .color(.white.opacity(0.9 * tw)))
            }
        case .rain:
            for i in 0..<Int(120 * mult) {
                let x = rnd(i, 1) * s.width
                let y = (rnd(i, 2) * (s.height + 80) + t * 900 * (0.7 + rnd(i, 3) * 0.6)).truncatingRemainder(dividingBy: s.height + 80) - 40
                var p = Path(); p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x - 6, y: y + 26))
                g.stroke(p, with: .color(.white.opacity(0.28)), lineWidth: 1)
            }
        case .snow:
            for i in 0..<Int(90 * mult) {
                let r = 1.5 + rnd(i, 3) * 3.5
                let x = (rnd(i, 1) * s.width + sin(t * 0.5 + Double(i)) * 30).truncatingRemainder(dividingBy: s.width)
                let y = (rnd(i, 2) * (s.height + 20) + t * (25 + rnd(i, 4) * 45)).truncatingRemainder(dividingBy: s.height + 20) - 10
                g.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                       with: .color(.white.opacity(0.55 + rnd(i, 5) * 0.4)))
            }
        case .fireflies:
            var c = g
            c.blendMode = .plusLighter
            for i in 0..<Int(40 * mult) {
                let cx = rnd(i, 1) * s.width + sin(t * 0.3 + Double(i) * 1.7) * 90
                let cy = rnd(i, 2) * s.height + cos(t * 0.23 + Double(i) * 2.3) * 60
                let blink = max(0, sin(t * (0.7 + rnd(i, 3)) + rnd(i, 4) * 6.28))
                let r = 5 + rnd(i, 5) * 9
                let col = Color(red: 0.85, green: 1, blue: 0.4)
                c.fill(Path(ellipseIn: CGRect(x: cx - r * 2, y: cy - r * 2, width: r * 4, height: r * 4)),
                       with: .radialGradient(Gradient(colors: [col.opacity(0.9 * blink), col.opacity(0)]),
                                             center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r * 2))
            }
        case .embers:
            var c = g
            c.blendMode = .plusLighter
            for i in 0..<Int(50 * mult) {
                let r = 1.2 + rnd(i, 3) * 2.6
                let x = (rnd(i, 1) * s.width + sin(t * 0.9 + Double(i)) * 35).truncatingRemainder(dividingBy: s.width)
                let travel = s.height + 40
                let y = s.height + 20 - (rnd(i, 2) * travel + t * (50 + rnd(i, 4) * 90)).truncatingRemainder(dividingBy: travel)
                let flick = 0.5 + 0.5 * sin(t * 6 + Double(i))
                c.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                       with: .color(Color(red: 1, green: 0.55 + rnd(i, 6) * 0.3, blue: 0.15).opacity(0.5 + 0.5 * flick)))
            }
        }
    }
}

