import ScreenSaver
import SwiftUI
import AVFoundation

/// Uygulamanın dışa aktardığı katmanları (arka plan + karakter) ve efekt ayarlarını okur.
final class SaverAssets {
    struct Item { let bg: CGImage; let strips: [Strip]; let readyAt: Date }

    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("HavaliDuvar")
    private(set) var count = 0
    private(set) var cfg = EffectConfig()
    private var cache: [Int: Item] = [:]

    init() { reload() }

    func reload() {
        if let d = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
           let m = try? JSONDecoder().decode([String: Int].self, from: d) { count = m["count"] ?? 0 }
        if let d = try? Data(contentsOf: dir.appendingPathComponent("config.json")),
           let c = try? JSONDecoder().decode(EffectConfig.self, from: d) { cfg = c }
    }

    func item(_ i: Int) -> Item? {
        guard count > 0 else { return nil }
        let k = i % count
        if let it = cache[k] { return it }
        guard let src = CGImageSourceCreateWithURL(dir.appendingPathComponent("bg\(k).jpg") as CFURL, nil),
              let bg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        var strips: [Strip] = []
        if let fs = CGImageSourceCreateWithURL(dir.appendingPathComponent("fg\(k).png") as CFURL, nil),
           let fg = CGImageSourceCreateImageAtIndex(fs, 0, nil) { strips = makeStrips(fg) }
        let it = Item(bg: bg, strips: strips, readyAt: Date())
        cache = cache.filter { abs($0.key - k) <= 1 }   // en fazla 3 sahne bellekte
        cache[k] = it
        return it
    }
}

struct SaverRoot: View {
    let assets = SaverAssets()
    @State private var start = Date()
    private let cycle = 20.0, fade = 2.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            Canvas { g, size in
                g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                guard assets.count > 0 else {
                    g.draw(Text("HavaliDuvar uygulamasını açın:\nmenü → Ekran Koruyucuyu Güncelle")
                        .font(.system(size: 22)).foregroundColor(.white),
                           at: CGPoint(x: size.width / 2, y: size.height / 2))
                    return
                }
                let cfg = assets.cfg
                let t = ctx.date.timeIntervalSinceReferenceDate * cfg.speed
                let tau = ctx.date.timeIntervalSince(start)
                let k = Int(tau / cycle), local = tau - Double(k) * cycle
                let pm = cfg.parallax.on ? cfg.parallax.amount * 2 : 0   // fare yok: kendi kendine sallanma
                let ox = sin(t * 0.35) * 0.35 * pm, oy = cos(t * 0.27) * 0.2 * pm

                if let a = assets.item(k) {
                    renderScene(&g, size, bg: a.bg, strips: a.strips, fgReadyAt: a.readyAt,
                                ox: ox, oy: oy, t: t, alpha: 1, cfg: cfg)
                }
                if assets.count > 1, local > cycle - fade, let b = assets.item(k + 1) {
                    renderScene(&g, size, bg: b.bg, strips: b.strips, fgReadyAt: b.readyAt,
                                ox: ox, oy: oy, t: t, alpha: (local - (cycle - fade)) / fade, cfg: cfg)
                }
                drawScreenFX(&g, size, t, cfg)
            }
        }
        .ignoresSafeArea()
    }
}

@objc(HavaliSaverView)
final class HavaliSaverView: ScreenSaverView {
    private var host: NSHostingView<SaverRoot>?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func videoURL() -> URL? {
        let dir = SaverAssets().dir
        guard let mode = try? String(contentsOf: dir.appendingPathComponent("mode.txt"), encoding: .utf8),
              mode.trimmingCharacters(in: .whitespacesAndNewlines) == "video" else { return nil }
        let f = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return f.first { $0.lastPathComponent.hasPrefix("video.") }
    }

    private func setup() {
        animationTimeInterval = 1.0 / 30.0
        if let v = videoURL() {
            // Video modu: ekranı kaplayan, sessiz, döngülü oynatma
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            let q = AVQueuePlayer()
            q.isMuted = true
            looper = AVPlayerLooper(player: q, templateItem: AVPlayerItem(url: v))
            let pl = AVPlayerLayer(player: q)
            pl.videoGravity = .resizeAspectFill
            pl.frame = bounds
            layer?.addSublayer(pl)
            player = q; playerLayer = pl
            q.play()
            return
        }
        let h = NSHostingView(rootView: SaverRoot())
        h.frame = bounds
        h.autoresizingMask = [.width, .height]
        addSubview(h)
        host = h
    }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }

    override func startAnimation() { super.startAnimation(); player?.play() }
    override func stopAnimation() { super.stopAnimation(); player?.pause() }
    override func animateOneFrame() {}            // SwiftUI / AVPlayer kendi çiziyor
    override var hasConfigureSheet: Bool { false }
}
