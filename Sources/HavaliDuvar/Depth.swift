import SwiftUI
import Vision
import CoreImage
import AppKit

private func rnd(_ i: Int, _ k: Int) -> Double {
    let x = sin(Double(i &* 127 &+ k &* 311)) * 43758.5453
    return x - floor(x)
}

/// Her fotoğrafı "karakter" ve "arka plan" katmanlarına ayırır (macOS Vision ile, arka planda).
final class DepthCache {
    static let shared = DepthCache()

    struct Scene {
        var bg: CGImage
        var fg: CGImage?
        var strips: [Strip] = []
        var fgReadyAt: Date?
    }

    private var store: [URL: Scene] = [:]
    private var started = Set<URL>()
    private var used: [URL: Date] = [:]
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "havaliduvar.depth", qos: .utility)
    private let ci = CIContext()

    func scene(_ u: URL) -> Scene? {
        lock.lock()
        used[u] = Date()
        if let s = store[u] { lock.unlock(); return s }
        lock.unlock()
        guard let img = PhotoCache.decode(u) else { return nil }
        lock.lock(); store[u] = Scene(bg: img); lock.unlock()
        process(u, img)
        return store[u]
    }

    func prefetch(_ u: URL) {
        queue.async { [self] in _ = scene(u) }
    }

    func reset() {
        lock.lock(); store = [:]; started = []; used = [:]; statuses = [:]; lock.unlock()
    }

    func trim(keep: Set<URL>) {
        // keep kullanılmaz: 45 sn'dir istenmeyen sahneleri bellekten at
        let cutoff = Date().addingTimeInterval(-45)
        lock.lock()
        let old = Set(used.filter { $0.value < cutoff }.keys)
        store = store.filter { !old.contains($0.key) }
        started = started.filter { !old.contains($0) }
        used = used.filter { !old.contains($0.key) }
        lock.unlock()
    }

    private var statuses: [URL: String] = [:]

    func status(_ u: URL) -> String {
        lock.lock(); defer { lock.unlock() }
        return statuses[u] ?? "bekliyor…"
    }

    private func setStatus(_ u: URL, _ msg: String) {
        lock.lock(); statuses[u] = msg; lock.unlock()
        // Hata ayıklama için günlüğe de yaz
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HavaliDuvar")
        let line = "\(Date()) \(u.lastPathComponent): \(msg)\n"
        let f = dir.appendingPathComponent("ayirma.log")
        if let h = try? FileHandle(forWritingTo: f) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(to: f, atomically: true, encoding: .utf8) }
    }

    private func process(_ u: URL, _ img: CGImage) {
        lock.lock()
        if started.contains(u) { lock.unlock(); return }
        started.insert(u); lock.unlock()
        setStatus(u, "ayrılıyor…")
        queue.async { [self] in
            let r = separate(img)
            guard let fg = r.fg, let bg = r.bg else { setStatus(u, r.msg); return }
            let strips = makeStrips(fg)
            lock.lock()
            if store[u] != nil { store[u] = Scene(bg: bg, fg: fg, strips: strips, fgReadyAt: Date()) }
            lock.unlock()
            setStatus(u, r.msg)
        }
    }

    private func separate(_ img: CGImage) -> (fg: CGImage?, bg: CGImage?, msg: String) {
        let handler = VNImageRequestHandler(cgImage: img)
        let req = VNGenerateForegroundInstanceMaskRequest()
        do { try handler.perform([req]) } catch { return (nil, nil, "ayrılamadı: motor hatası (\(error.localizedDescription))") }
        guard let obs = req.results?.first else { return (nil, nil, "ayrılamadı: resimde belirgin bir özne bulunamadı") }
        guard let buf = try? obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler,
                                                     croppedToInstancesExtent: false) else {
            return (nil, nil, "ayrılamadı: maske üretilemedi")
        }
        let fgCI = CIImage(cvPixelBuffer: buf)
        guard let fgCG = ci.createCGImage(fgCI, from: fgCI.extent) else { return (nil, nil, "ayrılamadı: katman çizilemedi") }

        let cov = coverage(of: fgCG)
        let pct = Int(cov * 100)
        if cov < 0.01 { return (nil, nil, "ayrılamadı: özne çok küçük (%\(pct))") }
        if cov > 0.97 { return (nil, nil, "ayrılamadı: özne resmin tamamı (%\(pct))") }

        let orig = CIImage(cgImage: img)
        let blur = orig.clampedToExtent().applyingGaussianBlur(sigma: 28).cropped(to: orig.extent)
        let mask = fgCI.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 8])
        let blended = blur.applyingFilter("CIBlendWithAlphaMask",
                                          parameters: [kCIInputBackgroundImageKey: orig, kCIInputMaskImageKey: mask])
        guard let bgCG = ci.createCGImage(blended, from: orig.extent) else { return (nil, nil, "ayrılamadı: arka plan hazırlanamadı") }
        return (fgCG, bgCG, "ayrıldı (özne resmin %\(pct)'i)")
    }

    private func coverage(of img: CGImage) -> Double {
        let n = 32
        var data = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &data, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: n, height: n))
        var sum = 0
        for i in stride(from: 3, to: data.count, by: 4) { sum += Int(data[i]) }
        return Double(sum) / Double(n * n * 255)
    }
}

/// Fare imlecini yumuşak takip eden değer (sınıf: Canvas içinde güncellenebilsin).
final class MouseSmoother {
    var x = 0.0, y = 0.0
    func update(frame: CGRect) -> (Double, Double) {
        let m = NSEvent.mouseLocation
        let tx = max(-1, min(1, (m.x - frame.midX) / (frame.width / 2)))
        let ty = max(-1, min(1, (frame.midY - m.y) / (frame.height / 2)))
        x += (tx - x) * 0.07
        y += (ty - y) * 0.07
        return (x, y)
    }
}

struct DepthShowView: View {
    let urls: [URL]
    let frame: CGRect
    var displayID: CGDirectDisplayID = 0
    @ObservedObject private var c = WallpaperController.shared
    @State private var start = Date()
    private let mouse = MouseSmoother()

    private let cycle = 20.0
    private let fade = 2.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: c.effectivePaused || c.coveredScreens.contains(displayID))) { ctx in
            let cfg = c.fx
            let t = ctx.date.timeIntervalSinceReferenceDate * cfg.speed
            let tau = ctx.date.timeIntervalSince(start)
            Canvas { g, size in
                g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                guard !urls.isEmpty else { return }
                let n = urls.count
                let k = Int(tau / cycle)
                let idx = k % n, next = (idx + 1) % n
                let local = tau - Double(k) * cycle

                DepthCache.shared.trim(keep: [])
                if local > 2 && n > 1 { DepthCache.shared.prefetch(urls[next]) }

                // Fare + kendi kendine hafif sallanma (fare ile derinlik kapalıysa sabit)
                let m = mouse.update(frame: frame)
                let pm = cfg.parallax.on ? cfg.parallax.amount * 2 : 0
                let ox = (m.0 + sin(t * 0.35) * 0.35) * pm
                let oy = (m.1 + cos(t * 0.27) * 0.2) * pm

                drawScene(&g, size, urls[idx], ox, oy, t, alpha: 1, cfg: cfg)
                if n > 1 && local > cycle - fade {
                    drawScene(&g, size, urls[next], ox, oy, t, alpha: (local - (cycle - fade)) / fade, cfg: cfg)
                }
                drawScreenFX(&g, size, t, cfg)
            }
        }
        .ignoresSafeArea()
    }

    private func drawScene(_ g: inout GraphicsContext, _ size: CGSize, _ url: URL,
                           _ ox: Double, _ oy: Double, _ t: Double, alpha: Double, cfg: EffectConfig) {
        guard let scene = DepthCache.shared.scene(url) else { return }
        renderScene(&g, size, bg: scene.bg, strips: scene.strips, fgReadyAt: scene.fgReadyAt,
                    ox: ox, oy: oy, t: t, alpha: alpha, cfg: cfg)
    }
}
