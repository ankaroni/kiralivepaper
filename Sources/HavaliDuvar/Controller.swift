import AppKit
import SwiftUI
import AVFoundation
import IOKit.ps
import ServiceManagement
import ImageIO
import UniformTypeIdentifiers

/// Başka bir pencere masaüstünü kapatınca duraklatma kuralı
enum PauseMode: String, CaseIterable, Identifiable {
    case off, anyWindow, mostly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: "Hiçbir zaman"
        case .anyWindow: "Pencere açılınca (ekranın %20'si)"
        case .mostly: "Ekranın çoğu kapanınca (%60)"
        }
    }
    var threshold: Double {
        switch self {
        case .off: 2
        case .anyWindow: 0.20
        case .mostly: 0.60
        }
    }
}

enum Kind: String, CaseIterable, Identifiable {
    case stars, particles, waves, video, photos, depth
    var id: String { rawValue }
    var title: String {
        switch self {
        case .photos: "Anime Fotoğraflarım"
        case .depth: "Anime Derinlik (fare ile)"
        case .stars: "Yıldızlı Gökyüzü"
        case .particles: "Parıldayan Küreler"
        case .waves: "Gradyan Dalgalar"
        case .video: "Kendi Videom"
        }
    }
}

final class VideoNSView: NSView {
    let playerLayer = AVPlayerLayer()
    init(player: AVPlayer) {
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }
}

@MainActor
final class WallpaperController: ObservableObject {
    static let shared = WallpaperController()

    @Published var kind: Kind {
        didSet { UserDefaults.standard.set(kind.rawValue, forKey: "kind"); rebuild(); exportSaverAssets() }
    }
    @Published var fx: EffectConfig {
        didSet {
            if let d = try? JSONEncoder().encode(fx) { UserDefaults.standard.set(d, forKey: "fx") }
            scheduleSaverConfigExport()
        }
    }
    @Published var pauseMode: PauseMode {
        didSet { UserDefaults.standard.set(pauseMode.rawValue, forKey: "pauseMode"); updatePlayback() }
    }
    @Published var userPaused = false { didSet { updatePlayback() } }
    @Published var pauseOnBattery: Bool {
        didSet { UserDefaults.standard.set(pauseOnBattery, forKey: "pauseOnBattery"); updatePlayback() }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch { /* imzasız uygulamada başarısız olabilir */ }
        }
    }
    @Published private(set) var effectivePaused = false
    /// Üzeri pencerelerle kapanmış ekranlar (yalnızca bu ekranların duvar kağıdı durur)
    @Published private(set) var coveredScreens: Set<CGDirectDisplayID> = []
    @Published private(set) var statusText = ""

    private var windows: [NSWindow] = []
    /// Ekran kilitli, uyuyor veya başka kullanıcıya geçildi
    private var screenInactive = false
    private var players: [AVQueuePlayer] = []
    private var playerScreens: [CGDirectDisplayID] = []
    private var loopers: [AVPlayerLooper] = []
    private var timer: Timer?
    private let supportDir = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("HavaliDuvar")

    private var videoURL: URL? {
        let f = (try? FileManager.default.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil)) ?? []
        return f.first { $0.lastPathComponent.hasPrefix("video.") }
    }

    private init() {
        let d = UserDefaults.standard
        kind = Kind(rawValue: d.string(forKey: "kind") ?? "") ?? .stars
        if let data = d.data(forKey: "fx"), let v = try? JSONDecoder().decode(EffectConfig.self, from: data) { fx = v }
        else { fx = EffectConfig() }
        pauseMode = PauseMode(rawValue: d.string(forKey: "pauseMode") ?? "") ?? .anyWindow
        pauseOnBattery = d.object(forKey: "pauseOnBattery") as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Ekran koruyucuya dışa aktarma

    /// Ekran koruyucu kendi güvenlik kutusunda (container) çalışır; yalnızca orayı okuyabilir.
    private var saverDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Application Support/HavaliDuvar")
    }
    private var configExportTask: Task<Void, Never>?
    @Published private(set) var saverStatus = ""
    /// Sistemdeki "Ekran koruyucuyu başlat" süresi (dakika, 0 = asla)
    @Published private(set) var saverIdleMinutes: Int = WallpaperController.readSaverIdle()

    nonisolated private static func defaultsTool(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: d, encoding: .utf8) ?? ""
    }

    nonisolated static func readSaverIdle() -> Int {
        let out = defaultsTool(["-currentHost", "read", "com.apple.screensaver", "idleTime"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (Int(out) ?? 0) / 60
    }

    func setSaverIdle(minutes: Int) {
        _ = Self.defaultsTool(["-currentHost", "write", "com.apple.screensaver", "idleTime", "-int", String(minutes * 60)])
        saverIdleMinutes = Self.readSaverIdle()   // gerçekten yazıldı mı, geri oku
    }

    func startSaverNow() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"))
    }

    private func scheduleSaverConfigExport() {
        configExportTask?.cancel()
        configExportTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let self else { return }
            self.writeSaverConfig()
        }
    }

    private func writeSaverConfig() {
        guard FileManager.default.fileExists(atPath: saverDir.path),
              let d = try? JSONEncoder().encode(fx) else { return }
        try? d.write(to: saverDir.appendingPathComponent("config.json"))
    }

    nonisolated private static func writeImage(_ img: CGImage, to url: URL, type: UTType, quality: Double? = nil) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return false }
        var opts: [CFString: Any] = [:]
        if let q = quality { opts[kCGImageDestinationLossyCompressionQuality] = q }
        CGImageDestinationAddImage(dest, img, opts as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    /// Fotoğrafları karakter/arka plan olarak ayırıp ekran koruyucunun klasörüne yazar.
    func exportSaverAssets() {
        let urls = photoURLs
        let dir = saverDir
        // Video modundaysa ekran koruyucuya videoyu aktar
        if kind == .video, let v = videoURL {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
                where f.lastPathComponent.hasPrefix("video.") { try? FileManager.default.removeItem(at: f) }
                try FileManager.default.copyItem(at: v, to: dir.appendingPathComponent("video." + v.pathExtension))
                try "video".write(to: dir.appendingPathComponent("mode.txt"), atomically: true, encoding: .utf8)
                saverStatus = "Ekran koruyucu hazır (video)"
            } catch { saverStatus = "Video aktarılamadı: \(error.localizedDescription)" }
            return
        }
        guard !urls.isEmpty else { saverStatus = "Önce anime fotoğrafı seçin"; return }
        saverStatus = "Ekran koruyucu hazırlanıyor…"
        let cfgData = try? JSONEncoder().encode(fx)
        Task.detached {
            do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
            catch { await MainActor.run { self.saverStatus = "Klasör oluşturulamadı: \(error.localizedDescription)" }; return }
            for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            where f.lastPathComponent.hasPrefix("bg") || f.lastPathComponent.hasPrefix("fg") { try? FileManager.default.removeItem(at: f) }

            var written = 0
            for (i, u) in urls.enumerated() {
                _ = DepthCache.shared.scene(u)   // ayırmayı başlatır
                var waited = 0.0
                while !(DepthCache.shared.status(u).hasPrefix("ayrıldı") || DepthCache.shared.status(u).hasPrefix("ayrılamadı")) && waited < 90 {
                    try? await Task.sleep(nanoseconds: 300_000_000); waited += 0.3
                }
                guard let sc = DepthCache.shared.scene(u) else { continue }
                if Self.writeImage(sc.bg, to: dir.appendingPathComponent("bg\(i).jpg"), type: .jpeg, quality: 0.9) {
                    written += 1
                    if let fg = sc.fg { _ = Self.writeImage(fg, to: dir.appendingPathComponent("fg\(i).png"), type: .png) }
                }
            }
            if let d = try? JSONEncoder().encode(["count": written]) { try? d.write(to: dir.appendingPathComponent("manifest.json")) }
            try? "photos".write(to: dir.appendingPathComponent("mode.txt"), atomically: true, encoding: .utf8)
            if let c = cfgData { try? c.write(to: dir.appendingPathComponent("config.json")) }
            await MainActor.run { self.saverStatus = written > 0 ? "Ekran koruyucu hazır (\(written) fotoğraf)" : "Hata: dosyalar yazılamadı" }
        }
    }

    private var photosDir: URL { supportDir.appendingPathComponent("photos") }

    var photoURLs: [URL] {
        let f = (try? FileManager.default.contentsOfDirectory(at: photosDir, includingPropertiesForKeys: nil)) ?? []
        return f.filter { !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Fotoğrafları veya bir klasörü seçtirir, uygulamanın kendi klasörüne kopyalar.
    func pickPhotos(then target: Kind = .photos) {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.allowsMultipleSelection = true
        p.canChooseDirectories = true
        p.message = "Anime fotoğraflarını veya içinde olduğu klasörü seçin"
        // Menü çubuğu uygulaması olduğu için pencere arkada kalmasın
        NSApp.activate(ignoringOtherApps: true)
        p.level = .floating
        guard p.runModal() == .OK else { return }
        var files: [URL] = []
        for u in p.urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir)
            if isDir.boolValue {
                let kids = (try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: nil)) ?? []
                files += kids.filter { ["jpg", "jpeg", "png", "heic", "webp", "tiff"].contains($0.pathExtension.lowercased()) }
            } else { files.append(u) }
        }
        guard !files.isEmpty else { return }
        try? FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
        // Yeni adlar benzersiz olsun: önbellek eski resmi dosya adıyla hatırlıyordu
        let old = photoURLs
        let stamp = Int(Date().timeIntervalSince1970)
        var copied = 0
        for (i, f) in files.enumerated() {
            let name = String(format: "p%d_%03d.", stamp, i) + f.pathExtension
            if (try? FileManager.default.copyItem(at: f, to: photosDir.appendingPathComponent(name))) != nil { copied += 1 }
        }
        guard copied > 0 else { return }   // kopyalanamadıysa eski fotoğrafları silme
        for f in old { try? FileManager.default.removeItem(at: f) }
        DepthCache.shared.reset()
        PhotoCache.shared.reset()
        if kind == target { rebuild() } else { kind = target }
        exportSaverAssets()
    }

    func start() {
        if (kind == .photos || kind == .depth) && photoURLs.isEmpty { kind = .stars }
        if kind == .video && videoURL == nil { kind = .stars }
        rebuild()
        exportSaverAssets()   // ekran koruyucu her açılışta güncel kalsın
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updatePlayback() }
        }
        // Kilit ekranı / ekran uykusu / kullanıcı değişimi: boşuna çalışma
        let dnc = DistributedNotificationCenter.default()
        let wnc = NSWorkspace.shared.notificationCenter
        func watch(_ center: NotificationCenter, _ name: Notification.Name, inactive: Bool) {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.screenInactive = inactive; self?.updatePlayback() }
            }
        }
        watch(dnc, Notification.Name("com.apple.screenIsLocked"), inactive: true)
        watch(dnc, Notification.Name("com.apple.screenIsUnlocked"), inactive: false)
        watch(wnc, NSWorkspace.screensDidSleepNotification, inactive: true)
        watch(wnc, NSWorkspace.screensDidWakeNotification, inactive: false)
        watch(wnc, NSWorkspace.sessionDidResignActiveNotification, inactive: true)
        watch(wnc, NSWorkspace.sessionDidBecomeActiveNotification, inactive: false)
        // Başka uygulamaya geçince hemen tepki ver
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updatePlayback() }
        }
    }

    func pickVideo() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        p.canChooseDirectories = false
        guard p.runModal() == .OK, let src = p.url else { return }
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        // Önceki videoyu temizle, yenisini uygulama klasörüne kopyala (izin sorunu olmasın)
        for f in (try? FileManager.default.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil)) ?? []
        where f.lastPathComponent.hasPrefix("video.") { try? FileManager.default.removeItem(at: f) }
        let dest = supportDir.appendingPathComponent("video." + src.pathExtension)
        do { try FileManager.default.copyItem(at: src, to: dest) } catch { return }
        if kind == .video { rebuild(); exportSaverAssets() } else { kind = .video }
    }

    func rebuild() {
        for w in windows { w.orderOut(nil) }
        windows = []
        for p in players { p.pause() }
        players = []
        playerScreens = []
        loopers = []

        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                             backing: .buffered, defer: false, screen: screen)
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            w.isOpaque = true
            w.backgroundColor = .black
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false

            if kind == .video, let url = videoURL {
                let queue = AVQueuePlayer()
                queue.isMuted = true
                loopers.append(AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url)))
                players.append(queue)
                playerScreens.append(screen.displayID)
                w.contentView = VideoNSView(player: queue)
            } else if kind == .depth, !photoURLs.isEmpty {
                w.contentView = NSHostingView(rootView: DepthShowView(urls: photoURLs, frame: screen.frame, displayID: screen.displayID))
            } else if kind == .photos, !photoURLs.isEmpty {
                w.contentView = NSHostingView(rootView: PhotoShowView(urls: photoURLs, displayID: screen.displayID))
            } else {
                w.contentView = NSHostingView(rootView: AnimationView(kind: [.video, .photos, .depth].contains(kind) ? .stars : kind, displayID: screen.displayID))
            }
            w.setFrame(screen.frame, display: true)
            w.orderBack(nil)
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                   object: w, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.updatePlayback() }
            }
            windows.append(w)
        }
        updatePlayback()
    }

    private func onBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeRetainedValue() as String? else { return false }
        return type == kIOPSBatteryPowerValue
    }

    /// Açık pencerelerin ekranı ne kadar kapladığı (0...1), ekran başına ızgara ile ölçülür.
    private func coverage(of screen: NSScreen, windows: [[String: Any]]) -> Double {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return 0 }
        let disp = CGDisplayBounds(id)
        let cols = 48, rows = 30
        var grid = [Bool](repeating: false, count: cols * rows)
        let me = getpid()
        for w in windows {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int).map({ Int32($0) }) != me,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                  let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bd as CFDictionary),
                  frame.width >= 120, frame.height >= 80 else { continue }
            let x = frame.minX, y = frame.minY, wd = frame.width, ht = frame.height
            let r = CGRect(x: x, y: y, width: wd, height: ht).intersection(disp)
            if r.isNull || r.isEmpty { continue }
            for row in 0..<rows {
                let cy = disp.minY + (Double(row) + 0.5) / Double(rows) * disp.height
                if cy < r.minY || cy > r.maxY { continue }
                for col in 0..<cols {
                    let cx = disp.minX + (Double(col) + 0.5) / Double(cols) * disp.width
                    if cx >= r.minX && cx <= r.maxX { grid[row * cols + col] = true }
                }
            }
        }
        return Double(grid.filter { $0 }.count) / Double(cols * rows)
    }

    /// Pencerelerle eşikten fazla kapanmış ekranların kümesi
    private func coveredSet() -> Set<CGDirectDisplayID> {
        guard pauseMode != .off else { return [] }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(NSScreen.screens.filter { coverage(of: $0, windows: list) >= pauseMode.threshold }.map { $0.displayID })
    }

    func updatePlayback() {
        let allHidden = !windows.isEmpty && windows.allSatisfy { !$0.occlusionState.contains(.visible) }
        var reason = ""
        if userPaused { reason = "Duraklatıldı" }
        else if screenInactive { reason = "Ekran kilitli/uykuda: duraklatıldı" }
        else if pauseOnBattery && onBattery() { reason = "Pilde: duraklatıldı" }
        else if ProcessInfo.processInfo.isLowPowerModeEnabled { reason = "Düşük güç modu: duraklatıldı" }
        else if allHidden { reason = "Masaüstü görünmüyor: duraklatıldı" }
        let globalPaused = !reason.isEmpty
        let covered = globalPaused ? [] : coveredSet()
        let all = Set(NSScreen.screens.map { $0.displayID })
        var text = reason
        if reason.isEmpty {
            if !covered.isEmpty && covered == all { text = "Pencere önde: duraklatıldı" }
            else if !covered.isEmpty { text = "Çalışıyor (\(covered.count) ekranda pencere önde: o ekran duraklatıldı)" }
            else { text = "Çalışıyor" }
        }
        // Değer değişmediyse yayınlama: arayüz her saniye boşuna yenilenmesin
        if effectivePaused != globalPaused { effectivePaused = globalPaused }
        if coveredScreens != covered { coveredScreens = covered }
        if statusText != text { statusText = text }
        for (i, p) in players.enumerated() {
            let pause = globalPaused || covered.contains(playerScreens[i])
            pause ? p.pause() : p.play()
        }
    }
}
