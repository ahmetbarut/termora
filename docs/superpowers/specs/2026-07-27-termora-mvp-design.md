# Termora MVP — Tasarım Dokümanı

Tarih: 2026-07-27
Durum: Onaylandı (brainstorming oturumu sonucu)
Kaynak gereksinimler: `brief.md`

## 1. Özet ve Kararlar

Termora, macOS için SwiftUI + SwiftTerm tabanlı native bir terminal uygulamasıdır.
Brainstorming sırasında brief üzerine alınan kararlar:

| Karar | Sonuç |
|---|---|
| Sandbox | **Kapatılacak** (`ENABLE_APP_SANDBOX = NO`). Terminal alt işlemleri sandbox'ı miras alır; sandbox'lı terminal kullanılamaz. Dağıtım: Hardened Runtime + Developer ID notarization, DMG/Homebrew. App Store hedeflenmiyor. |
| Minimum macOS | **14.0 Sonoma** (proje şablonundaki 26.5 düşürülecek). |
| Veri katmanı | **UserDefaults + Codable** (SwiftData değil). Servis katmanı arkasında; 2. fazda SwiftData'ya geçiş mümkün. |
| Profiller | **MVP'ye dahil.** Ayarlar penceresinde CRUD + profille yeni sekme açma. |
| Terminal motoru | **Yaklaşım A: SwiftTerm `LocalProcessTerminalView`** (PTY + emülasyon + resize kütüphanede). SwiftTerm 1.15.0, SPM: `.package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.15.0")`. |

## 2. Doğrulanmış Teknik Zemin

Tasarım, SwiftTerm 1.15.0 kaynak kodunda doğrulanan şu olgulara dayanır:

**Kütüphanenin sağladıkları (yeniden yazılmayacak):**

- `startProcess(executable:args:environment:execName:currentDirectory:)` — çalışma dizini ve login-shell argv[0] (`execName: "-zsh"`) desteği hazır.
- Delegate: `sizeChanged`, `setTerminalTitle`, `hostCurrentDirectoryUpdate`, `processTerminated`.
- PTY resize otomatik (`TIOCSWINSZ`); PTY okuma DispatchIO ile arka planda.
- Arama: `findNext` / `findPrevious` / `searchMatchSummary` ("2/14" sayacı) / `clearSearch`; `SearchOptions(caseSensitive:regex:wholeWord:)`.
- Görünüm: `font`, `nativeForegroundColor/BackgroundColor` (alpha → saydamlık korunur), `installColors(_:)` (tam 16 renk), `caretColor`, `lineSpacing` (çarpan), `getTerminal().setCursorStyle(_:)` (`CursorStyle`: blok/alt çizgi/çubuk × sabit/yanıp sönen), `getTerminal().changeScrollback(_:)` (varsayılan 500).
- Kopyala/yapıştır (`copy`/`paste`/`selectAll`, OSC 52), `allowMouseReporting` (+Shift bypass), `optionAsMetaKey`.

**Bizim yazacaklarımız (kütüphanede yok / hatalı):**

- Ortam kurulumu: SwiftTerm'ün `getEnvironmentVariables`'ında `LC_TYPE` yazım hatası var (LC_CTYPE hiç aynalanmaz) ve PATH/SHELL eklenmez → `ShellService` kendi env'ini kurar.
- Çalışan işlem tespiti: `tcgetpgrp(process.childfd) != process.shellPid` (iki alan da public; kalıp ampirik doğrulandı).
- Exit kodu ayrıştırma: `processTerminated`'a ham `waitpid` status'u gelir → `WIFEXITED`/`WEXITSTATUS`/`WIFSIGNALED` bizde.
- Süreç temizliği: `terminate()` yalnız shell pid'ine SIGTERM atar; SIGTERM → kısa bekleme → SIGKILL eskalasyonu bizde. (Master fd kapanınca çekirdek SIGHUP'ı yalnız oturum liderine iletir — torunlara garantili sinyal yoktur.)
- Varsayılan shell tespiti: `getpwuid_r().pw_shell` (yerelde doğrulandı; GUI uygulamada `SHELL` env bayat olabilir).
- Arama kısıtı: "tüm eşleşmeleri vurgula" public API'si yok; yalnız aktif eşleşme seçim olarak vurgulanır. MVP bunu kabul eder.
- macOS 14 kısıtları: `pointerStyle` (15+) yerine `NSCursor` push/pop; `containerBackground(.window)` (15+) yerine `NSVisualEffectView`; sekme çubuğu elle çizilir.

## 3. Mimari

```text
App katmanı          TermoraApp (WindowGroup + Settings scene), AppCommands (menü/kısayollar)
                          │  @FocusedValue ile odaktaki pencerenin WorkspaceViewModel'ine yönlenir
SwiftUI Views        MainWindowView = TabBarView + PaneTreeView + StatusBarView + SearchBarView
                          │  TerminalHostView (NSViewRepresentable) — yalnız yerleştirir, sahiplenmez
ViewModels           WorkspaceViewModel (sekmeler) → TerminalTab → PaneNode ağacı → TerminalSession
                          │  Observation framework (@Observable, macOS 14+)
Services             SessionManager · ShellService · SettingsStore · ThemeStore · ProfileStore
                          │
SwiftTerm 1.15.0     TermoraTerminalView: LocalProcessTerminalView alt sınıfı
                          │  forkpty → zsh/bash/fish (login shell: execName "-zsh" kalıbı)
```

Yapıyı belirleyen kararlar:

1. **Oturum ömrü ≠ görünüm ömrü.** `SessionManager`, `TermoraTerminalView` örneklerini oturum UUID'siyle cache'te tutar (CodeEdit'te doğrulanan kalıp). SwiftUI representable'ı söküp yeniden kursa da shell süreci ve scrollback yaşar. Sekme/panel kapanınca cache'ten düşer, süreç sonlandırılır.
2. **Sekme/panel modeli binary tree.** `PaneNode = leaf(paneID, sessionID) | split(eksen, oran, iki çocuk)`. Bölme = leaf → split dönüşümü; panel kapatma = kardeşin ebeveyni ikame etmesi. Divider'lı bölme görünümü özel ve hafif bir SwiftUI implementasyonudur (dış paket yok).
3. **Kısayol yönlendirme.** Kısayollar `Commands` API'sinde; `@FocusedValue` yalnız key window'un WorkspaceViewModel'ine ulaştırır. ⌘W: `CommandGroup(replacing: .saveItem)`. Son sekme kapanınca pencere kapanmaz; yerine yeni boş bir sekme açılır (terminal uygulaması konvansiyonu). Pencerenin kendisi kırmızı düğme veya ⌘Q ile kapatılır ve çalışan işlem varsa tek toplu onay istenir.
4. **SwiftTerm sınırı dar tutulur.** Kütüphane pürüzleri `TermoraTerminalView` + `ShellService`/`SessionManager` içinde kapatılır; uygulamanın geri kalanı bunları görmez. İleride özel PTY katmanına (yaklaşım B) geçiş bu sınır içinde kalır.
5. **Ayar akışı tek yönlü.** `SettingsStore` → değişiklik → `SessionManager` açık tüm terminallere uygular. Terminal tarafından ayar yazılmaz.

Klasör yapısı brief'teki öneriye uyar (`App/ Models/ Views/ ViewModels/ Services/ Extensions/ Resources/Themes/`).

## 4. Modeller ve Kalıcılık

| Model | İçerik | Kalıcılık |
|---|---|---|
| `AppSettings` | font adı+boyutu, satır aralığı çarpanı, imleç şekli (6'lı), tema ID, pencere saydamlığı, scrollback sınırı, varsayılan shell, başlangıç klasörü, durum çubuğu açık/kapalı | UserDefaults, tek JSON blob (`settings.v1`) |
| `TerminalProfile` | id, ad, shell, başlangıç klasörü, başlangıç komutu, font/tema override, ek ortam değişkenleri | UserDefaults, JSON dizisi (`profiles.v1`) |
| `Theme` | ad + arka plan/metin/imleç/seçim + 16'lı ANSI paleti (hex) | Salt okunur bundle: `Resources/Themes/*.json` — Termora Dark, Termora Light, Dracula, Nord, Tokyo Night |
| `PaneNode` | `leaf(paneID, sessionID)` \| `split(eksen, oran, iki çocuk)` (indirect enum) | Kalıcı değil (oturum geri yükleme 2. faz) |
| `TerminalTab` | id, başlık (otomatik/elle ayrımıyla), ağaç kökü, aktif panel | Kalıcı değil |
| `TerminalSession` | id, shell yolu, çalışma dizini, süreç durumu (çalışıyor/çıktı(kod)) | Kalıcı değil |

Sekme başlığı öncelik sırası: kullanıcının elle verdiği ad → shell'in OSC ile gönderdiği başlık (`setTerminalTitle`) → çalışma dizininin son bileşeni → shell adı. OSC başlığına bel bağlanmaz: macOS'un stok `zsh` yapılandırması başlık dizisini yalnız `TERM_PROGRAM=Apple_Terminal` iken yayar, Termora ise `TERM_PROGRAM=Termora` gönderir; bu yüzden dizin tabanlı geri düşüş (spec §7'deki "başlıkta aktif klasör") zorunludur.

## 5. Servisler

- **`ShellService`** — Varsayılan shell: `getpwuid_r().pw_shell`, yoksa `/bin/zsh`. Shell listesi: `/etc/shells` + `/opt/homebrew/bin/fish` + `/usr/local/bin/fish`, `access(X_OK)` süzgeciyle. Ortam: `TERM=xterm-256color`, `COLORTERM=truecolor`, `LANG`/`LC_CTYPE`, `HOME`, `USER`, `LOGNAME`, `TERM_PROGRAM=Termora`, `TERM_PROGRAM_VERSION`; PATH login shell'e bırakılır (her oturum login shell başlar).
- **`SessionManager`** — Oturum yaşam döngüsünün tek sahibi: yaratma (ayar/profilden), `[UUID: TermoraTerminalView]` cache'i, kapatmada SIGTERM → bekleme → SIGKILL, busy tespiti (`tcgetpgrp`), exit status ayrıştırma, ayar/tema değişikliklerini açık terminallere uygulama (`installColors` + `font` + `lineSpacing` + `changeScrollback`).
- **`SettingsStore` / `ProfileStore`** — @Observable; UserDefaults+Codable; bozuk veri kurtarma (bkz. §8).
- **`ThemeStore`** — bundle'daki tema JSON'larını yükler.

## 6. ViewModels

- **`WorkspaceViewModel`** (pencere başına bir; `@FocusedValue` ile menüye açılır)
  - Sekme: aç (⌘T, profille aç), kapat (⌘W; busy ise onay), seç (⌘1-9, ⌘⇧]/[), yeniden adlandır.
  - Panel: böl (⌘D dikey, ⌘⇧D yatay), kapat, yön tuşlarıyla odak (⌘⌥ok; panel ekran geometrisinden komşu bulma), divider oranı güncelleme (min. %15).
  - Bölme semantiği (iTerm2 konvansiyonu): **dikey böl (⌘D) = dikey ayraç, paneller yan yana**; **yatay böl (⌘⇧D) = yatay ayraç, paneller üst üste**.
- **`TerminalTab` / `TerminalSession`** — durum taşıyıcı @Observable sınıflar; delegate olayları (başlık, cwd, süreç çıkışı) SessionManager üzerinden bunlara yazılır.

## 7. Views

- **`TabBarView`** — HStack+ForEach özel çizim; aktif sekme vurgusu; hover'da kapatma; çift tıkla rename (TextField + @FocusState); "+" butonu; başlıkta aktif klasör/işlem adı.
- **`PaneTreeView`** — `PaneNode` ağacını özyinelemeli çizer; divider sürüklenebilir, imleç `NSCursor.resizeLeftRight/UpDown` (onHover push/pop); aktif olmayan panellere hafif karartma.
- **`TerminalHostView`** — NSViewRepresentable; view'ı SessionManager cache'inden alır. Odak: aktif panel değişince `DispatchQueue.main.async { view.window?.makeFirstResponder(view) }`.
- **`TermoraTerminalView`** — `LocalProcessTerminalView` alt sınıfı: sıfır-frame guard (SwiftUI yerleşim kırılganlığına karşı, CodeEdit kalıbı) + uygulama kısayollarının terminale yutulmamasını sağlayan tuş yönetimi.
- **`SearchBarView`** — ⌘F ile sekme üstünde açılır; `findNext`/`findPrevious` (⌘G/⌘⇧G), `searchMatchSummary` sayacı, Aa/regex/kelime seçenekleri; Esc → `clearSearch()` + kapat.
- **`StatusBarView`** (ayarlardan açılır/kapanır) — shell adı, çalışma dizini, git branch, terminal boyutu (cols×rows), işlem durumu. cwd: `libproc` (`proc_pidinfo` + `PROC_PIDVNODEPATHINFO`) ile shell pid'inden okunur (OSC 7'ye bel bağlanmaz; Apple'ın zsh entegrasyonu yalnız Terminal.app'te çalışır). Git branch: cwd'den yukarı `.git/HEAD` okuma. Güncelleme en fazla 1 Hz ve yalnız görünür sekme için.
- **`SettingsWindow`** (`Settings` scene, ⌘,) — üç sekme: **Genel** (varsayılan shell, başlangıç klasörü, scrollback, durum çubuğu), **Görünüm** (tema seçici + canlı önizleme, font+boyut, satır aralığı, imleç şekli/yanıp sönme, saydamlık), **Profiller** (liste + CRUD). Arka plan/metin/ANSI renkleri tema seçimiyle değişir; tek tek renk düzenleme (özel tema editörü) MVP dışıdır.
- "Belirli bir klasörde terminal açma"nın MVP karşılığı: Ayarlar'daki başlangıç klasörü + profil başlangıç klasörü (`startProcess(currentDirectory:)` ile). Finder entegrasyonu/hızlı klasör açma 2. fazdadır.
- Pencere saydamlığı: `NSVisualEffectView` arka planı + alpha'lı `nativeBackgroundColor`; `NSWindow` erişimi WindowAccessor (NSViewRepresentable) kalıbıyla.

## 8. Hata Yönetimi

- **Shell başlatılamadı:** panel içi hata görünümü + "Varsayılan shell ile dene"; `startProcess` öncesi `access(X_OK)` kontrolü.
- **Süreç sonlandı:** panel açık kalır; "İşlem sonlandı (çıkış kodu N)" bandı; Enter aynı panelde yeni oturum başlatır.
- **Bozuk kalıcı veri:** decode hatasında varsayılanlara dön; bozuk blob yedek anahtara taşınır (silinmez); bozuk temada Termora Dark'a düşülür. `os.Logger` (subsystem `com.ahmetbarut.Termora`) ile loglanır.
- **Kapatma onayları:** sekme kapatmada busy kontrolü; pencere/uygulama kapatmada çalışan işlemli sekmeler için tek toplu onay. `tcgetpgrp` başarısızsa (fd kapalı, -1) "işlem yok" sayılır.

## 9. Güvenlik

- Sandbox kapalı; Hardened Runtime + Developer ID notarization ile dağıtım.
- MVP'de secret saklanmaz → Keychain kullanımı yok; `KeychainService` 2. fazda (SSH) eklenir.
- Profil ortam değişkenleri UserDefaults'a düz metin gider → Ayarlar UI'ında "hassas değerleri (API anahtarı, parola) buraya koymayın" notu; 2. fazda Keychain'e taşınabilir.
- Terminal çıktısı hiçbir dış servise gönderilmez; uygulamada ağ erişimi yoktur. Profil başlangıç komutu yalnız kullanıcının açıkça tanımladığı komuttur; onun dışında otomatik komut çalıştırılmaz.

## 10. Performans

- PTY okuma SwiftTerm'de DispatchIO ile arka planda (kaynakta doğrulandı); yoğun çıktı UI'ı kilitlemez.
- Durum çubuğu güncellemeleri ≤1 Hz, yalnız görünür sekme.
- Scrollback sınırı kullanıcı ayarı (`changeScrollback`) ile bellek kontrol altında.
- Hedefler: <1 sn açılış, ≥10 eşzamanlı oturum, yazıda fark edilir gecikme yok (M5'te doğrulanır).

## 11. Test Stratejisi

TDD ile yürütülür (test önce).

- **Unit (çoğunluk):** ortam kurucusu; exit-status ayrıştırıcı (normal/sinyalli çıkış); `PaneNode` operasyonları (böl, kapat, kardeş yükseltme, oran sınırları); yön bazlı odak komşuluğu (saf geometri); shell listesi süzme (sahte `/etc/shells` fixture); Settings/Profile round-trip + bozuk veri kurtarma; 5 paket temanın decode doğrulaması; `.git/HEAD` okuyucu (branch/detached fixture'ları).
- **Entegrasyon:** gerçek PTY smoke testleri — `/bin/zsh` ile komut çalıştırıp çıktı doğrulama; `sleep` ile busy tespiti; SIGTERM→SIGKILL eskalasyonu.
- **ViewModel:** `SessionManager` protokol arkasına alınır; `WorkspaceViewModel` akışları mock ile.
- **UI:** açılış + sekme aç/kapat smoke testi; görsel doğrulama elle.

## 12. Fazlama

1. **M0** — Proje düzeltmeleri: sandbox kapat, deployment target 14.0, SwiftTerm 1.15.0 SPM, klasör iskeleti.
2. **M1** — Çekirdek terminal: tek sekme/panel; login shell + doğru env; boyutlandırma; kopyala/yapıştır; scrollback. Kabul: `vim`/`htop` sorunsuz.
3. **M2** — Sekmeler: TabBar, ⌘T/⌘W/⌘1-9/⌘⇧]/[, rename, kapatma onayı.
4. **M3** — Bölünmüş paneller: ağaç, divider, ⌘D/⌘⇧D, ⌘⌥ok ile odak.
5. **M4** — Ayarlar + temalar + profiller: Settings penceresi, 5 tema, canlı uygulama, saydamlık.
6. **M5** — Arama + durum çubuğu + cila: ⌘F, göstergeler, performans/kararlılık doğrulaması (10 oturum, <1 sn açılış).

## 13. Kapsam Dışı (MVP)

Brief'in "İlk Sürümde Olmayacaklar" listesi aynen geçerlidir (SSH, workspace, AI, bloklar, eklenti vb.). Ek olarak bu tasarımla netleşenler: oturum kalıcılığı yok, arama'da tüm eşleşmeleri vurgulama yok (yalnız aktif eşleşme), shell integration yok (cwd libproc ile çözülür), SwiftData yok.
