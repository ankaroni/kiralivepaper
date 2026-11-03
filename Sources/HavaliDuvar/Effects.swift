import SwiftUI

// MARK: - Ayar paneli

struct EffectRow: View {
    let title: String
    let subtitle: String
    @Binding var eff: Eff
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $eff.on) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            if eff.on {
                HStack {
                    Text("Şiddet").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $eff.amount, in: 0...1)
                    Text("%\(Int(eff.amount * 100))").font(.caption).monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct SettingsView: View {
    @ObservedObject private var c = WallpaperController.shared

    var body: some View {
        VStack(spacing: 0) {
            // Canlı önizleme
            Group {
                if let first = c.photoURLs.first {
                    DepthShowView(urls: [first], frame: NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080))
                } else {
                    ZStack { Color.black; Text("Önce bir anime fotoğrafı seçin").foregroundStyle(.white) }
                }
            }
            .frame(height: 190)
            .clipped()

            if let first = c.photoURLs.first {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let st = DepthCache.shared.status(first)
                    Label("Karakter: \(st)", systemImage: st.hasPrefix("ayrıldı") ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(st.hasPrefix("ayrıldı") ? Color.green : Color.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20).padding(.vertical, 6)
                }
            }

            Form {
                Section("Hazır ayarlar") {
                    HStack {
                        Button("Sakin") { c.fx = .calm }
                        Button("Dinamik") { c.fx = .dynamic }
                        Button("Siber (glitch)") { c.fx = .cyber }
                        Button("Hepsini kapat") { c.fx = .allOff }
                        Button("Varsayılan") { c.fx = EffectConfig() }
                    }
                    HStack {
                        Text("Genel hız")
                        Slider(value: $c.fx.speed, in: 0.2...2.5)
                        Text(String(format: "%.1f×", c.fx.speed)).monospacedDigit().frame(width: 44)
                    }
                }
                Section("Karakter efektleri") {
                    EffectRow(title: "Nefes alma", subtitle: "Göğüs yavaşça şişer ve iner", eff: $c.fx.breathe)
                    EffectRow(title: "Dalgalanma", subtitle: "Saç ve kıyafet bayrak gibi kıvrılır", eff: $c.fx.wave)
                    EffectRow(title: "Yalpalama", subtitle: "Gövde yana doğru hafifçe eğilip döner", eff: $c.fx.sway)
                    EffectRow(title: "Süzülme", subtitle: "Karakter havada yukarı aşağı süzülür", eff: $c.fx.float)
                    EffectRow(title: "Kalp atışı", subtitle: "Ritmik küçük zıplamalar", eff: $c.fx.pulse)
                    EffectRow(title: "Titreme", subtitle: "Gergin, hafif seğirme", eff: $c.fx.jitter)
                    EffectRow(title: "Glitch", subtitle: "Aralıklarla RGB kayması ve bozulma", eff: $c.fx.glitch)
                    EffectRow(title: "Parlama", subtitle: "Karakter çevresinde nabız gibi ışık", eff: $c.fx.glow)
                }
                Section("Arka plan ve sahne") {
                    EffectRow(title: "Fare ile derinlik", subtitle: "Fareyi oynatınca katmanlar kayar", eff: $c.fx.parallax)
                    EffectRow(title: "Yavaş yakınlaşma", subtitle: "Arka plan zoom yapar", eff: $c.fx.bgZoom)
                    EffectRow(title: "Renk döngüsü", subtitle: "Renkler yavaşça kayar", eff: $c.fx.hue)
                    EffectRow(title: "Kenar karartma", subtitle: "Sinematik koyu çerçeve", eff: $c.fx.vignette)
                    EffectRow(title: "Işık süpürmesi", subtitle: "Çapraz parlak bir şerit geçer", eff: $c.fx.sweep)
                    EffectRow(title: "Film greni", subtitle: "Eski film tanesi", eff: $c.fx.grain)
                }
                Section("Parçacıklar (birden fazla seçebilirsiniz)") {
                    ForEach(Particle.allCases) { p in
                        Toggle(isOn: Binding(
                            get: { c.fx.particles.contains(p) },
                            set: { on in if on { c.fx.particles.insert(p) } else { c.fx.particles.remove(p) } })) {
                            Label(p.title, systemImage: p.icon)
                        }
                    }
                    HStack {
                        Text("Yoğunluk").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $c.fx.particleAmount, in: 0...1)
                        Text("%\(Int(c.fx.particleAmount * 100))").font(.caption).monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 640, idealHeight: 820)
    }
}
