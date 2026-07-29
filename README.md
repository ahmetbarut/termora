# Termora

macOS için native terminal uygulaması: sekmeler, bölünebilir paneller, arama, temalar ve
profiller. SwiftUI kabuğu + [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 1.15.0.

- Gereksinim: macOS 14.0+, Xcode 16+ (Swift 5, Swift Testing)
- Bağımlılık: SwiftTerm ve Sparkle (SPM, ilk açılışta Xcode kendisi çözer)

## Kurulum

```bash
brew install --cask ahmetbarut/termora/termora
```

Tap henüz yayınlanmadıysa `.dmg` [yayınlar sayfasından](https://github.com/ahmetbarut/termora/releases)
indirilebilir. Cask dosyası depoda `Casks/termora.rb`; sürüm ve SHA256'yı
`scripts/update-cask.sh` yayınlanan DMG'den hesaplayıp yazar — elle düzenlenmez.

Kurulu uygulama kendini Sparkle ile günceller; imzası doğrulanamayan paket kurulmaz.
Kurulum ve anahtar üretimi: [docs/updates.md](docs/updates.md).

## Çalıştırma

Xcode: `Termora.xcodeproj` → `Termora` şeması → ⌘R.

Terminalden:

```bash
xcodebuild build -project Termora.xcodeproj -scheme Termora \
  -destination 'platform=macOS' -derivedDataPath /tmp/termora-dd -quiet
open -n /tmp/termora-dd/Build/Products/Debug/Termora.app
```

## Test

Tüm paket (birim + UI testleri):

```bash
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS'
```

Yalnız birim testleri (hızlı):

```bash
xcodebuild test -project Termora.xcodeproj -scheme Termora \
  -destination 'platform=macOS' -only-testing:TermoraTests
```

Tek bir suite:

```bash
xcodebuild test -project Termora.xcodeproj -scheme Termora \
  -destination 'platform=macOS' -only-testing:TermoraTests/WorkspaceViewModelTests
```

## Kısayollar

| Kısayol | İşlev |
|---|---|
| ⌘T / ⌘W | Yeni sekme / sekmeyi kapat |
| ⌘1…⌘9, ⌘⇧] , ⌘⇧[ | Sekmeye geç / sonraki / önceki |
| ⌘D / ⌘⇧D / ⌘⇧W | Dikey böl / yatay böl / paneli kapat |
| ⌘⌥ ok tuşları | Komşu panele odaklan |
| ⌘F / ⌘G / ⌘⇧G | Bul / sonraki / önceki eşleşme |
| ⌘, | Ayarlar (Genel, Görünüm, Profiller, Kısayollar, Güncellemeler, Hakkında) |

## Klasör düzeni

`Termora/App` uygulama girişi ve menüler · `Termora/Models` saf modeller ·
`Termora/ViewModels` pencere durumu · `Termora/Services` shell, oturum, tema, süreç
sorgulama · `Termora/Views` SwiftUI arayüzü · `TermoraTests` Swift Testing birim testleri.

Not: Uygulama sandbox'sız çalışır (yerel shell başlatabilmesi için) ve hiçbir ağ erişimi
yapmaz.
