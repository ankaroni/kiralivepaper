import SwiftUI

/// Ekran koruyucudaki saat ayarları. Uygulama yazar (clock.json), ekran koruyucu okur.
struct SaverClockSettings: Codable, Equatable {
    var enabled = true
    var position = "center"      // center, bottom, bottomLeft, bottomRight, topLeft, topRight
    var use24h = true
    var showSeconds = false
    var scale = 1.0

    static let positions: [(id: String, title: String)] = [
        ("center", "Ortada"), ("bottom", "Altta ortada"), ("bottomLeft", "Sol altta"),
        ("bottomRight", "Sağ altta"), ("topLeft", "Sol üstte"), ("topRight", "Sağ üstte"),
    ]
}

/// Büyük, ince yazılı saat ve tarih. Fotoğraf ve video modlarının üzerine biner.
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

    private func fmt(_ d: Date, _ f: String) -> String {
        let df = DateFormatter(); df.locale = Locale(identifier: "tr_TR"); df.dateFormat = f
        return df.string(from: d)
    }

    var body: some View {
        if s.enabled {
            GeometryReader { g in
                let base = min(g.size.height * 0.22, g.size.width * 0.13) * s.scale
                TimelineView(.periodic(from: .now, by: s.showSeconds ? 1 : 5)) { ctx in
                    VStack(alignment: textAlignment, spacing: base * 0.02) {
                        Text(fmt(ctx.date, (s.use24h ? "HH:mm" : "h:mm") + (s.showSeconds ? ":ss" : "")))
                            .font(.system(size: base, weight: .ultraLight, design: .rounded)).monospacedDigit()
                            .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.82)], startPoint: .top, endPoint: .bottom))
                        Text(fmt(ctx.date, "EEEE, d MMMM").uppercased())
                            .font(.system(size: max(9, base * 0.17), weight: .medium, design: .rounded)).tracking(base * 0.03)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .shadow(color: .black.opacity(0.5), radius: max(2, base * 0.07), y: base * 0.02)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
                    .padding(base * 0.45)
                }
            }
            .allowsHitTesting(false)
        }
    }
}
