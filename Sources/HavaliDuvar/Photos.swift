import SwiftUI
import ImageIO

private func rnd(_ i: Int, _ k: Int) -> Double {
    let x = sin(Double(i &* 127 &+ k &* 311)) * 43758.5453
    return x - floor(x)
}

/// Fotoğrafları ekran boyutuna küçülterek yükler, en fazla birkaç tanesini bellekte tutar.
final class PhotoCache {
    static let shared = PhotoCache()
    private var store: [URL: CGImage] = [:]
    private var loading = Set<URL>()
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "havaliduvar.prefetch", qos: .utility)

    func peek(_ u: URL) -> CGImage? { lock.lock(); defer { lock.unlock() }; return store[u] }

    func image(_ u: URL) -> CGImage? {
        if let c = peek(u) { return c }
        guard let img = Self.decode(u) else { return nil }
        lock.lock(); store[u] = img; lock.unlock()
        return img
    }

    func prefetch(_ u: URL) {
        lock.lock()
        if store[u] != nil || loading.contains(u) { lock.unlock(); return }
        loading.insert(u); lock.unlock()
        queue.async { [self] in
            _ = image(u)
            lock.lock(); loading.remove(u); lock.unlock()
        }
    }

    func reset() {
        lock.lock(); store = [:]; loading = []; lock.unlock()
    }

    func trim(keep: Set<URL>) {
        lock.lock(); store = store.filter { keep.contains($0.key) }; lock.unlock()
    }

    static func decode(_ u: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(u as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2880,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}

struct PhotoShowView: View {
    let urls: [URL]
    var displayID: CGDirectDisplayID = 0
    @ObservedObject private var c = WallpaperController.shared
    @State private var start = Date()

    private let cycle = 14.0   // bir fotoğrafın ekranda kalma süresi (sn)
    private let fade = 2.0     // geçiş süresi (sn)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: c.effectivePaused || c.coveredScreens.contains(displayID))) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let tau = ctx.date.timeIntervalSince(start)
            Canvas { g, size in
                g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                guard !urls.isEmpty else { return }
                let n = urls.count
                let k = Int(tau / cycle)
                let idx = k % n
                let local = tau - Double(k) * cycle
                let next = (idx + 1) % n

                PhotoCache.shared.trim(keep: [urls[idx], urls[next]])
                if local > 1 { PhotoCache.shared.prefetch(urls[next]) }

                drawPhoto(&g, size, index: idx, progress: (local + fade) / (cycle + fade), alpha: 1)
                if n > 1 && local > cycle - fade {
                    let a = (local - (cycle - fade)) / fade
                    drawPhoto(&g, size, index: next, progress: (local - cycle + fade) / (cycle + fade), alpha: a)
                }
                drawOverlay(&g, size, t)
            }
        }
        .ignoresSafeArea()
    }

    /// Ken Burns: yavaş zoom + kayma. Her fotoğrafın yönü farklı.
    private func drawPhoto(_ g: inout GraphicsContext, _ size: CGSize, index: Int, progress: Double, alpha: Double) {
        guard let img = PhotoCache.shared.image(urls[index]) else { return }
        let iw = Double(img.width), ih = Double(img.height)
        let fill = max(size.width / iw, size.height / ih)
        let p = min(max(progress, 0), 1)
        let zoom = index % 2 == 0 ? 1.06 + 0.12 * p : 1.18 - 0.12 * p
        let dw = iw * fill * zoom, dh = ih * fill * zoom
        let dirX = rnd(index, 1) * 2 - 1, dirY = rnd(index, 2) * 2 - 1
        let x = -(dw - size.width) / 2 + dirX * (p - 0.5) * (dw - size.width)
        let y = -(dh - size.height) / 2 + dirY * (p - 0.5) * (dh - size.height)
        let rect = CGRect(x: x, y: y, width: dw, height: dh)
        g.drawLayer { l in
            l.opacity = alpha
            l.draw(Image(decorative: img, scale: 1), in: rect)
        }
    }

    func drawOverlay(_ g: inout GraphicsContext, _ s: CGSize, _ t: Double) {
        drawParticles(&g, s, t * c.fx.speed, c.fx)
    }
}
