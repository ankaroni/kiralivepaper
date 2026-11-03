import SwiftUI

@main
struct HavaliDuvarApp: App {
    init() {
        DispatchQueue.main.async { WallpaperController.shared.start() }
    }

    var body: some Scene {
        MenuBarExtra("HavaliDuvar", systemImage: "moon.stars.fill") {
            MenuContent()
        }
        Window("HavaliDuvar Efektleri", id: "fx") {
            SettingsView()
        }
        .defaultSize(width: 560, height: 820)
    }
}

struct MenuContent: View {
    @ObservedObject private var c = WallpaperController.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Durum: \(c.statusText)")
        Divider()
        Button((c.kind == .depth ? "✓  " : "     ") + "Anime Derinlik (fare ile)") {
            if c.photoURLs.isEmpty { c.pickPhotos(then: .depth) } else { c.kind = .depth }
        }
        Menu("Ekran koruyucu başlasın: \(c.saverIdleMinutes == 0 ? "Asla" : "\(c.saverIdleMinutes) dk sonra")") {
            ForEach([0, 1, 2, 5, 10, 15, 30], id: \.self) { m in
                Button((c.saverIdleMinutes == m ? "✓  " : "     ") + (m == 0 ? "Asla" : "\(m) dakika")) { c.setSaverIdle(minutes: m) }
            }
        }
        Button("Ekran Koruyucuyu Şimdi Başlat") { c.startSaverNow() }
        Toggle("Ekran koruyucuda saat göster", isOn: $c.saverClock.enabled)
        Menu("Saat konumu: \(SaverClockSettings.positions.first { $0.id == c.saverClock.position }?.title ?? "")") {
            ForEach(SaverClockSettings.positions, id: \.id) { p in
                Button((c.saverClock.position == p.id ? "✓  " : "     ") + p.title) { c.saverClock.position = p.id }
            }
            Divider()
            Toggle("24 saat biçimi", isOn: $c.saverClock.use24h)
            Toggle("Saniyeyi göster", isOn: $c.saverClock.showSeconds)
        }
        Button("Ekran Koruyucuyu Güncelle") { c.exportSaverAssets() }
        if !c.saverStatus.isEmpty { Text(c.saverStatus) }
        Button("Efektleri Düzenle…") {
            openWindow(id: "fx")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Anime Fotoğraflarını Değiştir…") { c.pickPhotos(then: c.kind == .photos ? .photos : .depth) }
        Divider()
        Button((c.kind == .photos ? "✓  " : "     ") + "Düz Fotoğraf Gösterisi") {
            if c.photoURLs.isEmpty { c.pickPhotos(then: .photos) } else { c.kind = .photos }
        }
        ForEach(Kind.allCases.filter { ![.video, .photos, .depth].contains($0) }) { k in
            Button((c.kind == k ? "✓  " : "     ") + k.title) { c.kind = k }
        }
        Button((c.kind == .video ? "✓  " : "     ") + "Kendi Videom…") { c.pickVideo() }
        Divider()
        Button(c.userPaused ? "Devam Et" : "Duraklat") { c.userPaused.toggle() }
        Menu("Pencere önündeyken duraklat: \(c.pauseMode.title)") {
            ForEach(PauseMode.allCases) { m in
                Button((c.pauseMode == m ? "✓  " : "     ") + m.title) { c.pauseMode = m }
            }
        }
        Toggle("Pilde otomatik duraklat", isOn: $c.pauseOnBattery)
        Toggle("Girişte başlat", isOn: $c.launchAtLogin)
        Divider()
        Button("Çıkış") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
