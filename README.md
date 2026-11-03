# kiralivepaper

**Live wallpaper & screen saver for macOS.** Canlı duvar kağıdı ve ekran koruyucu (SwiftUI). Menü çubuğunda yaşar.

## Özellikler
- **Duvar kağıtları:** Yıldızlı Gökyüzü, Parıldayan Küreler, Gradyan Dalgalar, kendi videonuz, anime fotoğraf gösterisi
- **Anime Derinlik modu:** macOS Vision ile karakter arka plandan ayrılır; fare ile parallax, nefes alma, dalgalanma, yalpalama, glitch, parlama ve daha fazlası; sakura, kıvılcım, yağmur, kar gibi parçacıklar
- **Efekt paneli:** her efekt açılıp kapanır, şiddeti ayarlanır; hazır ayarlar
- **Ekran koruyucu (.saver):** aynı sahne (fotoğraf veya video) kilit sırasında çalışan macOS ekran koruyucusu olarak
- **Akıllı duraklatma:** pencere önde olunca (ekran başına), pilde, düşük güç modunda, ekran kilitliyken
- Masaüstü seviyesinde pencere; tıklamalar geçer

## Derleme
```bash
./build_app.sh     # HavaliDuvar.app
./build_saver.sh   # HavaliDuvar.saver, ~/Library/Screen Savers'a kurar
open HavaliDuvar.app
```
Ekran koruyucuyu Sistem Ayarları → Duvar Kâğıdı → Ekran Koruyucu → Diğer bölümünden seçin.

Gereksinim: macOS 14+, Xcode komut satırı araçları (Swift 5.9+).

## Notlar
- Ekran koruyucu yalnızca kendi güvenlik kutusundaki dosyaları okur; uygulama fotoğraf/video ve efekt ayarlarını oraya otomatik aktarır.
- Uygulama imzasızdır (ad-hoc). İlk açılışta engellenirse: sağ tık → Aç.

## Lisans

MIT, bkz. [LICENSE](LICENSE).
