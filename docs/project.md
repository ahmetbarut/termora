# Termora — Proje Dokümanı

Termora; yalnızca macOS için geliştirilen, native, hızlı ve klavye odaklı bir terminal
uygulaması. Bu doküman, projeyi baştan sona anlatır: mimari, geliştirme, test, sürüm,
yayın ve dağıtım.

> Kısa özet için `README.md`; imzalı otomatik güncelleme için `docs/updates.md`;
> ürün hedefleri için `briefs/1.md`, `briefs/2.md`, `briefs/3.md`.

## İçindekiler

1. [Proje Tanımı](#1-proje-tanımi)
2. [Teknoloji Yığını](#2-teknoloji-yığını)
3. [Mimari](#3-mimari)
4. [Özellikler ve Planlar](#4-özellikler-ve-planlar)
5. [Geliştirme Kurulumu](#5-geliştirme-kurulumu)
6. [Build](#6-build)
7. [Test](#7-test)
8. [Kod Kuralları](#8-kod-kuralları)
9. [Sürüm Yönetimi](#9-sürüm-yönetimi)
10. [Yayın ve Dağıtım](#10-yayın-ve-dağıtım)
11. [Otomatik Güncelleme (Sparkle)](#11-otomatik-güncelleme-sparkle)
12. [Lisanslama](#12-lisanslama)
13. [Gizlilik](#13-gizlilik)
14. [Erişilebilirlik](#14-erişilebilirlik)
15. [Hata Raporlama](#15-hata-raporlama)
16. [Sık Karşılaşılan Sorunlar](#16-sık-karşılaşılan-sorunlar)
17. [Yol Haritası](#17-yol-haritası)

---

## 1. Proje Tanımı

Termora; klasik terminal kullanımını sekmeler, bölünebilir paneller, çalışma alanları
(workspace), SSH yönetimi ve AI asistanı ile daha düzenli hale getirmeyi amaçlayan native
macOS terminalidir.

Temel his: **native, hızlı, sade, güçlü, klavye odaklı** ve gereksiz dikkat dağıtıcılardan
uzak. Terminal alanı her zaman uygulamanın ana odağı olarak kalır; araç çubukları ve
paneller onu gereksiz yere küçültmez.

İlk sürümün hedefi Warp kadar karmaşık bir sistem kurmak değil; günlük kullanıma uygun,
hızlı açılan ve güvenilir bir terminal deneyimi oluşturmaktır.

- **Repo:** <https://github.com/ahmetbarut/termora>
- **Platform:** yalnızca macOS 14 Sonoma ve üzeri
- **Lisans modeli:** Free (sınırsız yerel terminal) + Pro (workspace, SSH, AI, Docker,
  gelişmiş bloklar, oturum geri yükleme). Temel terminal özellikleri ücret duvarının
  arkasında değildir.

## 2. Teknoloji Yığını

| Katman | Seçim |
|---|---|
| Dil | Swift 5 |
| Arayüz | SwiftUI + AppKit köprüleri (`NSViewRepresentable`) |
| Terminal motoru | [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 1.15.0 |
| Mimari | MVVM |
| Veri saklama | UserDefaults + Codable (temel ayarlar/profiller) |
| Hassas bilgiler | macOS Keychain (API anahtarları, lisans anahtarı) |
| Paket yönetimi | Swift Package Manager (SwiftTerm, Sparkle) |
| Test | Swift Testing (`import Testing`), UI testleri XCUITest |
| Güncelleme | Sparkle 2 (imzalı appcast, EdDSA) |
| Minimum sürüm | macOS 14.0 Sonoma |

Notlar:

- macOS 15+ API'leri (`pointerStyle`, `containerBackground(.window)`, yeni `Tab`/
  `TabSection`, `@Entry`, `onModifierKeysChanged`) ve macOS 26 API'leri (Liquid Glass /
  `glassEffect`) **kullanılmaz** — minimum hedef 14.0 korunur.
- Uygulama **sandbox'sız** çalışır (yerel shell başlatabilmek için `ENABLE_APP_SANDBOX = NO`).
  `ENABLE_HARDENED_RUNTIME = YES` korunur (notarization zorunluluğu).
- **Hiçbir ağ erişimi** terminal tarafından yapılmaz; yalnız kullanıcı isteğiyle AI/Sparkle.

## 3. Mimari

### Klasör Düzeni

```text
Termora/
├── App/              Uygulama girişi, menüler, kısayol tek doğruluk kaynağı
├── Models/           Saf modeller (55 Swift dosyası)
├── ViewModels/       Pencere/oturum durumu (Observable)
├── Services/         Shell, oturum, tema, süreç, SSH, AI, lisans, güncelleme
│   └── AI/           AI sağlayıcıları (OpenAI, Anthropic, Ollama)
├── Views/
│   ├── Terminal/     SwiftTerm köprüsü, terminal yüzeyi
│   ├── CommandPalette/
│   ├── Onboarding/
│   ├── Settings/
│   ├── Sidebar/
│   ├── Workspace/
│   ├── AI/
│   └── Support/      Empty/loading/error durumları
├── Extensions/
├── Resources/Themes/ Dahili temalar
└── Config/Info.plist
TermoraTests/          Swift Testing birim testleri
TermoraUITests/        XCUITest UI testleri
```

Xcode projesi `PBXFileSystemSynchronizedRootGroup` (objectVersion 77) kullanır: `Termora/`
veya `TermoraTests/` altına diske yazılan her dosya otomatik derlemeye girer — pbxproj'a
dosya referansı eklenmesine gerek yoktur.

### Temel Tasarım Kararları

- **Terminal ömrü görünüm ömründen bağımsızdır.** `SessionManager`, terminal view'larını
  oturum UUID'siyle cache'ler. Görünüm hiyerarşisi yeniden kurulsa da shell süreci ve
  scrollback yaşar. Bu, SwiftUI'nin görünüm ömrü ile PTY sürecinin ömrünü ayıran kritik
  köprüdür.
- **Panel düzeni özyinelemeli bir binary tree'dir** (`PaneNode`). Sekme içi split'ler
  dikey/yatay ayraçlarla modellenir; bölme/odaklanma/kapatma ağacı dolaşır.
  - `SplitAxis.vertical` = dikey ayraç, paneller yan yana (⌘D)
  - `SplitAxis.horizontal` = yatay ayraç, paneller üst üste (⌘⇧D)
- **Ortam `EnvironmentBuilder` ile kurulur.** SwiftTerm'ün `Terminal.getEnvironmentVariables()`
  kullanılmaz (`LC_TYPE` yazım hatası içerir, PATH/SHELL eklemez).
- **Çıkış kodu `ExitStatus` ile ayrıştırılır.** `processTerminated` delegesine gelen
  `exitCode` ham `waitpid` status'udur.
- **Süreç sonlandırma eskalasyonu:** `terminate()` yalnız shell PID'ine SIGTERM gönderir;
  SIGKILL eskalasyonu `SessionManager`'ın sorumluluğundadır.
- **Aktör izolasyonu:** Proje `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` ve
  `SWIFT_APPROACHABLE_CONCURRENCY = YES` ile derlenir. Bildirimlerin varsayılan izolasyonu
  MainActor'dur. Swift Testing suite'leri yine de açıkça `@MainActor` işaretlenir.

### Veri ve Gizlilik Saklama

- Ayarlar, profiller, workspace'ler, SSH host listesi, saved commands: UserDefaults + Codable.
- API anahtarları, lisans anahtarı: Keychain.
- Terminal çıktısı/geçmişi: yalnızca bellek ve yerel scrollback; buluta gönderilmez.

## 4. Özellikler ve Planlar

### Free

- Sınırsız yerel terminal (zsh, bash, fish)
- Sekmeler ve bölünebilir paneller
- Temalar (dahili + özel içe/dışa aktarım)
- Arama
- Temel profiller

### Pro

- Sınırsız workspace
- SSH yöneticisi (bağlantı durumu, kopunca yeniden bağlanma)
- AI entegrasyonu (OpenAI, Anthropic, uyumlu adresler, yerel Ollama)
- Docker araçları
- Gelişmiş komut blokları
- Oturum geri yükleme
- Özel tema ve profiller

### Komut Blokları

Terminal çıktısı, geleneksel akış görünümüne ek olarak komut blokları olarak gösterilir:
girilen komut, çıktı, başlangıç/bitiş zamanı, çalışma süresi, çıkış kodu, çalışma dizini
ve durum (başarılı/başarısız/devam ediyor). Kopyala, yeniden çalıştır, düzenle, AI ile
açıkla, Markdown dışa aktar. Ayarlardan klasik akış görünümüne geçilebilir.

### Klavye Kısayolları

| Kısayol | İşlev |
|---|---|
| ⌘T / ⌘W | Yeni sekme / sekmeyi kapat |
| ⌘1…⌘9, ⌘⇧], ⌘⇧[ | Sekmeye geç / sonraki / önceki |
| ⌘D / ⌘⇧D / ⌘⇧W | Dikey böl / yatay böl / paneli kapat |
| ⌘⌥ ok tuşları | Komşu panele odaklan |
| ⌘F / ⌘G / ⌘⇧G | Bul / sonraki / önceki eşleşme |
| ⌘, | Ayarlar (Genel, Görünüm, Profiller, Kısayollar, Güncellemeler, Hakkında) |

Kısayollar tek doğruluk kaynağından (menu catalog) türetilir; ayarlar ve menüler arası
drift olmaz.

## 5. Geliştirme Kurulumu

### Önkoşullar

- macOS 14.0+ ve **Xcode 16+**
- **Metal Toolchain** (Xcode içinde ayrı indirilen bileşen) — SwiftTerm 1.15.0 bir `.metal`
  shader içerir; Metal derleyicisi yoksa her build düşer (bkz. [Sorunlar](#16-sık-karşılaşılan-sorunlar)).

```bash
# Metal Toolchain eksikse (bir kez):
xcodebuild -downloadComponent MetalToolchain
```

- Bağımlılıklar (SPM) ilk açılışta Xcode tarafından otomatik çözülür: SwiftTerm, Sparkle.

### Çalıştırma (Xcode)

`Termora.xcodeproj` → `Termora` şeması → ⌘R.

### Çalıştırma (Terminal)

```bash
xcodebuild build -project Termora.xcodeproj -scheme Termora \
  -destination 'platform=macOS' -derivedDataPath /tmp/termora-dd -quiet
open -n /tmp/termora-dd/Build/Products/Debug/Termora.app
```

## 6. Build

Sürüm numaraları iki build setting'de tutulur (`Termora.xcodeproj/project.pbxproj`,
tüm target'larda):

- `MARKETING_VERSION` — kullanıcıya görünen sürüm (örn. `1.0.1`)
- `CURRENT_PROJECT_VERSION` — build numarası (her yayın için artırılır, ör. `2`)

Sürüm bump'ı her iki alanı da (tüm Debug/Release + test target'ları) tutarlı günceller.
Doğrulama:

```bash
grep -c 'MARKETING_VERSION = 1.0.1;' Termora.xcodeproj/project.pbxproj   # beklenen: 6
grep -c 'CURRENT_PROJECT_VERSION = 2;' Termora.xcodeproj/project.pbxproj # beklenen: 6
```

Bir build'in gerçek sürümünü doğrulamak için:

```bash
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  -c "Print :CFBundleVersion" <app>/Contents/Info.plist
```

> Derleme uyarıları: `DangerousCommand.swift`, `AppShortcut.swift`, `SSHHost.swift`
> içinde MainActor izole statik metotların nonisolated bağlamdan çağrısına dair
> concurrency notları görünebilir. Bunlar hata değil, derleme geçer.

## 7. Test

Test framework'ü **Swift Testing** (`import Testing`, `@Test`, `@Suite`, `#expect`).
Tek istisna: `TermoraUITests` hedefi `XCUITest` gerektirir (`XCUIApplication` Swift Testing
ile kullanılamaz).

### Tüm paket (birim + UI)

```bash
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS'
```

### Yalnız birim testleri (hızlı)

```bash
xcodebuild test -project Termora.xcodeproj -scheme Termora \
  -destination 'platform=macOS' -only-testing:TermoraTests
```

### Tek suite

```bash
xcodebuild test -project Termora.xcodeproj -scheme Termora \
  -destination 'platform=macOS' -only-testing:TermoraTests/WorkspaceViewModelTests
```

> **Not:** UI test hedefi her makinede koşmayabilir (bkz. build ortamı kısıtları). Yayın
> kapısı yalnızca `TermoraTests` ile sınırlıdır. TermoraTests tam-suitte flaky olabiliyor;
> şüphede isolate koşun ve baseline ile karşılaştırın.

### Kapsam

Birim testleri: workspace oluşturma/geri yükleme, profil yönetimi, tema ayrıştırma,
ayar saklama, secret maskeleme, riskli komut tespiti, SSH config ayrıştırma, lisans
doğrulama, güncelleme denetleyicisi, pane ağacı geometrisi, komut blokları.

Uyumluluk testi (manuel): `zsh, bash, fish, vim, nano, tmux, ssh, git, docker, npm,
composer, php artisan, htop, Claude Code, Codex CLI, Ollama`.

## 8. Kod Kuralları

- **Dil:** Tüm identifier'lar, tip adları ve kod yorumlarının teknik terimleri İngilizce;
  açıklayıcı yorumlar ve kullanıcıya görünen metinler Türkçe.
- **Arayüz metin dili:** İngilizce öncelikli. Kısa, teknik olarak doğru, yönlendiren;
  belirsiz `OK`/`Yes` butonları kullanılmaz.
- **Commit:** Conventional commit önekleri (`feat:`, `test:`, `fix:`, `chore:`), mesaj
  gövdesi İngilizce ve kısa. Her görev en az bir commit ile biter.
- **Dosya ekleme:** pbxproj düzenlemesi gerekmez (`PBXFileSystemSynchronizedRootGroup`).
  Yalnızca SPM paketi, build setting veya target değişikliklerinde pbxproj'a dokunulur.

## 9. Sürüm Yönetimi

- **Branch:** Geliştirme `issues-sweep`/özellik branch'lerinde; yayınlar `main` üzerinden.
  Yayın öncesi özellik branch'i `main`'e fast-forward merge edilir ve `main` push edilir.
- **Etiketleme:** Her yayın `v<MARKETING_VERSION>` (örn. `v1.0.1`) annotated tag ile
  işaretlenir; tag `main` HEAD'ine atılır.
- **Sürüm bump adımları:**
  1. `MARKETING_VERSION` ve `CURRENT_PROJECT_VERSION`'ı bump et (tüm target'lar).
  2. Build al ve sürümü doğrula.
  3. Commit, `main`'e merge + push.
  4. `v<version>` tag + GitHub release (bkz. [Yayın](#10-yayın-ve-dağıtım)).

## 10. Yayın ve Dağıtım

Dağıtım biçimleri: **notarized DMG**, **Homebrew Cask**, (ileride) Mac App Store.

### Önkoşullar (bir kez)

1. **Developer ID Application** imzalama kimliği (Keychain'de).
2. **Notary credentials** — Apple app-specific password ile Keychain profilini sakla:

   ```bash
   xcrun notarytool store-credentials "termora-notary" \
     --apple-id "<Apple ID>" --team-id "WPLDF8U4M5" \
     --password "<app-specific password>"
   ```

3. **Sparkle EdDSA anahtar çifti** (otomatik güncelleme için, bkz. [bölüm 11](#11-otomatik-güncelleme-sparkle)).

### Otomatik Yayın Pipeline'ı

`scripts/release.sh` uçtan uca pipeline çalıştırır:

```text
preflight (imza + notary profili + sürüm)
  → test (TermoraTests kapısı)
  → archive (Release, Developer ID, manual signing)
  → export (developer-id method)
  → hardened runtime doğrulaması
  → DMG oluştur (UDZO, /Applications link)
  → DMG imzala (timestamp)
  → notarize (DMG'yi Apple'a upload, bekle)
  → staple
  → Gatekeeper + stapler doğrulaması
  → Casks/termora.rb checksum güncelle
```

```bash
./scripts/release.sh            # tam release (notarize dahil)
./scripts/release.sh --no-notarize   # lokal build + imzalı DMG (dağıtılamaz)
```

`--no-notarize` ile üretilen DMG bu Mac'te çalışır ama başka Mac'te Gatekeeper reddeder.

### Adım Adım (manuel/elde app varsa)

App zaten imzalı + notarized ise DMG paketleme:

```bash
APP=…/Termora.app
DMG=build/release/Termora-1.0.1.dmg
mkdir -p build/release/dmg-stage
cp -R "$APP" build/release/dmg-stage/
ln -s /Applications build/release/dmg-stage/Applications
hdiutil create -volname "Termora" -srcfolder build/release/dmg-stage \
  -ov -format UDZO "$DMG" -quiet
codesign --force --sign "Developer ID Application: Ahmet Barut (WPLDF8U4M5)" --timestamp "$DMG"
```

### Cask Güncelleme

`scripts/update-cask.sh`, yayımlanan DMG'den sürüm ve SHA256'yı hesaplayıp `Casks/termora.rb`
içine yazar — bu iki satır **elle düzenlenmez** (uyumsuz checksum `brew install`'ı herkes
için kırar).

```bash
./scripts/update-cask.sh build/release/Termora-1.0.1.dmg
```

Sonra `Casks/termora.rb`'yi `ahmetbarut/homebrew-termora` tap reposuna kopyalayıp push et.

### GitHub Release

```bash
gh release create v1.0.1 build/release/Termora-1.0.1.dmg \
  --target main --title "1.0.1" --notes-file release-notes.md --latest
```

Repo **public** olmalı; aksi halde cask'teki `github.com/ahmetbarut/termora/releases/download/…`
URL'i başkaları için 403 verir.

### Doğrulama

- `spctl -a -vvv -t install <app>` → `accepted`, `source=Notarized Developer ID`
- `codesign -dv --verbose=4 <app>` → `flags=…runtime` (hardened runtime)
- DMG indirilebilirliği (anonim): `curl -sIL <download-url>` → `HTTP/2 200`

## 11. Otomatik Güncelleme (Sparkle)

Termora Sparkle 2 gönderir, ama **sıradan bir build kendini güncellemez**. Güncelleyici
yalnızca app bundle şu iki Info.plist anahtarını taşıyorsa başlar:

| Anahtar | Nedir |
|---|---|
| `SUFeedURL` | appcast.xml'in HTTPS adresi |
| `SUPublicEDKey` | sürümleri imzalayan EdDSA **açık** anahtar |

Tek başına feed, imzası doğrulanamayan bir paketi indirmek demektir; brief 2 bunu yasaklar.
Bu yüzden ikisi birlikte aranır. Eksikse `AppUpdater` hiç başlamaz ve Settings ▸ Updates
durumu dürüstçe söyler.

### Kurulum (bir kez)

```bash
# Sparkle release arşivinden:
./bin/generate_keys            # private key login Keychain'de, public yazdırılır
./bin/generate_appcast releases/  # her DMG'yi private key ile imzalar, appcast.xml üretir
```

```text
INFOPLIST_KEY_SUFeedURL = https://<host>/appcast.xml
INFOPLIST_KEY_SUPublicEDKey = <generate_keys'in yazdığı açık anahtar>
```

appcast'i HTTPS host et (Sparkle plain HTTP reddeder). Private key asla repoya girmez ve
yedeklenmelidir (kayıp = mevcut kurulu kopyalar hiçbir güncellemeyi kabul etmez).

### Gizlilik

Güncelleme kontrolü yalnızca en son sürüm numarasını sorar. Sparkle'ın opsiyonel makine
profili (CPU, model, macOS sürümü) **kapalıdır** ve bu bir ayar değil sabittir
(`UpdaterConfiguration.sendsSystemProfile`). `UpdateController` her ayar değişiminde
yeniden uygular; başka kod yolu bunu açamaz.

## 12. Lisanslama

Brief 2 lisans modeli: **Free** + **Pro**. Temel terminal özellikleri ücret duvarının
arkasında değildir; uygulama gerçek anlamda ücretsiz kullanılabilir.

- **Doğrulama:** imzayla **çevrimdışı** doğrulama; lisans anahtarı Keychain'de tutulur.
- **Pro kapısı:** `ProGate` Pro özelliklerine girişi denetler; Pro kilitli ama görünür
  (kullanıcı özelliği görür, erişim için lisans ister).
- **Model:** ilk sürümde abonelik yerine tek seferlik lisans veya yıllık güncelleme modeli
  değerlendirilir. Lisans satış/distribütör mekanizması (Gumroad/Paddle/Lemon Squeezy
  vb.) ve satıcı açık anahtarının app içine gömülmesi yayın öncesi bağlanmalıdır.

## 13. Gizlilik

Termora gizlilik odaklı tasarlanır.

- Hesap zorunlu değildir.
- Terminal geçmişi buluta gönderilmez.
- Telemetri varsayılan kapalıdır.
- AI yalnızca kullanıcı isteğiyle çağrılır; gönderilecek bağlam kullanıcıya gösterilir.
- API anahtarları Keychain'de tutulur.
- Yerel Ollama kullanımı desteklenir.

Gizlilik sayfası hangi verinin neden işlendiğini açıkça anlatır.

## 14. Erişilebilirlik

- Tüm butonlarda VoiceOver etiketi.
- Yalnızca renkle durum anlatılmaz.
- Klavye focus görünür.
- Kontrast oranları korunur; terminal için yüksek kontrast seçeneği.
- Sistem font büyüklüğü (Dynamic Type) ve hareket (Reduce Motion) tercihleri izlenir.

## 15. Hata Raporlama

İsteğe bağlı çökme raporu sistemi: yalnızca beş alan, gönderim varsayılan **kapalı**.

Raporlarda **bulunmaması gerekenler:** terminal çıktısı, yazılan komutlar, dosya
içerikleri, ortam değişkenleri, API anahtarları, SSH bilgileri.

Yalnızca: uygulama sürümü, macOS sürümü, cihaz mimarisi ve stack trace gibi gerekli
teknik bilgiler.

## 16. Sık Karşılaşılan Sorunlar

### `error: cannot execute tool 'metal' due to missing Metal Toolchain`

SwiftTerm 1.15.0 bir `.metal` shader içerir ve Xcode 26'da Metal derleyicisi ayrı indirilen
bir bileşendir. Çözüm:

```bash
xcodebuild -downloadComponent MetalToolchain
```

Bu hatayı kendi kodunuzun hatası sanmayın.

### Build concurrency uyarıları

`DangerousCommand.swift`, `AppShortcut.swift`, `SSHHost.swift` içinde MainActor izole statik
metotların nonisolated bağlamdan çağrısına dair uyarılar normaldir; derlemeyi engellemez.

### UI testleri çalışmıyor

UI test hedefi her makinede koşmayabilir. Yayın kapısı yalnız `TermoraTests`'tir.

### TermoraTests flaky

Tam suite koşumunda flaky davranış görülebilir; şüpheli suite'i isolate koşun ve baseline
ile karşılaştırın.

### `brew install` başkaları için 403

Repo private ise release asset'leri herkese açık değildir. Çözüm: repo'yu public yap.

### Kurulu kopya güncellemiyor

`SUFeedURL`/`SUPublicEDKey` eksikse Sparkle başlamaz; appcast imzalanmamışsa güncelleme
kabul edilmez (bkz. [bölüm 11](#11-otomatik-güncelleme-sparkle)).

## 17. Yol Haritası

### Tamamlandı (1.0)

Terminal çekirdeği, sekmeler, split paneller, komut blokları, workspace, SSH yöneticisi,
AI paneli (OpenAI/Anthropic/Ollama), komut paleti, tema/profil sistemi, sidebar, status bar,
onboarding, ayarlar (tüm sekmeler), lisanslama (Free/Pro), çökme raporu, durum tasarımları,
erişilebilirlik, ses sistemi, küçük pencere davranışı, imzalı Sparkle güncelleme altyapısı.

### Bekleyen

- Sparkle appcast'inin etkinleştirilmesi (`SUFeedURL`/`SUPublicEDKey` + appcast host).
- Homebrew tap reposunun (`ahmetbarut/homebrew-termora`) yayınlanması.
- DMG'nin kendisinin notarize+staple edilmesi (notary profili kurunca `release.sh` full).
- Lisans satış/distribütör mekanizmasının bağlanması.
- Mac App Store dağıtımı (ilerleyen dönem).