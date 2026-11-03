import SwiftUI

/// Karakter katmanının yatay şeridi (dalga efekti için)
struct Strip {
    let img: CGImage
    let y0: Double   // şeridin kaynak resimdeki üst kenarı (piksel)
}

/// Karakter katmanını yatay şeritlere böler (bir kez yapılır).
func makeStrips(_ img: CGImage, count: Int = 72) -> [Strip] {
    let ih = Double(img.height), iw = img.width
    var out: [Strip] = []
    for j in 0..<count {
        let y0 = Int(Double(j) * ih / Double(count))
        let y1 = min(Int(Double(j + 1) * ih / Double(count)) + 1, img.height)  // +1: şeritler arası çizgi kalmasın
        if let c = img.cropping(to: CGRect(x: 0, y: y0, width: iw, height: y1 - y0)) {
            out.append(Strip(img: c, y0: Double(y0)))
        }
    }
    return out
}

private func rnd(_ i: Int, _ k: Int) -> Double {
    let x = sin(Double(i &* 127 &+ k &* 311)) * 43758.5453
    return x - floor(x)
}

/// Bir sahneyi (arka plan + efektli karakter) çizer. Uygulama ve ekran koruyucu ortak kullanır.
func renderScene(_ g: inout GraphicsContext, _ size: CGSize, bg: CGImage, strips: [Strip], fgReadyAt: Date?,
                 ox: Double, oy: Double, t: Double, alpha: Double, cfg: EffectConfig) {
    let iw = Double(bg.width), ih = Double(bg.height)
    let zoom = cfg.bgZoom.on ? 1 + cfg.bgZoom.amount * 0.08 * (0.5 + 0.5 * sin(t * 0.15)) : 1
    let scale = max(size.width / iw, size.height / ih) * 1.12 * zoom
    let w = iw * scale, h = ih * scale
    let baseX = (size.width - w) / 2, baseY = (size.height - h) / 2
    let ui = size.width / 1920   // ekran boyutuna göre ölçek

    g.drawLayer { l in
        l.opacity = alpha
        if cfg.hue.on { l.addFilter(.hueRotation(.degrees(sin(t * 0.2) * cfg.hue.amount * 90))) }
        l.draw(Image(decorative: bg, scale: 1),
               in: CGRect(x: baseX - ox * 12, y: baseY - oy * 8, width: w, height: h))

        guard !strips.isEmpty else { return }
        let fadeIn = min(1, Date().timeIntervalSince(fgReadyAt ?? Date()) / 1.0)
        l.opacity = alpha * fadeIn

        var c2 = l
        let cx = size.width / 2, bottom = baseY + h
        // 1) süzülme + titreme (konum)
        var jx = 0.0, jy = 0.0
        if cfg.float.on { jy += sin(t * 0.7) * cfg.float.amount * 28 * ui }
        if cfg.jitter.on {
            let seed = Int(t * 24)
            jx += (rnd(seed, 1) - 0.5) * cfg.jitter.amount * 8 * ui
            jy += (rnd(seed, 2) - 0.5) * cfg.jitter.amount * 8 * ui
        }
        c2.translateBy(x: jx, y: jy)
        // 2) kalp atışı: ekran merkezinden hafif büyüme
        if cfg.pulse.on {
            let beat = pow(max(0, sin(t * 3.2)), 8)
            let ps = 1 + 0.03 * cfg.pulse.amount * 2 * beat
            c2.translateBy(x: cx, y: size.height / 2); c2.scaleBy(x: ps, y: ps); c2.translateBy(x: -cx, y: -size.height / 2)
        }
        // 3) nefes alma: alt kenardan dikey genleşme
        if cfg.breathe.on {
            let b = sin(t * 1.1)
            let by = 1 + 0.03 * cfg.breathe.amount * 2 * b
            let bx = 1 + 0.006 * cfg.breathe.amount * 2 * b
            c2.translateBy(x: cx, y: bottom); c2.scaleBy(x: bx, y: by); c2.translateBy(x: -cx, y: -bottom)
        }

        let fx = baseX + ox * 26, fy = baseY + oy * 16
        let burst = cfg.glitch.on && t.truncatingRemainder(dividingBy: 4) < 0.25
        let burstSeed = Int(t * 20)

        func drawStrips(_ ctx: inout GraphicsContext, shift: Double, bands: Bool) {
            for (j, s) in strips.enumerated() {
                let yRel = s.y0 / ih
                var dx = 0.0
                if cfg.wave.on {
                    let wv = sin(yRel * 11 - t * 1.5) + 0.45 * sin(yRel * 29 + t * 2.4)
                    let envelope = 0.55 + 0.45 * abs(yRel - 0.5) * 2
                    dx += wv * cfg.wave.amount * 18 * ui * envelope
                }
                if cfg.sway.on { dx += sin(t * 0.9) * cfg.sway.amount * 44 * ui * (1 - yRel) }
                if bands && rnd(j, burstSeed) > 0.82 { dx += (rnd(j, burstSeed + 1) - 0.5) * cfg.glitch.amount * 180 * ui }
                ctx.draw(Image(decorative: s.img, scale: 1),
                         in: CGRect(x: fx + dx + shift, y: fy + yRel * h, width: w, height: Double(s.img.height) * scale))
            }
        }

        drawStrips(&c2, shift: 0, bands: burst)
        if burst {
            for (col, sh) in [(Color.red, -8.0), (Color.cyan, 8.0)] {
                var c3 = c2
                c3.blendMode = .plusLighter
                c3.opacity = alpha * fadeIn * 0.55
                c3.addFilter(.colorMultiply(col))
                drawStrips(&c3, shift: sh * cfg.glitch.amount * 2 * ui, bands: true)
            }
        }
        if cfg.glow.on {
            var c4 = c2
            c4.blendMode = .plusLighter
            c4.opacity = alpha * fadeIn * 0.28 * cfg.glow.amount * 2 * (0.5 + 0.5 * sin(t * 1.3))
            drawStrips(&c4, shift: 0, bands: false)
        }
    }
}
