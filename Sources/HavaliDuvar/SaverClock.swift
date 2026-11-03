import SwiftUI

/// Ekran koruyucudaki saat ayarları. Uygulama yazar (clock.json), ekran koruyucu okur.
struct SaverClockSettings: Codable, Equatable {
    var enabled = true
    var position = "center"      // center, bottom, bottomLeft, bottomRight, topLeft, topRight
    var use24h = true
    var showSeconds = false
    var scale = 1.0
    var style = "zarif"          // zarif, ince, flip, dikey, dijital, neon, klasik
    var color = "gold"           // white, gold, cyan, pink, green, orange

    init() {}
    // Eski dosyalarda olmayan alanlar varsayılan kalsın
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        position = try c.decodeIfPresent(String.self, forKey: .position) ?? "center"
        use24h = try c.decodeIfPresent(Bool.self, forKey: .use24h) ?? true
        showSeconds = try c.decodeIfPresent(Bool.self, forKey: .showSeconds) ?? false
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        style = try c.decodeIfPresent(String.self, forKey: .style) ?? "zarif"
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "gold"
    }

    static let positions: [(id: String, title: String)] = [
        ("center", "Ortada"), ("bottom", "Altta ortada"), ("bottomLeft", "Sol altta"),
        ("bottomRight", "Sağ altta"), ("topLeft", "Sol üstte"), ("topRight", "Sağ üstte"),
    ]
    static let styles: [(id: String, title: String)] = [
        ("zarif", "Zarif (Didot)"), ("ince", "İnce modern"), ("flip", "Flip kart"),
        ("dikey", "Dikey dev"), ("dijital", "Dijital (mono)"), ("neon", "Neon"), ("klasik", "Klasik (Copperplate)"),
    ]
    static let colors: [(id: String, title: String)] = [
        ("white", "Beyaz"), ("gold", "Altın"), ("cyan", "Turkuaz"), ("pink", "Pembe"), ("green", "Yeşil"), ("orange", "Turuncu"),
    ]

    var accent: Color {
        switch color {
        case "gold": Color(hue: 0.11, saturation: 0.50, brightness: 1)
        case "cyan": Color(hue: 0.50, saturation: 0.55, brightness: 1)
        case "pink": Color(hue: 0.93, saturation: 0.50, brightness: 1)
        case "green": Color(hue: 0.38, saturation: 0.55, brightness: 1)
        case "orange": Color(hue: 0.06, saturation: 0.65, brightness: 1)
        default: .white
        }
    }
}

/// Saatin çizimi: zaman dışarıdan verilir (test ve canlı kullanım için)
struct ClockFace: View {
    let s: SaverClockSettings
    let date: Date
    let base: CGFloat
    let align: HorizontalAlignment

    private func fmt(_ f: String) -> String {
        let df = DateFormatter(); df.locale = Locale(identifier: "tr_TR"); df.dateFormat = f
        return df.string(from: date)
    }
    private var hh: String { fmt(s.use24h ? "HH" : "h") }
    private var mm: String { fmt("mm") }
    private var ss: String { fmt("ss") }
    private var timeText: String { hh + ":" + mm + (s.showSeconds ? ":" + ss : "") }
    private var dateLong: String { fmt("EEEE, d MMMM") }
    private var acc: Color { s.accent }
    private var tintGradient: LinearGradient {
        LinearGradient(colors: [.white, s.color == "white" ? Color.white.opacity(0.85) : acc], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        switch s.style {
        case "ince": ince
        case "flip": flip
        case "dikey": dikey
        case "dijital": dijital
        case "neon": neon
        case "klasik": klasik
        default: zarif
        }
    }

    // Didot: ince-kalın kontrastlı zarif serif, süslü ayraç
    private var zarif: some View {
        VStack(alignment: align, spacing: base * 0.07) {
            Text(timeText).font(.custom("Didot", size: base * 1.0)).tracking(base * 0.02).foregroundStyle(tintGradient)
            HStack(spacing: base * 0.07) {
                Rectangle().fill(acc.opacity(0.7)).frame(width: base * 0.55, height: 1)
                Image(systemName: "diamond.fill").font(.system(size: base * 0.07)).foregroundStyle(acc)
                Rectangle().fill(acc.opacity(0.7)).frame(width: base * 0.55, height: 1)
            }
            Text(dateLong).font(.custom("Didot-Italic", size: base * 0.22)).foregroundStyle(acc)
        }
    }

    // Helvetica Neue UltraLight: dev, cam gibi ince
    private var ince: some View {
        VStack(alignment: align, spacing: base * 0.05) {
            Text(timeText).font(.custom("HelveticaNeue-UltraLight", size: base * 1.2)).foregroundStyle(tintGradient)
            HStack(spacing: base * 0.08) {
                Capsule().fill(acc).frame(width: base * 0.22, height: max(2, base * 0.025))
                Text(dateLong.uppercased()).font(.custom("HelveticaNeue-Medium", size: base * 0.15)).tracking(base * 0.035)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    // Flip kart: DIN Alternate rakamlar, ortadan bölünmüş kartlar
    private var flip: some View {
        let w = base * 0.58, h = base * 0.9
        func card(_ d: Character) -> some View {
            ZStack {
                RoundedRectangle(cornerRadius: base * 0.08, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.10)], startPoint: .top, endPoint: .bottom))
                Text(String(d)).font(.custom("DINAlternate-Bold", size: base * 0.78)).foregroundStyle(Color(white: 0.95))
                // üst yarı parlaması + orta ayırıcı
                VStack(spacing: 0) {
                    Rectangle().fill(.white.opacity(0.05)).frame(height: h / 2)
                    Spacer(minLength: 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: base * 0.08, style: .continuous))
                Rectangle().fill(.black.opacity(0.85)).frame(height: max(2, base * 0.025))
                HStack { Circle().fill(.black.opacity(0.9)).frame(width: base * 0.045); Spacer(); Circle().fill(.black.opacity(0.9)).frame(width: base * 0.045) }
                    .padding(.horizontal, -base * 0.02)
            }
            .frame(width: w, height: h)
            .shadow(color: .black.opacity(0.5), radius: base * 0.05, y: base * 0.03)
        }
        return VStack(alignment: align, spacing: base * 0.16) {
            HStack(spacing: base * 0.12) {
                HStack(spacing: base * 0.05) { ForEach(Array(hh.count == 1 ? "0" + hh : hh), id: \.self) { card($0) } }
                VStack(spacing: base * 0.18) { Circle().fill(acc).frame(width: base * 0.07); Circle().fill(acc).frame(width: base * 0.07) }
                HStack(spacing: base * 0.05) { ForEach(Array(mm), id: \.self) { card($0) } }
                if s.showSeconds {
                    VStack(spacing: base * 0.18) { Circle().fill(acc).frame(width: base * 0.07); Circle().fill(acc).frame(width: base * 0.07) }
                    HStack(spacing: base * 0.05) { ForEach(Array(ss), id: \.self) { card($0) } }
                }
            }
            Text(dateLong.uppercased()).font(.custom("AvenirNext-Medium", size: base * 0.15)).tracking(base * 0.04).foregroundStyle(acc)
        }
    }

    // Dikey: saat ve dakika alt alta dev rakamlar
    private var dikey: some View {
        VStack(alignment: align, spacing: -base * 0.2) {
            Text(hh.count == 1 ? "0" + hh : hh).font(.custom("AvenirNext-UltraLight", size: base * 1.3)).foregroundStyle(.white)
            Text(mm).font(.custom("AvenirNext-UltraLight", size: base * 1.3)).foregroundStyle(tintGradient)
            Text(dateLong.uppercased()).font(.custom("AvenirNext-DemiBold", size: base * 0.14)).tracking(base * 0.05)
                .foregroundStyle(acc).padding(.top, base * 0.3)
        }
    }

    // Dijital: Menlo, yanıp sönen ayraç, terminal havası
    private var dijital: some View {
        let colon = Int(date.timeIntervalSince1970) % 2 == 0 ? ":" : " "
        let t = hh + colon + mm + (s.showSeconds ? colon + ss : "")
        return VStack(alignment: align, spacing: base * 0.1) {
            Text(t).font(.custom("Menlo-Regular", size: base * 0.85)).foregroundStyle(acc)
                .shadow(color: acc.opacity(0.7), radius: base * 0.06)
            HStack(spacing: base * 0.06) {
                Text(">").foregroundStyle(acc)
                Text(dateLong.lowercased()).foregroundStyle(.white.opacity(0.85))
                Text("_").foregroundStyle(acc).opacity(Int(date.timeIntervalSince1970) % 2 == 0 ? 1 : 0)
            }
            .font(.custom("Menlo-Regular", size: base * 0.17))
        }
    }

    // Neon: Futura, çok katmanlı parıltı
    private var neon: some View {
        let glow = s.color == "white" ? Color(hue: 0.55, saturation: 0.5, brightness: 1) : acc
        return VStack(alignment: align, spacing: base * 0.08) {
            Text(timeText).font(.custom("Futura-Medium", size: base * 0.95)).foregroundStyle(.white)
                .shadow(color: glow, radius: base * 0.03)
                .shadow(color: glow, radius: base * 0.10)
                .shadow(color: glow.opacity(0.8), radius: base * 0.28)
            Text(dateLong.uppercased()).font(.custom("Futura-Medium", size: base * 0.16)).tracking(base * 0.05)
                .foregroundStyle(glow).shadow(color: glow, radius: base * 0.06)
        }
    }

    // Copperplate: klasik, geniş harf aralıklı
    private var klasik: some View {
        VStack(alignment: align, spacing: base * 0.12) {
            Rectangle().fill(acc.opacity(0.8)).frame(width: base * 1.9, height: 1)
            Text(timeText).font(.custom("Copperplate-Light", size: base * 0.95)).tracking(base * 0.05).foregroundStyle(tintGradient)
            Text(dateLong.uppercased()).font(.custom("Copperplate", size: base * 0.15)).tracking(base * 0.06).foregroundStyle(acc)
            Rectangle().fill(acc.opacity(0.8)).frame(width: base * 1.9, height: 1)
        }
    }
}

/// Büyük saat ve tarih. Fotoğraf ve video modlarının üzerine biner.
struct SaverClockView: View {
    let s: SaverClockSettings

    private var frameAlignment: Alignment {
        switch s.position {
        case "bottom": .bottom
        case "bottomLeft": .bottomLeading
        case "bottomRight": .bottomTrailing
        case "topLeft": .topLeading
        case "topRight": .topTrailing
        default: .center
        }
    }
    private var textAlignment: HorizontalAlignment {
        switch s.position {
        case "bottomLeft", "topLeft": .leading
        case "bottomRight", "topRight": .trailing
        default: .center
        }
    }

    var body: some View {
        if s.enabled {
            GeometryReader { g in
                let base = min(g.size.height * 0.22, g.size.width * 0.13) * s.scale
                let period: Double = (s.showSeconds || s.style == "dijital") ? 1 : 5
                TimelineView(.periodic(from: .now, by: period)) { ctx in
                    ClockFace(s: s, date: ctx.date, base: base, align: textAlignment)
                        .shadow(color: .black.opacity(s.style == "neon" ? 0 : 0.5), radius: max(2, base * 0.07), y: base * 0.02)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
                        .padding(base * 0.45)
                }
            }
            .allowsHitTesting(false)
        }
    }
}
