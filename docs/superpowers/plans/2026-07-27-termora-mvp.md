# Termora MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS için native, sekmeli, bölünebilir panelli, aranabilir ve temalandırılabilir bir terminal uygulaması (Termora MVP) inşa etmek.

**Architecture:** SwiftUI kabuğu (sekme çubuğu, panel ağacı, ayarlar, arama, durum çubuğu) SwiftTerm'ün `LocalProcessTerminalView`'ını `NSViewRepresentable` ile sarar. Terminal oturumlarının ömrü SwiftUI görünüm ömründen bağımsızdır: `SessionManager` terminal view'larını oturum UUID'siyle cache'ler, böylece görünüm hiyerarşisi yeniden kurulsa da shell süreci ve scrollback yaşar. Panel düzeni özyinelemeli bir binary tree (`PaneNode`) ile modellenir; kalıcı veri (ayarlar, profiller) UserDefaults + Codable ile saklanır.

**Tech Stack:** Swift 5, SwiftUI + AppKit köprüleri, Observation (`@Observable`), SwiftTerm 1.15.0 (SPM), Swift Testing (`import Testing`), UserDefaults + Codable, Darwin/libproc (PTY ve süreç sorgulama).

**Spec:** `docs/superpowers/specs/2026-07-27-termora-mvp-design.md`

## Global Constraints

Bu kısıtlar HER görev için geçerlidir; görev metinlerinde tekrar edilmese de uyulması zorunludur.

- **Xcode projesi:** `/Users/ahmetbarut/Apps/Termora/Termora.xcodeproj`, şema `Termora`, uygulama hedefi `Termora`, test hedefi `TermoraTests`.
- **Dosya ekleme:** Proje `PBXFileSystemSynchronizedRootGroup` kullanır (objectVersion 77). `Termora/` veya `TermoraTests/` altına diske yazılan her dosya otomatik olarak derlemeye girer — pbxproj düzenlemesi GEREKMEZ. Tek istisna Task 1'deki SwiftTerm SPM paketi eklemesidir.
- **Minimum macOS:** 14.0 Sonoma. macOS 15+ API'leri (`pointerStyle`, `containerBackground(.window)`, `windowBackgroundDragBehavior`, yeni `Tab`/`TabSection`, `@Entry`, `onModifierKeysChanged`) ve macOS 26 API'leri (Liquid Glass / `glassEffect`) YASAK.
- **Sandbox:** `ENABLE_APP_SANDBOX = NO` (Task 1 ayarlar). `ENABLE_HARDENED_RUNTIME = YES` korunur.
- **Test framework:** Swift Testing (`import Testing`, `@Test`, `@Suite`, `#expect`). XCTest kullanılmaz. **Tek istisna:** `TermoraUITests` hedefi XCUITest gerektirir (`XCUIApplication` Swift Testing ile kullanılamaz); yalnız o hedefte `import XCTest` serbesttir.
- **Metal Toolchain önkoşulu:** SwiftTerm 1.15.0 bir `.metal` shader içerir ve Xcode 26'da Metal derleyicisi ayrı indirilen bir bileşendir. Kurulu değilse **her** build `error: cannot execute tool 'metal' due to missing Metal Toolchain` ile düşer. Task 1 bunu `xcodebuild -downloadComponent MetalToolchain` ile çözer; sonraki hiçbir görev bu hatayı kendi kodunun hatası sanmamalıdır.
- **Aktör izolasyonu:** Proje `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` ve `SWIFT_APPROACHABLE_CONCURRENCY = YES` ile derlenir; bildirimlerin varsayılan izolasyonu MainActor'dır.
- **Derleme komutu:** `xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet`
- **Test komutu:** `xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/<SuiteAdı> 2>&1 | tail -20`
- **Kod dili:** Tüm identifier'lar, tip adları ve kod yorumlarının teknik terimleri İngilizce; açıklayıcı yorumlar ve kullanıcıya görünen metinler Türkçe.
- **Commit:** Her görev en az bir commit ile biter. Conventional commit önekleri (`feat:`, `test:`, `fix:`, `chore:`), mesaj gövdesi İngilizce ve kısa.
- **SwiftTerm sürümü:** 1.15.0 (`from: "1.15.0"`), ürün adı `SwiftTerm`, repo `https://github.com/migueldeicaza/SwiftTerm`.
- **SwiftTerm tuzakları:** `Terminal.getEnvironmentVariables()` KULLANILMAZ (`LC_TYPE` yazım hatası içerir, PATH/SHELL eklemez) — ortam `EnvironmentBuilder` ile kurulur. `processTerminated` delegesine gelen `exitCode` HAM `waitpid` status'udur; `ExitStatus` ile ayrıştırılır. `terminate()` yalnız shell PID'ine SIGTERM gönderir; SIGKILL eskalasyonu `SessionManager`'ın sorumluluğudur.
- **Bölme semantiği:** `SplitAxis.vertical` = dikey ayraç, paneller **yan yana** (⌘D). `SplitAxis.horizontal` = yatay ayraç, paneller **üst üste** (⌘⇧D).

---


---

### Task 1: Proje ayarları ve SwiftTerm bağımlılığı (M0)

**Files:**
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora.xcodeproj/project.pbxproj`
- Modify (taşı + sadeleştir): `/Users/ahmetbarut/Apps/Termora/Termora/TermoraApp.swift` → `/Users/ahmetbarut/Apps/Termora/Termora/App/TermoraApp.swift`
- Delete: `/Users/ahmetbarut/Apps/Termora/Termora/ContentView.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Services/SwiftTermLinkCheck.swift` (geçici import doğrulama dosyası; **Task 8 bu dosyayı `git rm` ile siler** — orada `TermoraTerminalView` gerçek SwiftTerm kullanımını getirir)
- Test: yok (altyapı görevi) — build doğrulaması şart

**Interfaces:**
- Consumes: —
- Produces: `import SwiftTerm` hem `Termora` hem `TermoraTests` hedeflerinde derlenebilir durumda; `MACOSX_DEPLOYMENT_TARGET = 14.0` (tüm konfigürasyonlar); `ENABLE_APP_SANDBOX = NO`; `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (app + test hedefi); klasör iskeleti (`Termora/App`, `Models`, `Views/{Terminal,Settings,Support}`, `ViewModels`, `Services`, `Extensions`, `Resources/Themes`)

Not: Proje `PBXFileSystemSynchronizedRootGroup` kullanıyor (objectVersion 77) — `Termora/` veya `TermoraTests/` altına yazılan her dosya otomatik derlemeye girer; pbxproj'a **dosya referansı** eklenmez. Bu görevdeki pbxproj düzenlemeleri yalnız build ayarları (Step 1) ve SwiftTerm SPM paketinin iki hedefe bağlanmasıdır (Step 2-5).

Aktör izolasyonu: şablonda `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` ve `SWIFT_APPROACHABLE_CONCURRENCY = YES` yalnız **uygulama** hedefinde açıktır ve KORUNUR; Step 1 aynı ayarı **`TermoraTests` hedefine de** ekler. Böylece uygulama tipleri (hepsi MainActor izole) ile test kodu aynı izolasyon varsayımı altında derlenir. Buna rağmen sonraki görevlerdeki Swift Testing suite'leri **açıkça `@MainActor` işaretlenir** (Task 5/6/7 ve sonrası) — ayar yanlışlıkla düşerse veya Swift 6 diline geçilirse testler yine de derlenir.

- [ ] **Step 1: Deployment target, sandbox ve test hedefi aktör izolasyonu ayarlarını değiştir**

```bash
cd /Users/ahmetbarut/Apps/Termora
sed -i '' 's/MACOSX_DEPLOYMENT_TARGET = 26.5;/MACOSX_DEPLOYMENT_TARGET = 14.0;/g' Termora.xcodeproj/project.pbxproj
sed -i '' 's/ENABLE_APP_SANDBOX = YES;/ENABLE_APP_SANDBOX = NO;/g' Termora.xcodeproj/project.pbxproj
grep -c 'MACOSX_DEPLOYMENT_TARGET = 14.0;' Termora.xcodeproj/project.pbxproj
grep -c 'ENABLE_APP_SANDBOX = NO;' Termora.xcodeproj/project.pbxproj
```

Beklenen: ilk grep `4` (proje Debug/Release + TermoraTests Debug/Release), ikinci grep `2` (app hedefi Debug/Release). `ENABLE_HARDENED_RUNTIME = YES` zaten var, dokunma.

Ardından `TermoraTests` hedefinin iki konfigürasyonuna `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` ekle. `SWIFT_APPROACHABLE_CONCURRENCY = YES;` satırı dosyada 6 kez geçtiğinden (app + test + UI test) düz `sed` kullanılamaz; aşağıdaki betik yalnız `PRODUCT_BUNDLE_IDENTIFIER = com.ahmetbarut.TermoraTests;` içeren `buildSettings` bloklarını yamalar, alfabetik sırayı korur ve tekrar çalıştırılabilir (idempotent):

```bash
cd /Users/ahmetbarut/Apps/Termora
python3 - <<'PY'
import pathlib
path = pathlib.Path("Termora.xcodeproj/project.pbxproj")
text = path.read_text()
opener = "\t\t\tbuildSettings = {\n"
marker = "PRODUCT_BUNDLE_IDENTIFIER = com.ahmetbarut.TermoraTests;"
anchor = "\t\t\t\tSWIFT_APPROACHABLE_CONCURRENCY = YES;\n"
line = "\t\t\t\tSWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;\n"
chunks = text.split(opener)
for i in range(1, len(chunks)):
    body, sep, rest = chunks[i].partition("\t\t\t};\n")
    if marker in body and line not in body:
        assert body.count(anchor) == 1, "SWIFT_APPROACHABLE_CONCURRENCY tekil degil"
        body = body.replace(anchor, anchor + line)
    chunks[i] = body + sep + rest
result = opener.join(chunks)
assert result.count(line) == 4, f"beklenen 4 satir, bulunan {result.count(line)}"
path.write_text(result)
print("ACTOR_ISOLATION_OK", result.count(line))
PY
grep -c 'SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;' Termora.xcodeproj/project.pbxproj
```

Beklenen: `ACTOR_ISOLATION_OK 4` ve grep çıktısı `4` (app Debug/Release + TermoraTests Debug/Release). Betik `AssertionError` verirse pbxproj beklenen şekilde değildir — hiçbir şey yazılmamıştır, dosya bozulmaz. `TermoraUITests` hedefine bu ayar **eklenmez** (XCUITest kodu XCTest kalıbında yazılır).

- [ ] **Step 2: pbxproj'a SwiftTerm SPM paketini ekle — PBXBuildFile bölümü**

`Termora.xcodeproj/project.pbxproj` içinde (girintiler TAB karakteridir) şu satırı bul:

```
/* Begin PBXContainerItemProxy section */
```

ve şununla değiştir (üstüne yeni bölüm eklenmiş olur — **iki** build file: biri app, biri test hedefi için):

```
/* Begin PBXBuildFile section */
		1FB09E01301781D200585465 /* SwiftTerm in Frameworks */ = {isa = PBXBuildFile; productRef = 1FB09E03301781D200585465 /* SwiftTerm */; };
		1FB09E04301781D200585465 /* SwiftTerm in Frameworks */ = {isa = PBXBuildFile; productRef = 1FB09E05301781D200585465 /* SwiftTerm */; };
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
```

Neden test hedefi de: `TermoraTests/ThemeTests.swift`, `AppSettingsTests.swift` ve `SessionManagerTests.swift` doğrudan `import SwiftTerm` yapar (`SwiftTerm.Color`, `SwiftTerm.CursorStyle`). Ürün test hedefine bağlanmazsa bu dosyalar `error: no such module 'SwiftTerm'` ile derlenmez. Bu **tek seferlik** ayardır; sonraki hiçbir görev "Xcode'da elle ekle" demez.

- [ ] **Step 3: pbxproj — app ve test hedeflerinin Frameworks build phase'lerine ürünü bağla**

Üç `PBXFrameworksBuildPhase` bloğu birbirinin aynısıdır; yalnız ID satırı ayırır. Önce app hedefininkini (`1FB09D52...`) bul:

```
		1FB09D52301781CF00585465 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

ve şununla değiştir:

```
		1FB09D52301781CF00585465 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				1FB09E01301781D200585465 /* SwiftTerm in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

Sonra test hedefininkini (`1FB09D5F...`) bul:

```
		1FB09D5F301781D100585465 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

ve şununla değiştir:

```
		1FB09D5F301781D100585465 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				1FB09E04301781D200585465 /* SwiftTerm in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

`1FB09D69...` bloğu (`TermoraUITests`) DEĞİŞMEZ — UI test hedefi SwiftTerm kullanmaz.

- [ ] **Step 4: pbxproj — target packageProductDependencies + proje packageReferences**

`PBXNativeTarget "Termora"` içinde şu ikiliyi bul (dosyada tek geçer):

```
			name = Termora;
			packageProductDependencies = (
			);
```

ve şununla değiştir:

```
			name = Termora;
			packageProductDependencies = (
				1FB09E03301781D200585465 /* SwiftTerm */,
			);
```

`PBXNativeTarget "TermoraTests"` içinde şu ikiliyi bul (dosyada tek geçer):

```
			name = TermoraTests;
			packageProductDependencies = (
			);
```

ve şununla değiştir:

```
			name = TermoraTests;
			packageProductDependencies = (
				1FB09E05301781D200585465 /* SwiftTerm */,
			);
```

`name = TermoraUITests;` bloğu DEĞİŞMEZ.

Sonra `PBXProject` bölümünde şu ikiliyi bul:

```
			minimizedProjectReferenceProxies = 1;
			preferredProjectObjectVersion = 77;
```

ve şununla değiştir (`packageReferences` alfabetik sırada bu iki anahtarın arasına girer):

```
			minimizedProjectReferenceProxies = 1;
			packageReferences = (
				1FB09E02301781D200585465 /* XCRemoteSwiftPackageReference "SwiftTerm" */,
			);
			preferredProjectObjectVersion = 77;
```

- [ ] **Step 5: pbxproj — XCRemoteSwiftPackageReference ve XCSwiftPackageProductDependency bölümleri**

Dosyanın sonuna doğru şu bloğu bul:

```
/* End XCConfigurationList section */
	};
```

ve şununla değiştir:

```
/* End XCConfigurationList section */

/* Begin XCRemoteSwiftPackageReference section */
		1FB09E02301781D200585465 /* XCRemoteSwiftPackageReference "SwiftTerm" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/migueldeicaza/SwiftTerm";
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = 1.15.0;
			};
		};
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		1FB09E03301781D200585465 /* SwiftTerm */ = {
			isa = XCSwiftPackageProductDependency;
			package = 1FB09E02301781D200585465 /* XCRemoteSwiftPackageReference "SwiftTerm" */;
			productName = SwiftTerm;
		};
		1FB09E05301781D200585465 /* SwiftTerm */ = {
			isa = XCSwiftPackageProductDependency;
			package = 1FB09E02301781D200585465 /* XCRemoteSwiftPackageReference "SwiftTerm" */;
			productName = SwiftTerm;
		};
/* End XCSwiftPackageProductDependency section */
	};
```

(İki ürün bağımlılığı da aynı paket referansını gösterir: `1FB09E03…` app hedefinin, `1FB09E05…` test hedefinin girdisidir — Xcode her hedef için ayrı `XCSwiftPackageProductDependency` bekler.)

- [ ] **Step 6: pbxproj düzenlemelerini ve paket çözümlemesini doğrula**

Önce eklenen kimliklerin sayısını doğrula (her biri beklenen sayıda geçmeli):

```bash
cd /Users/ahmetbarut/Apps/Termora
grep -c '1FB09E01301781D200585465' Termora.xcodeproj/project.pbxproj   # 2 (tanim + app Frameworks)
grep -c '1FB09E04301781D200585465' Termora.xcodeproj/project.pbxproj   # 2 (tanim + test Frameworks)
grep -c '1FB09E03301781D200585465' Termora.xcodeproj/project.pbxproj   # 3 (buildFile productRef + app packageProductDependencies + tanim)
grep -c '1FB09E05301781D200585465' Termora.xcodeproj/project.pbxproj   # 3 (buildFile productRef + test packageProductDependencies + tanim)
grep -c '1FB09E02301781D200585465' Termora.xcodeproj/project.pbxproj   # 4 (packageReferences + tanim + iki urun bagimliligi)
plutil -lint Termora.xcodeproj/project.pbxproj
```

Beklenen: sırasıyla `2`, `2`, `3`, `3`, `4` ve `project.pbxproj: OK`. Sayılar tutmuyorsa Step 2-5'teki bloklardan biri eksik/yanlış yapıştırılmıştır.

Sonra paketi çözümle:

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild -resolvePackageDependencies -project Termora.xcodeproj -scheme Termora 2>&1 | tail -5
```

Beklenen: çıktıda `Resolved source packages:` altında `SwiftTerm: https://github.com/migueldeicaza/SwiftTerm @ 1.15.x` satırı (ağ erişimi gerekir; ilk çözümleme 1-2 dk sürebilir). Hata (`xcodebuild: error:` / `could not resolve`) görülürse pbxproj düzenlemelerinde yazım hatası var demektir — Step 2-5'i tekrar kontrol et.

**Metal Toolchain önkoşulu (bu makinede DOĞRULANDI: eksik).** SwiftTerm 1.15.0 `Sources/SwiftTerm/Metal/Shaders.metal` içerir; `SwiftTerm_SwiftTerm` resource hedefi bu shader'ı derler. Xcode 26'da Metal derleyicisi ayrı indirilen bir bileşendir ve kurulu değilse **her** build şu hatayla düşer:

```
error: cannot execute tool 'metal' due to missing Metal Toolchain; use: xcodebuild -downloadComponent MetalToolchain
** BUILD FAILED **
```

Bu, Step 10'dan itibaren planın TÜM build/test adımlarını bloke eder. Step 10'a geçmeden bileşeni indir (tek seferlik, birkaç GB, ağ gerekir):

```bash
xcodebuild -downloadComponent MetalToolchain
```

Doğrulama: `xcodebuild -downloadComponent MetalToolchain` ikinci kez çalıştırıldığında bileşenin zaten kurulu olduğunu bildirir; kesin kontrol için Step 10'daki build'in `BUILD_OK` vermesidir.

- [ ] **Step 7: Klasör iskeletini aç**

```bash
mkdir -p /Users/ahmetbarut/Apps/Termora/Termora/App \
  /Users/ahmetbarut/Apps/Termora/Termora/Models \
  /Users/ahmetbarut/Apps/Termora/Termora/Views/Terminal \
  /Users/ahmetbarut/Apps/Termora/Termora/Views/Settings \
  /Users/ahmetbarut/Apps/Termora/Termora/Views/Support \
  /Users/ahmetbarut/Apps/Termora/Termora/ViewModels \
  /Users/ahmetbarut/Apps/Termora/Termora/Services \
  /Users/ahmetbarut/Apps/Termora/Termora/Extensions \
  /Users/ahmetbarut/Apps/Termora/Termora/Resources/Themes
```

Not: git boş klasörleri izlemez; klasörler sonraki görevlerde dosya aldıkça commit'lere girer. Bu normaldir.

İskelet, sonraki görevlerin gerçekten yazdığı yollarla birebir eşleşir: `Views/` kökü (`MainWindowView`, `TabBarView`, `SearchBarView`, `StatusBarView`, `SettingsPlaceholderView`), `Views/Terminal/` (`TermoraTerminalView`, `TerminalHostView`, `PaneTreeView`), `Views/Settings/` (Task 18) ve `Views/Support/` (Task 18 `WindowChrome`). Kullanılmayan `Views/{MainWindow,Tabs,SplitView,Search}` klasörleri bilinçli olarak açılmaz.

- [ ] **Step 8: ContentView.swift'i sil, TermoraApp.swift'i App/ altına taşı ve sadeleştir**

```bash
cd /Users/ahmetbarut/Apps/Termora
git rm Termora/ContentView.swift
git mv Termora/TermoraApp.swift Termora/App/TermoraApp.swift
```

Sonra `/Users/ahmetbarut/Apps/Termora/Termora/App/TermoraApp.swift` içeriğini tamamen şununla değiştir:

```swift
import SwiftUI

@main
struct TermoraApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Termora")
                .frame(minWidth: 480, minHeight: 320)
        }
    }
}
```

- [ ] **Step 9: SwiftTerm import doğrulama dosyasını oluştur**

`/Users/ahmetbarut/Apps/Termora/Termora/Services/SwiftTermLinkCheck.swift`:

```swift
import SwiftTerm

/// Build-time smoke check: SwiftTerm paketinin çözülüp linklendiğini garanti eder.
/// GEÇİCİDİR: Task 8 gerçek SwiftTerm kullanımını (TermoraTerminalView) getirir ve
/// kendi commit adımında bu dosyayı `git rm` ile siler.
enum SwiftTermLinkCheck {
    static let terminalViewType: AnyClass = LocalProcessTerminalView.self
}
```

- [ ] **Step 10: Build doğrula, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet && echo BUILD_OK
```

Beklenen: son satır `BUILD_OK` (exit code 0). `-quiet` ile başarılı build'de neredeyse hiç çıktı olmaz. `cannot find 'LocalProcessTerminalView'` hatası görülürse paket bağlanmamıştır — Step 2-5 blokları kontrol edilir.

Ardından test hedefinin de SwiftTerm'e erişebildiğini geçici bir sonda dosyasıyla doğrula (Task 5/6/8 testleri buna bağlıdır):

```bash
cd /Users/ahmetbarut/Apps/Termora
cat > TermoraTests/SwiftTermLinkProbe.swift <<'SWIFT'
import SwiftTerm
import Testing

@Test func swiftTermIsLinkedIntoTheTestTarget() {
    #expect(SwiftTerm.Color(red: 0, green: 0, blue: 0).red == 0)
}
SWIFT
xcodebuild build-for-testing -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet && echo TEST_TARGET_OK
rm TermoraTests/SwiftTermLinkProbe.swift
```

Beklenen: `TEST_TARGET_OK`. `error: no such module 'SwiftTerm'` görülürse Step 2-5'teki **test hedefi** blokları (`1FB09E04…` / `1FB09E05…`) eksiktir. Sonda dosyası doğrulamadan hemen sonra silinir; commit'e girmez.

Not: SwiftTerm hem uygulamaya hem test bundle'ına linklendiğinden test koşumunda `objc[…]: Class _TtC9SwiftTerm… is implemented in both …` uyarıları görülebilir. Bunlar zararsızdır (aynı sürümün iki kopyası); testleri düşürmezler.

- [ ] **Step 11: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora
git add -A
git commit -m "chore: target macOS 14, disable sandbox, add SwiftTerm 1.15.0, scaffold folders"
```

---

---

### Task 2: ExitStatus modeli (M1)

**Files:**
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Models/ExitStatus.swift`
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/ExitStatusTests.swift`

**Interfaces:**
- Consumes: —
- Produces: `struct ExitStatus: Equatable { let rawStatus: Int32; var exitCode: Int32?; var signal: Int32?; var localizedSummary: String }` — SwiftTerm `processTerminated(source:exitCode:)` delegate'inden gelen HAM `waitpid` status'unu ayrıştırır (Task 8/12 tüketir)

Arka plan: Darwin'in `WIFEXITED`/`WEXITSTATUS`/`WIFSIGNALED`/`WTERMSIG` makroları C makrosudur, Swift'e köprülenmez; formüller elle uygulanır:
- `WIFEXITED(s)   = (s & 0x7f) == 0`
- `WEXITSTATUS(s) = (s >> 8) & 0xff`
- `WIFSIGNALED(s) = ((s & 0x7f) != 0x7f) && ((s & 0x7f) != 0)`
- `WTERMSIG(s)    = s & 0x7f`

(`(s & 0x7f) == 0x7f` durdurulmuş süreçtir — WIFSTOPPED; bizde exitCode ve signal her ikisi nil döner.)

- [ ] **Step 1: Testi yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/ExitStatusTests.swift`:

```swift
import Testing
@testable import Termora

@Suite("ExitStatus")
struct ExitStatusTests {

    @Test("normal cikis: raw 0 -> exitCode 0, signal nil")
    func normalExitZero() {
        let status = ExitStatus(rawStatus: 0)
        #expect(status.exitCode == 0)
        #expect(status.signal == nil)
    }

    @Test("normal cikis: raw 256 -> exitCode 1 (WEXITSTATUS)")
    func normalExitOne() {
        let status = ExitStatus(rawStatus: 256)
        #expect(status.exitCode == 1)
        #expect(status.signal == nil)
    }

    @Test("sinyalli cikis: raw 15 -> signal 15 (SIGTERM), exitCode nil")
    func terminatedBySigterm() {
        let status = ExitStatus(rawStatus: 15)
        #expect(status.exitCode == nil)
        #expect(status.signal == 15)
    }

    @Test("sinyalli cikis: raw 9 -> signal 9 (SIGKILL)")
    func terminatedBySigkill() {
        let status = ExitStatus(rawStatus: 9)
        #expect(status.exitCode == nil)
        #expect(status.signal == 9)
    }

    @Test("durdurulmus surec: raw 0x7f -> ikisi de nil")
    func stoppedProcess() {
        let status = ExitStatus(rawStatus: 0x7f)
        #expect(status.exitCode == nil)
        #expect(status.signal == nil)
    }

    @Test("localizedSummary metinleri")
    func summaries() {
        #expect(ExitStatus(rawStatus: 0).localizedSummary == "çıkış kodu 0")
        #expect(ExitStatus(rawStatus: 256).localizedSummary == "çıkış kodu 1")
        #expect(ExitStatus(rawStatus: 15).localizedSummary == "SIGTERM ile sonlandı")
        #expect(ExitStatus(rawStatus: 9).localizedSummary == "SIGKILL ile sonlandı")
        #expect(ExitStatus(rawStatus: 28).localizedSummary == "sinyal 28 ile sonlandı")
        #expect(ExitStatus(rawStatus: 0x7f).localizedSummary == "bilinmeyen durum (raw: 127)")
    }

    @Test("Equatable rawStatus uzerinden")
    func equatable() {
        #expect(ExitStatus(rawStatus: 256) == ExitStatus(rawStatus: 256))
        #expect(ExitStatus(rawStatus: 256) != ExitStatus(rawStatus: 0))
    }
}
```

- [ ] **Step 2: Testi çalıştır, FAIL bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/ExitStatusTests 2>&1 | tail -20
```

Beklenen: derleme hatası `error: cannot find 'ExitStatus' in scope` ve sonda `Testing cancelled because the build failed.` / `** TEST FAILED **`. (TDD kırmızı adımı: tip henüz yok.)

- [ ] **Step 3: Minimal implementasyonu yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Models/ExitStatus.swift`:

```swift
import Foundation

/// `waitpid`'den gelen ham status degerini ayristirir.
/// Darwin'in WIFEXITED/WEXITSTATUS/WIFSIGNALED/WTERMSIG makrolari C makrosu oldugundan
/// Swift'e kopru kurulmaz; formuller elle uygulanir:
///   WIFEXITED(s)   = (s & 0x7f) == 0
///   WEXITSTATUS(s) = (s >> 8) & 0xff
///   WIFSIGNALED(s) = ((s & 0x7f) != 0x7f) && ((s & 0x7f) != 0)
///   WTERMSIG(s)    = s & 0x7f
struct ExitStatus: Equatable {
    let rawStatus: Int32

    /// WIFEXITED ise WEXITSTATUS, degilse nil.
    var exitCode: Int32? {
        guard (rawStatus & 0x7f) == 0 else { return nil }
        return (rawStatus >> 8) & 0xff
    }

    /// WIFSIGNALED ise WTERMSIG, degilse nil.
    var signal: Int32? {
        let low = rawStatus & 0x7f
        guard low != 0x7f, low != 0 else { return nil }
        return low
    }

    var localizedSummary: String {
        if let code = exitCode {
            return "çıkış kodu \(code)"
        }
        if let sig = signal {
            if let name = Self.signalNames[sig] {
                return "\(name) ile sonlandı"
            }
            return "sinyal \(sig) ile sonlandı"
        }
        return "bilinmeyen durum (raw: \(rawStatus))"
    }

    private static let signalNames: [Int32: String] = [
        SIGHUP: "SIGHUP", SIGINT: "SIGINT", SIGQUIT: "SIGQUIT",
        SIGILL: "SIGILL", SIGTRAP: "SIGTRAP", SIGABRT: "SIGABRT",
        SIGFPE: "SIGFPE", SIGKILL: "SIGKILL", SIGBUS: "SIGBUS",
        SIGSEGV: "SIGSEGV", SIGPIPE: "SIGPIPE", SIGALRM: "SIGALRM",
        SIGTERM: "SIGTERM",
    ]
}
```

- [ ] **Step 4: Testi çalıştır, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/ExitStatusTests 2>&1 | tail -20
```

Beklenen: `Test Suite 'ExitStatus' passed` satırları (7 test) ve sonda `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora
git add Termora/Models/ExitStatus.swift TermoraTests/ExitStatusTests.swift
git commit -m "feat: add ExitStatus model parsing raw waitpid status"
```

---

---

### Task 3: EnvironmentBuilder (M1)

**Files:**
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Services/EnvironmentBuilder.swift`
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/EnvironmentBuilderTests.swift`

**Interfaces:**
- Consumes: —
- Produces:
  - `EnvironmentBuilder.environment(extra: [String: String] = [:]) -> [String]` — sözleşmedeki kolaylık sarmalayıcı; base = `ProcessInfo.processInfo.environment` (Task 8 SessionManager `startProcess(environment:)` için tüketir)
  - `EnvironmentBuilder.environment(base: [String: String], extra: [String: String] = [:]) -> [String]` — test dikişli saf çekirdek

Neden bizde: SwiftTerm'ün `Terminal.getEnvironmentVariables`'ında `LC_TYPE` yazım hatası var (LC_CTYPE aynalanmaz) ve PATH/SHELL eklenmez — KULLANILMAZ. PATH bilinçli olarak env'e konmaz: her oturum login shell başlar (`-zsh` argv[0]), PATH'i shell'in kendi başlangıç dosyaları kurar.

- [ ] **Step 1: Testi yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/EnvironmentBuilderTests.swift`:

```swift
import Foundation
import Testing
@testable import Termora

@Suite("EnvironmentBuilder")
struct EnvironmentBuilderTests {

    /// "KEY=VALUE" listesini sozluge cevirir (deger icindeki '=' korunur).
    private func dict(_ entries: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for entry in entries {
            let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            result[String(parts[0])] = parts.count > 1 ? String(parts[1]) : ""
        }
        return result
    }

    @Test("sabit anahtarlar: TERM, COLORTERM, TERM_PROGRAM")
    func staticKeys() {
        let env = dict(EnvironmentBuilder.environment(base: [:], extra: [:]))
        #expect(env["TERM"] == "xterm-256color")
        #expect(env["COLORTERM"] == "truecolor")
        #expect(env["TERM_PROGRAM"] == "Termora")
        #expect(env["TERM_PROGRAM_VERSION"]?.isEmpty == false)
    }

    @Test("LANG: base'de yoksa en_US.UTF-8, varsa aynen")
    func langDefaultAndPassthrough() {
        let missing = dict(EnvironmentBuilder.environment(base: [:], extra: [:]))
        #expect(missing["LANG"] == "en_US.UTF-8")
        let present = dict(EnvironmentBuilder.environment(base: ["LANG": "tr_TR.UTF-8"], extra: [:]))
        #expect(present["LANG"] == "tr_TR.UTF-8")
    }

    @Test("LC_CTYPE yalniz base'de varsa gecer")
    func lcCtypeOnlyWhenPresent() {
        let without = dict(EnvironmentBuilder.environment(base: [:], extra: [:]))
        #expect(without["LC_CTYPE"] == nil)
        let with = dict(EnvironmentBuilder.environment(base: ["LC_CTYPE": "UTF-8"], extra: [:]))
        #expect(with["LC_CTYPE"] == "UTF-8")
    }

    @Test("HOME/USER/LOGNAME base'den aynalanir")
    func identityKeysFromBase() {
        let base = ["HOME": "/Users/test", "USER": "test", "LOGNAME": "test", "PATH": "/usr/bin"]
        let env = dict(EnvironmentBuilder.environment(base: base, extra: [:]))
        #expect(env["HOME"] == "/Users/test")
        #expect(env["USER"] == "test")
        #expect(env["LOGNAME"] == "test")
        #expect(env["PATH"] == nil) // PATH bilincli olarak login shell'e birakilir
    }

    @Test("extra en son uygulanir ve override eder")
    func extraOverrides() {
        let env = dict(EnvironmentBuilder.environment(
            base: ["LANG": "tr_TR.UTF-8"],
            extra: ["LANG": "C", "EDITOR": "vim", "TERM": "dumb"]
        ))
        #expect(env["LANG"] == "C")
        #expect(env["EDITOR"] == "vim")
        #expect(env["TERM"] == "dumb")
    }

    @Test("cikti bicimi KEY=VALUE ve anahtarlar tekil")
    func outputFormat() {
        let entries = EnvironmentBuilder.environment(base: ["HOME": "/Users/test"], extra: [:])
        for entry in entries {
            #expect(entry.contains("="), "beklenen KEY=VALUE, gelen: \(entry)")
        }
        let keys = entries.map { $0.split(separator: "=", maxSplits: 1)[0] }
        #expect(Set(keys).count == keys.count)
    }

    @Test("kolaylik sarmalayici gercek ortami kullanir")
    func convenienceUsesProcessEnvironment() {
        let env = dict(EnvironmentBuilder.environment())
        #expect(env["HOME"] == ProcessInfo.processInfo.environment["HOME"])
        #expect(env["TERM_PROGRAM"] == "Termora")
    }
}
```

- [ ] **Step 2: Testi çalıştır, FAIL bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/EnvironmentBuilderTests 2>&1 | tail -20
```

Beklenen: `error: cannot find 'EnvironmentBuilder' in scope` ve `** TEST FAILED **`.

- [ ] **Step 3: Minimal implementasyonu yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Services/EnvironmentBuilder.swift`:

```swift
import Foundation

/// Terminal alt sureci icin ortam degiskenlerini kurar.
/// SwiftTerm'un `Terminal.getEnvironmentVariables`'i KULLANILMAZ:
/// LC_TYPE yazim hatasi vardir (LC_CTYPE aynalanmaz) ve PATH/SHELL eklenmez.
/// PATH bilincli olarak eklenmez — her oturum login shell olarak baslar,
/// PATH'i shell'in kendi baslangic dosyalari kurar.
enum EnvironmentBuilder {

    /// Kolaylik sarmalayici: base = gercek surec ortami.
    static func environment(extra: [String: String] = [:]) -> [String] {
        environment(base: ProcessInfo.processInfo.environment, extra: extra)
    }

    /// Test dikisli saf cekirdek. Cikti "KEY=VALUE" dizisidir (deterministik siralama).
    static func environment(base: [String: String], extra: [String: String] = [:]) -> [String] {
        var env: [String: String] = [:]
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = base["LANG"] ?? "en_US.UTF-8"
        if let lcCtype = base["LC_CTYPE"] {
            env["LC_CTYPE"] = lcCtype
        }
        for key in ["HOME", "USER", "LOGNAME"] {
            if let value = base[key] {
                env[key] = value
            }
        }
        env["TERM_PROGRAM"] = "Termora"
        env["TERM_PROGRAM_VERSION"] = appVersion
        for (key, value) in extra {
            env[key] = value
        }
        return env.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
    }

    private static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
}
```

- [ ] **Step 4: Testi çalıştır, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/EnvironmentBuilderTests 2>&1 | tail -20
```

Beklenen: 7 test geçer, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora
git add Termora/Services/EnvironmentBuilder.swift TermoraTests/EnvironmentBuilderTests.swift
git commit -m "feat: add EnvironmentBuilder for terminal child environment"
```

---

---

### Task 4: ShellService (M1)

**Files:**
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Services/ShellService.swift`
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/ShellServiceTests.swift`

**Interfaces:**
- Consumes: —
- Produces:
  - `struct ShellInfo: Equatable, Identifiable { var id: String { path }; let path: String; let displayName: String }` — Settings/Profil shell seçicileri tüketir (Task 18/19)
  - `ShellService.defaultShellPath() -> String` — `getpwuid_r().pw_shell`, boşsa `/bin/zsh` (Task 8 SessionManager shell çözümü)
  - `ShellService.availableShells(etcShellsContents: String?, homebrewCandidates: [String], isExecutable: (String) -> Bool) -> [ShellInfo]` — test dikişli saf çekirdek
  - `ShellService.availableShells() -> [ShellInfo]` — gerçek dosya sisteminden çağıran kolaylık
  - `ShellService.loginArgv0(forShellPath:) -> String` — `"/bin/zsh"` → `"-zsh"` (Task 8 `startProcess(execName:)` için)

Neden `getpwuid_r`: GUI uygulamada `SHELL` env değişkeni bayat olabilir (kullanıcı `chsh` yaptıysa Dock'tan açılan uygulamaya eski değer gelir); kullanıcı veritabanındaki `pw_shell` gerçek kaynaktır.

- [ ] **Step 1: Testi yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/ShellServiceTests.swift`:

```swift
import Testing
@testable import Termora

@Suite("ShellService")
struct ShellServiceTests {

    // MARK: availableShells saf cekirdek

    @Test("/etc/shells parse: yorum ve bos satirlar atlanir, bosluk kirpilir")
    func parsesEtcShells() {
        let fixture = """
        # List of acceptable shells for chpass(1).
        # Ftpd will not allow users to connect who are not using
        /bin/bash

          /bin/zsh
        /bin/csh
        """
        let shells = ShellService.availableShells(
            etcShellsContents: fixture,
            homebrewCandidates: [],
            isExecutable: { _ in true }
        )
        #expect(shells.map(\.path) == ["/bin/bash", "/bin/zsh", "/bin/csh"])
    }

    @Test("homebrew adaylari listeye eklenir, isExecutable suzer")
    func homebrewCandidatesAndFilter() {
        let fixture = """
        /bin/bash
        /bin/csh
        /bin/zsh
        """
        let shells = ShellService.availableShells(
            etcShellsContents: fixture,
            homebrewCandidates: ["/opt/homebrew/bin/fish", "/usr/local/bin/fish"],
            isExecutable: { $0 != "/bin/csh" && $0 != "/usr/local/bin/fish" }
        )
        #expect(shells.map(\.path) == ["/bin/bash", "/bin/zsh", "/opt/homebrew/bin/fish"])
        #expect(shells.map(\.displayName) == ["bash", "zsh", "fish"])
    }

    @Test("tekillestirme: ayni yol iki kez gecmez")
    func deduplicates() {
        let fixture = """
        /bin/zsh
        /opt/homebrew/bin/fish
        """
        let shells = ShellService.availableShells(
            etcShellsContents: fixture,
            homebrewCandidates: ["/opt/homebrew/bin/fish"],
            isExecutable: { _ in true }
        )
        #expect(shells.map(\.path) == ["/bin/zsh", "/opt/homebrew/bin/fish"])
    }

    @Test("etcShellsContents nil -> yalniz homebrew adaylari")
    func nilEtcShells() {
        let shells = ShellService.availableShells(
            etcShellsContents: nil,
            homebrewCandidates: ["/opt/homebrew/bin/fish"],
            isExecutable: { _ in true }
        )
        #expect(shells.map(\.path) == ["/opt/homebrew/bin/fish"])
    }

    // MARK: ShellInfo

    @Test("ShellInfo.id == path")
    func shellInfoIdentity() {
        let info = ShellInfo(path: "/bin/zsh", displayName: "zsh")
        #expect(info.id == "/bin/zsh")
    }

    // MARK: loginArgv0

    @Test("loginArgv0: son bilesen basina tire")
    func loginArgv0() {
        #expect(ShellService.loginArgv0(forShellPath: "/bin/zsh") == "-zsh")
        #expect(ShellService.loginArgv0(forShellPath: "/opt/homebrew/bin/fish") == "-fish")
        #expect(ShellService.loginArgv0(forShellPath: "/bin/bash") == "-bash")
    }

    // MARK: defaultShellPath (gercek sistem smoke)

    @Test("defaultShellPath mutlak yol doner")
    func defaultShellIsAbsolute() {
        let path = ShellService.defaultShellPath()
        #expect(path.hasPrefix("/"))
        #expect(!path.isEmpty)
    }

    @Test("gercek availableShells en az bir shell bulur ve hepsi calistirilabilir yoldadir")
    func realAvailableShellsSmoke() {
        let shells = ShellService.availableShells()
        #expect(!shells.isEmpty) // macOS'ta /etc/shells her zaman vardir
        #expect(shells.allSatisfy { $0.path.hasPrefix("/") })
    }
}
```

- [ ] **Step 2: Testi çalıştır, FAIL bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/ShellServiceTests 2>&1 | tail -20
```

Beklenen: `error: cannot find 'ShellService' in scope` (ve `ShellInfo` için benzeri) ve `** TEST FAILED **`.

- [ ] **Step 3: Minimal implementasyonu yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Services/ShellService.swift`:

```swift
import Darwin
import Foundation

/// Secilebilir bir shell: path kimliktir, displayName son yol bilesenidir.
struct ShellInfo: Equatable, Identifiable {
    var id: String { path }
    let path: String
    let displayName: String
}

enum ShellService {

    /// Kullanicinin gercek varsayilan shell'i. GUI uygulamada SHELL env bayat
    /// olabileceginden kullanici veritabanindan (`getpwuid_r().pw_shell`) okunur;
    /// bos/erisilemezse /bin/zsh'e duser.
    ///
    /// `pw_shell` `buffer`'in icine isaret eder ve `&buffer` ile uretilen isaretci
    /// YALNIZ cagri suresince gecerlidir; bu yuzden String kopyasi
    /// `withUnsafeMutableBufferPointer` blogunun ICINDE alinir.
    static func defaultShellPath() -> String {
        var pwd = passwd()
        var result: UnsafeMutablePointer<passwd>? = nil
        var buffer = [CChar](repeating: 0, count: 4096)
        let shell: String? = buffer.withUnsafeMutableBufferPointer { raw -> String? in
            guard getpwuid_r(getuid(), &pwd, raw.baseAddress, raw.count, &result) == 0,
                  result != nil,
                  let shellPtr = pwd.pw_shell else { return nil }
            let value = String(cString: shellPtr)
            return value.isEmpty ? nil : value
        }
        return shell ?? "/bin/zsh"
    }

    /// Test dikisli saf cekirdek: /etc/shells icerigini parse eder (yorum/bos satir
    /// atlanir, bosluk kirpilir), homebrew adaylarini ekler, isExecutable ile suzer,
    /// sirayi koruyarak tekillestirir.
    static func availableShells(
        etcShellsContents: String?,
        homebrewCandidates: [String],
        isExecutable: (String) -> Bool
    ) -> [ShellInfo] {
        var candidates: [String] = []
        if let contents = etcShellsContents {
            for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                candidates.append(trimmed)
            }
        }
        candidates.append(contentsOf: homebrewCandidates)

        var seen = Set<String>()
        var shells: [ShellInfo] = []
        for path in candidates {
            guard seen.insert(path).inserted, isExecutable(path) else { continue }
            shells.append(ShellInfo(path: path, displayName: (path as NSString).lastPathComponent))
        }
        return shells
    }

    /// Gercek dosya sisteminden okuyan kolaylik sarmalayici.
    static func availableShells() -> [ShellInfo] {
        let contents = try? String(contentsOfFile: "/etc/shells", encoding: .utf8)
        return availableShells(
            etcShellsContents: contents,
            homebrewCandidates: ["/opt/homebrew/bin/fish", "/usr/local/bin/fish"],
            isExecutable: { access($0, X_OK) == 0 }
        )
    }

    /// Login shell konvansiyonu: argv[0] = "-" + son bilesen ("/bin/zsh" -> "-zsh").
    /// SwiftTerm `startProcess(execName:)` parametresine verilir.
    static func loginArgv0(forShellPath path: String) -> String {
        "-" + (path as NSString).lastPathComponent
    }
}
```

- [ ] **Step 4: Testi çalıştır, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/ShellServiceTests 2>&1 | tail -20
```

Beklenen: 8 test geçer, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora
git add Termora/Services/ShellService.swift TermoraTests/ShellServiceTests.swift
git commit -m "feat: add ShellService with shell discovery and login argv0"
```

---

---

### Task 5: Theme modeli, NSColor+Hex, ThemeStore ve 5 tema JSON'u (M1)

**Files:**
- Create: `Termora/Extensions/NSColor+Hex.swift`
- Create: `Termora/Models/Theme.swift`
- Create: `Termora/Services/ThemeStore.swift`
- Create: `Termora/Resources/Themes/termora-dark.json`, `Termora/Resources/Themes/termora-light.json`, `Termora/Resources/Themes/dracula.json`, `Termora/Resources/Themes/nord.json`, `Termora/Resources/Themes/tokyo-night.json`
- Test: `TermoraTests/NSColorHexTests.swift`, `TermoraTests/ThemeTests.swift`, `TermoraTests/ThemeStoreTests.swift`, `TermoraTests/fixture-valid-theme.json`, `TermoraTests/fixture-broken-theme.json`

**Interfaces:**
- Consumes: `SwiftTerm.Color` — kaynak koddan doğrulandı: `public class Color: Hashable`, `public var red: UInt16; public var green: UInt16; public var blue: UInt16`, `public init(red: UInt16, green: UInt16, blue: UInt16)`, `public static func == (lhs: Color, rhs: Color) -> Bool` (Task 1'in eklediği SPM paketi).
- Produces:
  - `extension NSColor { convenience init?(hexString: String) }` — `#RRGGBB` ve `#RRGGBBAA` (baştaki `#` opsiyonel), geçersiz girdi → `nil`.
  - `struct Theme: Codable, Identifiable, Equatable { var id: String; var name: String; var background: String; var foreground: String; var cursor: String; var selection: String; var ansi: [String] }`
  - `extension Theme { func swiftTermAnsiColors() -> [SwiftTerm.Color]; var backgroundNSColor: NSColor; var foregroundNSColor: NSColor; var cursorNSColor: NSColor; var selectionNSColor: NSColor }` — `selectionNSColor`'ı Task 19 `applyAppearance(to:sessionID:)` içinde terminale uygular (spec §4 seçim rengi); orada SwiftTerm'ün gerçek özellik adı doğrulanır.
  - `final class ThemeStore { init(bundle: Bundle = .main); let themes: [Theme]; func theme(id: String) -> Theme; static let fallback: Theme }`

**Notlar:**
- Dosya-senkronize proje (PBXFileSystemSynchronizedRootGroup): `Termora/Resources/Themes/*.json` diske yazılınca **otomatik olarak uygulama hedefine resource girer**; `TermoraTests/` altına yazılan `.json` fixture'ları da test bundle'ına resource olarak kopyalanır. pbxproj düzenlemesi gerekmez.
- Senkronize gruplar resource'ları bundle köküne **düzleştirebilir**; ThemeStore bu yüzden sırasıyla `Themes/`, `Resources/Themes/` alt dizinlerine ve bundle köküne bakar. Test fixture'ları bilinçli olarak `TermoraTests/` kökünde tutulur (her iki yerleşimde de bundle kökünde bulunurlar).
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` hem uygulama hem test hedefinde açıktır (Task 1 Step 1 test hedefine ekler); yine de tüm test suite'leri açıkça `@MainActor` işaretlenir — ayar düşse veya Swift 6 diline geçilse bile derleme bozulmasın.
- Test hedefi `TEST_HOST = Termora.app` ile koşar (pbxproj'dan doğrulandı) → testte `Bundle.main` uygulama bundle'ıdır; 5 temanın gerçekten pakete girdiği bu sayede test edilir.
- `import SwiftTerm` test hedefinde çalışır: SwiftTerm ürünü Task 1 Step 2-5'te **hem `Termora` hem `TermoraTests`** hedefine bağlanır. Elle Xcode ayarı gerekmez.

- [ ] **Step 1: NSColor+Hex testlerini yaz**
  `TermoraTests/NSColorHexTests.swift`:
  ```swift
  import AppKit
  import Testing
  @testable import Termora

  @MainActor
  @Suite struct NSColorHexTests {
      @Test func parsesSixDigitHexWithHash() throws {
          let color = try #require(NSColor(hexString: "#FF8000"))
          let rgb = try #require(color.usingColorSpace(.sRGB))
          #expect(abs(rgb.redComponent - 1.0) < 0.001)
          #expect(abs(rgb.greenComponent - 128.0 / 255.0) < 0.001)
          #expect(abs(rgb.blueComponent - 0.0) < 0.001)
          #expect(abs(rgb.alphaComponent - 1.0) < 0.001)
      }

      @Test func parsesLowercaseWithoutHash() throws {
          let color = try #require(NSColor(hexString: "1a2b3c"))
          let rgb = try #require(color.usingColorSpace(.sRGB))
          #expect(abs(rgb.redComponent - CGFloat(0x1A) / 255.0) < 0.001)
          #expect(abs(rgb.greenComponent - CGFloat(0x2B) / 255.0) < 0.001)
          #expect(abs(rgb.blueComponent - CGFloat(0x3C) / 255.0) < 0.001)
      }

      @Test func parsesEightDigitHexWithAlpha() throws {
          let color = try #require(NSColor(hexString: "#FF800080"))
          let rgb = try #require(color.usingColorSpace(.sRGB))
          #expect(abs(rgb.redComponent - 1.0) < 0.001)
          #expect(abs(rgb.alphaComponent - 128.0 / 255.0) < 0.001)
      }

      @Test(arguments: ["", "#", "#FFF", "12345", "#GGGGGG", "not-a-color", "#FFFFFFF"])
      func invalidStringsReturnNil(input: String) {
          #expect(NSColor(hexString: input) == nil)
      }
  }
  ```

- [ ] **Step 2: Testi çalıştır — derleme hatasıyla FAIL bekle**
  ```bash
  xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/NSColorHexTests 2>&1 | tail -20
  ```
  Beklenen: `error: no exact matches in call to initializer` (NSColor'da `hexString:` etiketli init henüz yok), ardından `Testing cancelled because the build failed.` ve `** TEST FAILED **`.

- [ ] **Step 3: NSColor+Hex implementasyonu**
  `Termora/Extensions/NSColor+Hex.swift`:
  ```swift
  import AppKit

  extension NSColor {
      /// Parses "#RRGGBB" or "#RRGGBBAA" (leading "#" optional). Returns nil for anything else.
      convenience init?(hexString: String) {
          var text = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
          if text.hasPrefix("#") {
              text.removeFirst()
          }
          guard text.count == 6 || text.count == 8,
                text.allSatisfy(\.isHexDigit),
                let value = UInt64(text, radix: 16) else {
              return nil
          }
          let rgb: UInt64
          let alpha: CGFloat
          if text.count == 8 {
              rgb = value >> 8
              alpha = CGFloat(value & 0xFF) / 255.0
          } else {
              rgb = value
              alpha = 1.0
          }
          self.init(
              srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255.0,
              green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
              blue: CGFloat(rgb & 0xFF) / 255.0,
              alpha: alpha)
      }
  }
  ```

- [ ] **Step 4: Testi çalıştır — PASS bekle**
  ```bash
  xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/NSColorHexTests 2>&1 | tail -20
  ```
  Beklenen: tüm NSColorHexTests testleri geçer, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**
  ```bash
  git add Termora/Extensions/NSColor+Hex.swift TermoraTests/NSColorHexTests.swift
  git commit -m "feat: add hex string initializer to NSColor"
  ```

- [ ] **Step 6: Theme model testlerini yaz**
  `TermoraTests/ThemeTests.swift`:
  ```swift
  import AppKit
  import Foundation
  import SwiftTerm
  import Testing
  @testable import Termora

  @MainActor
  @Suite struct ThemeTests {
      static let sampleJSON = """
      {
        "id": "sample",
        "name": "Sample",
        "background": "#101015",
        "foreground": "#F0F0F0",
        "cursor": "#FF5500",
        "selection": "#33467C",
        "ansi": ["#000000", "#FF0000", "#00FF00", "#FFFF00",
                 "#0000FF", "#FF00FF", "#00FFFF", "#FFFFFF",
                 "#808080", "#FF8080", "#80FF80", "#FFFF80",
                 "#8080FF", "#FF80FF", "#80FFFF", "#C0C0C0"]
      }
      """

      @Test func decodesFromJSON() throws {
          let theme = try JSONDecoder().decode(Theme.self, from: Data(Self.sampleJSON.utf8))
          #expect(theme.id == "sample")
          #expect(theme.name == "Sample")
          #expect(theme.background == "#101015")
          #expect(theme.selection == "#33467C")
          #expect(theme.ansi.count == 16)
          #expect(theme.ansi[1] == "#FF0000")
      }

      @Test func swiftTermAnsiColorsHasSixteenScaledEntries() throws {
          let theme = try JSONDecoder().decode(Theme.self, from: Data(Self.sampleJSON.utf8))
          let colors = theme.swiftTermAnsiColors()
          #expect(colors.count == 16)
          // 0x00 -> 0, 0xFF -> 65535, 0x80 -> 32896 (128 * 257)
          #expect(colors[0] == SwiftTerm.Color(red: 0, green: 0, blue: 0))
          #expect(colors[1].red == 65535)
          #expect(colors[1].green == 0)
          #expect(colors[1].blue == 0)
          #expect(colors[7] == SwiftTerm.Color(red: 65535, green: 65535, blue: 65535))
          #expect(colors[8].red == 32896)
          #expect(colors[8].green == 32896)
          #expect(colors[8].blue == 32896)
      }

      @Test func nsColorAccessorsParseThemeColors() throws {
          let theme = try JSONDecoder().decode(Theme.self, from: Data(Self.sampleJSON.utf8))
          let cursor = try #require(theme.cursorNSColor.usingColorSpace(.sRGB))
          #expect(abs(cursor.redComponent - 1.0) < 0.001)
          #expect(abs(cursor.greenComponent - CGFloat(0x55) / 255.0) < 0.001)
          #expect(abs(cursor.blueComponent - 0.0) < 0.001)
          let background = try #require(theme.backgroundNSColor.usingColorSpace(.sRGB))
          #expect(abs(background.blueComponent - CGFloat(0x15) / 255.0) < 0.001)
          let selection = try #require(theme.selectionNSColor.usingColorSpace(.sRGB))
          #expect(abs(selection.redComponent - CGFloat(0x33) / 255.0) < 0.001)
          #expect(abs(selection.greenComponent - CGFloat(0x46) / 255.0) < 0.001)
          #expect(abs(selection.blueComponent - CGFloat(0x7C) / 255.0) < 0.001)
      }
  }
  ```

- [ ] **Step 7: Testi çalıştır — derleme hatasıyla FAIL bekle**
  ```bash
  xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/ThemeTests 2>&1 | tail -20
  ```
  Beklenen: `error: cannot find 'Theme' in scope`, `Testing cancelled because the build failed.`, `** TEST FAILED **`.

- [ ] **Step 8: Theme modelini implemente et**
  `Termora/Models/Theme.swift`:
  ```swift
  import AppKit
  import Foundation
  import SwiftTerm

  struct Theme: Codable, Identifiable, Equatable {
      var id: String
      var name: String
      var background: String
      var foreground: String
      var cursor: String
      var selection: String
      var ansi: [String] // exactly 16 hex strings, ANSI colors 0-15
  }

  extension Theme {
      func swiftTermAnsiColors() -> [SwiftTerm.Color] {
          ansi.map { Self.swiftTermColor(fromHex: $0) }
      }

      var backgroundNSColor: NSColor { NSColor(hexString: background) ?? .black }
      var foregroundNSColor: NSColor { NSColor(hexString: foreground) ?? .white }
      var cursorNSColor: NSColor { NSColor(hexString: cursor) ?? .white }
      /// Applied to the terminal in Task 19's `applyAppearance(to:sessionID:)`.
      var selectionNSColor: NSColor { NSColor(hexString: selection) ?? .selectedTextBackgroundColor }

      /// Scales 8-bit hex channels to SwiftTerm's 16-bit channels (0xFF -> 65535, since 255 * 257 == 65535).
      private static func swiftTermColor(fromHex hex: String) -> SwiftTerm.Color {
          var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
          if text.hasPrefix("#") {
              text.removeFirst()
          }
          guard text.count == 6 || text.count == 8,
                let value = UInt64(text, radix: 16) else {
              return SwiftTerm.Color(red: 0, green: 0, blue: 0)
          }
          let rgb = text.count == 8 ? value >> 8 : value
          return SwiftTerm.Color(
              red: UInt16((rgb >> 16) & 0xFF) * 257,
              green: UInt16((rgb >> 8) & 0xFF) * 257,
              blue: UInt16(rgb & 0xFF) * 257)
      }
  }
  ```

- [ ] **Step 9: Testi çalıştır — PASS bekle**
  ```bash
  xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/ThemeTests 2>&1 | tail -20
  ```
  Beklenen: `** TEST SUCCEEDED **`.

- [ ] **Step 10: Commit**
  ```bash
  git add Termora/Models/Theme.swift TermoraTests/ThemeTests.swift
  git commit -m "feat: add Theme model with SwiftTerm color conversion"
  ```

- [ ] **Step 11: ThemeStore fixture'larını ve testlerini yaz**
  `TermoraTests/fixture-valid-theme.json` (folder-sync test bundle'ına resource olarak kopyalar):
  ```json
  {
    "id": "fixture-valid",
    "name": "Fixture Valid",
    "background": "#101015",
    "foreground": "#F0F0F0",
    "cursor": "#FF5500",
    "selection": "#33467C",
    "ansi": ["#000000", "#800000", "#008000", "#808000",
             "#000080", "#800080", "#008080", "#C0C0C0",
             "#808080", "#FF0000", "#00FF00", "#FFFF00",
             "#0000FF", "#FF00FF", "#00FFFF", "#FFFFFF"]
  }
  ```
  `TermoraTests/fixture-broken-theme.json` (geçerli JSON, ama Theme şemasına göre eksik alanlar → decode başarısız olmalı):
  ```json
  { "id": "fixture-broken", "name": "Fixture Broken" }
  ```
  `TermoraTests/ThemeStoreTests.swift`:
  ```swift
  import Foundation
  import Testing
  @testable import Termora

  private final class FixtureBundleToken {}

  @MainActor
  @Suite struct ThemeStoreTests {
      private var fixtureBundle: Bundle { Bundle(for: FixtureBundleToken.self) }

      @Test func loadsValidFixtureTheme() {
          let store = ThemeStore(bundle: fixtureBundle)
          let theme = store.theme(id: "fixture-valid")
          #expect(theme.id == "fixture-valid")
          #expect(theme.name == "Fixture Valid")
          #expect(theme.ansi.count == 16)
      }

      @Test func skipsBrokenFixtureTheme() {
          let store = ThemeStore(bundle: fixtureBundle)
          #expect(!store.themes.contains { $0.id == "fixture-broken" })
      }

      @Test func unknownIDReturnsFallback() {
          let store = ThemeStore(bundle: fixtureBundle)
          let theme = store.theme(id: "no-such-theme")
          #expect(theme == ThemeStore.fallback)
          #expect(theme.id == "termora-dark")
      }

      @Test func fallbackThemeIsComplete() {
          #expect(ThemeStore.fallback.id == "termora-dark")
          #expect(ThemeStore.fallback.ansi.count == 16)
          #expect(ThemeStore.fallback.swiftTermAnsiColors().count == 16)
      }
  }
  ```

- [ ] **Step 12: Testi çalıştır — derleme hatasıyla FAIL bekle**
  ```bash
  xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/ThemeStoreTests 2>&1 | tail -20
  ```
  Beklenen: `error: cannot find 'ThemeStore' in scope`, `Testing cancelled because the build failed.`, `** TEST FAILED **`.

- [ ] **Step 13: ThemeStore'u implemente et**
  `Termora/Services/ThemeStore.swift`:
  ```swift
  import Foundation
  import os

  final class ThemeStore {
      /// Embedded copy of termora-dark; used when a theme ID is unknown or no resources load.
      static let fallback = Theme(
          id: "termora-dark",
          name: "Termora Dark",
          background: "#16181D",
          foreground: "#EAEAEA",
          cursor: "#AEAFAD",
          selection: "#264F78",
          ansi: [
              "#000000", "#CD3131", "#0DBC79", "#E5E510",
              "#2472C8", "#BC3FBC", "#11A8CD", "#E5E5E5",
              "#666666", "#F14C4C", "#23D18B", "#F5F543",
              "#3B8EEA", "#D670D6", "#29B8DB", "#FFFFFF",
          ])

      private static let logger = Logger(subsystem: "com.ahmetbarut.Termora", category: "ThemeStore")

      let themes: [Theme]

      init(bundle: Bundle = .main) {
          // File-synchronized groups may flatten resources into the bundle root,
          // so probe the expected subdirectories first and fall back to the root.
          var urls: [URL] = []
          for subdirectory in ["Themes", "Resources/Themes", nil] {
              urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: subdirectory) ?? []
              if !urls.isEmpty { break }
          }
          let decoder = JSONDecoder()
          let loaded = urls.compactMap { url -> Theme? in
              guard let data = try? Data(contentsOf: url),
                    let theme = try? decoder.decode(Theme.self, from: data),
                    theme.ansi.count == 16 else {
                  Self.logger.error("Skipping theme resource that failed to load: \(url.lastPathComponent, privacy: .public)")
                  return nil
              }
              return theme
          }
          themes = loaded.isEmpty
              ? [Self.fallback]
              : loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
      }

      func theme(id: String) -> Theme {
          themes.first { $0.id == id } ?? Self.fallback
      }
  }
  ```
  Not: `fixture-broken-theme.json` decode edilemediği için loglanıp atlanır — `skipsBrokenFixtureTheme` bunu doğrular.

- [ ] **Step 14: Testi çalıştır — PASS bekle**
  ```bash
  xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/ThemeStoreTests 2>&1 | tail -20
  ```
  Beklenen: `** TEST SUCCEEDED **`.

- [ ] **Step 15: Commit**
  ```bash
  git add Termora/Services/ThemeStore.swift TermoraTests/ThemeStoreTests.swift TermoraTests/fixture-valid-theme.json TermoraTests/fixture-broken-theme.json
  git commit -m "feat: add ThemeStore with bundle loading and fallback theme"
  ```

- [ ] **Step 16: Uygulama bundle'ı testi ekle (5 tema)**
  `TermoraTests/ThemeStoreTests.swift` içine, suite'in sonuna şu testi ekle (test hedefi `TEST_HOST` ile Termora.app içinde koştuğu için `Bundle.main` uygulama bundle'ıdır):
  ```swift
      @Test func appBundleShipsFiveThemes() {
          let store = ThemeStore(bundle: .main)
          let ids = Set(store.themes.map(\.id))
          #expect(ids.isSuperset(of: ["termora-dark", "termora-light", "dracula", "nord", "tokyo-night"]))
      }
  ```

- [ ] **Step 17: Testi çalıştır — FAIL bekle (temalar henüz bundle'da yok)**
  ```bash
  xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/ThemeStoreTests 2>&1 | tail -20
  ```
  Beklenen: `Test appBundleShipsFiveThemes() recorded an issue` (`ids` yalnız fallback'ten gelen `{"termora-dark"}` olduğundan superset beklentisi düşer) ve `** TEST FAILED **`.

- [ ] **Step 18: 5 tema JSON'unu yaz**
  Dosyalar `Termora/Resources/Themes/` altına yazılır; folder-sync sayesinde otomatik olarak uygulama hedefine resource girerler (pbxproj düzenlemesi yok).
  `Termora/Resources/Themes/termora-dark.json` (fallback ile birebir aynı):
  ```json
  {
    "id": "termora-dark",
    "name": "Termora Dark",
    "background": "#16181D",
    "foreground": "#EAEAEA",
    "cursor": "#AEAFAD",
    "selection": "#264F78",
    "ansi": ["#000000", "#CD3131", "#0DBC79", "#E5E510",
             "#2472C8", "#BC3FBC", "#11A8CD", "#E5E5E5",
             "#666666", "#F14C4C", "#23D18B", "#F5F543",
             "#3B8EEA", "#D670D6", "#29B8DB", "#FFFFFF"]
  }
  ```
  `Termora/Resources/Themes/termora-light.json`:
  ```json
  {
    "id": "termora-light",
    "name": "Termora Light",
    "background": "#FFFFFF",
    "foreground": "#333333",
    "cursor": "#333333",
    "selection": "#ADD6FF",
    "ansi": ["#000000", "#CD3131", "#00BC00", "#949800",
             "#0451A5", "#BC05BC", "#0598BC", "#555555",
             "#666666", "#CD3131", "#14CE14", "#B5BA00",
             "#0451A5", "#BC05BC", "#0598BC", "#A5A5A5"]
  }
  ```
  `Termora/Resources/Themes/dracula.json` (resmî Dracula terminal paleti):
  ```json
  {
    "id": "dracula",
    "name": "Dracula",
    "background": "#282A36",
    "foreground": "#F8F8F2",
    "cursor": "#F8F8F2",
    "selection": "#44475A",
    "ansi": ["#21222C", "#FF5555", "#50FA7B", "#F1FA8C",
             "#BD93F9", "#FF79C6", "#8BE9FD", "#F8F8F2",
             "#6272A4", "#FF6E6E", "#69FF94", "#FFFFA5",
             "#D6ACFF", "#FF92DF", "#A4FFFF", "#FFFFFF"]
  }
  ```
  `Termora/Resources/Themes/nord.json` (resmî Nord terminal paleti):
  ```json
  {
    "id": "nord",
    "name": "Nord",
    "background": "#2E3440",
    "foreground": "#D8DEE9",
    "cursor": "#D8DEE9",
    "selection": "#434C5E",
    "ansi": ["#3B4252", "#BF616A", "#A3BE8C", "#EBCB8B",
             "#81A1C1", "#B48EAD", "#88C0D0", "#E5E9F0",
             "#4C566A", "#BF616A", "#A3BE8C", "#EBCB8B",
             "#81A1C1", "#B48EAD", "#8FBCBB", "#ECEFF4"]
  }
  ```
  `Termora/Resources/Themes/tokyo-night.json` (resmî Tokyo Night terminal paleti):
  ```json
  {
    "id": "tokyo-night",
    "name": "Tokyo Night",
    "background": "#1A1B26",
    "foreground": "#C0CAF5",
    "cursor": "#C0CAF5",
    "selection": "#33467C",
    "ansi": ["#15161E", "#F7768E", "#9ECE6A", "#E0AF68",
             "#7AA2F7", "#BB9AF7", "#7DCFFF", "#A9B1D6",
             "#414868", "#F7768E", "#9ECE6A", "#E0AF68",
             "#7AA2F7", "#BB9AF7", "#7DCFFF", "#C0CAF5"]
  }
  ```

- [ ] **Step 19: Testi çalıştır — PASS bekle**
  ```bash
  xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/ThemeStoreTests 2>&1 | tail -20
  ```
  Beklenen: `** TEST SUCCEEDED **`. (FAIL sürerse: JSON'ların uygulama bundle'ına kopyalandığını `ls $(xcodebuild -project Termora.xcodeproj -scheme Termora -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR/{print $3}')/Termora.app/Contents/Resources/` ile doğrula.)

- [ ] **Step 20: Commit**
  ```bash
  git add Termora/Resources/Themes TermoraTests/ThemeStoreTests.swift
  git commit -m "feat: bundle five built-in terminal themes"
  ```

---

### Task 6: AppSettings + SettingsStore (M1)

**Files:**
- Create: `Termora/Models/AppSettings.swift`
- Create: `Termora/Services/SettingsStore.swift`
- Test: `TermoraTests/AppSettingsTests.swift`, `TermoraTests/SettingsStoreTests.swift`

**Interfaces:**
- Consumes: `SwiftTerm.CursorStyle` (sözleşme: `blinkBlock, steadyBlock, blinkUnderline, steadyUnderline, blinkBar, steadyBar`; ilişkili değeri olmayan enum olduğundan `==` otomatik gelir). Task 5'ten yalnız `"termora-dark"` tema ID string'i (tip bağımlılığı yok).
- Produces:
  - `enum CursorStyleSetting: String, Codable, CaseIterable { case blinkBlock, steadyBlock, blinkUnderline, steadyUnderline, blinkBar, steadyBar; var swiftTermStyle: SwiftTerm.CursorStyle }`
  - `struct AppSettings: Codable, Equatable { var fontName: String?; var fontSize: Double = 13; var lineSpacing: Double = 1.0; var cursorStyle: CursorStyleSetting = .blinkBlock; var themeID: String = "termora-dark"; var windowOpacity: Double = 1.0; var scrollbackLines: Int = 10_000; var defaultShellPath: String?; var startupDirectory: String?; var showStatusBar: Bool = true }`
  - `@MainActor @Observable final class SettingsStore { init(defaults: UserDefaults = .standard); var settings: AppSettings /* didSet persist */; static let storageKey = "settings.v1"; static let backupKey = "settings.v1.corrupt-backup" }`

**Notlar:**
- `@Observable` makrosu `willSet`/`didSet` gözlemcilerini korur; init içindeki ilk atama init accessor üzerinden gittiği için `didSet` init'te **tetiklenmez** — `persist()` yalnız gerçek mutasyonlarda çalışır. `store.settings.fontSize = 18` gibi alan mutasyonları setter'dan geçtiği için `didSet`'i tetikler.
- Testler test-özel `UserDefaults(suiteName:)` kullanır (her testte benzersiz ad → paralel testler çakışmaz); temizlik `defer { removePersistentDomain }` ile yapılır (Swift Testing'in tearDown karşılığı).
- Bozuk veri kurtarma spec §8'e göre `os.Logger` (subsystem `com.ahmetbarut.Termora`) ile loglanır.

- [ ] **Step 1: AppSettings + CursorStyleSetting testlerini yaz**
  `TermoraTests/AppSettingsTests.swift`:
  ```swift
  import Foundation
  import SwiftTerm
  import Testing
  @testable import Termora

  @MainActor
  @Suite struct AppSettingsTests {
      @Test func defaultValuesMatchContract() {
          let settings = AppSettings()
          #expect(settings.fontName == nil)
          #expect(settings.fontSize == 13)
          #expect(settings.lineSpacing == 1.0)
          #expect(settings.cursorStyle == .blinkBlock)
          #expect(settings.themeID == "termora-dark")
          #expect(settings.windowOpacity == 1.0)
          #expect(settings.scrollbackLines == 10_000)
          #expect(settings.defaultShellPath == nil)
          #expect(settings.startupDirectory == nil)
          #expect(settings.showStatusBar == true)
      }

      @Test func codableRoundTrip() throws {
          var settings = AppSettings()
          settings.fontName = "JetBrainsMono-Regular"
          settings.fontSize = 15
          settings.lineSpacing = 1.2
          settings.cursorStyle = .steadyBar
          settings.themeID = "nord"
          settings.windowOpacity = 0.9
          settings.scrollbackLines = 50_000
          settings.defaultShellPath = "/bin/bash"
          settings.startupDirectory = "/Users/me"
          settings.showStatusBar = false
          let data = try JSONEncoder().encode(settings)
          let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
          #expect(decoded == settings)
      }

      @Test func cursorStyleMapsToSwiftTermForAllSixCases() {
          #expect(CursorStyleSetting.allCases.count == 6)
          #expect(CursorStyleSetting.blinkBlock.swiftTermStyle == .blinkBlock)
          #expect(CursorStyleSetting.steadyBlock.swiftTermStyle == .steadyBlock)
          #expect(CursorStyleSetting.blinkUnderline.swiftTermStyle == .blinkUnderline)
          #expect(CursorStyleSetting.steadyUnderline.swiftTermStyle == .steadyUnderline)
          #expect(CursorStyleSetting.blinkBar.swiftTermStyle == .blinkBar)
          #expect(CursorStyleSetting.steadyBar.swiftTermStyle == .steadyBar)
      }

      @Test func cursorStyleRawValuesAreStableForPersistence() {
          #expect(CursorStyleSetting.blinkBlock.rawValue == "blinkBlock")
          #expect(CursorStyleSetting.steadyBar.rawValue == "steadyBar")
      }
  }
  ```

- [ ] **Step 2: Testi çalıştır — derleme hatasıyla FAIL bekle**
  ```bash
  xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/AppSettingsTests 2>&1 | tail -20
  ```
  Beklenen: `error: cannot find 'AppSettings' in scope` (ve/veya `cannot find 'CursorStyleSetting' in scope`), `Testing cancelled because the build failed.`, `** TEST FAILED **`.

- [ ] **Step 3: AppSettings modelini implemente et**
  `Termora/Models/AppSettings.swift`:
  ```swift
  import Foundation
  import SwiftTerm

  enum CursorStyleSetting: String, Codable, CaseIterable {
      case blinkBlock
      case steadyBlock
      case blinkUnderline
      case steadyUnderline
      case blinkBar
      case steadyBar

      var swiftTermStyle: SwiftTerm.CursorStyle {
          switch self {
          case .blinkBlock: return .blinkBlock
          case .steadyBlock: return .steadyBlock
          case .blinkUnderline: return .blinkUnderline
          case .steadyUnderline: return .steadyUnderline
          case .blinkBar: return .blinkBar
          case .steadyBar: return .steadyBar
          }
      }
  }

  struct AppSettings: Codable, Equatable {
      var fontName: String? = nil
      var fontSize: Double = 13
      var lineSpacing: Double = 1.0
      var cursorStyle: CursorStyleSetting = .blinkBlock
      var themeID: String = "termora-dark"
      var windowOpacity: Double = 1.0
      var scrollbackLines: Int = 10_000
      var defaultShellPath: String? = nil
      var startupDirectory: String? = nil
      var showStatusBar: Bool = true
  }
  ```

- [ ] **Step 4: Testi çalıştır — PASS bekle**
  ```bash
  xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/AppSettingsTests 2>&1 | tail -20
  ```
  Beklenen: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**
  ```bash
  git add Termora/Models/AppSettings.swift TermoraTests/AppSettingsTests.swift
  git commit -m "feat: add AppSettings model with cursor style mapping"
  ```

- [ ] **Step 6: SettingsStore kalıcılık testlerini yaz**
  `TermoraTests/SettingsStoreTests.swift`:
  ```swift
  import Foundation
  import Testing
  @testable import Termora

  @MainActor
  @Suite struct SettingsStoreTests {
      private static func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
          let suiteName = "SettingsStoreTests-\(UUID().uuidString)"
          return (UserDefaults(suiteName: suiteName)!, suiteName)
      }

      @Test func freshStoreUsesDefaults() {
          let (defaults, suiteName) = Self.makeDefaults()
          defer { defaults.removePersistentDomain(forName: suiteName) }

          let store = SettingsStore(defaults: defaults)
          #expect(store.settings == AppSettings())
      }

      @Test func mutationPersistsAndRoundTrips() {
          let (defaults, suiteName) = Self.makeDefaults()
          defer { defaults.removePersistentDomain(forName: suiteName) }

          let store = SettingsStore(defaults: defaults)
          store.settings.fontSize = 18
          store.settings.themeID = "dracula"

          let reloaded = SettingsStore(defaults: defaults)
          #expect(reloaded.settings.fontSize == 18)
          #expect(reloaded.settings.themeID == "dracula")
          #expect(reloaded.settings == store.settings)
      }

      @Test func didSetWritesEncodedBlobUnderStorageKey() throws {
          let (defaults, suiteName) = Self.makeDefaults()
          defer { defaults.removePersistentDomain(forName: suiteName) }

          let store = SettingsStore(defaults: defaults)
          store.settings.scrollbackLines = 25_000

          let data = try #require(defaults.data(forKey: SettingsStore.storageKey))
          let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
          #expect(decoded.scrollbackLines == 25_000)
      }
  }
  ```

- [ ] **Step 7: Testi çalıştır — derleme hatasıyla FAIL bekle**
  ```bash
  xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/SettingsStoreTests 2>&1 | tail -20
  ```
  Beklenen: `error: cannot find 'SettingsStore' in scope`, `Testing cancelled because the build failed.`, `** TEST FAILED **`.

- [ ] **Step 8: SettingsStore'u implemente et (kurtarma henüz yok)**
  `Termora/Services/SettingsStore.swift`:
  ```swift
  import Foundation
  import Observation

  @MainActor
  @Observable
  final class SettingsStore {
      static let storageKey = "settings.v1"
      static let backupKey = "settings.v1.corrupt-backup"

      var settings: AppSettings {
          didSet { persist() }
      }

      private let defaults: UserDefaults

      init(defaults: UserDefaults = .standard) {
          self.defaults = defaults
          if let data = defaults.data(forKey: Self.storageKey),
             let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
              self.settings = decoded
          } else {
              self.settings = AppSettings()
          }
      }

      private func persist() {
          guard let data = try? JSONEncoder().encode(settings) else { return }
          defaults.set(data, forKey: Self.storageKey)
      }
  }
  ```

- [ ] **Step 9: Testi çalıştır — PASS bekle**
  ```bash
  xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/SettingsStoreTests 2>&1 | tail -20
  ```
  Beklenen: `** TEST SUCCEEDED **`.

- [ ] **Step 10: Commit**
  ```bash
  git add Termora/Services/SettingsStore.swift TermoraTests/SettingsStoreTests.swift
  git commit -m "feat: add SettingsStore persisting to UserDefaults"
  ```

- [ ] **Step 11: Bozuk blob kurtarma testini ekle**
  `TermoraTests/SettingsStoreTests.swift` suite'inin sonuna ekle:
  ```swift
      @Test func corruptBlobFallsBackToDefaultsAndIsBackedUp() {
          let (defaults, suiteName) = Self.makeDefaults()
          defer { defaults.removePersistentDomain(forName: suiteName) }

          let garbage = Data("definitely{not-json".utf8)
          defaults.set(garbage, forKey: SettingsStore.storageKey)

          let store = SettingsStore(defaults: defaults)
          #expect(store.settings == AppSettings())
          #expect(defaults.data(forKey: SettingsStore.backupKey) == garbage)
          #expect(defaults.data(forKey: SettingsStore.storageKey) == nil)
      }
  ```

- [ ] **Step 12: Testi çalıştır — FAIL bekle (backup davranışı henüz yok)**
  ```bash
  xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/SettingsStoreTests 2>&1 | tail -20
  ```
  Beklenen: `Test corruptBlobFallsBackToDefaultsAndIsBackedUp() recorded an issue` — naif init sessizce varsayılana döndüğü için `backupKey` boş (`nil == garbage` beklentisi düşer) ve bozuk blob `storageKey`'de kalır; `** TEST FAILED **`.

- [ ] **Step 13: Kurtarma + backup davranışını ekle**
  `Termora/Services/SettingsStore.swift` dosyasını şu son haliyle değiştir:
  ```swift
  import Foundation
  import Observation
  import os

  @MainActor
  @Observable
  final class SettingsStore {
      static let storageKey = "settings.v1"
      static let backupKey = "settings.v1.corrupt-backup"

      private static let logger = Logger(subsystem: "com.ahmetbarut.Termora", category: "SettingsStore")

      var settings: AppSettings {
          didSet { persist() }
      }

      private let defaults: UserDefaults

      init(defaults: UserDefaults = .standard) {
          self.defaults = defaults
          guard let data = defaults.data(forKey: Self.storageKey) else {
              self.settings = AppSettings()
              return
          }
          if let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
              self.settings = decoded
          } else {
              defaults.set(data, forKey: Self.backupKey)
              defaults.removeObject(forKey: Self.storageKey)
              Self.logger.error("Corrupt settings blob moved to \(Self.backupKey, privacy: .public); falling back to defaults")
              self.settings = AppSettings()
          }
      }

      private func persist() {
          guard let data = try? JSONEncoder().encode(settings) else { return }
          defaults.set(data, forKey: Self.storageKey)
      }
  }
  ```

- [ ] **Step 14: Tüm suite'i çalıştır — PASS bekle**
  ```bash
  xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/SettingsStoreTests 2>&1 | tail -20
  ```
  Beklenen: 4 testin tamamı geçer, `** TEST SUCCEEDED **`.

- [ ] **Step 15: Commit**
  ```bash
  git add Termora/Services/SettingsStore.swift TermoraTests/SettingsStoreTests.swift
  git commit -m "feat: back up corrupt settings blob before restoring defaults"
  ```

---

### Task 7: TerminalProfile + ProfileStore (M1)

**Files:**
- Create: `Termora/Models/TerminalProfile.swift`
- Create: `Termora/Services/ProfileStore.swift`
- Test: `TermoraTests/TerminalProfileTests.swift`, `TermoraTests/ProfileStoreTests.swift`

**Interfaces:**
- Consumes: yok (Task 6'nın UserDefaults + backup kalıbı aynen tekrarlanır; tip bağımlılığı yoktur).
- Produces:
  - `struct TerminalProfile: Codable, Identifiable, Equatable { var id: UUID = UUID(); var name: String; var shellPath: String?; var startupDirectory: String?; var startupCommand: String?; var fontName: String?; var fontSize: Double?; var themeID: String?; var environment: [String: String] = [:] }`
  - `@MainActor @Observable final class ProfileStore { init(defaults: UserDefaults = .standard); var profiles: [TerminalProfile] /* didSet persist */; static let storageKey = "profiles.v1"; static let backupKey = "profiles.v1.corrupt-backup" }`

**Notlar:**
- Opsiyonel alanlara açıkça `= nil` yazılır ki memberwise init'te varsayılan parametre değeri oluşsun (`TerminalProfile(name: "Work")` çağrılabilir olsun); sözleşmedeki public şekil (ad/tip) değişmez.
- CRUD, `profiles` dizisi üzerinde `append` / index'e atama / `removeAll(where:)` ile yapılır; `@Observable` altında dizi mutasyonları setter'dan geçtiği için `didSet` → `persist()` tetiklenir. Bu üç yol da testte doğrulanır.
- Spec §9 gereği: profil ortam değişkenleri UserDefaults'a düz metin gider — Ayarlar UI görevi (Profiller sekmesi) "hassas değerleri buraya koymayın" notunu göstermekle yükümlüdür; bu görev yalnız modeli kurar.

- [ ] **Step 1: TerminalProfile testlerini yaz**
  `TermoraTests/TerminalProfileTests.swift`:
  ```swift
  import Foundation
  import Testing
  @testable import Termora

  @MainActor
  @Suite struct TerminalProfileTests {
      @Test func codableRoundTripPreservesAllFields() throws {
          var profile = TerminalProfile(name: "Work")
          profile.shellPath = "/opt/homebrew/bin/fish"
          profile.startupDirectory = "/Users/me/Projects"
          profile.startupCommand = "git status"
          profile.fontName = "JetBrainsMono-Regular"
          profile.fontSize = 14
          profile.themeID = "nord"
          profile.environment = ["FOO": "bar"]

          let data = try JSONEncoder().encode(profile)
          let decoded = try JSONDecoder().decode(TerminalProfile.self, from: data)
          #expect(decoded == profile)
          #expect(decoded.id == profile.id)
      }

      @Test func minimalProfileHasExpectedDefaults() {
          let profile = TerminalProfile(name: "Minimal")
          #expect(profile.name == "Minimal")
          #expect(profile.shellPath == nil)
          #expect(profile.startupDirectory == nil)
          #expect(profile.startupCommand == nil)
          #expect(profile.fontName == nil)
          #expect(profile.fontSize == nil)
          #expect(profile.themeID == nil)
          #expect(profile.environment.isEmpty)
      }

      @Test func newProfilesGetDistinctIDs() {
          #expect(TerminalProfile(name: "A").id != TerminalProfile(name: "B").id)
      }

      @Test func environmentDictionaryRoundTripsThroughCodable() throws {
          var profile = TerminalProfile(name: "Deploy")
          profile.environment = ["DEPLOY_ENV": "staging", "EDITOR": "vim", "EMPTY": ""]
          let data = try JSONEncoder().encode(profile)
          let decoded = try JSONDecoder().decode(TerminalProfile.self, from: data)
          #expect(decoded.environment == ["DEPLOY_ENV": "staging", "EDITOR": "vim", "EMPTY": ""])
      }
  }
  ```

- [ ] **Step 2: Testi çalıştır — derleme hatasıyla FAIL bekle**
  ```bash
  xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/TerminalProfileTests 2>&1 | tail -20
  ```
  Beklenen: `error: cannot find 'TerminalProfile' in scope`, `Testing cancelled because the build failed.`, `** TEST FAILED **`.

- [ ] **Step 3: TerminalProfile modelini implemente et**
  `Termora/Models/TerminalProfile.swift`:
  ```swift
  import Foundation

  struct TerminalProfile: Codable, Identifiable, Equatable {
      var id: UUID = UUID()
      var name: String
      var shellPath: String? = nil
      var startupDirectory: String? = nil
      var startupCommand: String? = nil
      var fontName: String? = nil
      var fontSize: Double? = nil
      var themeID: String? = nil
      var environment: [String: String] = [:]
  }
  ```

- [ ] **Step 4: Testi çalıştır — PASS bekle**
  ```bash
  xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/TerminalProfileTests 2>&1 | tail -20
  ```
  Beklenen: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**
  ```bash
  git add Termora/Models/TerminalProfile.swift TermoraTests/TerminalProfileTests.swift
  git commit -m "feat: add TerminalProfile model"
  ```

- [ ] **Step 6: ProfileStore kalıcılık + CRUD testlerini yaz**
  `TermoraTests/ProfileStoreTests.swift`:
  ```swift
  import Foundation
  import Testing
  @testable import Termora

  @MainActor
  @Suite struct ProfileStoreTests {
      private static func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
          let suiteName = "ProfileStoreTests-\(UUID().uuidString)"
          return (UserDefaults(suiteName: suiteName)!, suiteName)
      }

      @Test func freshStoreStartsEmpty() {
          let (defaults, suiteName) = Self.makeDefaults()
          defer { defaults.removePersistentDomain(forName: suiteName) }
          #expect(ProfileStore(defaults: defaults).profiles.isEmpty)
      }

      @Test func crudOperationsPersistAcrossReloads() throws {
          let (defaults, suiteName) = Self.makeDefaults()
          defer { defaults.removePersistentDomain(forName: suiteName) }

          let store = ProfileStore(defaults: defaults)

          // Create
          let work = TerminalProfile(name: "Work")
          let deploy = TerminalProfile(name: "Deploy")
          store.profiles.append(work)
          store.profiles.append(deploy)
          #expect(ProfileStore(defaults: defaults).profiles == [work, deploy])

          // Update
          var updatedWork = work
          updatedWork.shellPath = "/bin/bash"
          updatedWork.environment = ["CI": "1"]
          let index = try #require(store.profiles.firstIndex(where: { $0.id == work.id }))
          store.profiles[index] = updatedWork
          #expect(ProfileStore(defaults: defaults).profiles == [updatedWork, deploy])

          // Delete
          store.profiles.removeAll { $0.id == deploy.id }
          #expect(ProfileStore(defaults: defaults).profiles == [updatedWork])
      }
  }
  ```

- [ ] **Step 7: Testi çalıştır — derleme hatasıyla FAIL bekle**
  ```bash
  xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/ProfileStoreTests 2>&1 | tail -20
  ```
  Beklenen: `error: cannot find 'ProfileStore' in scope`, `Testing cancelled because the build failed.`, `** TEST FAILED **`.

- [ ] **Step 8: ProfileStore'u implemente et (kurtarma henüz yok)**
  `Termora/Services/ProfileStore.swift`:
  ```swift
  import Foundation
  import Observation

  @MainActor
  @Observable
  final class ProfileStore {
      static let storageKey = "profiles.v1"
      static let backupKey = "profiles.v1.corrupt-backup"

      var profiles: [TerminalProfile] {
          didSet { persist() }
      }

      private let defaults: UserDefaults

      init(defaults: UserDefaults = .standard) {
          self.defaults = defaults
          if let data = defaults.data(forKey: Self.storageKey),
             let decoded = try? JSONDecoder().decode([TerminalProfile].self, from: data) {
              self.profiles = decoded
          } else {
              self.profiles = []
          }
      }

      private func persist() {
          guard let data = try? JSONEncoder().encode(profiles) else { return }
          defaults.set(data, forKey: Self.storageKey)
      }
  }
  ```

- [ ] **Step 9: Testi çalıştır — PASS bekle**
  ```bash
  xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/ProfileStoreTests 2>&1 | tail -20
  ```
  Beklenen: `** TEST SUCCEEDED **`.

- [ ] **Step 10: Commit**
  ```bash
  git add Termora/Services/ProfileStore.swift TermoraTests/ProfileStoreTests.swift
  git commit -m "feat: add ProfileStore persisting to UserDefaults"
  ```

- [ ] **Step 11: Bozuk veri kurtarma testini ekle**
  `TermoraTests/ProfileStoreTests.swift` suite'inin sonuna ekle:
  ```swift
      @Test func corruptBlobFallsBackToEmptyAndIsBackedUp() {
          let (defaults, suiteName) = Self.makeDefaults()
          defer { defaults.removePersistentDomain(forName: suiteName) }

          let garbage = Data("[{broken".utf8)
          defaults.set(garbage, forKey: ProfileStore.storageKey)

          let store = ProfileStore(defaults: defaults)
          #expect(store.profiles.isEmpty)
          #expect(defaults.data(forKey: ProfileStore.backupKey) == garbage)
          #expect(defaults.data(forKey: ProfileStore.storageKey) == nil)
      }
  ```

- [ ] **Step 12: Testi çalıştır — FAIL bekle (backup davranışı henüz yok)**
  ```bash
  xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/ProfileStoreTests 2>&1 | tail -20
  ```
  Beklenen: `Test corruptBlobFallsBackToEmptyAndIsBackedUp() recorded an issue` — `backupKey` boş ve bozuk blob `storageKey`'de duruyor; `** TEST FAILED **`.

- [ ] **Step 13: Kurtarma + backup davranışını ekle**
  `Termora/Services/ProfileStore.swift` dosyasını şu son haliyle değiştir:
  ```swift
  import Foundation
  import Observation
  import os

  @MainActor
  @Observable
  final class ProfileStore {
      static let storageKey = "profiles.v1"
      static let backupKey = "profiles.v1.corrupt-backup"

      private static let logger = Logger(subsystem: "com.ahmetbarut.Termora", category: "ProfileStore")

      var profiles: [TerminalProfile] {
          didSet { persist() }
      }

      private let defaults: UserDefaults

      init(defaults: UserDefaults = .standard) {
          self.defaults = defaults
          guard let data = defaults.data(forKey: Self.storageKey) else {
              self.profiles = []
              return
          }
          if let decoded = try? JSONDecoder().decode([TerminalProfile].self, from: data) {
              self.profiles = decoded
          } else {
              defaults.set(data, forKey: Self.backupKey)
              defaults.removeObject(forKey: Self.storageKey)
              Self.logger.error("Corrupt profiles blob moved to \(Self.backupKey, privacy: .public); falling back to empty list")
              self.profiles = []
          }
      }

      private func persist() {
          guard let data = try? JSONEncoder().encode(profiles) else { return }
          defaults.set(data, forKey: Self.storageKey)
      }
  }
  ```

- [ ] **Step 14: Tüm suite'i çalıştır — PASS bekle**
  ```bash
  xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/ProfileStoreTests 2>&1 | tail -20
  ```
  Beklenen: 3 testin tamamı geçer, `** TEST SUCCEEDED **`.

- [ ] **Step 15: Commit**
  ```bash
  git add Termora/Services/ProfileStore.swift TermoraTests/ProfileStoreTests.swift
  git commit -m "feat: back up corrupt profiles blob before restoring defaults"
  ```

---

---

### Task 8: TerminalSession, TermoraTerminalView, SessionManager (M1)

**Files:**
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Models/TerminalSession.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Views/Terminal/TermoraTerminalView.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Services/ProcessProbe.swift` (Task 9 bunu `currentWorkingDirectory` ile tamamlar)
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Services/SessionManager.swift`
- Delete: `/Users/ahmetbarut/Apps/Termora/Termora/Services/SwiftTermLinkCheck.swift` (Task 1'in geçici bağlantı kontrolü; gerçek SwiftTerm kullanımı geldiği için Step 10'da `git rm` ile silinir)
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/TerminalSessionTests.swift`
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/TermoraTerminalViewTests.swift`
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/ProcessProbeTests.swift`
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/SessionManagerTests.swift`

**Interfaces:**

*Consumes:*
- Task 2 — `ExitStatus(rawStatus: Int32)`, `.exitCode: Int32?`, `.signal: Int32?`
- Task 3 — `EnvironmentBuilder.environment(extra: [String: String]) -> [String]`
- Task 4 — `ShellService.defaultShellPath() -> String`, `ShellService.loginArgv0(forShellPath: String) -> String`
- Task 5 — `ThemeStore.init(bundle:)`, `ThemeStore.theme(id: String) -> Theme`, `Theme.swiftTermAnsiColors() -> [SwiftTerm.Color]`, `Theme.backgroundNSColor/foregroundNSColor/cursorNSColor: NSColor`
- Task 6 — `SettingsStore.init(defaults: UserDefaults)`, `SettingsStore.settings: AppSettings`, `CursorStyleSetting.swiftTermStyle: SwiftTerm.CursorStyle`
- Task 7 — `TerminalProfile` (memberwise init; `Optional` alanların varsayılanı `nil`), `ProfileStore.init(defaults: UserDefaults = .standard)`, `ProfileStore.profiles: [TerminalProfile]`

*Produces:*
- `enum ProcessState: Equatable { case running; case exited(ExitStatus) }`
- `@Observable final class TerminalSession: Identifiable` — `init(id: UUID = UUID(), shellPath: String, profileID: UUID? = nil, workingDirectory: String? = nil)`, `var shellPath: String` (yeniden başlatma varsayılan shell'e düşerse güncellenir), `var launchFailure: String?` (shell çalıştırılamadıysa denenen yol; başarılı başlatmada `nil`), `var restartGeneration: Int` (yeniden başlatma sayacı — panel `TerminalHostView`'ı `.id(session.restartGeneration)` ile anahtarlar ki SwiftUI ölü NSView'ı bırakıp yenisini kursun; yalnız `SessionManager` yazar)
- `final class TermoraTerminalView: LocalProcessTerminalView` — `let sessionID: UUID`, `init(sessionID: UUID, frame: CGRect)`, `override func performKeyEquivalent(with: NSEvent) -> Bool` (⌘ kombinasyonlarını menüye bırakır)
- `enum ProcessProbe` — `nonisolated static func hasForegroundJob(masterFD: Int32, shellPID: pid_t) -> Bool`, `nonisolated static func isAlive(pid: pid_t) -> Bool`
- `@MainActor protocol SessionManaging: AnyObject` — `createSession(profile:workingDirectory:)`, `session(id:)`, `terminateSession(id:)`, `hasRunningProcess(sessionID:)`, **`func restartSession(id: UUID, forceDefaultShell: Bool)`** (spec §8: panel açık kalır, aynı `sessionID` ile yeni shell başlar; `forceDefaultShell == true` iken ayar/profil yolu yok sayılıp `ShellService.defaultShellPath()` kullanılır. Protokolde varsayılan argüman YOKTUR — `any SessionManaging` üzerinden her çağrı iki argümanı da verir; `MockSessionManager` bunu `restartedSessionIDs`'e kaydederek gerçekler.)
- `@MainActor @Observable final class SessionManager: SessionManaging, LocalProcessTerminalViewDelegate` — `init(settings: SettingsStore, themes: ThemeStore, profiles: ProfileStore, escalationDelay: TimeInterval = 1.5)`, `func terminalView(for sessionID: UUID) -> TermoraTerminalView?`, `func applyAppearanceToAllSessions()`, `func restartSession(id: UUID, forceDefaultShell: Bool)`, `static func resolveFont(name: String?, size: Double) -> NSFont` (Task 18'de `FontCatalog.resolvedFont` ile değiştirilir), `static func workingDirectory(fromHostReport report: String?) -> String?`
- Task 19'un dolduracağı özel yüzey (bu görevde adı ve imzası kesinleşir, gövdesi M1'de sade kalır): `private func applyAppearance(to view: TermoraTerminalView, sessionID: UUID)` — `apply(appearanceTo:)` adı planın hiçbir yerinde kullanılmaz.

**Notlar (bu görevde uyulacak teknik kısıtlar):**
- App hedefinde `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` açık (pbxproj'da doğrulandı). Bu yüzden SwiftTerm'ün izole olmayan delegate metotları `nonisolated` yazılıp gövdede `MainActor.assumeIsolated` ile ana aktöre girilir. `LocalProcess` delegate'i `DispatchQueue.main` üzerinde çağırır (`LocalProcess.swift:127` — `dispatchQueue ?? DispatchQueue.main`), dolayısıyla `assumeIsolated` güvenlidir.
- `ProcessProbe`'un statik fonksiyonları `nonisolated` işaretlenir; `DispatchQueue.main.asyncAfter` bloğu (izole olmayan `@Sendable` closure) içinden çağrılabilmesi için bu şarttır.
- Task 1 test hedefine de `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` ekler; yine de `SessionManager`/`TerminalSession`/`TermoraTerminalView`'a dokunan suite'ler açıkça `@MainActor` işaretlenir (Global Constraints kuralı; ayarın hedefte olup olmamasından bağımsız derlenir).

- [ ] **Step 1: TerminalSession testini yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/TerminalSessionTests.swift`:

```swift
//
//  TerminalSessionTests.swift
//  TermoraTests
//

import Foundation
import Testing
@testable import Termora

@MainActor
struct TerminalSessionTests {

    @Test func initialisesWithRunningStateAndEmptyTitle() {
        let session = TerminalSession(shellPath: "/bin/zsh")

        #expect(session.shellPath == "/bin/zsh")
        #expect(session.profileID == nil)
        #expect(session.workingDirectory == nil)
        #expect(session.title == "")
        #expect(session.processState == .running)
        #expect(session.launchFailure == nil)
    }

    @Test func keepsTheIdentityAndOptionalArgumentsItWasGiven() {
        let id = UUID()
        let profileID = UUID()
        let session = TerminalSession(
            id: id,
            shellPath: "/bin/bash",
            profileID: profileID,
            workingDirectory: "/tmp"
        )

        #expect(session.id == id)
        #expect(session.shellPath == "/bin/bash")
        #expect(session.profileID == profileID)
        #expect(session.workingDirectory == "/tmp")
    }

    @Test func exitedStateCarriesADecodedExitStatus() {
        let session = TerminalSession(shellPath: "/bin/zsh")

        session.processState = .exited(ExitStatus(rawStatus: 256))

        #expect(session.processState == .exited(ExitStatus(rawStatus: 256)))
        #expect(session.processState != .running)

        guard case .exited(let status) = session.processState else {
            Issue.record("processState should be .exited")
            return
        }
        #expect(status.exitCode == 1)
        #expect(status.signal == nil)
    }

    @Test func signalledExitIsDistinguishableFromANormalExit() {
        let session = TerminalSession(shellPath: "/bin/zsh")

        session.processState = .exited(ExitStatus(rawStatus: SIGKILL))

        guard case .exited(let status) = session.processState else {
            Issue.record("processState should be .exited")
            return
        }
        #expect(status.signal == SIGKILL)
        #expect(status.exitCode == nil)
    }
}
```

- [ ] **Step 2: Testi çalıştır, FAIL bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/TerminalSessionTests 2>&1 | tail -20
```

Beklenen: derleme hatası — `error: cannot find 'TerminalSession' in scope` ve `error: cannot infer contextual base in reference to member 'running'`, ardından `** TEST BUILD FAILED **`.

- [ ] **Step 3: TerminalSession'ı yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Models/TerminalSession.swift`:

```swift
//
//  TerminalSession.swift
//  Termora
//

import Foundation
import Observation

/// Lifecycle of the shell process behind a session.
enum ProcessState: Equatable {
    case running
    case exited(ExitStatus)
}

/// One shell process plus everything the UI shows about it.
/// The AppKit view that renders it lives in `SessionManager`'s cache, not here:
/// the session outlives any particular SwiftUI representable.
@Observable
final class TerminalSession: Identifiable {
    let id: UUID
    let profileID: UUID?

    /// Not `let`: `SessionManager.restartSession(id:forceDefaultShell:)` may bring the session
    /// back up on the default shell after a broken path, and the status bar must then show the
    /// shell that is actually running.
    var shellPath: String

    var workingDirectory: String?
    var title: String = ""
    var processState: ProcessState = .running

    /// The shell path that could not be executed, or nil after a successful start.
    /// Spec §8: the pane draws an in-pane error banner with a "try the default shell" action.
    var launchFailure: String?

    /// Bumped by `SessionManager.restartSession(id:forceDefaultShell:)`, which installs a brand
    /// new AppKit view for the same session id. SwiftUI would otherwise keep showing the dead
    /// one, so the pane keys its `TerminalHostView` on this value. Only `SessionManager` writes it.
    var restartGeneration: Int = 0

    init(
        id: UUID = UUID(),
        shellPath: String,
        profileID: UUID? = nil,
        workingDirectory: String? = nil
    ) {
        self.id = id
        self.shellPath = shellPath
        self.profileID = profileID
        self.workingDirectory = workingDirectory
    }
}
```

- [ ] **Step 4: Testi çalıştır, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/TerminalSessionTests 2>&1 | tail -20
```

Beklenen: `Test Suite 'TerminalSessionTests' passed` / `** TEST SUCCEEDED **` (4 test).

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora
git add Termora/Models/TerminalSession.swift TermoraTests/TerminalSessionTests.swift
git commit -m "feat: add TerminalSession model with process state"
```

- [ ] **Step 6: TermoraTerminalView testini yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/TermoraTerminalViewTests.swift`:

```swift
//
//  TermoraTerminalViewTests.swift
//  TermoraTests
//

import AppKit
import Foundation
import Testing
@testable import Termora

@MainActor
struct TermoraTerminalViewTests {

    private func makeView(sessionID: UUID = UUID()) -> TermoraTerminalView {
        TermoraTerminalView(
            sessionID: sessionID,
            frame: CGRect(x: 0, y: 0, width: 400, height: 240)
        )
    }

    @Test func remembersItsSessionIdentifier() {
        let id = UUID()
        #expect(makeView(sessionID: id).sessionID == id)
    }

    @Test func swallowsZeroSizedLayoutPasses() {
        let view = makeView()

        view.setFrameSize(NSSize(width: 0, height: 240))
        #expect(view.frame.size == NSSize(width: 400, height: 240))

        view.setFrameSize(NSSize(width: 400, height: 0))
        #expect(view.frame.size == NSSize(width: 400, height: 240))

        view.setFrameSize(NSSize(width: 0, height: 0))
        #expect(view.frame.size == NSSize(width: 400, height: 240))
    }

    @Test func swallowsNegativeSizedLayoutPasses() {
        let view = makeView()

        view.setFrameSize(NSSize(width: -10, height: -10))

        #expect(view.frame.size == NSSize(width: 400, height: 240))
    }

    @Test func acceptsPositiveSizes() {
        let view = makeView()

        view.setFrameSize(NSSize(width: 320, height: 180))

        #expect(view.frame.size == NSSize(width: 320, height: 180))
    }

    @Test func commandShortcutsAreLeftToTheMenu() throws {
        // Spec §7: application shortcuts must not be swallowed by the terminal.
        let view = makeView()
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "t",
            charactersIgnoringModifiers: "t",
            isARepeat: false,
            keyCode: 17
        ))

        #expect(view.performKeyEquivalent(with: event) == false)
    }
}
```

- [ ] **Step 7: Testi çalıştır, FAIL bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/TermoraTerminalViewTests 2>&1 | tail -20
```

Beklenen: `error: cannot find 'TermoraTerminalView' in scope` + `** TEST BUILD FAILED **`.

- [ ] **Step 8: TermoraTerminalView'ı yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Views/Terminal/TermoraTerminalView.swift`:

```swift
//
//  TermoraTerminalView.swift
//  Termora
//

import AppKit
import Foundation
import SwiftTerm

/// `LocalProcessTerminalView` subclass with the three things Termora needs on top of SwiftTerm:
///
/// 1. It knows which session it renders, so `SessionManager` can route delegate callbacks
///    back to a `TerminalSession` from the `source` argument alone.
/// 2. It ignores zero and negative layout passes. SwiftUI hands an `NSViewRepresentable`
///    a 0x0 frame during transient layout; SwiftTerm would recompute a 0-column terminal
///    and push that size onto the PTY with `TIOCSWINSZ`, wrecking the running program.
/// 3. Spec §7 key handling: AppKit offers a ⌘ key equivalent to the key window's view
///    hierarchy *before* the main menu, so a terminal that handles ⌘ itself would swallow
///    ⌘T / ⌘W / ⌘D / ⌘F. Declining every ⌘ combination here hands them to the menu;
///    ⌘C / ⌘V keep working through the standard Edit menu and SwiftTerm's `copy(_:)`/`paste(_:)`.
final class TermoraTerminalView: LocalProcessTerminalView {
    let sessionID: UUID

    init(sessionID: UUID, frame: CGRect) {
        self.sessionID = sessionID
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("TermoraTerminalView is created in code only")
    }

    override func setFrameSize(_ newSize: NSSize) {
        guard newSize.width > 0, newSize.height > 0 else { return }
        super.setFrameSize(newSize)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) { return false }
        return super.performKeyEquivalent(with: event)
    }
}
```

- [ ] **Step 9: Testi çalıştır, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/TermoraTerminalViewTests 2>&1 | tail -20
```

Beklenen: `** TEST SUCCEEDED **` (5 test).

- [ ] **Step 10: Commit**

Gerçek SwiftTerm kullanımı geldiği için Task 1'in geçici bağlantı kontrolü dosyası da bu commit'te düşer:

```bash
cd /Users/ahmetbarut/Apps/Termora
git rm Termora/Services/SwiftTermLinkCheck.swift
git add Termora/Views/Terminal/TermoraTerminalView.swift TermoraTests/TermoraTerminalViewTests.swift
git commit -m "feat: add TermoraTerminalView with zero-size layout guard"
```

- [ ] **Step 11: ProcessProbe'un SessionManager'ın ihtiyaç duyduğu iki fonksiyonu için test yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/ProcessProbeTests.swift` (Task 9 bu dosyaya test ekleyecek):

```swift
//
//  ProcessProbeTests.swift
//  TermoraTests
//

import Darwin
import Foundation
import Testing
@testable import Termora

struct ProcessProbeTests {

    @Test func aClosedOrInvalidMasterDescriptorReportsNoForegroundJob() {
        // tcgetpgrp() returns -1 for a closed/invalid descriptor; that must read as "idle",
        // never as "busy", otherwise closing a tab would always ask for confirmation.
        #expect(ProcessProbe.hasForegroundJob(masterFD: -1, shellPID: 1234) == false)
    }

    @Test func livenessFollowsProcessExistence() {
        #expect(ProcessProbe.isAlive(pid: getpid()) == true)
        #expect(ProcessProbe.isAlive(pid: 999_999) == false)
    }

    @Test func nonPositivePidsAreNeverAlive() {
        // kill(0, 0) would signal our own process group, so pid <= 0 must short-circuit.
        #expect(ProcessProbe.isAlive(pid: 0) == false)
        #expect(ProcessProbe.isAlive(pid: -1) == false)
    }
}
```

- [ ] **Step 12: Testi çalıştır, FAIL bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/ProcessProbeTests 2>&1 | tail -20
```

Beklenen: `error: cannot find 'ProcessProbe' in scope` + `** TEST BUILD FAILED **`.

- [ ] **Step 13: ProcessProbe'u yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Services/ProcessProbe.swift`:

```swift
//
//  ProcessProbe.swift
//  Termora
//

import Darwin
import Foundation

/// Dependency-free wrappers around the POSIX / libproc calls Termora needs in order to
/// reason about the shell processes it started. Everything here is `nonisolated` on
/// purpose: these are plain syscalls and they are called from GCD blocks that carry no
/// actor isolation.
enum ProcessProbe {

    /// True when the pseudo-terminal's foreground process group is something other than the
    /// shell itself, i.e. the user is running a command right now.
    ///
    /// `tcgetpgrp` returns -1 for a closed or invalid descriptor; per the design doc that
    /// counts as "nothing is running" so a torn-down session never blocks a close.
    nonisolated static func hasForegroundJob(masterFD: Int32, shellPID: pid_t) -> Bool {
        let foregroundGroup = tcgetpgrp(masterFD)
        guard foregroundGroup > 0 else { return false }
        return foregroundGroup != shellPID
    }

    /// True while `pid` still exists. A zombie (exited but not yet reaped) also counts as
    /// existing, which is what the SIGTERM -> SIGKILL escalation wants: it reaps in that case.
    /// Only valid for our own children — for foreign processes `kill` may fail with EPERM.
    nonisolated static func isAlive(pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0
    }
}
```

- [ ] **Step 14: Testi çalıştır, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/ProcessProbeTests 2>&1 | tail -20
```

Beklenen: `** TEST SUCCEEDED **` (3 test).

- [ ] **Step 15: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora
git add Termora/Services/ProcessProbe.swift TermoraTests/ProcessProbeTests.swift
git commit -m "feat: add ProcessProbe foreground-job and liveness checks"
```

- [ ] **Step 16: SessionManager'ın saf fonksiyonları için test yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/SessionManagerTests.swift`:

```swift
//
//  SessionManagerTests.swift
//  TermoraTests
//

import AppKit
import Darwin
import Foundation
import SwiftTerm
import Testing
@testable import Termora

@MainActor
struct SessionManagerTests {

    @Test func fontResolutionFallsBackToTheMonospacedSystemFont() {
        let expectedFallback = NSFont.monospacedSystemFont(ofSize: 17, weight: .regular)

        let noName = SessionManager.resolveFont(name: nil, size: 13)
        #expect(noName.pointSize == 13)
        #expect(noName.fontName == NSFont.monospacedSystemFont(ofSize: 13, weight: .regular).fontName)

        let emptyName = SessionManager.resolveFont(name: "", size: 17)
        #expect(emptyName.fontName == expectedFallback.fontName)

        let unknownName = SessionManager.resolveFont(name: "ThereIsNoSuchFont-42", size: 17)
        #expect(unknownName.fontName == expectedFallback.fontName)
        #expect(unknownName.pointSize == 17)
    }

    @Test func fontResolutionHonoursAnInstalledFont() {
        let menlo = SessionManager.resolveFont(name: "Menlo-Regular", size: 15)

        #expect(menlo.fontName == "Menlo-Regular")
        #expect(menlo.pointSize == 15)
    }

    @Test func hostDirectoryReportsAreParsedIntoPlainPaths() {
        #expect(SessionManager.workingDirectory(fromHostReport: "file:///private/tmp") == "/private/tmp")
        #expect(SessionManager.workingDirectory(fromHostReport: "file://localhost/usr/local") == "/usr/local")
        #expect(SessionManager.workingDirectory(fromHostReport: "/Users/test/dev") == "/Users/test/dev")
    }

    @Test func unusableHostDirectoryReportsAreIgnored() {
        #expect(SessionManager.workingDirectory(fromHostReport: nil) == nil)
        #expect(SessionManager.workingDirectory(fromHostReport: "") == nil)
        #expect(SessionManager.workingDirectory(fromHostReport: "http://example.com/x") == nil)
    }
}
```

- [ ] **Step 17: Testi çalıştır, FAIL bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/SessionManagerTests 2>&1 | tail -20
```

Beklenen: `error: cannot find 'SessionManager' in scope` + `** TEST BUILD FAILED **`.

- [ ] **Step 18: SessionManager'ı yaz (yaratma, cache, görünüm uygulama, saf yardımcılar, boş delegate gövdeleri)**

`/Users/ahmetbarut/Apps/Termora/Termora/Services/SessionManager.swift`:

```swift
//
//  SessionManager.swift
//  Termora
//

import AppKit
import Foundation
import Observation
import SwiftTerm
import os

/// The surface `WorkspaceViewModel` depends on, so window logic can be tested with a mock.
@MainActor
protocol SessionManaging: AnyObject {
    func createSession(profile: TerminalProfile?, workingDirectory: String?) -> TerminalSession
    func session(id: UUID) -> TerminalSession?
    func terminateSession(id: UUID)
    func hasRunningProcess(sessionID: UUID) -> Bool
}

/// Single owner of terminal session lifetime.
///
/// It creates the shell, caches the AppKit view keyed by session id — so SwiftUI may tear
/// the representable down and rebuild it without killing the process or losing scrollback —
/// applies appearance settings to every live terminal, and shuts processes down
/// deterministically (SIGTERM, then SIGKILL).
@MainActor
@Observable
final class SessionManager: SessionManaging, LocalProcessTerminalViewDelegate {

    private let settings: SettingsStore
    private let themes: ThemeStore
    private let profiles: ProfileStore
    private let escalationDelay: TimeInterval
    private let logger = Logger(subsystem: "com.ahmetbarut.Termora", category: "SessionManager")

    private var sessions: [UUID: TerminalSession] = [:]
    @ObservationIgnored private var views: [UUID: TermoraTerminalView] = [:]

    /// `profiles` is injected from day one: `restartSession` needs the session's profile to
    /// bring the shell back up with the same environment, and Task 19 resolves the per-profile
    /// theme/font override through the same store. Every call site (AppServices, tests) is
    /// written against this initialiser, so the object graph is never rewired later.
    init(
        settings: SettingsStore,
        themes: ThemeStore,
        profiles: ProfileStore,
        escalationDelay: TimeInterval = 1.5
    ) {
        self.settings = settings
        self.themes = themes
        self.profiles = profiles
        self.escalationDelay = escalationDelay
    }

    // MARK: - SessionManaging

    func createSession(profile: TerminalProfile?, workingDirectory: String?) -> TerminalSession {
        let shellPath = resolveShellPath(profile: profile)
        let directory = workingDirectory
            ?? profile?.startupDirectory
            ?? settings.settings.startupDirectory

        let session = TerminalSession(
            shellPath: shellPath,
            profileID: profile?.id,
            workingDirectory: directory
        )
        sessions[session.id] = session

        let view = makeView(sessionID: session.id)
        views[session.id] = view

        startShell(
            shellPath,
            in: view,
            session: session,
            environment: profile?.environment ?? [:],
            startupCommand: profile?.startupCommand,
            workingDirectory: directory
        )

        return session
    }

    func session(id: UUID) -> TerminalSession? {
        sessions[id]
    }

    func terminateSession(id: UUID) {
        sessions[id] = nil
        guard let view = views.removeValue(forKey: id) else { return }
        view.processDelegate = nil
        killProcess(of: view)
    }

    func hasRunningProcess(sessionID: UUID) -> Bool {
        guard let process = views[sessionID]?.process else { return false }
        return ProcessProbe.hasForegroundJob(masterFD: process.childfd, shellPID: process.shellPid)
    }

    // MARK: - Shell lifecycle

    /// A terminal view wired to this manager and dressed in the current appearance.
    private func makeView(sessionID: UUID) -> TermoraTerminalView {
        let view = TermoraTerminalView(
            sessionID: sessionID,
            frame: CGRect(x: 0, y: 0, width: 640, height: 400)
        )
        view.processDelegate = self
        applyAppearance(to: view, sessionID: sessionID)
        return view
    }

    /// Starts `shellPath` behind `view`, or records the failure on the session.
    ///
    /// §8: X_OK is checked before `startProcess`, otherwise `forkpty` succeeds and the child
    /// dies silently inside `exec` with nothing to show the user. `launchFailure` is what the
    /// pane's error banner (M3) reads in order to offer "try the default shell".
    private func startShell(
        _ shellPath: String,
        in view: TermoraTerminalView,
        session: TerminalSession,
        environment: [String: String],
        startupCommand: String?,
        workingDirectory: String?
    ) {
        guard access(shellPath, X_OK) == 0 else {
            logger.error("Shell is not executable: \(shellPath, privacy: .public)")
            view.feed(text: "Termora: cannot execute \(shellPath)\r\n")
            session.launchFailure = shellPath
            session.processState = .exited(ExitStatus(rawStatus: 127 << 8))
            return
        }

        session.launchFailure = nil
        view.startProcess(
            executable: shellPath,
            args: [],
            environment: EnvironmentBuilder.environment(extra: environment),
            execName: ShellService.loginArgv0(forShellPath: shellPath),
            currentDirectory: workingDirectory
        )

        if let startupCommand, !startupCommand.isEmpty {
            view.send(txt: startupCommand + "\n")
        }
    }

    /// SIGTERM now, SIGKILL after `escalationDelay` if the shell is still there.
    /// The caller has already dropped the view from `views` and cleared its delegate.
    private func killProcess(of view: TermoraTerminalView) {
        let pid = view.process.shellPid
        guard pid > 0 else { return }

        view.terminate() // SwiftTerm sends SIGTERM to the shell pid only.

        DispatchQueue.main.asyncAfter(deadline: .now() + escalationDelay) {
            var status: Int32 = 0
            // != 0 covers both "we reaped it" (> 0) and "already gone" (-1/ECHILD).
            if waitpid(pid, &status, WNOHANG) != 0 { return }
            kill(pid, SIGKILL)
            _ = waitpid(pid, &status, 0) // returns immediately once SIGKILL lands
        }
    }

    // MARK: - View cache

    /// The cached AppKit view for a session. Never creates one: views come into existence
    /// together with their session in `createSession` and die in `terminateSession`.
    func terminalView(for sessionID: UUID) -> TermoraTerminalView? {
        views[sessionID]
    }

    // MARK: - Appearance

    /// One-way settings flow (§3.5): settings change -> every open terminal is updated.
    func applyAppearanceToAllSessions() {
        for (sessionID, view) in views {
            applyAppearance(to: view, sessionID: sessionID)
        }
    }

    /// M1 applies the global settings to every terminal alike. `sessionID` is already part of
    /// the signature because Task 19 resolves the session's profile through it (per-profile
    /// theme and font overrides); the name and the parameter list are final from here on.
    private func applyAppearance(to view: TermoraTerminalView, sessionID: UUID) {
        let current = settings.settings
        let theme = themes.theme(id: current.themeID)

        view.font = Self.resolveFont(name: current.fontName, size: current.fontSize)
        view.lineSpacing = CGFloat(current.lineSpacing)
        view.nativeForegroundColor = theme.foregroundNSColor

        let opacity = min(max(current.windowOpacity, 0.2), 1.0)
        view.nativeBackgroundColor = opacity < 1.0
            ? theme.backgroundNSColor.withAlphaComponent(CGFloat(opacity))
            : theme.backgroundNSColor

        view.caretColor = theme.cursorNSColor
        view.installColors(theme.swiftTermAnsiColors())
        view.getTerminal().setCursorStyle(current.cursorStyle.swiftTermStyle)
        view.changeScrollback(current.scrollbackLines)
    }

    /// Pure: a missing, empty or unknown font name falls back to the system monospaced face.
    static func resolveFont(name: String?, size: Double) -> NSFont {
        let pointSize = CGFloat(size)
        guard let name, !name.isEmpty, let font = NSFont(name: name, size: pointSize) else {
            return NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        }
        return font
    }

    /// Pure: OSC 7 payloads arrive as `file:///path`, but some shells emit a bare path.
    static func workingDirectory(fromHostReport report: String?) -> String? {
        guard let report, !report.isEmpty else { return nil }
        if report.hasPrefix("/") { return report }
        guard let url = URL(string: report), url.isFileURL else { return nil }
        return url.path
    }

    private func resolveShellPath(profile: TerminalProfile?) -> String {
        if let path = profile?.shellPath, !path.isEmpty { return path }
        if let path = settings.settings.defaultShellPath, !path.isEmpty { return path }
        return ShellService.defaultShellPath()
    }

    // MARK: - LocalProcessTerminalViewDelegate
    //
    // The conformance is declared on the class itself rather than in an extension because
    // `makeView` assigns `view.processDelegate = self`: without it this file does not compile
    // (`cannot assign value of type 'SessionManager' to type '(any LocalProcessTerminalViewDelegate)?'`).
    // The bodies stay empty until Step 26 — no extension adds the conformance later.
    //
    // SwiftTerm's delegate is not actor-isolated, but `LocalProcess` dispatches every callback
    // on `DispatchQueue.main` (its `dispatchQueue` defaults to the main queue), so the bodies
    // hop in with `MainActor.assumeIsolated` instead of an async detour.

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {}
}
```

- [ ] **Step 19: Testi çalıştır, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/SessionManagerTests 2>&1 | tail -20
```

Beklenen: `** TEST SUCCEEDED **` (4 test).

- [ ] **Step 20: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora
git add Termora/Services/SessionManager.swift TermoraTests/SessionManagerTests.swift
git commit -m "feat: add SessionManager with shell startup and view cache"
```

- [ ] **Step 21: Gerçek PTY yaşam döngüsü testlerini yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/SessionManagerTests.swift` dosyasının **başına** (import'lardan sonra, `struct SessionManagerTests` tanımından önce) dosya kapsamlı yardımcıları ekle:

```swift
// MARK: - Test helpers

/// Fresh store stack on an isolated UserDefaults suite so tests never see (or leave) real settings.
@MainActor
private func makeStack(escalationDelay: TimeInterval = 1.5) -> (settings: SettingsStore, manager: SessionManager) {
    // Swift Testing runs these tests in parallel by default, so the suite name must be unique
    // per call: a shared suite would let one test wipe another test's defaultShellPath.
    let suiteName = "TermoraTests.SessionManager.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let settings = SettingsStore(defaults: defaults)
    settings.settings.defaultShellPath = "/bin/zsh"

    let manager = SessionManager(
        settings: settings,
        themes: ThemeStore(),
        profiles: ProfileStore(defaults: defaults),
        escalationDelay: escalationDelay
    )
    return (settings, manager)
}

/// A profile whose ZDOTDIR points at an empty directory, so the developer's own ~/.zshrc
/// cannot make these PTY tests slow or flaky.
private func makeHermeticProfile() throws -> TerminalProfile {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("TermoraTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return TerminalProfile(
        name: "Hermetic",
        shellPath: "/bin/zsh",
        environment: ["ZDOTDIR": directory.path]
    )
}

/// Polls `condition` while yielding to the main run loop — SwiftTerm drains the PTY master
/// on the main queue, so a blocking sleep here would stall the shell and hang the test.
@MainActor
private func poll(timeout: Duration = .seconds(10), until condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(100))
    }
    return condition()
}
```

Ardından `struct SessionManagerTests` gövdesine şu testleri ekle:

```swift
    @Test func createSessionRegistersBothTheSessionAndItsView() throws {
        let (_, manager) = makeStack()
        let session = manager.createSession(profile: try makeHermeticProfile(), workingDirectory: nil)
        defer { manager.terminateSession(id: session.id) }

        #expect(manager.session(id: session.id)?.shellPath == "/bin/zsh")
        #expect(manager.session(id: session.id)?.processState == .running)

        let view = try #require(manager.terminalView(for: session.id))
        #expect(view.sessionID == session.id)
        #expect(view.process.shellPid > 0)
        #expect(view.process.childfd >= 0)

        #expect(manager.terminalView(for: UUID()) == nil)
        #expect(manager.session(id: UUID()) == nil)
    }

    @Test func anIdleShellIsNotBusyButAForegroundCommandIs() async throws {
        let (_, manager) = makeStack()
        let session = manager.createSession(profile: try makeHermeticProfile(), workingDirectory: nil)
        defer { manager.terminateSession(id: session.id) }
        let view = try #require(manager.terminalView(for: session.id))

        let becameIdle = await poll { manager.hasRunningProcess(sessionID: session.id) == false }
        #expect(becameIdle, "an idle shell must not report a foreground job")

        view.send(txt: "sleep 5\n")

        let becameBusy = await poll { manager.hasRunningProcess(sessionID: session.id) }
        #expect(becameBusy, "`sleep 5` must show up as a foreground job")
    }

    @Test func terminateSessionKillsTheShellAndDropsItFromTheCache() async throws {
        let (_, manager) = makeStack(escalationDelay: 0.05)
        let session = manager.createSession(profile: try makeHermeticProfile(), workingDirectory: nil)
        let view = try #require(manager.terminalView(for: session.id))
        let pid = view.process.shellPid

        let started = await poll { ProcessProbe.isAlive(pid: pid) }
        #expect(started)

        manager.terminateSession(id: session.id)

        #expect(manager.terminalView(for: session.id) == nil)
        #expect(manager.session(id: session.id) == nil)
        #expect(manager.hasRunningProcess(sessionID: session.id) == false)

        let died = await poll { ProcessProbe.isAlive(pid: pid) == false }
        #expect(died, "SIGTERM/SIGKILL escalation must reap the shell")
    }

    @Test func terminatingAnUnknownSessionIsAHarmlessNoOp() {
        let (_, manager) = makeStack()
        manager.terminateSession(id: UUID())
    }
```

- [ ] **Step 22: Testi çalıştır, PASS bekle (gerçek PTY karakterizasyonu)**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/SessionManagerTests 2>&1 | tail -30
```

Bu testler Step 18'de yazılan implementasyona karşı koşar ve ilk çalıştırmada geçmelidir (kırmızıdan yeşile geçiş değil, gerçek PTY davranışının karakterizasyonudur). Beklenen çıktı: `** TEST SUCCEEDED **` (8 test). Eğer `becameBusy` false gelirse `hasRunningProcess` yanlıştır (çoğu zaman `childfd`/`shellPid` karışması); eğer `died` false gelirse `terminateSession`'daki eskalasyon bloğu çalışmıyordur (ana kuyruk beslenmemiş olabilir) — düzeltip tekrar çalıştır.

- [ ] **Step 23: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora
git add TermoraTests/SessionManagerTests.swift
git commit -m "test: cover SessionManager shell lifecycle against a real PTY"
```

- [ ] **Step 24: Delegate yönlendirme ve görünüm uygulama testlerini yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/SessionManagerTests.swift` içine ekle:

```swift
    @Test func delegateCallbacksAreRoutedByTheViewsSessionIdentifier() throws {
        let (_, manager) = makeStack()
        let session = manager.createSession(profile: try makeHermeticProfile(), workingDirectory: nil)
        defer { manager.terminateSession(id: session.id) }

        // A detached view proves routing goes through `sessionID`, not object identity.
        let detached = TermoraTerminalView(
            sessionID: session.id,
            frame: CGRect(x: 0, y: 0, width: 400, height: 240)
        )

        manager.setTerminalTitle(source: detached, title: "make build")
        #expect(session.title == "make build")

        manager.hostCurrentDirectoryUpdate(source: detached, directory: "file:///private/tmp")
        #expect(session.workingDirectory == "/private/tmp")

        manager.hostCurrentDirectoryUpdate(source: detached, directory: nil)
        #expect(session.workingDirectory == "/private/tmp", "an empty OSC 7 report must not clear the cwd")

        manager.processTerminated(source: detached, exitCode: 256)
        #expect(session.processState == .exited(ExitStatus(rawStatus: 256)))
    }

    @Test func delegateCallbacksFromForeignViewsAreIgnored() throws {
        let (_, manager) = makeStack()
        let session = manager.createSession(profile: try makeHermeticProfile(), workingDirectory: nil)
        defer { manager.terminateSession(id: session.id) }

        let stranger = TermoraTerminalView(
            sessionID: UUID(),
            frame: CGRect(x: 0, y: 0, width: 400, height: 240)
        )

        manager.setTerminalTitle(source: stranger, title: "not mine")
        manager.processTerminated(source: stranger, exitCode: 9)

        #expect(session.title == "")
        #expect(session.processState == .running)
    }

    @Test func appearanceSettingsReachEveryOpenTerminal() throws {
        let (settings, manager) = makeStack()
        let session = manager.createSession(profile: try makeHermeticProfile(), workingDirectory: nil)
        defer { manager.terminateSession(id: session.id) }
        let view = try #require(manager.terminalView(for: session.id))

        settings.settings.fontName = "Menlo-Regular"
        settings.settings.fontSize = 18
        settings.settings.lineSpacing = 1.4
        settings.settings.windowOpacity = 0.8
        manager.applyAppearanceToAllSessions()

        #expect(view.font.fontName == "Menlo-Regular")
        #expect(view.font.pointSize == 18)
        #expect(view.lineSpacing == 1.4)
        #expect(abs(view.nativeBackgroundColor.alphaComponent - 0.8) < 0.001)

        settings.settings.windowOpacity = 1.0
        manager.applyAppearanceToAllSessions()
        #expect(abs(view.nativeBackgroundColor.alphaComponent - 1.0) < 0.001)
    }
```

- [ ] **Step 25: Testi çalıştır, FAIL bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/SessionManagerTests 2>&1 | tail -30
```

Beklenen: testler **derlenir** (dört delegate metodu Step 18'de boş gövdelerle sınıfta duruyor) ama `delegateCallbacksAreRoutedByTheViewsSessionIdentifier` başarısız olur: `Expectation failed: session.title == "make build"` + `** TEST FAILED **`. Diğer iki test (yabancı görünüm yok sayma, görünüm uygulama) bu aşamada zaten geçer.

- [ ] **Step 26: Delegate gövdelerini doldur**

`/Users/ahmetbarut/Apps/Termora/Termora/Services/SessionManager.swift` içindeki `// MARK: - LocalProcessTerminalViewDelegate` bölümünde duran dört boş metodu aşağıdakilerle **değiştir**. Uyum (`conformance`) zaten sınıf bildiriminde olduğu için burada **extension eklenmez**:

```swift
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // SwiftTerm already pushed the new winsize onto the PTY. The status bar consumes
        // cols/rows in M5 (Task 21 fills this body); nothing to do in M1.
    }

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        MainActor.assumeIsolated {
            guard let sessionID = (source as? TermoraTerminalView)?.sessionID else { return }
            sessions[sessionID]?.title = title
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        MainActor.assumeIsolated {
            guard let sessionID = (source as? TermoraTerminalView)?.sessionID,
                  let path = Self.workingDirectory(fromHostReport: directory)
            else { return }
            sessions[sessionID]?.workingDirectory = path
        }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        MainActor.assumeIsolated {
            guard let sessionID = (source as? TermoraTerminalView)?.sessionID else { return }
            // `exitCode` is the raw waitpid status, not a exit code (SwiftTerm passes `n` from
            // `waitpid` straight through). nil means the PTY died before waitpid ran, which we
            // report as "hung up".
            sessions[sessionID]?.processState = .exited(ExitStatus(rawStatus: exitCode ?? SIGHUP))
        }
    }
```

- [ ] **Step 27: Testi çalıştır, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/SessionManagerTests 2>&1 | tail -20
```

Beklenen: `** TEST SUCCEEDED **` (11 test).

- [ ] **Step 28: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora
git add Termora/Services/SessionManager.swift TermoraTests/SessionManagerTests.swift
git commit -m "feat: route SwiftTerm delegate events into terminal sessions"
```

- [ ] **Step 29: Oturum yeniden başlatma testlerini yaz**

Spec §8: shell çıktığında (ya da hiç çalıştırılamadığında) panel açık kalır ve **aynı panelde** yeni bir oturum başlatılabilir. Panel bandını Task 17 çizer; buradaki iş, aynı `sessionID`'yi koruyarak süreci yeniden ayağa kaldıran API'dir.

`/Users/ahmetbarut/Apps/Termora/TermoraTests/SessionManagerTests.swift` içine ekle:

```swift
    @Test func restartSessionPutsAFreshShellBehindTheSameIdentifier() async throws {
        let (_, manager) = makeStack(escalationDelay: 0.05)
        let session = manager.createSession(profile: try makeHermeticProfile(), workingDirectory: nil)
        defer { manager.terminateSession(id: session.id) }

        let firstView = try #require(manager.terminalView(for: session.id))
        let firstPID = firstView.process.shellPid
        let firstStarted = await poll { ProcessProbe.isAlive(pid: firstPID) }
        #expect(firstStarted)

        // The shell exited on its own; the pane is still there and asks for a new one.
        session.processState = .exited(ExitStatus(rawStatus: 0))
        manager.restartSession(id: session.id, forceDefaultShell: false)

        let secondView = try #require(manager.terminalView(for: session.id))
        #expect(secondView !== firstView, "restart must install a brand new view")
        #expect(secondView.sessionID == session.id)
        #expect(manager.session(id: session.id) === session, "the session object must survive")
        #expect(session.processState == .running)
        #expect(session.launchFailure == nil)
        #expect(session.restartGeneration == 1, "the pane keys its host view on this")

        let secondPID = secondView.process.shellPid
        #expect(secondPID > 0)
        #expect(secondPID != firstPID)

        let restarted = await poll { ProcessProbe.isAlive(pid: secondPID) }
        #expect(restarted, "the replacement shell must be running")

        let oldOneDied = await poll { ProcessProbe.isAlive(pid: firstPID) == false }
        #expect(oldOneDied, "the old shell must be reaped, not leaked")
    }

    @Test func aBrokenShellPathIsRecordedAndRecoverableWithTheDefaultShell() async throws {
        let (settings, manager) = makeStack(escalationDelay: 0.05)
        settings.settings.defaultShellPath = "/nonexistent/shell"

        let session = manager.createSession(profile: nil, workingDirectory: nil)
        defer { manager.terminateSession(id: session.id) }

        #expect(session.launchFailure == "/nonexistent/shell")
        #expect(session.processState == .exited(ExitStatus(rawStatus: 127 << 8)))
        #expect((manager.terminalView(for: session.id)?.process.shellPid ?? 0) <= 0)

        // §8 recovery action: ignore the broken setting and come up on the login shell.
        manager.restartSession(id: session.id, forceDefaultShell: true)

        #expect(session.launchFailure == nil)
        #expect(session.processState == .running)
        #expect(session.shellPath == ShellService.defaultShellPath())

        let view = try #require(manager.terminalView(for: session.id))
        let alive = await poll { ProcessProbe.isAlive(pid: view.process.shellPid) }
        #expect(alive, "the default shell must come up even though the setting is broken")
    }

    @Test func restartingAnUnknownSessionIsAHarmlessNoOp() {
        let (_, manager) = makeStack()
        manager.restartSession(id: UUID(), forceDefaultShell: false)
        manager.restartSession(id: UUID(), forceDefaultShell: true)
    }
```

- [ ] **Step 30: Testi çalıştır, FAIL bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/SessionManagerTests 2>&1 | tail -20
```

Beklenen: `error: value of type 'SessionManager' has no member 'restartSession'` + `** TEST BUILD FAILED **`.

- [ ] **Step 31: `restartSession(id:forceDefaultShell:)`'i yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Services/SessionManager.swift` içinde önce protokole yeni gereksinimi ekle (`hasRunningProcess` satırının altına):

```swift
    /// §8: the pane stays open when the shell dies. Restart puts a new shell behind the SAME
    /// session id, so panes, tabs and every id-keyed lookup survive it. `forceDefaultShell`
    /// ignores the settings/profile path and uses the login shell — the recovery action for
    /// "this shell cannot be executed".
    func restartSession(id: UUID, forceDefaultShell: Bool)
```

Ardından `killProcess(of:)`'in altına implementasyonu ekle:

```swift
    func restartSession(id: UUID, forceDefaultShell: Bool) {
        guard let session = sessions[id] else { return }

        if let oldView = views.removeValue(forKey: id) {
            // Clear the delegate first: `terminate()` fires processTerminated on the main queue
            // and it must not overwrite the state of the session we are just reviving.
            oldView.processDelegate = nil
            killProcess(of: oldView)
        }

        let profile = session.profileID.flatMap { profileID in
            profiles.profiles.first { $0.id == profileID }
        }
        let shellPath = forceDefaultShell
            ? ShellService.defaultShellPath()
            : resolveShellPath(profile: profile)
        session.shellPath = shellPath

        let view = makeView(sessionID: id)
        views[id] = view

        // The pane's `TerminalHostView` is keyed on this, so SwiftUI drops the dead NSView and
        // hosts the new one; the session id — and therefore the pane and the tab — stays put.
        session.restartGeneration += 1
        session.processState = .running
        startShell(
            shellPath,
            in: view,
            session: session,
            environment: profile?.environment ?? [:],
            startupCommand: profile?.startupCommand,
            workingDirectory: session.workingDirectory
        )
    }
```

`startShell` başarısız olursa `session.processState`'i tekrar `.exited(...)` yapar ve `launchFailure`'ı doldurur, yani bozuk yolla yeniden deneme sessizce "çalışıyor" görünmez.

- [ ] **Step 32: Testi çalıştır, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/SessionManagerTests 2>&1 | tail -20
```

Beklenen: `** TEST SUCCEEDED **` (14 test).

- [ ] **Step 33: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora
git add Termora/Services/SessionManager.swift TermoraTests/SessionManagerTests.swift
git commit -m "feat: restart a session in place after the shell exits or fails to launch"
```

- [ ] **Step 34: Tüm test hedefini çalıştır**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests 2>&1 | tail -20
git status --short
```

Beklenen: `** TEST SUCCEEDED **` (Task 2-8 arası tüm suite'ler yeşil) ve `git status --short` temiz — bu görevin her parçası Step 5/10/15/20/23/28/33 commit'lerinde tarihçeye girdi.

---

---

### Task 9: ProcessProbe (M1)

**Files:**
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/Services/ProcessProbe.swift` (Task 8'de yaratıldı; `currentWorkingDirectory` burada eklenir)
- Create: `/Users/ahmetbarut/Apps/Termora/TermoraTests/PTYTestHarness.swift` (test yardımcıları `TermoraTests/` kökünde durur — `MockSessionManager.swift` gibi; `Support/` alt klasörü Task 1 iskeletinde açılmaz)
- Modify: `/Users/ahmetbarut/Apps/Termora/TermoraTests/ProcessProbeTests.swift`

**Interfaces:**

*Consumes:*
- Task 8 — `ProcessProbe.hasForegroundJob(masterFD:shellPID:) -> Bool`, `ProcessProbe.isAlive(pid:) -> Bool`

*Produces:*
- `nonisolated static func ProcessProbe.currentWorkingDirectory(pid: pid_t) -> String?`
- Test altyapısı: `struct PTYChild { let master: Int32; let pid: pid_t }`, `enum PTYTestHarness` — `spawn(executable:args:environment:) -> PTYChild`, `drain(_:seconds:) -> String`, `write(_:_:)`, `waitUntil(_:timeout:condition:) -> Bool`, `kill(_:)`

**Doğrulanmış davranış (bu görev yazılırken gerçek makinede ölçüldü):**
- `forkpty` ile başlatılan etkileşimli `/bin/zsh -f -i`: boştayken `tcgetpgrp(master) == shellPid` → `hasForegroundJob == false`; `sleep 5` gönderildiğinde `tcgetpgrp(master)` sleep'in pgid'sine döner → `true` (3/3 tekrar).
- **Kritik:** master fd beklerken boşaltılmazsa (`read`) zsh çıktı tamponunda tıkanır ve `sleep` hiç başlamaz; bu durumda test yanlışlıkla `false` görür. Bu yüzden `waitUntil` her yoklamada `drain` çağırır.
- `close(master)` sonrası `tcgetpgrp` -1 döner → `false`.
- `proc_pidinfo(getpid(), PROC_PIDVNODEPATHINFO, ...)` sonucu `FileManager.default.currentDirectoryPath` ile birebir eşleşti.
- Var olmayan pid (999999) için `proc_pidinfo` boyut eşleşmesi başarısız → `nil`.

- [ ] **Step 1: currentWorkingDirectory testini yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/ProcessProbeTests.swift` içindeki `struct ProcessProbeTests` gövdesine ekle:

```swift
    @Test func readsTheWorkingDirectoryOfThisProcessFromTheKernel() {
        // libproc, not OSC 7: a stock zsh only emits OSC 7 under Terminal.app.
        #expect(ProcessProbe.currentWorkingDirectory(pid: getpid()) == FileManager.default.currentDirectoryPath)
    }

    @Test func theWorkingDirectoryOfAnImpossiblePidIsNil() {
        #expect(ProcessProbe.currentWorkingDirectory(pid: 999_999) == nil)
        #expect(ProcessProbe.currentWorkingDirectory(pid: 0) == nil)
        #expect(ProcessProbe.currentWorkingDirectory(pid: -1) == nil)
    }
```

- [ ] **Step 2: Testi çalıştır, FAIL bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/ProcessProbeTests 2>&1 | tail -20
```

Beklenen: `error: type 'ProcessProbe' has no member 'currentWorkingDirectory'` + `** TEST BUILD FAILED **`.

- [ ] **Step 3: currentWorkingDirectory'yi yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Services/ProcessProbe.swift` içinde `isAlive`'dan **önce** ekle:

```swift
    /// Current working directory of `pid`, read straight from the kernel via libproc.
    ///
    /// `proc_pidinfo` fills a `proc_vnodepathinfo`; `pvi_cdir.vip_path` is a fixed-size C
    /// char tuple, so it is read through `withUnsafeBytes` rather than indexed member by member.
    /// A short return (anything other than the full struct size) means the pid is gone or
    /// not ours, and yields nil.
    nonisolated static func currentWorkingDirectory(pid: pid_t) -> String? {
        guard pid > 0 else { return nil }

        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }

        return withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw -> String? in
            guard let base = raw.baseAddress else { return nil }
            let path = String(cString: base.assumingMemoryBound(to: CChar.self))
            return path.isEmpty ? nil : path
        }
    }
```

- [ ] **Step 4: Testi çalıştır, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/ProcessProbeTests 2>&1 | tail -20
```

Beklenen: `** TEST SUCCEEDED **` (5 test).

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora
git add Termora/Services/ProcessProbe.swift TermoraTests/ProcessProbeTests.swift
git commit -m "feat: read a process working directory via libproc"
```

- [ ] **Step 6: PTY test altyapısını yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/PTYTestHarness.swift`:

```swift
//
//  PTYTestHarness.swift
//  TermoraTests
//

import Darwin
import Foundation

/// A child process running on the far side of a real pseudo-terminal.
struct PTYChild {
    let master: Int32
    let pid: pid_t
}

/// Spawns real processes on real PTYs so `ProcessProbe` can be tested against the kernel
/// behaviour it actually wraps, instead of against a mock of our own assumptions.
///
/// `forkpty` is used rather than `posix_spawn`: only forkpty gives the child a controlling
/// terminal with `setsid` + `TIOCSCTTY`, which is the precondition for shell job control —
/// and job control is exactly what `hasForegroundJob` observes.
enum PTYTestHarness {

    static func spawn(
        executable: String,
        args: [String] = [],
        environment: [String] = [
            "TERM=xterm-256color",
            "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
        ]
    ) -> PTYChild {
        // Everything the child touches is allocated before the fork: after fork() in a
        // multithreaded process only async-signal-safe work is legal until exec.
        let path = strdup(executable)!
        var argv: [UnsafeMutablePointer<CChar>?] = ([executable] + args).map { strdup($0) }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup($0) }
        envp.append(nil)

        var size = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        var master: Int32 = 0
        let pid = forkpty(&master, nil, nil, &size)
        precondition(pid >= 0, "forkpty failed: \(String(cString: strerror(errno)))")

        if pid == 0 {
            execve(path, &argv, &envp)
            _exit(127)
        }

        free(path)
        for pointer in argv { free(pointer) }
        for pointer in envp { free(pointer) }
        return PTYChild(master: master, pid: pid)
    }

    /// Reads whatever the child wrote for `seconds`. A real terminal always drains its master
    /// descriptor; without this the PTY buffer fills, the shell blocks on write, and the
    /// command under test never actually starts.
    @discardableResult
    static func drain(_ child: PTYChild, seconds: Double) -> String {
        var text = ""
        var buffer = [UInt8](repeating: 0, count: 4096)
        let flags = fcntl(child.master, F_GETFL, 0)
        _ = fcntl(child.master, F_SETFL, flags | O_NONBLOCK)

        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            let count = read(child.master, &buffer, buffer.count)
            if count > 0 {
                text += String(decoding: buffer[0..<count], as: UTF8.self)
            } else {
                usleep(20_000)
            }
        }

        _ = fcntl(child.master, F_SETFL, flags)
        return text
    }

    static func write(_ child: PTYChild, _ text: String) {
        text.withCString { _ = Darwin.write(child.master, $0, strlen($0)) }
    }

    /// Polls `condition` while draining, up to `timeout` seconds.
    static func waitUntil(_ child: PTYChild, timeout: Double, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            drain(child, seconds: 0.05)
        }
        return condition()
    }

    /// SIGKILL, reap, close the master descriptor. Safe to call more than once per test run
    /// only through `defer` — the descriptor is closed here.
    static func kill(_ child: PTYChild) {
        Darwin.kill(child.pid, SIGKILL)
        var status: Int32 = 0
        waitpid(child.pid, &status, 0)
        close(child.master)
    }
}
```

- [ ] **Step 7: Derlemeyi doğrula**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/ProcessProbeTests 2>&1 | tail -20
```

Beklenen: `** TEST SUCCEEDED **` (hâlâ 5 test; yeni dosya yalnız derlenir).

- [ ] **Step 8: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora
git add TermoraTests/PTYTestHarness.swift
git commit -m "test: add forkpty harness for pseudo-terminal tests"
```

- [ ] **Step 9: Gerçek PTY entegrasyon testlerini yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/ProcessProbeTests.swift` içindeki `struct ProcessProbeTests` gövdesine ekle:

```swift
    @Test func anIdleShellIsIdleAndAForegroundCommandIsNot() {
        let child = PTYTestHarness.spawn(executable: "/bin/zsh", args: ["-f", "-i"])
        defer { PTYTestHarness.kill(child) }

        PTYTestHarness.drain(child, seconds: 1.0)
        #expect(ProcessProbe.hasForegroundJob(masterFD: child.master, shellPID: child.pid) == false)

        PTYTestHarness.write(child, "sleep 5\n")
        let busy = PTYTestHarness.waitUntil(child, timeout: 5) {
            ProcessProbe.hasForegroundJob(masterFD: child.master, shellPID: child.pid)
        }
        #expect(busy, "zsh puts `sleep` in its own process group and tcsetpgrp's it to the front")
    }

    @Test func theForegroundGroupIsComparedAgainstTheShellPid() {
        // /bin/sleep is the session leader here, so the foreground group *is* the child pid.
        let child = PTYTestHarness.spawn(executable: "/bin/sleep", args: ["5"])
        defer { PTYTestHarness.kill(child) }
        PTYTestHarness.drain(child, seconds: 0.3)

        #expect(ProcessProbe.hasForegroundJob(masterFD: child.master, shellPID: child.pid) == false)
        #expect(ProcessProbe.hasForegroundJob(masterFD: child.master, shellPID: getpid()) == true)
    }

    @Test func aKilledChildIsDeadAndItsClosedDescriptorIsIdle() {
        let child = PTYTestHarness.spawn(executable: "/bin/sleep", args: ["30"])
        #expect(ProcessProbe.isAlive(pid: child.pid) == true)

        PTYTestHarness.kill(child) // SIGKILL + waitpid + close(master)

        #expect(ProcessProbe.isAlive(pid: child.pid) == false)
        #expect(ProcessProbe.hasForegroundJob(masterFD: child.master, shellPID: child.pid) == false)
    }

    @Test func aChildSeesTheWorkingDirectoryItWasStartedIn() {
        let child = PTYTestHarness.spawn(executable: "/bin/sleep", args: ["5"])
        defer { PTYTestHarness.kill(child) }
        PTYTestHarness.drain(child, seconds: 0.3)

        #expect(ProcessProbe.currentWorkingDirectory(pid: child.pid) == FileManager.default.currentDirectoryPath)
    }
```

- [ ] **Step 10: Testi çalıştır, PASS bekle (karakterizasyon adımı)**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/ProcessProbeTests 2>&1 | tail -20
```

Beklenen: `** TEST SUCCEEDED **` (9 test). Bu dört test kırmızıdan yeşile geçiş değil, Task 8'de yazılan `hasForegroundJob`/`isAlive` implementasyonunun **gerçek çekirdek davranışına karşı** doğrulanmasıdır ve ilk çalıştırmada geçmelidir. Geçmezse implementasyon yanlıştır:
- `anIdleShellIsIdleAndAForegroundCommandIsNot` FAIL → `hasForegroundJob` `!= shellPID` karşılaştırmasını yapmıyordur (veya `waitUntil` drain etmiyordur).
- `aKilledChildIsDead...` FAIL → `guard foregroundGroup > 0` dalı eksiktir.

- [ ] **Step 11: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora
git add TermoraTests/ProcessProbeTests.swift
git commit -m "test: verify ProcessProbe against real pseudo-terminals"
```

---

---

### Task 10: Minimal çalışan uygulama (M1 kapanışı)

**Files:**
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/App/AppServices.swift` (uygulamanın tek servis kapsayıcısı; Task 12 bunu yeniden yaratmaz, yalnız kullanır)
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Views/Terminal/TerminalHostView.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Views/MainWindowView.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Views/SettingsPlaceholderView.swift`
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/App/TermoraApp.swift` (Task 1 Step 8'de bu yola taşındı)
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/TerminalHostViewTests.swift`

**Interfaces:**

*Consumes:*
- Task 5 — `ThemeStore.init(bundle:)`
- Task 6 — `SettingsStore.init(defaults:)`
- Task 7 — `ProfileStore.init(defaults:)`
- Task 8 — `SessionManager.init(settings:themes:profiles:escalationDelay:)`, `SessionManager.createSession(profile:workingDirectory:) -> TerminalSession`, `SessionManager.terminalView(for:) -> TermoraTerminalView?`, `TermoraTerminalView`

*Produces:*
- `@MainActor final class AppServices` — `init()`, `let settings: SettingsStore`, `let themes: ThemeStore`, `let profiles: ProfileStore`, `let sessionManager: SessionManager`. Plan boyunca tek servis grafiği budur; `AppEnvironment` diye bir tip hiç var olmaz.
- `struct TerminalHostView: NSViewRepresentable` — `init(sessionID: UUID, sessionManager: SessionManager, isActive: Bool)`, iç sınıf `TerminalHostView.Coordinator` (`shouldRequestFocus(sessionID:isActive:) -> Bool`, `resignFocusTracking()`)
- `struct MainWindowView: View` — `init(services: AppServices)`; özellik adı `private let services` (Task 12 buna `@State private var workspace: WorkspaceViewModel` ekler)
- `struct SettingsPlaceholderView: View`

- [ ] **Step 1: Odak mantığı testini yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/TerminalHostViewTests.swift`:

```swift
//
//  TerminalHostViewTests.swift
//  TermoraTests
//

import Foundation
import Testing
@testable import Termora

@MainActor
struct TerminalHostViewTests {

    @Test func asksForFocusOnceWhileActive() {
        let coordinator = TerminalHostView.Coordinator()
        let sessionID = UUID()

        #expect(coordinator.shouldRequestFocus(sessionID: sessionID, isActive: true) == true)
        #expect(coordinator.shouldRequestFocus(sessionID: sessionID, isActive: true) == false)
        #expect(coordinator.shouldRequestFocus(sessionID: sessionID, isActive: true) == false)
    }

    @Test func neverAsksForFocusWhileInactive() {
        let coordinator = TerminalHostView.Coordinator()

        #expect(coordinator.shouldRequestFocus(sessionID: UUID(), isActive: false) == false)
    }

    @Test func asksAgainWhenTheHostedSessionChanges() {
        let coordinator = TerminalHostView.Coordinator()

        #expect(coordinator.shouldRequestFocus(sessionID: UUID(), isActive: true) == true)
        #expect(coordinator.shouldRequestFocus(sessionID: UUID(), isActive: true) == true)
    }

    @Test func asksAgainAfterFocusTrackingIsReset() {
        let coordinator = TerminalHostView.Coordinator()
        let sessionID = UUID()

        #expect(coordinator.shouldRequestFocus(sessionID: sessionID, isActive: true) == true)
        coordinator.resignFocusTracking()
        #expect(coordinator.shouldRequestFocus(sessionID: sessionID, isActive: true) == true)
    }
}
```

- [ ] **Step 2: Testi çalıştır, FAIL bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/TerminalHostViewTests 2>&1 | tail -20
```

Beklenen: `error: cannot find 'TerminalHostView' in scope` + `** TEST BUILD FAILED **`.

- [ ] **Step 3: TerminalHostView'ı yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Views/Terminal/TerminalHostView.swift`:

```swift
//
//  TerminalHostView.swift
//  Termora
//

import AppKit
import SwiftUI

/// Places the AppKit terminal that `SessionManager` owns into the SwiftUI tree.
///
/// It never creates or destroys terminals. SwiftUI may tear this representable down and
/// rebuild it (tab switch, split rebuild) without the shell process or its scrollback
/// noticing — that is the whole point of the view cache in `SessionManager`.
///
/// The one case where the hosted NSView is replaced is `SessionManager.restartSession`, which
/// puts a new terminal behind the same session id. Callers therefore key this representable on
/// `session.restartGeneration` (M3 panes do) so SwiftUI asks for the new view instead of
/// keeping the dead one on screen.
struct TerminalHostView: NSViewRepresentable {

    let sessionID: UUID
    let sessionManager: SessionManager
    let isActive: Bool

    /// Remembers which session this host last handed first-responder status to, so a routine
    /// re-render does not steal focus on every layout pass.
    final class Coordinator {
        private(set) var focusedSessionID: UUID?

        func shouldRequestFocus(sessionID: UUID, isActive: Bool) -> Bool {
            guard isActive else { return false }
            guard focusedSessionID != sessionID else { return false }
            focusedSessionID = sessionID
            return true
        }

        func resignFocusTracking() {
            focusedSessionID = nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TermoraTerminalView {
        guard let view = sessionManager.terminalView(for: sessionID) else {
            // Invariant: a pane is only ever built from a session SessionManager created, and
            // the view is created together with the session. Silently substituting a blank
            // terminal here would hide the bug behind a dead-looking window.
            preconditionFailure("TerminalHostView asked to host session \(sessionID), which SessionManager never created")
        }
        return view
    }

    func updateNSView(_ nsView: TermoraTerminalView, context: Context) {
        guard context.coordinator.shouldRequestFocus(sessionID: sessionID, isActive: isActive) else {
            if !isActive { context.coordinator.resignFocusTracking() }
            return
        }

        // The view is not in a window yet during the first update pass; defer to the next
        // run-loop turn, and if it still has no window, reset so a later update retries.
        DispatchQueue.main.async {
            guard let window = nsView.window else {
                context.coordinator.resignFocusTracking()
                return
            }
            window.makeFirstResponder(nsView)
        }
    }
}
```

- [ ] **Step 4: Testi çalıştır, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/TerminalHostViewTests 2>&1 | tail -20
```

Beklenen: `** TEST SUCCEEDED **` (4 test).

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora
git add Termora/Views/Terminal/TerminalHostView.swift TermoraTests/TerminalHostViewTests.swift
git commit -m "feat: host SessionManager terminal views in SwiftUI"
```

- [ ] **Step 6: AppServices'i yaz**

Bu dosya planın **tek** servis grafiğidir: Task 12, 13, 17, 18, 19 hepsi bu tipi kullanır, hiçbiri yeniden yaratmaz.

`/Users/ahmetbarut/Apps/Termora/Termora/App/AppServices.swift`:

```swift
//
//  AppServices.swift
//  Termora
//

import AppKit
import Foundation

/// Object graph for one running Termora instance, built once by `TermoraApp`.
/// Stores are shared by every window, and so is `SessionManager` — it owns the terminal view
/// cache, so a per-window copy would lose live shells. `WorkspaceViewModel` (M2) is per-window.
@MainActor
final class AppServices {
    let settings: SettingsStore
    let themes: ThemeStore
    let profiles: ProfileStore
    let sessionManager: SessionManager

    init() {
        // Termora draws its own tab bar (M2); leaving the system tabbing on would add a
        // "Show Tab Bar" menu item and fight ⌘T for the same gesture.
        NSWindow.allowsAutomaticWindowTabbing = false

        let settings = SettingsStore()
        let themes = ThemeStore()
        let profiles = ProfileStore()
        self.settings = settings
        self.themes = themes
        self.profiles = profiles
        self.sessionManager = SessionManager(settings: settings, themes: themes, profiles: profiles)
    }
}
```

Derlemeyi doğrula:

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet && echo BUILD_OK
```

Beklenen: `BUILD_OK`.

- [ ] **Step 7: MainWindowView ve ayar penceresi yer tutucusunu yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Views/MainWindowView.swift`:

```swift
//
//  MainWindowView.swift
//  Termora
//

import SwiftUI

/// M1 window: exactly one tab holding exactly one pane.
/// Tabs arrive in M2 (`TabBarView`), splits in M3 (`PaneTreeView`).
struct MainWindowView: View {

    private let services: AppServices

    @State private var sessionID: UUID?

    /// Explicit because `services` is private: the synthesised memberwise initialiser would be
    /// private too. Task 12 keeps this initialiser and adds the workspace view model to it.
    init(services: AppServices) {
        self.services = services
    }

    var body: some View {
        Group {
            if let sessionID {
                TerminalHostView(
                    sessionID: sessionID,
                    sessionManager: services.sessionManager,
                    isActive: true
                )
            } else {
                Color.black
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .onAppear {
            guard sessionID == nil else { return }
            sessionID = services.sessionManager
                .createSession(profile: nil, workingDirectory: nil)
                .id
        }
    }
}
```

`/Users/ahmetbarut/Apps/Termora/Termora/Views/SettingsPlaceholderView.swift`:

```swift
//
//  SettingsPlaceholderView.swift
//  Termora
//

import SwiftUI

/// Stands in for the real Settings window until M4, so the ⌘, menu item is not dead.
struct SettingsPlaceholderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Settings")
                .font(.title3.weight(.semibold))
            Text("Appearance, profiles and shell options arrive in milestone M4.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(width: 420, height: 180)
    }
}
```

Derlemeyi doğrula:

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet && echo BUILD_OK
```

Beklenen: `BUILD_OK`.

- [ ] **Step 8: TermoraApp'i bağla**

`Termora/App/TermoraApp.swift` dosyasının (Task 1 Step 8'de bu yola taşındı; `Termora/ContentView.swift` de orada silindi) **tüm içeriğini** şununla değiştir:

```swift
//
//  TermoraApp.swift
//  Termora
//

import SwiftUI

@main
struct TermoraApp: App {

    /// `@State`, not `let`: SwiftUI may rebuild the `App` struct, and a fresh `AppServices`
    /// on every rebuild would mean a fresh `SessionManager` — every open shell would vanish.
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            MainWindowView(services: services)
        }
        .defaultSize(width: 900, height: 560)

        Settings {
            SettingsPlaceholderView()
        }
    }
}
```

Ardından derle:

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet && echo BUILD_OK
```

Beklenen: `BUILD_OK`.

- [ ] **Step 9: Tüm testleri çalıştır ve commit**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests 2>&1 | tail -20
git add -A
git commit -m "feat: boot Termora into a live terminal window"
```

Beklenen: `** TEST SUCCEEDED **`.

- [ ] **Step 10: Uygulamayı Xcode olmadan çalıştır**

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet
PRODUCTS_DIR=$(xcodebuild -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -showBuildSettings 2>/dev/null | awk -F' = ' '/^ *BUILT_PRODUCTS_DIR/ {print $2; exit}')
echo "$PRODUCTS_DIR"
open "$PRODUCTS_DIR/Termora.app"
```

Beklenen: 900×560 boyutunda bir pencere açılır, içinde çalışan bir shell prompt'u görünür ve klavye odağı doğrudan terminaldedir (tıklamadan yazılabilir).

- [ ] **Step 11: Elle doğrulama — M1 kabul listesi**

Açılan Termora penceresinde sırayla çalıştır ve her maddenin karşılığını gözle doğrula:

1. `echo $TERM $COLORTERM $TERM_PROGRAM $TERM_PROGRAM_VERSION`
   → `xterm-256color truecolor Termora <sürüm>` görülmeli (EnvironmentBuilder doğru bağlanmış).
2. `echo $0`
   → `-zsh` (veya varsayılan shell'in `-` önekli hâli) görülmeli — login shell argv[0] kalıbı çalışıyor.
3. `echo $LANG; locale`
   → `LANG` ve `LC_CTYPE` dolu; `locale` çıktısında `?` / "Cannot set" uyarısı olmamalı.
4. `printf '\033[31mRED\033[0m \033[1mBOLD\033[0m \033[4mUNDER\033[0m\n'`
   → kırmızı, kalın ve altı çizili metin doğru render edilmeli.
5. `vim` → birkaç satır yaz → `:q!`
   → tam ekran alternatif tampon açılıp kapanmalı, çıkışta prompt bozulmadan geri gelmeli. **Kabul kriteri.**
6. `htop` (kurulu değilse `top`) → `q` ile çık
   → renkli tablo düzgün çizilmeli, imleç konumları kaymamalı. **Kabul kriteri.**
7. Pencereyi fare ile küçült/büyüt, sonra `tput cols; tput lines` ve `stty size`
   → değerler pencerede görünen sütun/satır sayısıyla uyuşmalı; yeniden boyutlandırma sırasında ekran bozulmamalı.
8. `seq 1 5000` → fare tekerleği ile yukarı kaydır
   → scrollback ile geçmiş çıktı görülebilmeli.
9. Bir metin parçası seç → ⌘C → prompt'a ⌘V
   → seçilen metin yapıştırılmalı (SwiftTerm'ün hazır `copy(_:)`/`paste(_:)` implementasyonu).
10. `sleep 30` başlat, sonra ⌘Q ile uygulamayı kapat, terminalden `pgrep -f "sleep 30"` çalıştır
    → çıktı boş olmalı (PTY master kapanınca oturum liderine SIGHUP gider).
11. Menüden **Termora ▸ Settings…** (⌘,)
    → "Appearance, profiles and shell options arrive in milestone M4." yazan yer tutucu pencere açılmalı.

Herhangi bir madde başarısız olursa Task 8/Task 10 implementasyonuna dön; M1 ancak 5. ve 6. maddeler ("vim ve htop sorunsuz") elle onaylandığında kapanır.

- [ ] **Step 12: M1 kapanış commit'i**

```bash
cd /Users/ahmetbarut/Apps/Termora
git status --short
git commit --allow-empty -m "chore: close milestone M1 after manual vim/htop verification"
```

Beklenen: `git status --short` temiz (Step 9'da her şey commit'lendi); boş commit M1 kabulünü tarihçeye işaretler.

---

---

### Task 11: TerminalTab + WorkspaceViewModel sekme operasyonları (M2)

**Files:**
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Models/PaneNode.swift` (yalnız enum tanımı + salt-okunur erişimciler; Task 14 aynı dosyayı **Modify** ederek `splitting`/`removing`/`updatingRatio`/`siblingLeafPaneID` operasyonlarını ekler)
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Models/TerminalTab.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/ViewModels/WorkspaceViewModel.swift`
- Test (Create): `/Users/ahmetbarut/Apps/Termora/TermoraTests/MockSessionManager.swift`
- Test (Create): `/Users/ahmetbarut/Apps/Termora/TermoraTests/PaneNodeLeafTests.swift`
- Test (Create): `/Users/ahmetbarut/Apps/Termora/TermoraTests/TerminalTabTests.swift`
- Test (Create): `/Users/ahmetbarut/Apps/Termora/TermoraTests/WorkspaceViewModelTests.swift`

**Interfaces:**

Consumes (Task 6/7/8'den, kesin imzalar):
- `@MainActor @Observable final class SettingsStore { init(defaults: UserDefaults = .standard) }`
- `@MainActor @Observable final class ProfileStore { init(defaults: UserDefaults = .standard); var profiles: [TerminalProfile] }`
- `struct TerminalProfile: Codable, Identifiable, Equatable { var id: UUID = UUID(); var name: String; var shellPath: String?; ... }`
- `@Observable final class TerminalSession: Identifiable { let id: UUID; let shellPath: String; let profileID: UUID?; var workingDirectory: String?; var title: String; var processState: ProcessState; init(id: UUID = UUID(), shellPath: String, profileID: UUID? = nil, workingDirectory: String? = nil) }`
- `@MainActor protocol SessionManaging: AnyObject { func createSession(profile: TerminalProfile?, workingDirectory: String?) -> TerminalSession; func session(id: UUID) -> TerminalSession?; func terminateSession(id: UUID); func restartSession(id: UUID, forceDefaultShell: Bool); func hasRunningProcess(sessionID: UUID) -> Bool }` — `restartSession(id:forceDefaultShell:)` panel içi "İşlem sonlandı" bandının yeniden başlatma eylemini karşılar (Task 8 tanımlar, Task 17 kullanır); `MockSessionManager` bu görevde onu da gerçekler.

Produces (sonraki görevler bunları kullanır):
- `enum SplitAxis: String, Codable { case vertical, horizontal }`
- `indirect enum PaneNode: Equatable { case leaf(paneID: UUID, sessionID: UUID); case split(id: UUID, axis: SplitAxis, ratio: Double, first: PaneNode, second: PaneNode); var leaves: [(paneID: UUID, sessionID: UUID)]; func sessionID(ofPane paneID: UUID) -> UUID? }` — Task 14 bu dosyayı **Modify** ederek `splitting(paneID:axis:newPaneID:newSessionID:)`, `removing(paneID:)`, `updatingRatio(splitID:ratio:)` ekler; buradaki iki erişimcinin imzası değişmez.
- `@Observable final class TerminalTab: Identifiable { let id: UUID; var customTitle: String?; var automaticTitle: String; var displayTitle: String { get }; var root: PaneNode; var activePaneID: UUID; var isSearchVisible: Bool; init(id: UUID = UUID(), root: PaneNode, activePaneID: UUID) }`
- `@MainActor @Observable final class WorkspaceViewModel` — `init(sessionManager: any SessionManaging, settings: SettingsStore, profiles: ProfileStore)`, `let settings: SettingsStore`, `let profiles: ProfileStore`, `private(set) var tabs: [TerminalTab]`, `var activeTabID: UUID?`, `var activeTab: TerminalTab? { get }`, `var pendingClose: PendingClose?`, `var paneFrames: [UUID: CGRect]`, `struct PendingClose: Identifiable, Equatable { let id: UUID; let target: Target; enum Target: Equatable { case tab(UUID); case pane(paneID: UUID); case window } }`, `func newTab(profile: TerminalProfile? = nil)`, `func requestCloseTab(id: UUID)`, `func confirmPendingClose()`, `func cancelPendingClose()`, `func closeAllTabs()`, `func selectTab(at index: Int)`, `func nextTab()`, `func previousTab()`, `func renameTab(id: UUID, to newName: String?)`, `func hasAnyRunningProcess() -> Bool`, `func syncAutomaticTitles()`, `var sessionTitleDigest: String { get }`
- `@MainActor final class MockSessionManager: SessionManaging` (test hedefi, **tek dosya**: `TermoraTests/MockSessionManager.swift` — `Support/` alt klasörü yok) — `var busySessionIDs: Set<UUID>`, `var defaultShellPath: String`, `private(set) var sessions: [UUID: TerminalSession]`, `private(set) var createdSessions: [TerminalSession]`, `private(set) var terminatedSessionIDs: [UUID]`, `private(set) var createdProfiles: [TerminalProfile?]`, `private(set) var createdWorkingDirectories: [String?]`, `private(set) var restartedSessionIDs: [UUID]`. Task 16 ve Task 17 testleri de tam olarak bu adları kullanır (`terminatedIDs` diye bir üye YOKTUR).

---

- [ ] **Step 1: PaneNode yaprak erişimcileri için testi yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/PaneNodeLeafTests.swift` dosyasını oluştur:

```swift
import Foundation
import Testing
@testable import Termora

@MainActor
@Suite struct PaneNodeLeafTests {

    @Test func leafReturnsItselfAsOnlyLeaf() {
        let paneID = UUID()
        let sessionID = UUID()
        let node = PaneNode.leaf(paneID: paneID, sessionID: sessionID)

        #expect(node.leaves.count == 1)
        #expect(node.leaves[0].paneID == paneID)
        #expect(node.leaves[0].sessionID == sessionID)
    }

    @Test func leavesAreReturnedInFirstThenSecondOrder() {
        let a = (pane: UUID(), session: UUID())
        let b = (pane: UUID(), session: UUID())
        let c = (pane: UUID(), session: UUID())
        let node = PaneNode.split(
            id: UUID(),
            axis: .vertical,
            ratio: 0.5,
            first: .leaf(paneID: a.pane, sessionID: a.session),
            second: .split(
                id: UUID(),
                axis: .horizontal,
                ratio: 0.5,
                first: .leaf(paneID: b.pane, sessionID: b.session),
                second: .leaf(paneID: c.pane, sessionID: c.session)
            )
        )

        #expect(node.leaves.map(\.paneID) == [a.pane, b.pane, c.pane])
    }

    @Test func sessionIDOfPaneFindsMatchingLeafOrNil() {
        let a = (pane: UUID(), session: UUID())
        let b = (pane: UUID(), session: UUID())
        let node = PaneNode.split(
            id: UUID(),
            axis: .vertical,
            ratio: 0.5,
            first: .leaf(paneID: a.pane, sessionID: a.session),
            second: .leaf(paneID: b.pane, sessionID: b.session)
        )

        #expect(node.sessionID(ofPane: b.pane) == b.session)
        #expect(node.sessionID(ofPane: UUID()) == nil)
    }

    @Test func equalTreesCompareEqual() {
        let paneID = UUID()
        let sessionID = UUID()
        #expect(PaneNode.leaf(paneID: paneID, sessionID: sessionID)
                == PaneNode.leaf(paneID: paneID, sessionID: sessionID))
        #expect(PaneNode.leaf(paneID: paneID, sessionID: sessionID)
                != PaneNode.leaf(paneID: UUID(), sessionID: sessionID))
    }
}
```

- [ ] **Step 2: Testi çalıştır, derleme hatası bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/PaneNodeLeafTests 2>&1 | tail -20
```

Beklenen: `error: cannot find 'PaneNode' in scope` (ve `SplitAxis` için aynısı), en sonda `** TEST BUILD FAILED **`.

- [ ] **Step 3: PaneNode enum'unu yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Models/PaneNode.swift`:

```swift
import Foundation

/// Bölme ekseni. iTerm2 konvansiyonu: dikey bölme ayracı diktir, paneller yan yana durur.
enum SplitAxis: String, Codable {
    /// Dikey ayraç, paneller YAN YANA (⌘D).
    case vertical
    /// Yatay ayraç, paneller ÜST ÜSTE (⌘⇧D).
    case horizontal
}

/// Bir sekmenin panel yerleşimini tutan ikili ağaç.
/// Bu dosya M2'de yalnız veri tipini ve salt-okunur erişimcileri içerir;
/// bölme/kapatma/oran operasyonları M3'te (Task 14) eklenir.
indirect enum PaneNode: Equatable {
    case leaf(paneID: UUID, sessionID: UUID)
    case split(id: UUID, axis: SplitAxis, ratio: Double, first: PaneNode, second: PaneNode)

    /// Soldan sağa / üstten alta sırayla tüm yapraklar.
    var leaves: [(paneID: UUID, sessionID: UUID)] {
        switch self {
        case let .leaf(paneID, sessionID):
            return [(paneID: paneID, sessionID: sessionID)]
        case let .split(_, _, _, first, second):
            return first.leaves + second.leaves
        }
    }

    func sessionID(ofPane paneID: UUID) -> UUID? {
        leaves.first { $0.paneID == paneID }?.sessionID
    }
}
```

- [ ] **Step 4: Testi çalıştır, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/PaneNodeLeafTests 2>&1 | tail -20
```

Beklenen: `Test run with 4 tests passed` ve `** TEST SUCCEEDED **`.

- [ ] **Step 5: TerminalTab başlık mantığı testini yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/TerminalTabTests.swift`:

```swift
import Foundation
import Testing
@testable import Termora

@MainActor
@Suite struct TerminalTabTests {

    private func makeTab() -> TerminalTab {
        let paneID = UUID()
        return TerminalTab(root: .leaf(paneID: paneID, sessionID: UUID()), activePaneID: paneID)
    }

    @Test func displayTitleFallsBackToTerminalWhenEverythingIsEmpty() {
        let tab = makeTab()
        #expect(tab.customTitle == nil)
        #expect(tab.automaticTitle.isEmpty)
        #expect(tab.displayTitle == "Terminal")
    }

    @Test func displayTitleUsesAutomaticTitleWhenThereIsNoCustomTitle() {
        let tab = makeTab()
        tab.automaticTitle = "~/code — zsh"
        #expect(tab.displayTitle == "~/code — zsh")
    }

    @Test func customTitleWinsOverAutomaticTitle() {
        let tab = makeTab()
        tab.automaticTitle = "~/code — zsh"
        tab.customTitle = "Build"
        #expect(tab.displayTitle == "Build")
    }

    @Test func emptyCustomTitleIsIgnored() {
        let tab = makeTab()
        tab.automaticTitle = "zsh"
        tab.customTitle = ""
        #expect(tab.displayTitle == "zsh")
    }

    @Test func activePaneAndRootAreStoredAsGiven() {
        let paneID = UUID()
        let sessionID = UUID()
        let tab = TerminalTab(root: .leaf(paneID: paneID, sessionID: sessionID), activePaneID: paneID)
        #expect(tab.activePaneID == paneID)
        #expect(tab.root.sessionID(ofPane: paneID) == sessionID)
        #expect(tab.isSearchVisible == false)
    }
}
```

- [ ] **Step 6: Testi çalıştır, derleme hatası bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/TerminalTabTests 2>&1 | tail -20
```

Beklenen: `error: cannot find 'TerminalTab' in scope`, `** TEST BUILD FAILED **`.

- [ ] **Step 7: TerminalTab'ı yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Models/TerminalTab.swift`:

```swift
import Foundation
import Observation

/// Bir sekme: panel ağacı + aktif panel + başlık durumu.
/// Kalıcı değildir (oturum geri yükleme 2. fazda).
@Observable
final class TerminalTab: Identifiable {
    let id: UUID

    /// Kullanıcının elle verdiği ad. nil ise otomatik başlık gösterilir.
    var customTitle: String?

    /// Shell'in OSC ile bildirdiği başlık (SessionManager → TerminalSession → burası).
    var automaticTitle: String = ""

    var root: PaneNode
    var activePaneID: UUID
    var isSearchVisible: Bool = false

    var displayTitle: String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        return automaticTitle.isEmpty ? "Terminal" : automaticTitle
    }

    init(id: UUID = UUID(), root: PaneNode, activePaneID: UUID) {
        self.id = id
        self.root = root
        self.activePaneID = activePaneID
    }
}
```

- [ ] **Step 8: Testi çalıştır, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/TerminalTabTests 2>&1 | tail -20
```

Beklenen: `Test run with 5 tests passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 9: Modelleri commit et**

```bash
cd /Users/ahmetbarut/Apps/Termora && git add Termora/Models/PaneNode.swift Termora/Models/TerminalTab.swift TermoraTests/PaneNodeLeafTests.swift TermoraTests/TerminalTabTests.swift && git commit -m "feat: add PaneNode tree and TerminalTab models"
```

- [ ] **Step 10: MockSessionManager test double'ını yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/MockSessionManager.swift`:

```swift
import Foundation
@testable import Termora

/// SessionManaging'in test double'ı. Task 11, Task 16 ve Task 17 testleri bunu paylaşır.
/// Üye adları kanoniktir; sonraki görevler tam olarak bu adları kullanır.
@MainActor
final class MockSessionManager: SessionManaging {

    /// Bu kümedeki oturumlar "çalışan işlem var" olarak raporlanır.
    var busySessionIDs: Set<UUID> = []

    /// createSession'ın üreteceği varsayılan shell yolu (profil belirtmezse).
    var defaultShellPath: String = "/bin/zsh"

    private(set) var sessions: [UUID: TerminalSession] = [:]
    private(set) var createdSessions: [TerminalSession] = []
    private(set) var terminatedSessionIDs: [UUID] = []
    private(set) var createdProfiles: [TerminalProfile?] = []
    private(set) var createdWorkingDirectories: [String?] = []
    private(set) var restartedSessionIDs: [UUID] = []

    func createSession(profile: TerminalProfile?, workingDirectory: String?) -> TerminalSession {
        createdProfiles.append(profile)
        createdWorkingDirectories.append(workingDirectory)
        let session = TerminalSession(
            shellPath: profile?.shellPath ?? defaultShellPath,
            profileID: profile?.id,
            workingDirectory: workingDirectory
        )
        sessions[session.id] = session
        createdSessions.append(session)
        return session
    }

    func session(id: UUID) -> TerminalSession? {
        sessions[id]
    }

    func terminateSession(id: UUID) {
        terminatedSessionIDs.append(id)
        sessions[id] = nil
        busySessionIDs.remove(id)
    }

    /// Gerçek yönetici gibi AYNI sessionID ile taze bir oturum kurar; çağrı sırası kaydedilir.
    func restartSession(id: UUID, forceDefaultShell: Bool) {
        restartedSessionIDs.append(id)
        guard let old = sessions[id] else { return }
        sessions[id] = TerminalSession(
            id: id,
            shellPath: forceDefaultShell ? defaultShellPath : old.shellPath,
            profileID: forceDefaultShell ? nil : old.profileID,
            workingDirectory: old.workingDirectory
        )
        busySessionIDs.remove(id)
    }

    func hasRunningProcess(sessionID: UUID) -> Bool {
        busySessionIDs.contains(sessionID)
    }
}
```

- [ ] **Step 11: newTab testlerini yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/WorkspaceViewModelTests.swift`:

```swift
import Foundation
import Testing
@testable import Termora

@MainActor
@Suite struct WorkspaceViewModelTests {

    private func makeWorkspace() -> (WorkspaceViewModel, MockSessionManager) {
        let defaults = UserDefaults(suiteName: "WorkspaceViewModelTests.\(UUID().uuidString)")!
        let manager = MockSessionManager()
        let workspace = WorkspaceViewModel(
            sessionManager: manager,
            settings: SettingsStore(defaults: defaults),
            profiles: ProfileStore(defaults: defaults)
        )
        return (workspace, manager)
    }

    @Test func newTabCreatesSessionAndActivatesTab() {
        let (workspace, manager) = makeWorkspace()

        workspace.newTab()

        #expect(workspace.tabs.count == 1)
        let tab = workspace.tabs[0]
        #expect(workspace.activeTabID == tab.id)
        #expect(workspace.activeTab === tab)
        #expect(tab.root.leaves.count == 1)
        #expect(tab.root.leaves[0].paneID == tab.activePaneID)
        #expect(manager.session(id: tab.root.leaves[0].sessionID) != nil)
        #expect(manager.createdProfiles == [TerminalProfile?.none])
    }

    @Test func newTabWithProfilePassesProfileAndSeedsAutomaticTitle() {
        let (workspace, manager) = makeWorkspace()
        let profile = TerminalProfile(name: "Sunucu")

        workspace.newTab(profile: profile)

        #expect(manager.createdProfiles.count == 1)
        #expect(manager.createdProfiles[0]?.id == profile.id)
        #expect(workspace.tabs[0].automaticTitle == "Sunucu")
        #expect(workspace.tabs[0].displayTitle == "Sunucu")
    }

    @Test func newTabAppendsAndMovesActivationToTheNewTab() {
        let (workspace, _) = makeWorkspace()

        workspace.newTab()
        let first = workspace.tabs[0].id
        workspace.newTab()

        #expect(workspace.tabs.count == 2)
        #expect(workspace.tabs[0].id == first)
        #expect(workspace.activeTabID == workspace.tabs[1].id)
    }
}
```

- [ ] **Step 12: Testi çalıştır, derleme hatası bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/WorkspaceViewModelTests 2>&1 | tail -20
```

Beklenen: `error: cannot find 'WorkspaceViewModel' in scope`, `** TEST BUILD FAILED **`.

- [ ] **Step 13: WorkspaceViewModel iskeletini + newTab'ı yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/ViewModels/WorkspaceViewModel.swift`:

```swift
import Foundation
import CoreGraphics
import Observation

/// Pencere başına bir tane. Sekme ve panel operasyonlarının tek sahibi.
/// Menü kısayolları @FocusedValue üzerinden key window'un örneğine ulaşır.
@MainActor
@Observable
final class WorkspaceViewModel {

    /// Çalışan işlem yüzünden onay bekleyen kapatma isteği.
    struct PendingClose: Identifiable, Equatable {
        let id: UUID
        let target: Target

        enum Target: Equatable {
            case tab(UUID)
            case pane(paneID: UUID)
            case window
        }
    }

    private let sessionManager: any SessionManaging
    let settings: SettingsStore
    let profiles: ProfileStore

    private(set) var tabs: [TerminalTab] = []
    var activeTabID: UUID?
    var pendingClose: PendingClose?

    /// PaneTreeView'ın preference key ile bildirdiği panel çerçeveleri (AppKit koordinatları).
    var paneFrames: [UUID: CGRect] = [:]

    var activeTab: TerminalTab? {
        guard let activeTabID else { return nil }
        return tabs.first { $0.id == activeTabID }
    }

    init(sessionManager: any SessionManaging, settings: SettingsStore, profiles: ProfileStore) {
        self.sessionManager = sessionManager
        self.settings = settings
        self.profiles = profiles
    }

    // MARK: - Sekme açma

    func newTab(profile: TerminalProfile? = nil) {
        let session = sessionManager.createSession(profile: profile, workingDirectory: nil)
        let paneID = UUID()
        let tab = TerminalTab(
            root: .leaf(paneID: paneID, sessionID: session.id),
            activePaneID: paneID
        )
        if let profile {
            tab.automaticTitle = profile.name
        }
        tabs.append(tab)
        activeTabID = tab.id
    }
}
```

- [ ] **Step 14: Testi çalıştır, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/WorkspaceViewModelTests 2>&1 | tail -20
```

Beklenen: `Test run with 3 tests passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 15: Kapatma akışı testlerini yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/WorkspaceViewModelTests.swift` içine, `newTabAppendsAndMovesActivationToTheNewTab` testinden sonra ekle:

```swift
    // MARK: - Kapatma

    @Test func requestCloseTabClosesIdleTabAndTerminatesItsSessions() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        let tab = workspace.tabs[0]
        let sessionID = tab.root.leaves[0].sessionID

        workspace.requestCloseTab(id: tab.id)

        #expect(workspace.pendingClose == nil)
        #expect(workspace.tabs.isEmpty)
        #expect(manager.terminatedSessionIDs == [sessionID])
    }

    @Test func requestCloseTabWithRunningProcessAsksForConfirmation() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        let tab = workspace.tabs[0]
        manager.busySessionIDs.insert(tab.root.leaves[0].sessionID)

        workspace.requestCloseTab(id: tab.id)

        #expect(workspace.pendingClose?.target == .tab(tab.id))
        #expect(workspace.tabs.count == 1)
        #expect(manager.terminatedSessionIDs.isEmpty)
    }

    @Test func confirmPendingCloseClosesTheTab() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        workspace.newTab()
        let tab = workspace.tabs[1]
        let sessionID = tab.root.leaves[0].sessionID
        manager.busySessionIDs.insert(sessionID)
        workspace.requestCloseTab(id: tab.id)

        workspace.confirmPendingClose()

        #expect(workspace.pendingClose == nil)
        #expect(workspace.tabs.count == 1)
        #expect(manager.terminatedSessionIDs == [sessionID])
    }

    @Test func cancelPendingCloseKeepsTheTabAlive() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        let tab = workspace.tabs[0]
        manager.busySessionIDs.insert(tab.root.leaves[0].sessionID)
        workspace.requestCloseTab(id: tab.id)

        workspace.cancelPendingClose()

        #expect(workspace.pendingClose == nil)
        #expect(workspace.tabs.count == 1)
        #expect(manager.terminatedSessionIDs.isEmpty)
    }

    @Test func closingLastTabClearsActiveTabID() {
        let (workspace, _) = makeWorkspace()
        workspace.newTab()

        workspace.requestCloseTab(id: workspace.tabs[0].id)

        #expect(workspace.tabs.isEmpty)
        #expect(workspace.activeTabID == nil)
    }

    @Test func closingActiveTabActivatesTheNeighbourAtTheSameIndex() {
        let (workspace, _) = makeWorkspace()
        workspace.newTab()
        workspace.newTab()
        workspace.newTab()
        let middle = workspace.tabs[1]
        let last = workspace.tabs[2].id
        workspace.selectTab(at: 1)

        workspace.requestCloseTab(id: middle.id)

        #expect(workspace.tabs.count == 2)
        #expect(workspace.activeTabID == last)
    }

    @Test func closingInactiveTabKeepsCurrentActivation() {
        let (workspace, _) = makeWorkspace()
        workspace.newTab()
        workspace.newTab()
        let active = workspace.activeTabID

        workspace.requestCloseTab(id: workspace.tabs[0].id)

        #expect(workspace.tabs.count == 1)
        #expect(workspace.activeTabID == active)
    }

    @Test func confirmingWindowCloseTerminatesEverySession() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        workspace.newTab()
        let sessionIDs = workspace.tabs.map { $0.root.leaves[0].sessionID }
        workspace.pendingClose = WorkspaceViewModel.PendingClose(id: UUID(), target: .window)

        workspace.confirmPendingClose()

        #expect(workspace.tabs.isEmpty)
        #expect(workspace.activeTabID == nil)
        #expect(Set(manager.terminatedSessionIDs) == Set(sessionIDs))
    }

    @Test func hasAnyRunningProcessReflectsSessionState() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()

        #expect(workspace.hasAnyRunningProcess() == false)

        manager.busySessionIDs.insert(workspace.tabs[0].root.leaves[0].sessionID)
        #expect(workspace.hasAnyRunningProcess())
    }
```

- [ ] **Step 16: Testi çalıştır, derleme hatası bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/WorkspaceViewModelTests 2>&1 | tail -20
```

Beklenen: `error: value of type 'WorkspaceViewModel' has no member 'requestCloseTab'` (ve `selectTab`, `hasAnyRunningProcess` için aynısı), `** TEST BUILD FAILED **`.

- [ ] **Step 17: Kapatma akışını implemente et**

`/Users/ahmetbarut/Apps/Termora/Termora/ViewModels/WorkspaceViewModel.swift` dosyasında `newTab(profile:)` metodundan sonra, sınıfın kapanış parantezinden önce ekle:

```swift
    // MARK: - Sekme kapatma

    /// Sekmede çalışan bir işlem varsa onay ister, yoksa doğrudan kapatır.
    func requestCloseTab(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        let busy = tab.root.leaves.contains { sessionManager.hasRunningProcess(sessionID: $0.sessionID) }
        if busy {
            pendingClose = PendingClose(id: UUID(), target: .tab(id))
        } else {
            closeTab(id: id)
        }
    }

    func confirmPendingClose() {
        guard let pending = pendingClose else { return }
        pendingClose = nil
        switch pending.target {
        case let .tab(tabID):
            closeTab(id: tabID)
        case let .pane(paneID):
            closePane(paneID: paneID)
        case .window:
            closeAllTabs()
        }
    }

    func cancelPendingClose() {
        pendingClose = nil
    }

    /// Pencere kapatılırken: onay alınmışsa tüm oturumları sonlandırır.
    func closeAllTabs() {
        for tab in tabs {
            for leaf in tab.root.leaves {
                sessionManager.terminateSession(id: leaf.sessionID)
            }
        }
        tabs.removeAll()
        activeTabID = nil
    }

    func hasAnyRunningProcess() -> Bool {
        tabs.contains { tab in
            tab.root.leaves.contains { sessionManager.hasRunningProcess(sessionID: $0.sessionID) }
        }
    }

    private func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        for leaf in tabs[index].root.leaves {
            sessionManager.terminateSession(id: leaf.sessionID)
        }
        tabs.remove(at: index)
        if activeTabID == id {
            activeTabID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        }
    }

    /// M2 değişmezi: her sekmede tek panel vardır, dolayısıyla paneli kapatmak sekmeyi kapatır.
    /// Task 16 bunu PaneNode.removing(paneID:) ile ağaç budamasına genişletir.
    private func closePane(paneID: UUID) {
        guard let tab = tabs.first(where: { $0.root.sessionID(ofPane: paneID) != nil }) else { return }
        closeTab(id: tab.id)
    }
```

- [ ] **Step 18: Testi çalıştır, seçim testlerinin derlenmediğini gör**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/WorkspaceViewModelTests 2>&1 | tail -20
```

Beklenen: hâlâ `error: value of type 'WorkspaceViewModel' has no member 'selectTab'`, `** TEST BUILD FAILED **` (kapatma testleri Step 19'daki seçim API'si eklenene kadar derlenemez).

- [ ] **Step 19: Sekme seçimi ve yeniden adlandırma testlerini yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/WorkspaceViewModelTests.swift` sonuna (sınıfın kapanışından önce) ekle:

```swift
    // MARK: - Seçim ve yeniden adlandırma

    @Test func selectTabUsesZeroBasedIndexAndIgnoresOutOfBounds() {
        let (workspace, _) = makeWorkspace()
        workspace.newTab()
        workspace.newTab()

        workspace.selectTab(at: 0)
        #expect(workspace.activeTabID == workspace.tabs[0].id)

        workspace.selectTab(at: 5)
        #expect(workspace.activeTabID == workspace.tabs[0].id)

        workspace.selectTab(at: -1)
        #expect(workspace.activeTabID == workspace.tabs[0].id)
    }

    @Test func nextAndPreviousTabWrapAround() {
        let (workspace, _) = makeWorkspace()
        workspace.newTab()
        workspace.newTab()
        workspace.newTab()

        workspace.selectTab(at: 2)
        workspace.nextTab()
        #expect(workspace.activeTabID == workspace.tabs[0].id)

        workspace.previousTab()
        #expect(workspace.activeTabID == workspace.tabs[2].id)

        workspace.previousTab()
        #expect(workspace.activeTabID == workspace.tabs[1].id)
    }

    @Test func nextTabOnEmptyWorkspaceIsNoOp() {
        let (workspace, _) = makeWorkspace()
        workspace.nextTab()
        workspace.previousTab()
        #expect(workspace.activeTabID == nil)
    }

    @Test func renameTabSetsCustomTitleAndBlankNameRestoresAutomaticTitle() {
        let (workspace, _) = makeWorkspace()
        workspace.newTab()
        let tab = workspace.tabs[0]
        tab.automaticTitle = "zsh"

        workspace.renameTab(id: tab.id, to: "  Build  ")
        #expect(tab.customTitle == "Build")
        #expect(tab.displayTitle == "Build")

        workspace.renameTab(id: tab.id, to: "   ")
        #expect(tab.customTitle == nil)
        #expect(tab.displayTitle == "zsh")

        workspace.renameTab(id: tab.id, to: "Build")
        workspace.renameTab(id: tab.id, to: nil)
        #expect(tab.customTitle == nil)
    }

    @Test func syncAutomaticTitlesCopiesActivePaneSessionTitle() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        let tab = workspace.tabs[0]
        let sessionID = tab.root.leaves[0].sessionID
        manager.session(id: sessionID)?.title = "~/code — zsh"

        #expect(workspace.sessionTitleDigest.contains("~/code — zsh"))

        workspace.syncAutomaticTitles()
        #expect(tab.automaticTitle == "~/code — zsh")
        #expect(tab.displayTitle == "~/code — zsh")
    }

    @Test func syncAutomaticTitlesKeepsLastKnownTitleWhenSessionIsGone() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        let tab = workspace.tabs[0]
        let sessionID = tab.root.leaves[0].sessionID
        manager.session(id: sessionID)?.title = "vim"
        workspace.syncAutomaticTitles()

        manager.terminateSession(id: sessionID)
        workspace.syncAutomaticTitles()

        #expect(tab.automaticTitle == "vim")
    }

    @Test func automaticTitleFallsBackToWorkingDirectoryBasename() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        let tab = workspace.tabs[0]
        let sessionID = tab.root.leaves[0].sessionID
        manager.session(id: sessionID)?.workingDirectory = "/Users/ahmetbarut/code"

        workspace.syncAutomaticTitles()

        #expect(tab.automaticTitle == "code")
        #expect(tab.displayTitle == "code")
    }

    @Test func automaticTitleFallsBackToShellNameWhenNothingIsKnown() {
        let (workspace, manager) = makeWorkspace()
        manager.defaultShellPath = "/bin/zsh"
        workspace.newTab()
        let tab = workspace.tabs[0]

        workspace.syncAutomaticTitles()

        #expect(tab.automaticTitle == "zsh")
        #expect(tab.displayTitle == "zsh")
    }
```

Not (spec §7 "başlıkta aktif klasör/işlem adı"): macOS'un stok `/etc/zshrc`'si OSC başlık dizisini yalnız `TERM_PROGRAM = Apple_Terminal` iken yayar. Termora `TERM_PROGRAM=Termora` gönderdiği için varsayılan zsh hiç başlık yaymaz; `session.title` boş kalır. Bu iki test, o durumda sekmenin kalıcı olarak "Terminal" yazmasını engelleyen geri düşüş zincirini (oturum başlığı → çalışma dizini adı → shell adı) sabitler.

- [ ] **Step 20: Testi çalıştır, derleme hatası bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/WorkspaceViewModelTests 2>&1 | tail -20
```

Beklenen: `error: value of type 'WorkspaceViewModel' has no member 'selectTab'` / `'renameTab'` / `'syncAutomaticTitles'` / `'sessionTitleDigest'`, `** TEST BUILD FAILED **`.

- [ ] **Step 21: Seçim, yeniden adlandırma ve başlık senkronunu implemente et**

`/Users/ahmetbarut/Apps/Termora/Termora/ViewModels/WorkspaceViewModel.swift` içinde `private func closePane(paneID:)` metodundan sonra, sınıfın kapanış parantezinden önce ekle:

```swift
    // MARK: - Sekme seçimi

    /// 0 tabanlı index (⌘1 → 0). Sınır dışı index yok sayılır.
    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeTabID = tabs[index].id
    }

    func nextTab() {
        guard let index = activeIndex else { return }
        activeTabID = tabs[(index + 1) % tabs.count].id
    }

    func previousTab() {
        guard let index = activeIndex else { return }
        activeTabID = tabs[(index - 1 + tabs.count) % tabs.count].id
    }

    private var activeIndex: Int? {
        guard let activeTabID else { return nil }
        return tabs.firstIndex { $0.id == activeTabID }
    }

    // MARK: - Başlıklar

    /// nil veya yalnız boşluktan oluşan ad otomatik başlığa döner.
    func renameTab(id: UUID, to newName: String?) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        let trimmed = newName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        tab.customTitle = trimmed.isEmpty ? nil : trimmed
    }

    /// Aktif panelin başlığını sekmeye yansıtır. Geri düşüş zinciri:
    /// shell'in OSC ile bildirdiği başlık → çalışma dizininin son bileşeni → profil adı → shell adı.
    /// (Stok macOS zsh'ı `TERM_PROGRAM=Termora` iken OSC başlık YAYMAZ; geri düşüş olmadan
    /// tüm sekmeler kalıcı olarak "Terminal" yazardı — spec §7.)
    /// Oturum kapandıysa son bilinen başlık korunur.
    func syncAutomaticTitles() {
        for tab in tabs {
            guard let sessionID = tab.root.sessionID(ofPane: tab.activePaneID),
                  let session = sessionManager.session(id: sessionID) else { continue }

            if !session.title.isEmpty {
                tab.automaticTitle = session.title
            } else if let directory = session.workingDirectory, !directory.isEmpty {
                let basename = (directory as NSString).lastPathComponent
                tab.automaticTitle = basename.isEmpty ? "/" : basename
            } else if let profileName = profileName(for: session), !profileName.isEmpty {
                // newTab(profile:) sekmeye profil adını tohumlar; senkron onu ezmemeli.
                tab.automaticTitle = profileName
            } else {
                tab.automaticTitle = (session.shellPath as NSString).lastPathComponent
            }
        }
    }

    private func profileName(for session: TerminalSession) -> String? {
        guard let profileID = session.profileID else { return nil }
        return profiles.profiles.first { $0.id == profileID }?.name
    }

    /// Observation köprüsü: MainWindowView bu değeri .onChange ile izleyip
    /// syncAutomaticTitles() çağırır (oturum başlıkları @Observable üzerinden okunur).
    /// Çalışma dizini de karışıma girer, çünkü başlık geri düşüşü ona da bakar
    /// (yalnız `title` izlenseydi cwd değişince sekme başlığı güncellenmezdi).
    var sessionTitleDigest: String {
        tabs.map { tab in
            tab.root.leaves
                .compactMap { leaf -> String? in
                    guard let session = sessionManager.session(id: leaf.sessionID) else { return nil }
                    return session.title + "\u{1D}" + (session.workingDirectory ?? "")
                }
                .joined(separator: "\u{1F}")
        }
        .joined(separator: "\u{1E}")
    }
```

- [ ] **Step 22: Testi çalıştır, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/WorkspaceViewModelTests 2>&1 | tail -20
```

Beklenen: `Test run with 20 tests passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 23: Tüm test hedefini çalıştır ve commit et**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' 2>&1 | tail -10
```

Beklenen: `** TEST SUCCEEDED **` (önceki görevlerin süitleri dahil).

```bash
cd /Users/ahmetbarut/Apps/Termora && git add Termora/ViewModels/WorkspaceViewModel.swift TermoraTests/MockSessionManager.swift TermoraTests/WorkspaceViewModelTests.swift && git commit -m "feat: add WorkspaceViewModel tab operations"
```

---

---

### Task 12: TabBarView (M2)

**Files:**
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Views/TabBarView.swift` (`TabBarLayout` + `TabBarView`)
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/Views/MainWindowView.swift` (Task 10'un tek terminalli gövdesi bu görevde tamamen yenilenir)
- Test (Create): `/Users/ahmetbarut/Apps/Termora/TermoraTests/TabBarLayoutTests.swift`

Bu görev `AppServices`'i **yaratmaz**: `Termora/App/AppServices.swift` Task 10'da yazıldı ve `TermoraApp` orada ona bağlandı. Burada yalnız kullanılır.

**Interfaces:**

Consumes:
- Task 11: `WorkspaceViewModel` (tabs / activeTabID / activeTab / newTab / requestCloseTab / renameTab / syncAutomaticTitles / sessionTitleDigest / profiles), `TerminalTab.displayTitle`, `PaneNode.sessionID(ofPane:)`
- Task 10: `struct TerminalHostView: NSViewRepresentable { let sessionID: UUID; let sessionManager: SessionManager; let isActive: Bool }` — terminal NSView'ını `SessionManager` cache'inden alıp yerleştirir; üç argüman da her çağrıda verilir.
- Task 10: `@MainActor final class AppServices { let settings: SettingsStore; let themes: ThemeStore; let profiles: ProfileStore; let sessionManager: SessionManager; init() }` ve `struct TermoraApp: App { @State private var services = AppServices() }`
- Task 8: `@MainActor @Observable final class SessionManager: SessionManaging { init(settings: SettingsStore, themes: ThemeStore, profiles: ProfileStore, escalationDelay: TimeInterval = 1.5) }`
- Task 5/6/7: `ThemeStore(bundle:)`, `SettingsStore(defaults:)`, `ProfileStore(defaults:)`

Produces:
- `enum TabBarLayout { static let height: CGFloat; static let newTabButtonWidth: CGFloat; static let maxTabWidth: CGFloat; static let minTabWidth: CGFloat; static func tabWidth(availableWidth: CGFloat, tabCount: Int) -> CGFloat }`
- `struct TabBarView: View { init(workspace: WorkspaceViewModel) }` — her sekme öğesinde `.accessibilityIdentifier("tab-<tab.id>")`, yeni sekme düğmesinde `.accessibilityIdentifier("new-tab-button")` bulunur (Task 13'ün XCUITest smoke testi bunları kullanır).
- `struct MainWindowView: View { @MainActor init(services: AppServices) }` — `private let services: AppServices` + `@State private var workspace: WorkspaceViewModel`; Task 13 buna `.focusedSceneValue` ve onay diyaloğunu ekler.

---

- [ ] **Step 1: Sekme genişliği hesabının testini yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/TabBarLayoutTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import Termora

@MainActor
@Suite struct TabBarLayoutTests {

    @Test func zeroTabsHaveZeroWidth() {
        #expect(TabBarLayout.tabWidth(availableWidth: 800, tabCount: 0) == 0)
    }

    @Test func singleTabIsCappedAtMaxWidth() {
        #expect(TabBarLayout.tabWidth(availableWidth: 1000, tabCount: 1) == TabBarLayout.maxTabWidth)
    }

    @Test func tabsShareAvailableWidthEqually() {
        #expect(TabBarLayout.tabWidth(availableWidth: 1000, tabCount: 10) == 100)
        #expect(TabBarLayout.tabWidth(availableWidth: 600, tabCount: 4) == 150)
    }

    @Test func widthNeverDropsBelowMinimum() {
        #expect(TabBarLayout.tabWidth(availableWidth: 1000, tabCount: 40) == TabBarLayout.minTabWidth)
    }

    @Test func negativeAvailableWidthFallsBackToMinimum() {
        #expect(TabBarLayout.tabWidth(availableWidth: -120, tabCount: 3) == TabBarLayout.minTabWidth)
    }

    @Test func layoutConstantsAreConsistent() {
        #expect(TabBarLayout.minTabWidth < TabBarLayout.maxTabWidth)
        #expect(TabBarLayout.height > 0)
        #expect(TabBarLayout.newTabButtonWidth > 0)
    }
}
```

- [ ] **Step 2: Testi çalıştır, derleme hatası bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/TabBarLayoutTests 2>&1 | tail -20
```

Beklenen: `error: cannot find 'TabBarLayout' in scope`, `** TEST BUILD FAILED **`.

- [ ] **Step 3: TabBarLayout'u yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Views/TabBarView.swift` dosyasını oluştur (şimdilik yalnız saf mantık):

```swift
import SwiftUI

/// Sekme çubuğunun saf yerleşim hesapları (test edilebilir).
enum TabBarLayout {
    static let height: CGFloat = 28
    static let newTabButtonWidth: CGFloat = 28
    static let maxTabWidth: CGFloat = 200
    static let minTabWidth: CGFloat = 72

    /// Sekmeler kalan genişliği eşit paylaşır; 200'ü aşmaz, 72'nin altına inmez.
    static func tabWidth(availableWidth: CGFloat, tabCount: Int) -> CGFloat {
        guard tabCount > 0 else { return 0 }
        let usable = max(0, availableWidth)
        let equalShare = usable / CGFloat(tabCount)
        return min(maxTabWidth, max(minTabWidth, equalShare))
    }
}
```

- [ ] **Step 4: Testi çalıştır, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/TabBarLayoutTests 2>&1 | tail -20
```

Beklenen: `Test run with 6 tests passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 5: TabBarView'ı yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Views/TabBarView.swift` dosyasının sonuna (TabBarLayout'tan sonra) ekle:

```swift
/// Elle çizilen sekme çubuğu (macOS 14'te NSWindow tab bar'ı kullanılmaz).
struct TabBarView: View {
    let workspace: WorkspaceViewModel

    @State private var hoveredTabID: UUID?
    @State private var editingTabID: UUID?
    @State private var editingText: String = ""
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = TabBarLayout.tabWidth(
                availableWidth: proxy.size.width - TabBarLayout.newTabButtonWidth,
                tabCount: workspace.tabs.count
            )
            HStack(spacing: 0) {
                ForEach(workspace.tabs) { tab in
                    tabItem(tab, width: width)
                    Divider().frame(height: TabBarLayout.height * 0.6)
                }
                newTabButton
                Spacer(minLength: 0)
            }
        }
        .frame(height: TabBarLayout.height)
        .background(.bar)
    }

    // MARK: - Parçalar

    private func tabItem(_ tab: TerminalTab, width: CGFloat) -> some View {
        let isActive = tab.id == workspace.activeTabID
        let isHovered = hoveredTabID == tab.id

        return HStack(spacing: 4) {
            if editingTabID == tab.id {
                TextField("", text: $editingText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename(tab) }
                    .onChange(of: renameFieldFocused) { _, focused in
                        if !focused { commitRename(tab) }
                    }
            } else {
                Text(tab.displayTitle)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
            }

            Spacer(minLength: 0)

            if isHovered || isActive {
                Button {
                    workspace.requestCloseTab(id: tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sekmeyi kapat")
            }
        }
        .padding(.horizontal, 8)
        .frame(width: width, height: TabBarLayout.height)
        .background(isActive ? Color.accentColor.opacity(0.22) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isActive ? Color.accentColor : Color.clear)
                .frame(height: 2)
        }
        .contentShape(Rectangle())
        // XCUITest smoke testi (Task 13) sekmeleri bu önekle sayar.
        .accessibilityIdentifier("tab-\(tab.id)")
        .onHover { hovering in
            if hovering {
                hoveredTabID = tab.id
            } else if hoveredTabID == tab.id {
                hoveredTabID = nil
            }
        }
        .onTapGesture(count: 2) { beginRename(tab) }
        .onTapGesture { workspace.activeTabID = tab.id }
    }

    private var newTabButton: some View {
        Button {
            workspace.newTab()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .frame(width: TabBarLayout.newTabButtonWidth, height: TabBarLayout.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("new-tab-button")
        .help("Yeni sekme (⌘T)")
        .contextMenu {
            if workspace.profiles.profiles.isEmpty {
                Text("Profil yok")
            } else {
                ForEach(workspace.profiles.profiles) { profile in
                    Button(profile.name) { workspace.newTab(profile: profile) }
                }
            }
        }
    }

    // MARK: - Yeniden adlandırma

    private func beginRename(_ tab: TerminalTab) {
        editingText = tab.customTitle ?? tab.displayTitle
        editingTabID = tab.id
        renameFieldFocused = true
    }

    private func commitRename(_ tab: TerminalTab) {
        guard editingTabID == tab.id else { return }
        editingTabID = nil
        workspace.renameTab(id: tab.id, to: editingText)
    }
}
```

- [ ] **Step 6: Derle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet && echo BUILD_OK
```

Beklenen: `BUILD_OK`.

- [ ] **Step 7: MainWindowView'ı sekme çubuğuyla yeniden yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Views/MainWindowView.swift` içeriğini tamamen aşağıdakiyle değiştir:

```swift
import AppKit
import SwiftUI

struct MainWindowView: View {
    private let services: AppServices
    @State private var workspace: WorkspaceViewModel

    @MainActor
    init(services: AppServices) {
        self.services = services
        _workspace = State(initialValue: WorkspaceViewModel(
            sessionManager: services.sessionManager,
            settings: services.settings,
            profiles: services.profiles
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(workspace: workspace)
            Divider()
            terminalContent
        }
        .frame(minWidth: 480, minHeight: 320)
        .onAppear {
            // Sistemin otomatik pencere sekmelerini kapat: kendi sekme çubuğumuzu çiziyoruz,
            // aksi hâlde macOS "Show Tab Bar" öğesini ekler ve ⌘T ile çakışır.
            NSWindow.allowsAutomaticWindowTabbing = false
            if workspace.tabs.isEmpty { workspace.newTab() }
        }
        .onChange(of: workspace.sessionTitleDigest, initial: true) { _, _ in
            workspace.syncAutomaticTitles()
        }
    }

    @ViewBuilder
    private var terminalContent: some View {
        if let tab = workspace.activeTab,
           let sessionID = tab.root.sessionID(ofPane: tab.activePaneID) {
            TerminalHostView(sessionID: sessionID,
                             sessionManager: services.sessionManager,
                             isActive: true)
                .id(sessionID)
        } else {
            Color.clear
        }
    }
}
```

- [ ] **Step 8: TermoraApp'in AppServices bağlantısını doğrula**

`TermoraApp` Task 10 Step 8'de zaten `AppServices`'e bağlandı; bu görevde **yeniden yazılmaz**. Yalnız dosyanın aşağıdaki hâlde olduğunu doğrula (değilse yalnız farkı düzelt — `Settings` sahnesi ve `.defaultSize` KORUNUR):

```swift
@main
struct TermoraApp: App {
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            MainWindowView(services: services)
        }
        .defaultSize(width: 900, height: 560)

        Settings {
            SettingsPlaceholderView()
        }
    }
}
```

```bash
cd /Users/ahmetbarut/Apps/Termora && grep -n "@State private var services\|MainWindowView(services:\|Settings {" Termora/App/TermoraApp.swift
```

Beklenen: üç satır da bulunur (`App` bir struct olduğu ve SwiftUI onu yeniden oluşturabildiği için servisler `@State` ile tutulur; `let` olsaydı her yeniden oluşturmada yeni `SessionManager` doğar ve açık oturumlar kaybolurdu).

- [ ] **Step 9: Derle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet && echo BUILD_OK
```

Beklenen: `BUILD_OK`.

- [ ] **Step 10: Elle doğrulama — sekme çubuğu**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -derivedDataPath /tmp/TermoraDD -quiet && open /tmp/TermoraDD/Build/Products/Debug/Termora.app
```

Görülmesi gerekenler:
1. Pencerenin üstünde 28 pt yüksekliğinde bir sekme çubuğu var; tek sekme, altında aksan rengi çizgi, başlık "Terminal" ya da shell'in bildirdiği başlık.
2. "+" butonuna tıkla → ikinci sekme açılır ve aktifleşir; içerikte yeni bir shell prompt'u belirir.
3. İlk sekmede `echo merhaba` çalıştır, ikinci sekmeye geç, geri dön → çıktı hâlâ duruyor (oturum ömrü ≠ görünüm ömrü).
4. Fareyi aktif olmayan sekmenin üstüne getir → sağda "x" butonu belirir; fareyi çek → kaybolur.
5. Bir sekmeye çift tıkla → başlık TextField'a döner; "Build" yazıp Enter → başlık "Build" olur ve shell başlığı artık ezmez.
6. Aynı sekmeye çift tıkla, tümünü sil, Enter → otomatik başlığa döner.
7. "x" butonuna tıkla → sekme kapanır, komşu sekme aktifleşir.
8. Menü çubuğunda **View** altında "Show Tab Bar" öğesi **yok** (`MainWindowView.onAppear`'daki `NSWindow.allowsAutomaticWindowTabbing = false`).
9. ⌘, ile Ayarlar penceresi hâlâ açılıyor (Task 10'un `SettingsPlaceholderView` yer tutucusu; M4'te gerçek panelle değişir).

Uygulamayı kapat.

- [ ] **Step 11: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora && git add Termora/Views/TabBarView.swift Termora/Views/MainWindowView.swift TermoraTests/TabBarLayoutTests.swift && git commit -m "feat: add tab bar with rename and close affordances"
```

---

---

### Task 13: AppCommands + kapatma onayı (M2)

**Files:**
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/App/AppCommands.swift`
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/App/TermoraApp.swift` (`.commands { AppCommands() }`)
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/Views/MainWindowView.swift` (`.focusedSceneValue` + `.confirmationDialog`)
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/ViewModels/WorkspaceViewModel.swift` (son sekme kapanınca yeni sekme)
- Test (Modify): `/Users/ahmetbarut/Apps/Termora/TermoraTests/WorkspaceViewModelTests.swift`
- Test (Create): `/Users/ahmetbarut/Apps/Termora/TermoraUITests/TabSmokeUITests.swift` (XCUITest; `TermoraUITests` hedefi projede zaten var)

**Interfaces:**

Consumes:
- Task 11: `WorkspaceViewModel` (newTab / requestCloseTab / confirmPendingClose / cancelPendingClose / selectTab / nextTab / previousTab / activeTabID / pendingClose / tabs)
- Task 12: `MainWindowView(services:)` (`private let services: AppServices` + `@State private var workspace: WorkspaceViewModel`), `TabBarView` (sekme öğelerinde `tab-<id>` accessibility identifier'ı)
- Task 10: `AppServices`, `TermoraApp` (`@State private var services = AppServices()`, `Settings` sahnesi, `.defaultSize`)

Produces:
- `struct WorkspaceFocusedKey: FocusedValueKey { typealias Value = WorkspaceViewModel }`
- `extension FocusedValues { var workspace: WorkspaceViewModel? { get set } }`
- `struct AppCommands: Commands` — ⌘T yeni sekme, ⌘W (`CommandGroup(replacing: .saveItem)`) aktif sekmeyi kapat, ⌘1–⌘9 `selectTab(at: n-1)`, ⌘⇧] / ⌘⇧[ next/previous. Task 17 buna ⌘D/⌘⇧D/⌘⌥ok, Task 20 ⌘F ekler.
- `final class TabSmokeUITests: XCTestCase` — açılış + ⌘T + ⌘W smoke testi (spec §11).
- Davranış değişikliği: `WorkspaceViewModel` son sekme kapandığında otomatik olarak yeni boş sekme açar (pencere açık kalır; `dismissWindow` kullanılmaz). Bu, spec §3 madde 3'ten **bilinçli sapmadır** (terminal uygulaması konvansiyonu) — spec bu kararla güncellenmeli.
- Not (test çerçevesi istisnası): `TermoraUITests` hedefi XCUITest gerektirir (XCUIApplication Swift Testing ile kullanılamaz); yalnız bu hedefte `import XCTest` serbesttir.

---

- [ ] **Step 1: Son sekme davranışının yeni testini yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/WorkspaceViewModelTests.swift` içindeki `closingLastTabClearsActiveTabID` testini tamamen aşağıdakiyle değiştir (davranış değişti: pencere boş kalmaz):

```swift
    @Test func closingLastTabOpensAReplacementTab() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        let firstTabID = workspace.tabs[0].id
        let firstSessionID = workspace.tabs[0].root.leaves[0].sessionID

        workspace.requestCloseTab(id: firstTabID)

        #expect(workspace.tabs.count == 1)
        #expect(workspace.tabs[0].id != firstTabID)
        #expect(workspace.activeTabID == workspace.tabs[0].id)
        #expect(manager.terminatedSessionIDs == [firstSessionID])
        #expect(manager.sessions.count == 1)
    }

    @Test func confirmingCloseOfTheLastBusyTabAlsoOpensAReplacementTab() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        let tab = workspace.tabs[0]
        manager.busySessionIDs.insert(tab.root.leaves[0].sessionID)
        workspace.requestCloseTab(id: tab.id)
        #expect(workspace.tabs.count == 1)

        workspace.confirmPendingClose()

        #expect(workspace.tabs.count == 1)
        #expect(workspace.tabs[0].id != tab.id)
        #expect(workspace.pendingClose == nil)
    }
```

- [ ] **Step 2: Testi çalıştır, FAIL bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/WorkspaceViewModelTests 2>&1 | tail -20
```

Beklenen: `✘ Test closingLastTabOpensAReplacementTab() recorded an issue` — `Expectation failed: (workspace.tabs.count → 0) == 1`, ve `** TEST FAILED **`.

- [ ] **Step 3: closeTab'ı yedek sekme açacak şekilde güncelle**

`/Users/ahmetbarut/Apps/Termora/Termora/ViewModels/WorkspaceViewModel.swift` içindeki `private func closeTab(id:)` gövdesini değiştir:

```swift
    private func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        for leaf in tabs[index].root.leaves {
            sessionManager.terminateSession(id: leaf.sessionID)
        }
        tabs.remove(at: index)

        if tabs.isEmpty {
            // Terminal uygulaması konvansiyonu: pencere boş kalmaz, yeni oturum açılır.
            newTab()
        } else if activeTabID == id {
            activeTabID = tabs[min(index, tabs.count - 1)].id
        }
    }
```

(`closeAllTabs()` bu yolu kullanmaz; pencere kapatma onayında sekmeler doğrudan temizlenir, yedek sekme açılmaz.)

- [ ] **Step 4: Testi çalıştır, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/WorkspaceViewModelTests 2>&1 | tail -20
```

Beklenen: `Test run with 21 tests passed`, `** TEST SUCCEEDED **` (Task 11'in 20 testi; biri ikiye bölündü).

- [ ] **Step 5: AppCommands'i yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/App/AppCommands.swift`:

```swift
import SwiftUI

/// Menü komutları key window'un WorkspaceViewModel'ine @FocusedValue ile ulaşır.
struct WorkspaceFocusedKey: FocusedValueKey {
    typealias Value = WorkspaceViewModel
}

extension FocusedValues {
    var workspace: WorkspaceViewModel? {
        get { self[WorkspaceFocusedKey.self] }
        set { self[WorkspaceFocusedKey.self] = newValue }
    }
}

struct AppCommands: Commands {
    @FocusedValue(\.workspace) private var workspace

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Yeni Sekme") {
                workspace?.newTab()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(workspace == nil)
        }

        // ⌘W standart "Close Window" öğesinin yerine geçer: önce sekme kapanır.
        CommandGroup(replacing: .saveItem) {
            Button("Sekmeyi Kapat") {
                if let workspace, let activeTabID = workspace.activeTabID {
                    workspace.requestCloseTab(id: activeTabID)
                }
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(workspace?.activeTabID == nil)
        }

        // DİKKAT: `Commands` protokolünde `disabled` YOKTUR (yalnız `View` üzerinde vardır);
        // `CommandMenu { … }.disabled(…)` derlenmez. Etkinlik her Button'a tek tek verilir.
        CommandMenu("Sekme") {
            Button("Sonraki Sekme") { workspace?.nextTab() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(workspace == nil)
            Button("Önceki Sekme") { workspace?.previousTab() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(workspace == nil)

            Divider()

            ForEach(1...9, id: \.self) { number in
                Button("Sekme \(number)") {
                    workspace?.selectTab(at: number - 1)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                .disabled(workspace == nil)
            }
        }
    }
}
```

- [ ] **Step 6: TermoraApp'e komutları bağla**

`/Users/ahmetbarut/Apps/Termora/Termora/App/TermoraApp.swift` içindeki `WindowGroup` bloğuna yalnız `.commands` ekle; `Settings` sahnesi ve `.defaultSize` olduğu gibi KALIR (⌘, ölü menü öğesine dönmemeli):

```swift
@main
struct TermoraApp: App {
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            MainWindowView(services: services)
        }
        .defaultSize(width: 900, height: 560)
        .commands {
            AppCommands()
        }

        Settings {
            SettingsPlaceholderView()
        }
    }
}
```

- [ ] **Step 7: MainWindowView'a odak değeri ve onay diyaloğunu ekle**

`/Users/ahmetbarut/Apps/Termora/Termora/Views/MainWindowView.swift` içinde `body`'yi aşağıdakiyle değiştir ve altına `pendingCloseBinding` ile `pendingCloseMessage`'ı ekle:

```swift
    var body: some View {
        VStack(spacing: 0) {
            TabBarView(workspace: workspace)
            Divider()
            terminalContent
        }
        .frame(minWidth: 480, minHeight: 320)
        .onAppear {
            NSWindow.allowsAutomaticWindowTabbing = false
            if workspace.tabs.isEmpty { workspace.newTab() }
        }
        .onChange(of: workspace.sessionTitleDigest, initial: true) { _, _ in
            workspace.syncAutomaticTitles()
        }
        .focusedSceneValue(\.workspace, workspace)
        .confirmationDialog(
            pendingCloseMessage,
            isPresented: pendingCloseBinding
        ) {
            Button("Kapat", role: .destructive) { workspace.confirmPendingClose() }
            Button("Vazgeç", role: .cancel) { workspace.cancelPendingClose() }
        }
    }

    private var pendingCloseBinding: Binding<Bool> {
        Binding(
            get: { workspace.pendingClose != nil },
            set: { isPresented in
                if !isPresented { workspace.cancelPendingClose() }
            }
        )
    }

    /// Onay metni hedefe göre değişir; M3'te panel (Task 17), M5'te pencere (Task 22) dalı da kullanılır.
    private var pendingCloseMessage: String {
        switch workspace.pendingClose?.target {
        case .pane:
            return "Bu panelde çalışan bir işlem var. Panel kapatılsın mı?"
        case .window:
            return "Çalışan işlemler var. Pencere kapatılsın mı?"
        case .tab, .none:
            return "Bu sekmede çalışan bir işlem var. Sekme kapatılsın mı?"
        }
    }
```

- [ ] **Step 8: Derle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet && echo BUILD_OK
```

Beklenen: `BUILD_OK`.

- [ ] **Step 9: Tüm testleri çalıştır**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' 2>&1 | tail -10
```

Beklenen: `** TEST SUCCEEDED **`.

- [ ] **Step 10: XCUITest smoke testini yaz (açılış + sekme aç/kapat)**

Spec §11 "UI: açılış + sekme aç/kapat smoke testi" maddesi. Bu tek testin hedefi `TermoraUITests`'tir; XCUIApplication Swift Testing ile kullanılamadığı için **yalnız bu hedefte** `import XCTest` serbesttir (Global Constraints'teki test çerçevesi istisnası). `TermoraUITests` hedefi şablondan geldiği için projede zaten var (`project.pbxproj`, `com.apple.product-type.bundle.ui-testing`), yeni hedef eklemek gerekmez.

`/Users/ahmetbarut/Apps/Termora/TermoraUITests/TabSmokeUITests.swift`:

```swift
import XCTest

/// Spec §11 smoke testi: uygulama açılıyor, ⌘T sekme ekliyor, ⌘W sekmeyi kapatıyor.
/// Sekmeler TabBarView'ın verdiği "tab-<uuid>" accessibility identifier'ı ile sayılır.
final class TabSmokeUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testLaunchesThenOpensAndClosesATab() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15),
                      "Ana pencere 15 sn içinde açılmadı")
        XCTAssertTrue(waitForTabCount(1, in: app), "Açılışta tam olarak bir sekme beklenir")

        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(waitForTabCount(2, in: app), "⌘T ikinci sekmeyi açmadı")

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForTabCount(1, in: app), "⌘W sekmeyi kapatmadı")
    }

    // MARK: - Yardımcılar

    private func tabCount(in app: XCUIApplication) -> Int {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "tab-"))
            .count
    }

    private func waitForTabCount(_ expected: Int,
                                 in app: XCUIApplication,
                                 timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if tabCount(in: app) == expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }
}
```

Testi çalıştır:

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraUITests/TabSmokeUITests 2>&1 | tail -20
```

Beklenen: `Test Suite 'TabSmokeUITests' passed` ve `** TEST SUCCEEDED **`. Test koşarken pencere görünür biçimde açılır; makineyi kilitleme.

`xcodebuild` "does not match any tests" derse şemanın test eylemi `TermoraUITests` hedefini içermiyordur: `xcodebuild -project Termora.xcodeproj -scheme Termora -showTestPlans` / `xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraUITests 2>&1 | grep -i "TermoraUITests"` ile doğrula (otomatik üretilen şemalarda hedef zaten ekli olur).

Şablondan gelen boş `TermoraUITests/TermoraUITests.swift` ve `TermoraUITests/TermoraUITestsLaunchTests.swift` dosyaları duruyorsa ve derlemeyi yavaşlatıyorsa oldukları gibi bırak (silmek gerekmez); yalnız bu smoke testi eklenir.

- [ ] **Step 11: Elle doğrulama — kısayollar ve onay**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -derivedDataPath /tmp/TermoraDD -quiet && open /tmp/TermoraDD/Build/Products/Debug/Termora.app
```

Görülmesi gerekenler:
1. **File** menüsünde "Yeni Sekme ⌘T" ve "Sekmeyi Kapat ⌘W" var; standart "Close Window" öğesi yok.
2. Menü çubuğunda **Sekme** menüsü var: "Sonraki Sekme ⌘⇧]", "Önceki Sekme ⌘⇧[", ayraç, "Sekme 1…9 ⌘1…⌘9".
3. ⌘T üç kez → dört sekme; ⌘1 → ilk sekme aktifleşir; ⌘3 → üçüncü; ⌘⇧] son sekmeden ilk sekmeye sarmalar; ⌘⇧[ geri sarmalar.
4. Aktif sekmede `sleep 60` yaz ve çalıştır, ⌘W → "Bu sekmede çalışan bir işlem var. Sekme kapatılsın mı?" diyaloğu çıkar. "Vazgeç" → sekme kalır, `sleep` sürüyor. Tekrar ⌘W → "Kapat" → sekme kapanır.
5. Boştaki (komut çalışmayan) bir sekmede ⌘W → onaysız kapanır.
6. Tek sekme kalana kadar kapat, sonra ⌘W → pencere **kapanmaz**, yeni boş bir sekme açılır ve prompt gelir.
7. Terminale odaklıyken `echo ⌘W` gibi bir metin yazarken kısayolların terminale kaçmadığını, menü öğelerinin çalıştığını gör.

Uygulamayı kapat.

- [ ] **Step 12: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora && git add Termora/App/AppCommands.swift Termora/App/TermoraApp.swift Termora/Views/MainWindowView.swift Termora/ViewModels/WorkspaceViewModel.swift TermoraTests/WorkspaceViewModelTests.swift TermoraUITests/TabSmokeUITests.swift && git commit -m "feat: add menu commands and tab close confirmation"
```

---

---

### Task 14: PaneNode ağacı (M3)

**Files:**
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/Models/PaneNode.swift` (Task 11'de yaratıldı; `splitting`/`removing`/`updatingRatio`/`siblingLeafPaneID` burada eklenir)
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/PaneNodeTests.swift`

**Interfaces:**

*Consumes:*
- Task 11: `enum SplitAxis` ve `indirect enum PaneNode` (`leaf`/`split` case'leri, `leaves`, `sessionID(ofPane:)`) — `/Users/ahmetbarut/Apps/Termora/Termora/Models/PaneNode.swift`. Bu görev dosyayı **sıfırdan yazmaz**, yalnız yeni operasyonları ekler; mevcut case'lerin ve iki erişimcinin imzası değişmez.
- Task 11 testleri: `TermoraTests/PaneNodeLeafTests.swift` (ayrı tip adı — bu görevin `PaneNodeTests`'i ile çakışmaz, ikisi de kalır).

*Produces:*
```swift
// Task 11'de zaten var — burada DEĞİŞMEZ, yalnız referans için:
enum SplitAxis: String, Codable { case vertical; case horizontal }

indirect enum PaneNode: Equatable {
    case leaf(paneID: UUID, sessionID: UUID)
    case split(id: UUID, axis: SplitAxis, ratio: Double, first: PaneNode, second: PaneNode)

    var leaves: [(paneID: UUID, sessionID: UUID)] { get }
    func sessionID(ofPane paneID: UUID) -> UUID?
}

// Bu görevde EKLENEN operasyonlar (aynı dosyanın sonuna `extension PaneNode` olarak):
extension PaneNode {
    static let ratioRange: ClosedRange<Double>         // 0.15...0.85 — Task 17 SplitLayoutMath da okur

    func splitting(paneID: UUID, axis: SplitAxis, newPaneID: UUID, newSessionID: UUID) -> PaneNode
    func removing(paneID: UUID) -> PaneNode?
    func updatingRatio(splitID: UUID, ratio: Double) -> PaneNode
    func siblingLeafPaneID(of paneID: UUID) -> UUID?   // Task 16 odak devri için kullanır
}
```
`SplitAxis.vertical` = dikey ayraç, paneller **yan yana** (⌘D). `SplitAxis.horizontal` = yatay ayraç, paneller **üst üste** (⌘⇧D).

- [ ] **Step 1: `PaneNodeTests.swift` test dosyasını yaz (böl / iç içe böl / leaves / sessionID)**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/PaneNodeTests.swift` dosyasını oluştur (`Termora/Models/` klasörü Task 1 Step 7'de, `PaneNode.swift` Task 11 Step 3'te açıldı):

```swift
//
//  PaneNodeTests.swift
//  TermoraTests
//

import Foundation
import Testing
@testable import Termora

@Suite("PaneNode")
struct PaneNodeTests {

    // MARK: - Helpers

    private func makeLeaf() -> (node: PaneNode, paneID: UUID, sessionID: UUID) {
        let paneID = UUID()
        let sessionID = UUID()
        return (.leaf(paneID: paneID, sessionID: sessionID), paneID, sessionID)
    }

    private func splitID(of node: PaneNode) -> UUID? {
        if case let .split(id, _, _, _, _) = node { return id }
        return nil
    }

    // MARK: - splitting

    @Test("splitting hedef leaf'i 0.5 oranlı split'e çevirir, eski panel first'te kalır")
    func splittingConvertsTargetLeaf() {
        let (node, paneID, sessionID) = makeLeaf()
        let newPaneID = UUID()
        let newSessionID = UUID()

        let result = node.splitting(paneID: paneID,
                                    axis: .vertical,
                                    newPaneID: newPaneID,
                                    newSessionID: newSessionID)

        guard case let .split(_, axis, ratio, first, second) = result else {
            Issue.record("split bekleniyordu, gelen: \(result)")
            return
        }
        #expect(axis == .vertical)
        #expect(ratio == 0.5)
        #expect(first == .leaf(paneID: paneID, sessionID: sessionID))
        #expect(second == .leaf(paneID: newPaneID, sessionID: newSessionID))
    }

    @Test("iç içe bölme yalnız hedef leaf'i etkiler")
    func splittingNested() {
        let paneA = UUID(), sessionA = UUID()
        let paneB = UUID(), sessionB = UUID()
        let paneC = UUID(), sessionC = UUID()

        let root = PaneNode.leaf(paneID: paneA, sessionID: sessionA)
        let twoPanes = root.splitting(paneID: paneA, axis: .vertical,
                                      newPaneID: paneB, newSessionID: sessionB)
        let threePanes = twoPanes.splitting(paneID: paneB, axis: .horizontal,
                                            newPaneID: paneC, newSessionID: sessionC)

        guard case let .split(_, outerAxis, _, outerFirst, outerSecond) = threePanes else {
            Issue.record("dış split bekleniyordu")
            return
        }
        #expect(outerAxis == .vertical)
        #expect(outerFirst == .leaf(paneID: paneA, sessionID: sessionA))

        guard case let .split(_, innerAxis, innerRatio, innerFirst, innerSecond) = outerSecond else {
            Issue.record("iç split bekleniyordu")
            return
        }
        #expect(innerAxis == .horizontal)
        #expect(innerRatio == 0.5)
        #expect(innerFirst == .leaf(paneID: paneB, sessionID: sessionB))
        #expect(innerSecond == .leaf(paneID: paneC, sessionID: sessionC))
    }

    // MARK: - leaves / sessionID

    @Test("leaves soldan sağa (first→second) sırayı korur")
    func leavesOrder() {
        let paneA = UUID(), sessionA = UUID()
        let paneB = UUID(), sessionB = UUID()
        let paneC = UUID(), sessionC = UUID()

        let tree = PaneNode.split(
            id: UUID(), axis: .vertical, ratio: 0.5,
            first: .split(id: UUID(), axis: .horizontal, ratio: 0.5,
                          first: .leaf(paneID: paneA, sessionID: sessionA),
                          second: .leaf(paneID: paneB, sessionID: sessionB)),
            second: .leaf(paneID: paneC, sessionID: sessionC))

        #expect(tree.leaves.map { $0.paneID } == [paneA, paneB, paneC])
        #expect(tree.leaves.map { $0.sessionID } == [sessionA, sessionB, sessionC])
    }

    @Test("sessionID(ofPane:) doğru oturumu bulur, bilinmeyen panel için nil döner")
    func sessionLookup() {
        let (leaf, paneID, sessionID) = makeLeaf()
        let newPaneID = UUID(), newSessionID = UUID()
        let tree = leaf.splitting(paneID: paneID, axis: .horizontal,
                                  newPaneID: newPaneID, newSessionID: newSessionID)

        #expect(tree.sessionID(ofPane: paneID) == sessionID)
        #expect(tree.sessionID(ofPane: newPaneID) == newSessionID)
        #expect(tree.sessionID(ofPane: UUID()) == nil)
    }
}
```

- [ ] **Step 2: Testi çalıştır, derleme hatasıyla FAIL bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/PaneNodeTests 2>&1 | tail -20
```

Beklenen (kırmızı): `PaneNodeTests.swift:...: error: value of type 'PaneNode' has no member 'splitting'` ve son satırda `** TEST BUILD FAILED **`.

(Not: `PaneNode` ve `SplitAxis` Task 11 Step 3'te tanımlandığı için "cannot find 'PaneNode' in scope" hatası **beklenmez**; eksik olan yalnız operasyonlardır.)

- [ ] **Step 3: `splitting(paneID:axis:newPaneID:newSessionID:)` operasyonunu MEVCUT dosyaya ekle**

`/Users/ahmetbarut/Apps/Termora/Termora/Models/PaneNode.swift` dosyasının **sonuna** aşağıdaki extension'ı ekle. Dosyanın başındaki `import Foundation`, `enum SplitAxis`, `indirect enum PaneNode` bildirimi ve enum gövdesindeki `leaves` / `sessionID(ofPane:)` erişimcileri Task 11'den olduğu gibi KALIR — tekrar yazılmaz (yoksa `error: invalid redeclaration of 'SplitAxis'` alınır).

```swift
extension PaneNode {

    /// Turns the target leaf into a 50/50 split; the old pane stays in `first`.
    /// Returns an unchanged tree when `paneID` is not present.
    func splitting(paneID: UUID, axis: SplitAxis, newPaneID: UUID, newSessionID: UUID) -> PaneNode {
        switch self {
        case let .leaf(id, sessionID):
            guard id == paneID else { return self }
            return .split(id: UUID(),
                          axis: axis,
                          ratio: 0.5,
                          first: .leaf(paneID: id, sessionID: sessionID),
                          second: .leaf(paneID: newPaneID, sessionID: newSessionID))

        case let .split(id, splitAxis, ratio, first, second):
            return .split(id: id,
                          axis: splitAxis,
                          ratio: ratio,
                          first: first.splitting(paneID: paneID, axis: axis,
                                                 newPaneID: newPaneID, newSessionID: newSessionID),
                          second: second.splitting(paneID: paneID, axis: axis,
                                                   newPaneID: newPaneID, newSessionID: newSessionID))
        }
    }
}
```

- [ ] **Step 4: Testi çalıştır, PASS bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/PaneNodeTests 2>&1 | tail -20
```

Beklenen: `Test run with 4 tests passed` ve `** TEST SUCCEEDED **`.

- [ ] **Step 5: `removing` ve `siblingLeafPaneID` testlerini ekle**

`PaneNodeTests.swift` içinde, `// MARK: - leaves / sessionID` bloğunun sonrasına (son `}` öncesine) ekle:

```swift
    // MARK: - removing

    @Test("removing kardeşi ebeveynin yerine yükseltir")
    func removingPromotesSibling() {
        let paneA = UUID(), sessionA = UUID()
        let paneB = UUID(), sessionB = UUID()
        let tree = PaneNode.leaf(paneID: paneA, sessionID: sessionA)
            .splitting(paneID: paneA, axis: .vertical, newPaneID: paneB, newSessionID: sessionB)

        #expect(tree.removing(paneID: paneB) == .leaf(paneID: paneA, sessionID: sessionA))
        #expect(tree.removing(paneID: paneA) == .leaf(paneID: paneB, sessionID: sessionB))
    }

    @Test("derin ağaçta removing yalnız ilgili alt ağacı sadeleştirir")
    func removingInNestedTree() {
        let paneA = UUID(), sessionA = UUID()
        let paneB = UUID(), sessionB = UUID()
        let paneC = UUID(), sessionC = UUID()
        let outerID = UUID()

        let tree = PaneNode.split(
            id: outerID, axis: .vertical, ratio: 0.4,
            first: .leaf(paneID: paneA, sessionID: sessionA),
            second: .split(id: UUID(), axis: .horizontal, ratio: 0.5,
                           first: .leaf(paneID: paneB, sessionID: sessionB),
                           second: .leaf(paneID: paneC, sessionID: sessionC)))

        let result = tree.removing(paneID: paneC)
        #expect(result == .split(id: outerID, axis: .vertical, ratio: 0.4,
                                 first: .leaf(paneID: paneA, sessionID: sessionA),
                                 second: .leaf(paneID: paneB, sessionID: sessionB)))
    }

    @Test("kökteki tek leaf kaldırılırsa nil döner")
    func removingLastLeafReturnsNil() {
        let (node, paneID, _) = makeLeaf()
        #expect(node.removing(paneID: paneID) == nil)
    }

    @Test("bilinmeyen panel kaldırılınca ağaç değişmez")
    func removingUnknownPaneKeepsTree() {
        let paneA = UUID(), sessionA = UUID()
        let paneB = UUID(), sessionB = UUID()
        let tree = PaneNode.leaf(paneID: paneA, sessionID: sessionA)
            .splitting(paneID: paneA, axis: .vertical, newPaneID: paneB, newSessionID: sessionB)

        #expect(tree.removing(paneID: UUID()) == tree)
    }

    // MARK: - siblingLeafPaneID

    @Test("siblingLeafPaneID kardeş alt ağacın ilk yaprağını verir")
    func siblingLookup() {
        let paneA = UUID(), sessionA = UUID()
        let paneB = UUID(), sessionB = UUID()
        let paneC = UUID(), sessionC = UUID()

        // split( split(A, B), C ) — B'nin kardeşi A'dır, leaves sırasında bir SONRAKİ eleman C olsa bile.
        let tree = PaneNode.split(
            id: UUID(), axis: .vertical, ratio: 0.5,
            first: .split(id: UUID(), axis: .horizontal, ratio: 0.5,
                          first: .leaf(paneID: paneA, sessionID: sessionA),
                          second: .leaf(paneID: paneB, sessionID: sessionB)),
            second: .leaf(paneID: paneC, sessionID: sessionC))

        #expect(tree.siblingLeafPaneID(of: paneB) == paneA)
        #expect(tree.siblingLeafPaneID(of: paneA) == paneB)
        #expect(tree.siblingLeafPaneID(of: paneC) == paneA)   // C'nin kardeşi split(A,B) → ilk yaprak A
        #expect(tree.siblingLeafPaneID(of: UUID()) == nil)
        #expect(PaneNode.leaf(paneID: paneA, sessionID: sessionA).siblingLeafPaneID(of: paneA) == nil)
    }
```

- [ ] **Step 6: Testi çalıştır, FAIL bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/PaneNodeTests 2>&1 | tail -20
```

Beklenen: `error: value of type 'PaneNode' has no member 'removing'` (ve `siblingLeafPaneID` için aynısı), `** TEST BUILD FAILED **`.

- [ ] **Step 7: `removing` ve `siblingLeafPaneID`'i uygula**

`PaneNode.swift` içinde Step 3'te eklenen `extension PaneNode` bloğunun sonuna, `splitting(paneID:axis:newPaneID:newSessionID:)` fonksiyonundan sonra ekle:

```swift
    /// Removes a pane; the sibling subtree replaces the parent split.
    /// Returns `nil` when the removed pane was the only leaf.
    func removing(paneID: UUID) -> PaneNode? {
        switch self {
        case let .leaf(id, _):
            return id == paneID ? nil : self

        case let .split(id, axis, ratio, first, second):
            let newFirst = first.removing(paneID: paneID)
            let newSecond = second.removing(paneID: paneID)
            switch (newFirst, newSecond) {
            case (nil, nil):
                return nil
            case let (nil, .some(remaining)):
                return remaining
            case let (.some(remaining), nil):
                return remaining
            case let (.some(lhs), .some(rhs)):
                return .split(id: id, axis: axis, ratio: ratio, first: lhs, second: rhs)
            }
        }
    }

    /// First leaf of the sibling subtree — the focus target after `paneID` is closed.
    func siblingLeafPaneID(of paneID: UUID) -> UUID? {
        switch self {
        case .leaf:
            return nil
        case let .split(_, _, _, first, second):
            if case let .leaf(id, _) = first, id == paneID {
                return second.leaves.first?.paneID
            }
            if case let .leaf(id, _) = second, id == paneID {
                return first.leaves.first?.paneID
            }
            if first.sessionID(ofPane: paneID) != nil {
                return first.siblingLeafPaneID(of: paneID) ?? second.leaves.first?.paneID
            }
            if second.sessionID(ofPane: paneID) != nil {
                return second.siblingLeafPaneID(of: paneID) ?? first.leaves.first?.paneID
            }
            return nil
        }
    }
```

- [ ] **Step 8: Testi çalıştır, PASS bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/PaneNodeTests 2>&1 | tail -20
```

Beklenen: `Test run with 9 tests passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 9: `updatingRatio` testlerini ekle**

`PaneNodeTests.swift` içine, son `}` öncesine ekle:

```swift
    // MARK: - updatingRatio

    @Test("updatingRatio hedef split'in oranını değiştirir")
    func updatingRatioChangesTarget() {
        let paneA = UUID(), sessionA = UUID()
        let paneB = UUID(), sessionB = UUID()
        let tree = PaneNode.leaf(paneID: paneA, sessionID: sessionA)
            .splitting(paneID: paneA, axis: .vertical, newPaneID: paneB, newSessionID: sessionB)
        guard let id = splitID(of: tree) else {
            Issue.record("split id okunamadı")
            return
        }

        let updated = tree.updatingRatio(splitID: id, ratio: 0.3)
        guard case let .split(_, _, ratio, _, _) = updated else {
            Issue.record("split bekleniyordu")
            return
        }
        #expect(ratio == 0.3)
    }

    @Test("updatingRatio oranı 0.15...0.85 aralığına kırpar")
    func updatingRatioClamps() {
        let paneA = UUID(), sessionA = UUID()
        let paneB = UUID(), sessionB = UUID()
        let tree = PaneNode.leaf(paneID: paneA, sessionID: sessionA)
            .splitting(paneID: paneA, axis: .vertical, newPaneID: paneB, newSessionID: sessionB)
        guard let id = splitID(of: tree) else {
            Issue.record("split id okunamadı")
            return
        }

        var ratios: [Double] = []
        for candidate in [-1.0, 0.0, 0.15, 0.5, 0.85, 1.0, 4.2] {
            if case let .split(_, _, ratio, _, _) = tree.updatingRatio(splitID: id, ratio: candidate) {
                ratios.append(ratio)
            }
        }
        #expect(ratios == [0.15, 0.15, 0.15, 0.5, 0.85, 0.85, 0.85])
    }

    @Test("updatingRatio iç split'i bulur, bilinmeyen id ağacı değiştirmez")
    func updatingRatioNestedAndUnknown() {
        let paneA = UUID(), sessionA = UUID()
        let paneB = UUID(), sessionB = UUID()
        let paneC = UUID(), sessionC = UUID()
        let innerID = UUID()

        let tree = PaneNode.split(
            id: UUID(), axis: .vertical, ratio: 0.4,
            first: .leaf(paneID: paneA, sessionID: sessionA),
            second: .split(id: innerID, axis: .horizontal, ratio: 0.5,
                           first: .leaf(paneID: paneB, sessionID: sessionB),
                           second: .leaf(paneID: paneC, sessionID: sessionC)))

        let updated = tree.updatingRatio(splitID: innerID, ratio: 0.7)
        guard case let .split(_, _, outerRatio, _, second) = updated,
              case let .split(_, _, innerRatio, _, _) = second else {
            Issue.record("iç içe split bekleniyordu")
            return
        }
        #expect(outerRatio == 0.4)
        #expect(innerRatio == 0.7)

        #expect(tree.updatingRatio(splitID: UUID(), ratio: 0.7) == tree)
    }
```

- [ ] **Step 10: Testi çalıştır, FAIL bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/PaneNodeTests 2>&1 | tail -20
```

Beklenen: `error: value of type 'PaneNode' has no member 'updatingRatio'`, `** TEST BUILD FAILED **`.

- [ ] **Step 11: `updatingRatio`'yu uygula**

`PaneNode.swift` içinde Step 3'te eklenen `extension PaneNode` bloğunun sonuna ekle:

```swift
    /// Allowed divider range; keeps both panes usable.
    static let ratioRange: ClosedRange<Double> = 0.15...0.85

    /// Updates one split's ratio, clamped to `ratioRange`. Other nodes are untouched.
    func updatingRatio(splitID: UUID, ratio: Double) -> PaneNode {
        switch self {
        case .leaf:
            return self

        case let .split(id, axis, currentRatio, first, second):
            if id == splitID {
                let clamped = min(max(ratio, PaneNode.ratioRange.lowerBound), PaneNode.ratioRange.upperBound)
                return .split(id: id, axis: axis, ratio: clamped, first: first, second: second)
            }
            return .split(id: id,
                          axis: axis,
                          ratio: currentRatio,
                          first: first.updatingRatio(splitID: splitID, ratio: ratio),
                          second: second.updatingRatio(splitID: splitID, ratio: ratio))
        }
    }
```

- [ ] **Step 12: Testi çalıştır, PASS bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/PaneNodeTests 2>&1 | tail -20
```

Beklenen: `Test run with 12 tests passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 13: Commit**

```bash
git -C /Users/ahmetbarut/Apps/Termora add Termora/Models/PaneNode.swift TermoraTests/PaneNodeTests.swift
git -C /Users/ahmetbarut/Apps/Termora commit -m "feat: add PaneNode split tree model with split/remove/ratio operations"
```

---

---

### Task 15: PaneGeometry komşu bulma (M3)

**Files:**
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Models/PaneGeometry.swift`
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/PaneGeometryTests.swift`

**Interfaces:**

*Consumes:* Yok (saf geometri; yalnız `Foundation` + `CoreGraphics`).

*Produces:*
```swift
enum FocusDirection { case left, right, up, down }

enum PaneGeometry {
    static func neighbor(of paneID: UUID, direction: FocusDirection, frames: [UUID: CGRect]) -> UUID?
}
```
`frames` **AppKit koordinatlarındadır**: origin sol-alt, +y yukarı. Dolayısıyla `.up` = `minY`'si mevcut panelin `maxY`'sinden büyük olan aday. (SwiftUI çerçevelerinin bu düzene çevrimi Task 17'deki `PaneFrameConverter`'ın işidir.)

Algoritma: yöne göre adayları filtrele (1pt tolerans), dik eksende örtüşmesi sıfır olanları ele, kalanlardan **örtüşmesi en büyük** olanı seç; eşitlikte **en yakın** olanı, o da eşitse dik eksende merkezi en yakın olanı seç (sözlük sırası deterministik olmadığı için üçüncü anahtar gerekli).

- [ ] **Step 1: Test dosyasını yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/PaneGeometryTests.swift`:

```swift
//
//  PaneGeometryTests.swift
//  TermoraTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Termora

@Suite("PaneGeometry")
struct PaneGeometryTests {

    // İki panel yan yana (AppKit: origin sol-alt).
    private struct SideBySide {
        let left = UUID()
        let right = UUID()
        var frames: [UUID: CGRect] {
            [left: CGRect(x: 0, y: 0, width: 100, height: 200),
             right: CGRect(x: 100, y: 0, width: 100, height: 200)]
        }
    }

    // Sol: tam boy. Sağ: alt (yüksek) ve üst (alçak) iki panel.
    private struct MixedLayout {
        let left = UUID()
        let rightBottom = UUID()
        let rightTop = UUID()
        var frames: [UUID: CGRect] {
            [left: CGRect(x: 0, y: 0, width: 100, height: 200),
             rightBottom: CGRect(x: 100, y: 0, width: 100, height: 120),
             rightTop: CGRect(x: 100, y: 120, width: 100, height: 80)]
        }
    }

    @Test("yan yana yerleşimde right ve left komşuları bulunur")
    func horizontalNeighbors() {
        let layout = SideBySide()
        #expect(PaneGeometry.neighbor(of: layout.left, direction: .right, frames: layout.frames) == layout.right)
        #expect(PaneGeometry.neighbor(of: layout.right, direction: .left, frames: layout.frames) == layout.left)
    }

    @Test("yan yana yerleşimde dikey yönlerde komşu yoktur")
    func noVerticalNeighbors() {
        let layout = SideBySide()
        #expect(PaneGeometry.neighbor(of: layout.left, direction: .up, frames: layout.frames) == nil)
        #expect(PaneGeometry.neighbor(of: layout.left, direction: .down, frames: layout.frames) == nil)
    }

    @Test("kenardaki panelde yön dışına çıkınca nil döner")
    func edgeReturnsNil() {
        let layout = SideBySide()
        #expect(PaneGeometry.neighbor(of: layout.right, direction: .right, frames: layout.frames) == nil)
        #expect(PaneGeometry.neighbor(of: layout.left, direction: .left, frames: layout.frames) == nil)
    }

    @Test("üç panelli yerleşimde en çok örtüşen aday seçilir")
    func picksLargestOverlap() {
        let layout = MixedLayout()
        // Sol panelin sağındaki iki aday: alt 120pt, üst 80pt örtüşür → alt kazanır.
        #expect(PaneGeometry.neighbor(of: layout.left, direction: .right, frames: layout.frames) == layout.rightBottom)
        #expect(PaneGeometry.neighbor(of: layout.rightTop, direction: .left, frames: layout.frames) == layout.left)
        #expect(PaneGeometry.neighbor(of: layout.rightBottom, direction: .left, frames: layout.frames) == layout.left)
    }

    @Test("AppKit koordinatlarında up = daha büyük y")
    func appKitVerticalOrientation() {
        let layout = MixedLayout()
        #expect(PaneGeometry.neighbor(of: layout.rightBottom, direction: .up, frames: layout.frames) == layout.rightTop)
        #expect(PaneGeometry.neighbor(of: layout.rightTop, direction: .down, frames: layout.frames) == layout.rightBottom)
        #expect(PaneGeometry.neighbor(of: layout.rightTop, direction: .up, frames: layout.frames) == nil)
        #expect(PaneGeometry.neighbor(of: layout.rightBottom, direction: .down, frames: layout.frames) == nil)
    }

    @Test("dik eksende örtüşmeyen aday komşu sayılmaz")
    func requiresPerpendicularOverlap() {
        let a = UUID(), b = UUID()
        let frames: [UUID: CGRect] = [
            a: CGRect(x: 0, y: 0, width: 100, height: 100),
            b: CGRect(x: 100, y: 150, width: 100, height: 100)
        ]
        #expect(PaneGeometry.neighbor(of: a, direction: .right, frames: frames) == nil)
    }

    @Test("örtüşme eşitse en yakın aday seçilir")
    func tieBreaksOnDistance() {
        let current = UUID(), near = UUID(), far = UUID()
        let frames: [UUID: CGRect] = [
            current: CGRect(x: 0, y: 0, width: 100, height: 100),
            near: CGRect(x: 100, y: 0, width: 50, height: 100),
            far: CGRect(x: 150, y: 0, width: 50, height: 100)
        ]
        #expect(PaneGeometry.neighbor(of: current, direction: .right, frames: frames) == near)
    }

    @Test("bilinmeyen panel veya boş sözlük için nil döner")
    func unknownPaneReturnsNil() {
        let layout = SideBySide()
        #expect(PaneGeometry.neighbor(of: UUID(), direction: .right, frames: layout.frames) == nil)
        #expect(PaneGeometry.neighbor(of: layout.left, direction: .right, frames: [:]) == nil)
    }
}
```

- [ ] **Step 2: Testi çalıştır, FAIL bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/PaneGeometryTests 2>&1 | tail -20
```

Beklenen: `error: cannot find 'PaneGeometry' in scope`, `** TEST BUILD FAILED **`.

- [ ] **Step 3: `PaneGeometry.swift`'i uygula**

`/Users/ahmetbarut/Apps/Termora/Termora/Models/PaneGeometry.swift`:

```swift
//
//  PaneGeometry.swift
//  Termora
//

import CoreGraphics
import Foundation

enum FocusDirection {
    case left
    case right
    case up
    case down
}

/// Directional pane navigation over on-screen frames.
/// Frames use AppKit coordinates: origin bottom-left, +y up.
enum PaneGeometry {

    /// Layout rounding tolerance in points.
    private static let tolerance: CGFloat = 1

    static func neighbor(of paneID: UUID, direction: FocusDirection, frames: [UUID: CGRect]) -> UUID? {
        guard let source = frames[paneID] else { return nil }

        var best: (id: UUID, overlap: CGFloat, distance: CGFloat, centerDelta: CGFloat)?

        for (candidateID, frame) in frames where candidateID != paneID {
            let overlap: CGFloat
            let distance: CGFloat
            let centerDelta: CGFloat

            switch direction {
            case .right:
                guard frame.minX >= source.maxX - tolerance else { continue }
                overlap = verticalOverlap(source, frame)
                distance = frame.minX - source.maxX
                centerDelta = abs(frame.midY - source.midY)
            case .left:
                guard frame.maxX <= source.minX + tolerance else { continue }
                overlap = verticalOverlap(source, frame)
                distance = source.minX - frame.maxX
                centerDelta = abs(frame.midY - source.midY)
            case .up:
                guard frame.minY >= source.maxY - tolerance else { continue }
                overlap = horizontalOverlap(source, frame)
                distance = frame.minY - source.maxY
                centerDelta = abs(frame.midX - source.midX)
            case .down:
                guard frame.maxY <= source.minY + tolerance else { continue }
                overlap = horizontalOverlap(source, frame)
                distance = source.minY - frame.maxY
                centerDelta = abs(frame.midX - source.midX)
            }

            guard overlap > 0 else { continue }

            guard let incumbent = best else {
                best = (candidateID, overlap, distance, centerDelta)
                continue
            }

            if isBetter(overlap: overlap, distance: distance, centerDelta: centerDelta,
                        than: incumbent) {
                best = (candidateID, overlap, distance, centerDelta)
            }
        }

        return best?.id
    }

    private static func isBetter(overlap: CGFloat,
                                 distance: CGFloat,
                                 centerDelta: CGFloat,
                                 than incumbent: (id: UUID, overlap: CGFloat, distance: CGFloat, centerDelta: CGFloat)) -> Bool {
        let epsilon: CGFloat = 0.001
        if overlap > incumbent.overlap + epsilon { return true }
        if overlap < incumbent.overlap - epsilon { return false }
        if distance < incumbent.distance - epsilon { return true }
        if distance > incumbent.distance + epsilon { return false }
        return centerDelta < incumbent.centerDelta - epsilon
    }

    private static func verticalOverlap(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        max(0, min(lhs.maxY, rhs.maxY) - max(lhs.minY, rhs.minY))
    }

    private static func horizontalOverlap(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        max(0, min(lhs.maxX, rhs.maxX) - max(lhs.minX, rhs.minX))
    }
}
```

- [ ] **Step 4: Testi çalıştır, PASS bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/PaneGeometryTests 2>&1 | tail -20
```

Beklenen: `Test run with 8 tests passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git -C /Users/ahmetbarut/Apps/Termora add Termora/Models/PaneGeometry.swift TermoraTests/PaneGeometryTests.swift
git -C /Users/ahmetbarut/Apps/Termora commit -m "feat: add directional pane neighbor lookup"
```

---

---

### Task 16: WorkspaceViewModel panel operasyonları (M3)

**Files:**
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/ViewModels/WorkspaceViewModel.swift`
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/WorkspacePaneOperationsTests.swift`

**Interfaces:**

*Consumes:*
- Task 14: `PaneNode.splitting(paneID:axis:newPaneID:newSessionID:)`, `.removing(paneID:)`, `.updatingRatio(splitID:ratio:)`, `.leaves`, `.sessionID(ofPane:)`, `.siblingLeafPaneID(of:)`, `SplitAxis`.
- Task 15: `PaneGeometry.neighbor(of:direction:frames:)`, `FocusDirection`.
- Task 11: `@Observable final class TerminalTab` (`id`, `root: PaneNode`, `activePaneID: UUID`), `@MainActor @Observable final class WorkspaceViewModel` — mevcut üyeleri: `private let sessionManager: any SessionManaging`, `private(set) var tabs: [TerminalTab]`, `var activeTabID: UUID?`, `var activeTab: TerminalTab?`, `var pendingClose: PendingClose?`, `var paneFrames: [UUID: CGRect]`, `func newTab(profile:)`, `func requestCloseTab(id:)`, `func confirmPendingClose()`, `func cancelPendingClose()`, ve iç yardımcı `private func closeTab(id: UUID)`. Dikkat: `func closeAllTabs()` **internal**'dır (`private` DEĞİL) — Task 22'deki `WindowCloseCoordinator` onu dışarıdan çağırır.
- Task 11 test desteği: `/Users/ahmetbarut/Apps/Termora/TermoraTests/MockSessionManager.swift` (tek dosya, `Support/` alt klasörü YOK)
  ```swift
  @MainActor final class MockSessionManager: SessionManaging {
      var busySessionIDs: Set<UUID> = []                              // hasRunningProcess bunu okur
      var defaultShellPath: String = "/bin/zsh"
      private(set) var sessions: [UUID: TerminalSession] = [:]
      private(set) var createdSessions: [TerminalSession] = []        // createSession sırayla ekler
      private(set) var terminatedSessionIDs: [UUID] = []
      private(set) var createdProfiles: [TerminalProfile?] = []
      private(set) var createdWorkingDirectories: [String?] = []
      private(set) var restartedSessionIDs: [UUID] = []
      func createSession(profile: TerminalProfile?, workingDirectory: String?) -> TerminalSession
      // → TerminalSession(shellPath: profile?.shellPath ?? defaultShellPath,
      //                   profileID: profile?.id, workingDirectory: workingDirectory)
      func session(id: UUID) -> TerminalSession?
      func terminateSession(id: UUID)
      func restartSession(id: UUID, forceDefaultShell: Bool)
      func hasRunningProcess(sessionID: UUID) -> Bool
  }
  ```
- Task 8: `TerminalSession` (`id`, `workingDirectory`), `@MainActor protocol SessionManaging` — `createSession(profile:workingDirectory:)`, `session(id:)`, `terminateSession(id:)`, `restartSession(id:forceDefaultShell:)`, `hasRunningProcess(sessionID:)`.
- Task 6/7: `SettingsStore(defaults:)`, `ProfileStore(defaults:)`.

*Produces:* `WorkspaceViewModel` üzerinde
```swift
func splitActivePane(axis: SplitAxis)
func requestCloseActivePane()
func activatePane(paneID: UUID)          // Task 17 tıklamayla odak için kullanır
func focusPane(_ direction: FocusDirection)
func updateSplitRatio(tabID: UUID, splitID: UUID, ratio: Double)
func restartPaneSession(paneID: UUID, forceDefaultShell: Bool = false)   // Task 17 çıkış bandı kullanır
```
ve `confirmPendingClose()` artık `PendingClose.Target.pane(paneID:)` hedefini de işler.

- [ ] **Step 1: Panel testleri dosyasını yaz (bölme + cwd devri)**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/WorkspacePaneOperationsTests.swift`:

```swift
//
//  WorkspacePaneOperationsTests.swift
//  TermoraTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Termora

@MainActor
@Suite("WorkspacePaneOperations")
struct WorkspacePaneOperationsTests {

    // MARK: - Fixture

    private struct Fixture {
        let viewModel: WorkspaceViewModel
        let sessions: MockSessionManager
    }

    private func makeFixture() -> Fixture {
        let sessions = MockSessionManager()
        let settingsDefaults = UserDefaults(suiteName: "termora.test.settings.\(UUID().uuidString)")!
        let profileDefaults = UserDefaults(suiteName: "termora.test.profiles.\(UUID().uuidString)")!
        let viewModel = WorkspaceViewModel(sessionManager: sessions,
                                           settings: SettingsStore(defaults: settingsDefaults),
                                           profiles: ProfileStore(defaults: profileDefaults))
        if viewModel.tabs.isEmpty {
            viewModel.newTab()
        }
        return Fixture(viewModel: viewModel, sessions: sessions)
    }

    private func splitID(of node: PaneNode) -> UUID? {
        if case let .split(id, _, _, _, _) = node { return id }
        return nil
    }

    // MARK: - splitActivePane

    @Test("splitActivePane yeni oturum yaratır ve odağı yeni panele taşır")
    func splitCreatesSessionAndMovesFocus() {
        let fixture = makeFixture()
        guard let tab = fixture.viewModel.activeTab else {
            Issue.record("aktif sekme yok")
            return
        }
        let originalPaneID = tab.activePaneID
        let sessionCountBefore = fixture.sessions.createdSessions.count

        fixture.viewModel.splitActivePane(axis: .vertical)

        #expect(fixture.sessions.createdSessions.count == sessionCountBefore + 1)
        let leaves = tab.root.leaves
        #expect(leaves.count == 2)
        #expect(leaves.first?.paneID == originalPaneID)
        #expect(tab.activePaneID != originalPaneID)
        #expect(tab.activePaneID == leaves.last?.paneID)
        #expect(tab.root.sessionID(ofPane: tab.activePaneID) == fixture.sessions.createdSessions.last?.id)

        if case let .split(_, axis, ratio, _, _) = tab.root {
            #expect(axis == .vertical)
            #expect(ratio == 0.5)
        } else {
            Issue.record("kök split olmalıydı")
        }
    }

    @Test("splitActivePane yeni panele aktif panelin çalışma dizinini devreder")
    func splitInheritsWorkingDirectory() {
        let fixture = makeFixture()
        fixture.sessions.createdSessions.first?.workingDirectory = "/tmp/termora-fixture"

        fixture.viewModel.splitActivePane(axis: .horizontal)

        #expect(fixture.sessions.createdSessions.last?.workingDirectory == "/tmp/termora-fixture")
    }

    @Test("art arda bölme derin ağaç üretir")
    func repeatedSplitsBuildTree() {
        let fixture = makeFixture()
        fixture.viewModel.splitActivePane(axis: .vertical)
        fixture.viewModel.splitActivePane(axis: .horizontal)

        #expect(fixture.viewModel.activeTab?.root.leaves.count == 3)
        #expect(fixture.sessions.createdSessions.count == 3)
    }
}
```

- [ ] **Step 2: Testi çalıştır, FAIL bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/WorkspacePaneOperationsTests 2>&1 | tail -20
```

Beklenen: `error: value of type 'WorkspaceViewModel' has no member 'splitActivePane'`, `** TEST BUILD FAILED **`.

- [ ] **Step 3: `splitActivePane`'i uygula**

`WorkspaceViewModel.swift` sınıf gövdesinin sonuna (son `}` öncesine) ekle:

```swift
    // MARK: - Pane operations

    /// Splits the active pane; the new pane becomes active and inherits the current
    /// pane's working directory.
    func splitActivePane(axis: SplitAxis) {
        guard let tab = activeTab else { return }
        let session = sessionManager.createSession(profile: nil,
                                                   workingDirectory: workingDirectoryOfActivePane(in: tab))
        let newPaneID = UUID()
        tab.root = tab.root.splitting(paneID: tab.activePaneID,
                                      axis: axis,
                                      newPaneID: newPaneID,
                                      newSessionID: session.id)
        tab.activePaneID = newPaneID
    }

    private func workingDirectoryOfActivePane(in tab: TerminalTab) -> String? {
        guard let sessionID = tab.root.sessionID(ofPane: tab.activePaneID) else { return nil }
        return sessionManager.session(id: sessionID)?.workingDirectory
    }
```

- [ ] **Step 4: Testi çalıştır, PASS bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/WorkspacePaneOperationsTests 2>&1 | tail -20
```

Beklenen: `Test run with 3 tests passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Panel kapatma testlerini ekle**

`WorkspacePaneOperationsTests.swift` içine, son `}` öncesine ekle:

```swift
    // MARK: - requestCloseActivePane

    @Test("boşta panel kapatılınca kardeş yükselir ve odak kardeşe geçer")
    func closeIdlePaneCollapsesTree() {
        let fixture = makeFixture()
        guard let tab = fixture.viewModel.activeTab else {
            Issue.record("aktif sekme yok")
            return
        }
        let firstPaneID = tab.activePaneID
        fixture.viewModel.splitActivePane(axis: .vertical)
        let secondPaneID = tab.activePaneID
        guard let secondSessionID = tab.root.sessionID(ofPane: secondPaneID) else {
            Issue.record("yeni panelin oturumu bulunamadı")
            return
        }

        fixture.viewModel.requestCloseActivePane()

        #expect(fixture.viewModel.pendingClose == nil)
        #expect(tab.root == .leaf(paneID: firstPaneID,
                                  sessionID: tab.root.sessionID(ofPane: firstPaneID)!))
        #expect(tab.activePaneID == firstPaneID)
        #expect(fixture.sessions.terminatedSessionIDs == [secondSessionID])
        #expect(fixture.viewModel.paneFrames[secondPaneID] == nil)
        #expect(fixture.viewModel.tabs.count == 1)
    }

    @Test("çalışan işlemli panel kapatma onay ister ve ağacı değiştirmez")
    func closeBusyPaneRequestsConfirmation() {
        let fixture = makeFixture()
        guard let tab = fixture.viewModel.activeTab else {
            Issue.record("aktif sekme yok")
            return
        }
        fixture.viewModel.splitActivePane(axis: .vertical)
        let busyPaneID = tab.activePaneID
        let busySessionID = tab.root.sessionID(ofPane: busyPaneID)!
        fixture.sessions.busySessionIDs.insert(busySessionID)
        let treeBefore = tab.root

        fixture.viewModel.requestCloseActivePane()

        #expect(fixture.viewModel.pendingClose?.target == .pane(paneID: busyPaneID))
        #expect(tab.root == treeBefore)
        #expect(fixture.sessions.terminatedSessionIDs.isEmpty)
    }

    @Test("onay verilince panel kapanır")
    func confirmClosesPane() {
        let fixture = makeFixture()
        guard let tab = fixture.viewModel.activeTab else {
            Issue.record("aktif sekme yok")
            return
        }
        let firstPaneID = tab.activePaneID
        fixture.viewModel.splitActivePane(axis: .vertical)
        let busyPaneID = tab.activePaneID
        let busySessionID = tab.root.sessionID(ofPane: busyPaneID)!
        fixture.sessions.busySessionIDs.insert(busySessionID)
        fixture.viewModel.requestCloseActivePane()

        fixture.viewModel.confirmPendingClose()

        #expect(fixture.viewModel.pendingClose == nil)
        #expect(tab.root.leaves.count == 1)
        #expect(tab.activePaneID == firstPaneID)
        #expect(fixture.sessions.terminatedSessionIDs == [busySessionID])
    }

    @Test("iptal edilince panel açık kalır")
    func cancelKeepsPane() {
        let fixture = makeFixture()
        guard let tab = fixture.viewModel.activeTab else {
            Issue.record("aktif sekme yok")
            return
        }
        fixture.viewModel.splitActivePane(axis: .vertical)
        let busySessionID = tab.root.sessionID(ofPane: tab.activePaneID)!
        fixture.sessions.busySessionIDs.insert(busySessionID)
        fixture.viewModel.requestCloseActivePane()

        fixture.viewModel.cancelPendingClose()

        #expect(fixture.viewModel.pendingClose == nil)
        #expect(tab.root.leaves.count == 2)
        #expect(fixture.sessions.terminatedSessionIDs.isEmpty)
    }

    @Test("tek panelli sekmede panel kapatma sekme kapatmaya delege eder")
    func closingOnlyPaneClosesTab() {
        let fixture = makeFixture()
        guard let tab = fixture.viewModel.activeTab else {
            Issue.record("aktif sekme yok")
            return
        }
        let onlySessionID = tab.root.sessionID(ofPane: tab.activePaneID)!
        fixture.sessions.busySessionIDs.insert(onlySessionID)

        fixture.viewModel.requestCloseActivePane()

        #expect(fixture.viewModel.pendingClose?.target == .tab(tab.id))
        #expect(fixture.viewModel.tabs.count == 1)
    }
```

- [ ] **Step 6: Testi çalıştır, FAIL bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/WorkspacePaneOperationsTests 2>&1 | tail -20
```

Beklenen: `error: value of type 'WorkspaceViewModel' has no member 'requestCloseActivePane'`, `** TEST BUILD FAILED **`.

- [ ] **Step 7: `requestCloseActivePane` + `closePane` uygula**

`WorkspaceViewModel.swift` içinde `workingDirectoryOfActivePane(in:)`'in altına ekle:

```swift
    /// Closes the active pane. A single-pane tab is closed as a tab instead.
    /// Panes with a running foreground job ask for confirmation first.
    func requestCloseActivePane() {
        guard let tab = activeTab else { return }
        guard tab.root.leaves.count > 1 else {
            requestCloseTab(id: tab.id)
            return
        }
        let paneID = tab.activePaneID
        guard let sessionID = tab.root.sessionID(ofPane: paneID) else { return }

        if sessionManager.hasRunningProcess(sessionID: sessionID) {
            pendingClose = PendingClose(id: UUID(), target: .pane(paneID: paneID))
            return
        }
        closePane(paneID: paneID, in: tab)
    }

    /// Removes a pane from its tab: the sibling subtree takes over the space and,
    /// when the closed pane was active, focus moves to the sibling.
    private func closePane(paneID: UUID, in tab: TerminalTab) {
        guard let sessionID = tab.root.sessionID(ofPane: paneID),
              let sibling = tab.root.siblingLeafPaneID(of: paneID),
              let newRoot = tab.root.removing(paneID: paneID) else { return }

        sessionManager.terminateSession(id: sessionID)
        tab.root = newRoot
        if tab.activePaneID == paneID {
            tab.activePaneID = sibling
        }
        paneFrames[paneID] = nil
    }
```

- [ ] **Step 8: `confirmPendingClose()`'a `.pane` dalını ekle**

Task 11'de yazılan `confirmPendingClose()` gövdesindeki `switch pending.target` ifadesine, `.tab` ve `.window` dalları aynen kalacak şekilde `.pane` dalını ekle. Sonuç gövde:

```swift
    func confirmPendingClose() {
        guard let pending = pendingClose else { return }
        pendingClose = nil
        switch pending.target {
        case let .tab(tabID):
            closeTab(id: tabID)          // Task 11
        case let .pane(paneID):
            guard let tab = tabs.first(where: { $0.root.sessionID(ofPane: paneID) != nil }) else { return }
            closePane(paneID: paneID, in: tab)
        case .window:
            closeAllTabs()               // Task 11
        }
    }
```

Aynı düzenlemede Task 11 Step 17'de yazılan tek argümanlı `private func closePane(paneID: UUID)` metodu (ve üstündeki `/// M2 değişmezi: …` yorumu) `WorkspaceViewModel.swift`'ten **SİLİNİR**; artık yalnız `closePane(paneID:in:)` kullanılır. (Aşırı yükleme olduğu için derleme hatası vermez, silinmezse ölü kod olarak kalır.)

- [ ] **Step 9: Testi çalıştır, PASS bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/WorkspacePaneOperationsTests 2>&1 | tail -20
```

Beklenen: `Test run with 8 tests passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 10: Odak ve oran testlerini ekle**

`WorkspacePaneOperationsTests.swift` içine, son `}` öncesine ekle:

```swift
    // MARK: - focusPane / activatePane / updateSplitRatio

    @Test("focusPane paneFrames geometrisine göre komşuya geçer")
    func focusPaneUsesGeometry() {
        let fixture = makeFixture()
        guard let tab = fixture.viewModel.activeTab else {
            Issue.record("aktif sekme yok")
            return
        }
        let leftPaneID = tab.activePaneID
        fixture.viewModel.splitActivePane(axis: .vertical)
        let rightPaneID = tab.activePaneID

        fixture.viewModel.paneFrames = [
            leftPaneID: CGRect(x: 0, y: 0, width: 100, height: 200),
            rightPaneID: CGRect(x: 100, y: 0, width: 100, height: 200)
        ]

        fixture.viewModel.focusPane(.left)
        #expect(tab.activePaneID == leftPaneID)

        fixture.viewModel.focusPane(.up)
        #expect(tab.activePaneID == leftPaneID)   // o yönde komşu yok → değişmez

        fixture.viewModel.focusPane(.right)
        #expect(tab.activePaneID == rightPaneID)
    }

    @Test("focusPane çerçeve bilgisi yokken odağı değiştirmez")
    func focusPaneWithoutFramesIsNoop() {
        let fixture = makeFixture()
        guard let tab = fixture.viewModel.activeTab else {
            Issue.record("aktif sekme yok")
            return
        }
        fixture.viewModel.splitActivePane(axis: .vertical)
        let activeBefore = tab.activePaneID

        fixture.viewModel.focusPane(.left)

        #expect(tab.activePaneID == activeBefore)
    }

    @Test("activatePane yalnız mevcut paneller için odağı değiştirir")
    func activatePaneValidatesID() {
        let fixture = makeFixture()
        guard let tab = fixture.viewModel.activeTab else {
            Issue.record("aktif sekme yok")
            return
        }
        let firstPaneID = tab.activePaneID
        fixture.viewModel.splitActivePane(axis: .vertical)

        fixture.viewModel.activatePane(paneID: firstPaneID)
        #expect(tab.activePaneID == firstPaneID)

        fixture.viewModel.activatePane(paneID: UUID())
        #expect(tab.activePaneID == firstPaneID)
    }

    @Test("updateSplitRatio ağacı günceller ve sınırları uygular")
    func updateSplitRatioAppliesClamp() {
        let fixture = makeFixture()
        guard let tab = fixture.viewModel.activeTab else {
            Issue.record("aktif sekme yok")
            return
        }
        fixture.viewModel.splitActivePane(axis: .vertical)
        guard let id = splitID(of: tab.root) else {
            Issue.record("split id okunamadı")
            return
        }

        fixture.viewModel.updateSplitRatio(tabID: tab.id, splitID: id, ratio: 0.25)
        if case let .split(_, _, ratio, _, _) = tab.root {
            #expect(ratio == 0.25)
        } else {
            Issue.record("split bekleniyordu")
        }

        fixture.viewModel.updateSplitRatio(tabID: tab.id, splitID: id, ratio: 0.95)
        if case let .split(_, _, ratio, _, _) = tab.root {
            #expect(ratio == 0.85)
        } else {
            Issue.record("split bekleniyordu")
        }

        fixture.viewModel.updateSplitRatio(tabID: UUID(), splitID: id, ratio: 0.2)
        if case let .split(_, _, ratio, _, _) = tab.root {
            #expect(ratio == 0.85)   // bilinmeyen sekme → değişiklik yok
        } else {
            Issue.record("split bekleniyordu")
        }
    }
```

- [ ] **Step 11: Testi çalıştır, FAIL bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/WorkspacePaneOperationsTests 2>&1 | tail -20
```

Beklenen: `error: value of type 'WorkspaceViewModel' has no member 'focusPane'`, `** TEST BUILD FAILED **`.

- [ ] **Step 12: `focusPane`, `activatePane`, `updateSplitRatio` uygula**

`WorkspaceViewModel.swift` içinde `closePane(paneID:in:)`'in altına ekle:

```swift
    /// Moves focus to the neighbouring pane in the given direction, if any.
    func focusPane(_ direction: FocusDirection) {
        guard let tab = activeTab else { return }
        let visiblePaneIDs = Set(tab.root.leaves.map { $0.paneID })
        let frames = paneFrames.filter { visiblePaneIDs.contains($0.key) }
        guard let target = PaneGeometry.neighbor(of: tab.activePaneID,
                                                 direction: direction,
                                                 frames: frames) else { return }
        tab.activePaneID = target
    }

    /// Focuses a pane directly (click on an inactive pane).
    func activatePane(paneID: UUID) {
        guard let tab = activeTab, tab.root.sessionID(ofPane: paneID) != nil else { return }
        tab.activePaneID = paneID
    }

    /// Applies a divider drag to the layout tree (ratio is clamped by `PaneNode`).
    func updateSplitRatio(tabID: UUID, splitID: UUID, ratio: Double) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        tab.root = tab.root.updatingRatio(splitID: splitID, ratio: ratio)
    }
```

- [ ] **Step 13: Testi çalıştır, PASS bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/WorkspacePaneOperationsTests 2>&1 | tail -20
```

Beklenen: `Test run with 12 tests passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 14: `restartPaneSession` testlerini ekle**

Spec §8: shell çıkınca panel açık kalır ve kullanıcı aynı panelde yeni oturum başlatabilir; shell hiç başlatılamadıysa "varsayılan shell ile dene" kurtarma yolu vardır. Görünüm tarafı Task 17'deki çıkış bandıdır, bu adım onun çağırdığı view model metodunu yazar.

`WorkspacePaneOperationsTests.swift` içine, son `}` öncesine ekle:

```swift
    // MARK: - restartPaneSession

    @Test("restartPaneSession panelin oturumunu SessionManager'a yeniden başlatır")
    func restartPaneSessionForwardsToSessionManager() {
        let fixture = makeFixture()
        guard let tab = fixture.viewModel.activeTab else {
            Issue.record("aktif sekme yok")
            return
        }
        let paneID = tab.activePaneID
        guard let sessionID = tab.root.sessionID(ofPane: paneID) else {
            Issue.record("panelin oturumu bulunamadı")
            return
        }

        fixture.viewModel.restartPaneSession(paneID: paneID)

        #expect(fixture.sessions.restartedSessionIDs == [sessionID])
        // Ağaç ve odak değişmez: aynı panelde yeni oturum başlar.
        #expect(tab.root.sessionID(ofPane: paneID) == sessionID)
        #expect(tab.activePaneID == paneID)
        #expect(fixture.sessions.terminatedSessionIDs.isEmpty)
    }

    @Test("varsayılan shell ile yeniden başlatma da aynı oturuma yönlenir")
    func restartWithDefaultShellTargetsTheSameSession() {
        let fixture = makeFixture()
        guard let tab = fixture.viewModel.activeTab else {
            Issue.record("aktif sekme yok")
            return
        }
        fixture.viewModel.splitActivePane(axis: .vertical)
        let paneID = tab.activePaneID
        guard let sessionID = tab.root.sessionID(ofPane: paneID) else {
            Issue.record("panelin oturumu bulunamadı")
            return
        }

        fixture.viewModel.restartPaneSession(paneID: paneID, forceDefaultShell: true)

        #expect(fixture.sessions.restartedSessionIDs == [sessionID])
    }

    @Test("bilinmeyen panel için restartPaneSession sessizce hiçbir şey yapmaz")
    func restartUnknownPaneIsNoop() {
        let fixture = makeFixture()

        fixture.viewModel.restartPaneSession(paneID: UUID())

        #expect(fixture.sessions.restartedSessionIDs.isEmpty)
    }
```

- [ ] **Step 15: Testi çalıştır, FAIL bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/WorkspacePaneOperationsTests 2>&1 | tail -20
```

Beklenen: `error: value of type 'WorkspaceViewModel' has no member 'restartPaneSession'`, `** TEST BUILD FAILED **`.

- [ ] **Step 16: `restartPaneSession`'ı uygula**

`WorkspaceViewModel.swift` içinde `updateSplitRatio(tabID:splitID:ratio:)`'nun altına ekle:

```swift
    /// Starts a fresh shell in the pane that is already on screen (spec §8: the pane
    /// stays open after the process exits). `forceDefaultShell` ignores the configured
    /// shell path — the recovery action for an unlaunchable shell.
    func restartPaneSession(paneID: UUID, forceDefaultShell: Bool = false) {
        guard let tab = activeTab,
              let sessionID = tab.root.sessionID(ofPane: paneID) else { return }
        sessionManager.restartSession(id: sessionID, forceDefaultShell: forceDefaultShell)
        tab.activePaneID = paneID
    }
```

Oturum kimliği ve panel ağacı KORUNUR — `SessionManager.restartSession(id:forceDefaultShell:)` (Task 8) aynı `sessionID` için yeni bir terminal view + süreç kurar, bu yüzden `PaneNode` güncellenmez.

- [ ] **Step 17: Testi çalıştır, PASS bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/WorkspacePaneOperationsTests 2>&1 | tail -20
```

Beklenen: `Test run with 15 tests passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 18: Sekme testlerinin bozulmadığını doğrula**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests 2>&1 | tail -20
```

Beklenen: `** TEST SUCCEEDED **` (Task 11'in sekme suite'i dahil tüm testler geçer).

- [ ] **Step 19: Commit**

```bash
git -C /Users/ahmetbarut/Apps/Termora add Termora/ViewModels/WorkspaceViewModel.swift TermoraTests/WorkspacePaneOperationsTests.swift
git -C /Users/ahmetbarut/Apps/Termora commit -m "feat: add pane split, close, focus, ratio and restart operations to workspace"
```

---

---

### Task 17: PaneTreeView + bölme komutları (M3)

**Files:**
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Models/SplitLayoutMath.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Models/PaneFrameConverter.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Views/Terminal/PaneTreeView.swift`
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/Views/MainWindowView.swift`
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/App/AppCommands.swift`
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/SplitLayoutMathTests.swift`
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/PaneFrameConverterTests.swift`

**Interfaces:**

*Consumes:*
- Task 14: `PaneNode` (`splitting`/`removing`/`updatingRatio`/`ratioRange`), `SplitAxis`.
- Task 16: `WorkspaceViewModel.splitActivePane(axis:)`, `.requestCloseActivePane()`, `.activatePane(paneID:)`, `.focusPane(_:)`, `.updateSplitRatio(tabID:splitID:ratio:)`, `.restartPaneSession(paneID:forceDefaultShell:)`, `.paneFrames`, `.activeTab`.
- Task 15: `FocusDirection`.
- Task 10: `struct TerminalHostView: NSViewRepresentable { let sessionID: UUID; let sessionManager: SessionManager; let isActive: Bool }` (`/Users/ahmetbarut/Apps/Termora/Termora/Views/Terminal/TerminalHostView.swift`).
- Task 12: `struct MainWindowView: View` — `private let services: AppServices` ve `@State private var workspace: WorkspaceViewModel` özelliklerine sahip; terminal içeriğini çizen `terminalContent` hesaplanan özelliği bu görevde `PaneTreeView` ile değiştirilir. (Oturum yöneticisine `services.sessionManager` ile erişilir; `viewModel` / çıplak `sessionManager` diye üye YOKTUR.)
- Task 13: `AppCommands` (`@FocusedValue(\.workspace) private var workspace: WorkspaceViewModel?`).
- Task 8 (çıkış bandı için): `@Observable final class TerminalSession` — `var processState: ProcessState` (`.running` / `.exited(ExitStatus)`), `var launchFailure: String?` (shell çalıştırılamadıysa denenen yol), `SessionManager.session(id:) -> TerminalSession?`.
- Task 2: `ExitStatus.localizedSummary` (ör. `"çıkış kodu 1"`, `"SIGTERM ile sonlandı"`).

*Produces:*
```swift
enum SplitLayoutMath {
    static let dividerThickness: CGFloat            // 6
    static func usableLength(totalLength: CGFloat) -> CGFloat
    static func firstLength(totalLength: CGFloat, ratio: Double) -> CGFloat
    static func secondLength(totalLength: CGFloat, ratio: Double) -> CGFloat
    static func ratio(atPosition position: CGFloat, totalLength: CGFloat) -> Double
}
enum PaneFrameConverter {
    static func appKitFrame(_ frame: CGRect, containerHeight: CGFloat) -> CGRect
    static func appKitFrames(_ frames: [UUID: CGRect], containerHeight: CGFloat) -> [UUID: CGRect]
}
struct PaneFramesPreferenceKey: PreferenceKey { static var defaultValue: [UUID: CGRect] { get } }
struct PaneTreeView: View {
    static let coordinateSpaceName: String          // "termora.pane-tree"
    init(node: PaneNode, tabID: UUID, activePaneID: UUID,
         viewModel: WorkspaceViewModel, sessionManager: SessionManager)
}
```
Kısayollar: ⌘D dikey böl, ⌘⇧D yatay böl, ⌘⇧W panel kapat, ⌘⌥←/→/↑/↓ panel odağı.

Ayrıca `PaneTreeView.swift` içindeki `private struct PaneLeafView`, oturumun `processState`'i `.exited` olduğunda terminalin üstünde bir **süreç sonlandı bandı** çizer (spec §8): shell hiç başlatılamadıysa `"'<yol>' çalıştırılamadı"` + **Yeniden dene** / **Varsayılan shell ile dene** düğmeleri, normal çıkışta `"İşlem sonlandı (<özet>)"` + **Yeniden başlat** düğmesi ve Enter kısayolu. Hepsi `WorkspaceViewModel.restartPaneSession(paneID:forceDefaultShell:)` çağırır.

- [ ] **Step 1: `SplitLayoutMath` testlerini yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/SplitLayoutMathTests.swift`:

```swift
//
//  SplitLayoutMathTests.swift
//  TermoraTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Termora

@Suite("SplitLayoutMath")
struct SplitLayoutMathTests {

    @Test("ayraç kalınlığı 6pt ve iki panel + ayraç toplam uzunluğu doldurur")
    func lengthsFillTotal() {
        #expect(SplitLayoutMath.dividerThickness == 6)

        let total: CGFloat = 200
        let first = SplitLayoutMath.firstLength(totalLength: total, ratio: 0.5)
        let second = SplitLayoutMath.secondLength(totalLength: total, ratio: 0.5)
        #expect(first == 97)
        #expect(second == 97)
        #expect(first + second + SplitLayoutMath.dividerThickness == total)
    }

    @Test("oran uzunluklara doğrusal yansır")
    func lengthsFollowRatio() {
        let total: CGFloat = 406            // usable = 400
        #expect(SplitLayoutMath.usableLength(totalLength: total) == 400)
        #expect(SplitLayoutMath.firstLength(totalLength: total, ratio: 0.25) == 100)
        #expect(SplitLayoutMath.secondLength(totalLength: total, ratio: 0.25) == 300)
    }

    @Test("çok küçük veya sıfır alanda uzunluklar negatife düşmez")
    func degenerateSizes() {
        #expect(SplitLayoutMath.usableLength(totalLength: 0) == 0)
        #expect(SplitLayoutMath.usableLength(totalLength: 4) == 0)
        #expect(SplitLayoutMath.firstLength(totalLength: 0, ratio: 0.5) == 0)
        #expect(SplitLayoutMath.secondLength(totalLength: 0, ratio: 0.5) == 0)
    }

    @Test("sürükleme konumu orana çevrilir ve 0.15...0.85 aralığına kırpılır")
    func ratioFromPosition() {
        #expect(SplitLayoutMath.ratio(atPosition: 50, totalLength: 100) == 0.5)
        #expect(SplitLayoutMath.ratio(atPosition: 20, totalLength: 100) == 0.2)
        #expect(SplitLayoutMath.ratio(atPosition: 0, totalLength: 100) == 0.15)
        #expect(SplitLayoutMath.ratio(atPosition: -40, totalLength: 100) == 0.15)
        #expect(SplitLayoutMath.ratio(atPosition: 100, totalLength: 100) == 0.85)
        #expect(SplitLayoutMath.ratio(atPosition: 400, totalLength: 100) == 0.85)
    }

    @Test("sıfır uzunlukta oran 0.5'e düşer")
    func ratioWithZeroLength() {
        #expect(SplitLayoutMath.ratio(atPosition: 10, totalLength: 0) == 0.5)
    }
}
```

- [ ] **Step 2: `PaneFrameConverter` testlerini yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/PaneFrameConverterTests.swift`:

```swift
//
//  PaneFrameConverterTests.swift
//  TermoraTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Termora

@Suite("PaneFrameConverter")
struct PaneFrameConverterTests {

    @Test("SwiftUI üst panel AppKit'te yüksek y'ye taşınır")
    func flipsTopPane() {
        let top = CGRect(x: 0, y: 0, width: 100, height: 80)       // SwiftUI: en üstte
        let converted = PaneFrameConverter.appKitFrame(top, containerHeight: 200)
        #expect(converted == CGRect(x: 0, y: 120, width: 100, height: 80))
    }

    @Test("SwiftUI alt panel AppKit'te y = 0 olur")
    func flipsBottomPane() {
        let bottom = CGRect(x: 0, y: 80, width: 100, height: 120)  // SwiftUI: altta
        let converted = PaneFrameConverter.appKitFrame(bottom, containerHeight: 200)
        #expect(converted == CGRect(x: 0, y: 0, width: 100, height: 120))
    }

    @Test("çevrim kendi tersidir")
    func conversionIsInvolutive() {
        let frame = CGRect(x: 10, y: 30, width: 50, height: 40)
        let once = PaneFrameConverter.appKitFrame(frame, containerHeight: 200)
        let twice = PaneFrameConverter.appKitFrame(once, containerHeight: 200)
        #expect(twice == frame)
    }

    @Test("sözlük çevriminde x ve boyut korunur, dikey sıralama ters döner")
    func convertsDictionary() {
        let topID = UUID(), bottomID = UUID()
        let frames: [UUID: CGRect] = [
            topID: CGRect(x: 0, y: 0, width: 100, height: 80),
            bottomID: CGRect(x: 0, y: 80, width: 100, height: 120)
        ]
        let converted = PaneFrameConverter.appKitFrames(frames, containerHeight: 200)

        #expect(converted.count == 2)
        #expect(converted[topID]?.minX == 0)
        #expect(converted[topID]?.size == CGSize(width: 100, height: 80))
        #expect((converted[topID]?.minY ?? 0) > (converted[bottomID]?.minY ?? 0))
        // PaneGeometry semantiği: üst panel yukarıda
        #expect(PaneGeometry.neighbor(of: bottomID, direction: .up, frames: converted) == topID)
    }
}
```

- [ ] **Step 3: İki testi de çalıştır, FAIL bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/SplitLayoutMathTests -only-testing:TermoraTests/PaneFrameConverterTests 2>&1 | tail -20
```

Beklenen: `error: cannot find 'SplitLayoutMath' in scope` ve `error: cannot find 'PaneFrameConverter' in scope`, `** TEST BUILD FAILED **`.

- [ ] **Step 4: `SplitLayoutMath` ve `PaneFrameConverter`'ı uygula**

`/Users/ahmetbarut/Apps/Termora/Termora/Models/SplitLayoutMath.swift`:

```swift
//
//  SplitLayoutMath.swift
//  Termora
//

import CoreGraphics
import Foundation

/// Pure layout math for split panes. Kept out of the view so it can be unit tested.
enum SplitLayoutMath {

    /// Divider hit area / drawn thickness in points.
    static let dividerThickness: CGFloat = 6

    /// Space left for the two panes once the divider is subtracted.
    static func usableLength(totalLength: CGFloat) -> CGFloat {
        max(0, totalLength - dividerThickness)
    }

    static func firstLength(totalLength: CGFloat, ratio: Double) -> CGFloat {
        usableLength(totalLength: totalLength) * CGFloat(ratio)
    }

    static func secondLength(totalLength: CGFloat, ratio: Double) -> CGFloat {
        let usable = usableLength(totalLength: totalLength)
        return usable - usable * CGFloat(ratio)
    }

    /// Converts a divider position (measured inside the usable length) into a clamped ratio.
    static func ratio(atPosition position: CGFloat, totalLength: CGFloat) -> Double {
        guard totalLength > 0 else { return 0.5 }
        let raw = Double(position / totalLength)
        return min(max(raw, PaneNode.ratioRange.lowerBound), PaneNode.ratioRange.upperBound)
    }
}
```

`/Users/ahmetbarut/Apps/Termora/Termora/Models/PaneFrameConverter.swift`:

```swift
//
//  PaneFrameConverter.swift
//  Termora
//

import CoreGraphics
import Foundation

/// Converts SwiftUI frames (origin top-left, +y down) into the AppKit layout
/// (origin bottom-left, +y up) that `PaneGeometry` expects.
enum PaneFrameConverter {

    static func appKitFrame(_ frame: CGRect, containerHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX,
               y: containerHeight - frame.maxY,
               width: frame.width,
               height: frame.height)
    }

    static func appKitFrames(_ frames: [UUID: CGRect], containerHeight: CGFloat) -> [UUID: CGRect] {
        frames.mapValues { appKitFrame($0, containerHeight: containerHeight) }
    }
}
```

- [ ] **Step 5: İki testi de çalıştır, PASS bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/SplitLayoutMathTests -only-testing:TermoraTests/PaneFrameConverterTests 2>&1 | tail -20
```

Beklenen: `Test run with 9 tests passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 6: Saf yerleşim matematiğini commit'le**

```bash
git -C /Users/ahmetbarut/Apps/Termora add Termora/Models/SplitLayoutMath.swift Termora/Models/PaneFrameConverter.swift TermoraTests/SplitLayoutMathTests.swift TermoraTests/PaneFrameConverterTests.swift
git -C /Users/ahmetbarut/Apps/Termora commit -m "feat: add split layout math and SwiftUI-to-AppKit frame conversion"
```

- [ ] **Step 7: `PaneTreeView`'i oluştur**

```bash
mkdir -p /Users/ahmetbarut/Apps/Termora/Termora/Views/Terminal
```

`/Users/ahmetbarut/Apps/Termora/Termora/Views/Terminal/PaneTreeView.swift`:

```swift
//
//  PaneTreeView.swift
//  Termora
//

import AppKit
import SwiftUI

/// Collects every leaf frame in the pane tree coordinate space.
struct PaneFramesPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] { [:] }

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Draws a `PaneNode` tree recursively. Recursion is broken with `AnyView`
/// inside `SplitContainerView`, otherwise the `Body` type would be infinite.
struct PaneTreeView: View {

    static let coordinateSpaceName = "termora.pane-tree"

    let node: PaneNode
    let tabID: UUID
    let activePaneID: UUID
    let viewModel: WorkspaceViewModel
    let sessionManager: SessionManager

    @ViewBuilder
    var body: some View {
        switch node {
        case let .leaf(paneID, sessionID):
            PaneLeafView(paneID: paneID,
                         sessionID: sessionID,
                         isActive: paneID == activePaneID,
                         viewModel: viewModel,
                         sessionManager: sessionManager)

        case let .split(id, axis, ratio, first, second):
            SplitContainerView(splitID: id,
                               axis: axis,
                               ratio: ratio,
                               first: first,
                               second: second,
                               tabID: tabID,
                               activePaneID: activePaneID,
                               viewModel: viewModel,
                               sessionManager: sessionManager)
        }
    }
}

// MARK: - Leaf

private struct PaneLeafView: View {
    let paneID: UUID
    let sessionID: UUID
    let isActive: Bool
    let viewModel: WorkspaceViewModel
    let sessionManager: SessionManager

    var body: some View {
        TerminalHostView(sessionID: sessionID,
                         sessionManager: sessionManager,
                         isActive: isActive)
            .overlay {
                // The dimming layer only exists while inactive, so an active pane
                // never intercepts clicks meant for the terminal (selection, links).
                if !isActive {
                    Color.black.opacity(0.15)
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.activatePane(paneID: paneID) }
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: PaneFramesPreferenceKey.self,
                        value: [paneID: proxy.frame(in: .named(PaneTreeView.coordinateSpaceName))]
                    )
                }
            )
    }
}

// MARK: - Split

private struct SplitContainerView: View {
    let splitID: UUID
    let axis: SplitAxis
    let ratio: Double
    let first: PaneNode
    let second: PaneNode
    let tabID: UUID
    let activePaneID: UUID
    let viewModel: WorkspaceViewModel
    let sessionManager: SessionManager

    /// First pane length captured when a divider drag begins, so the ratio does
    /// not drift while the divider moves under the cursor.
    @State private var dragStartLength: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let total = axis == .vertical ? proxy.size.width : proxy.size.height
            let firstLength = SplitLayoutMath.firstLength(totalLength: total, ratio: ratio)
            let secondLength = SplitLayoutMath.secondLength(totalLength: total, ratio: ratio)

            if axis == .vertical {
                HStack(spacing: 0) {
                    childView(first).frame(width: firstLength)
                    divider(total: total, firstLength: firstLength)
                    childView(second).frame(width: secondLength)
                }
            } else {
                VStack(spacing: 0) {
                    childView(first).frame(height: firstLength)
                    divider(total: total, firstLength: firstLength)
                    childView(second).frame(height: secondLength)
                }
            }
        }
    }

    private func childView(_ node: PaneNode) -> AnyView {
        AnyView(PaneTreeView(node: node,
                             tabID: tabID,
                             activePaneID: activePaneID,
                             viewModel: viewModel,
                             sessionManager: sessionManager))
    }

    private func divider(total: CGFloat, firstLength: CGFloat) -> some View {
        PaneDividerView(axis: axis)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStartLength ?? firstLength
                        dragStartLength = start
                        // SwiftUI's +y points down and VStack's first child is on top,
                        // so a downward drag grows the first pane in both axes.
                        let delta = axis == .vertical ? value.translation.width : value.translation.height
                        let newRatio = SplitLayoutMath.ratio(
                            atPosition: start + delta,
                            totalLength: SplitLayoutMath.usableLength(totalLength: total))
                        viewModel.updateSplitRatio(tabID: tabID, splitID: splitID, ratio: newRatio)
                    }
                    .onEnded { _ in dragStartLength = nil }
            )
    }
}

// MARK: - Divider

private struct PaneDividerView: View {
    let axis: SplitAxis

    /// Guards against unbalanced `NSCursor.pop()` calls.
    @State private var didPushCursor = false

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: axis == .vertical ? SplitLayoutMath.dividerThickness : nil,
                   height: axis == .horizontal ? SplitLayoutMath.dividerThickness : nil)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    guard !didPushCursor else { return }
                    didPushCursor = true
                    switch axis {
                    case .vertical: NSCursor.resizeLeftRight.push()
                    case .horizontal: NSCursor.resizeUpDown.push()
                    }
                } else if didPushCursor {
                    didPushCursor = false
                    NSCursor.pop()
                }
            }
            .onDisappear {
                if didPushCursor {
                    didPushCursor = false
                    NSCursor.pop()
                }
            }
    }
}
```

Not: `NSCursor.resizeLeftRight` / `resizeUpDown` macOS 15'te `columnResize`/`rowResize` lehine deprecate edildi; dağıtım hedefimiz macOS 14 olduğu için bunları kullanıyoruz — yeni SDK ile derlerken uyarı görülebilir, hata değildir.

- [ ] **Step 8: Derle, PaneTreeView'ın derlendiğini doğrula**

```bash
xcodebuild build -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet 2>&1 | tail -20
```

Beklenen: hata yok, `** BUILD SUCCEEDED **`. (`PaneTreeView` henüz hiçbir yerden kullanılmıyor; bu adım yalnız tip/derleme doğrulaması.)

- [ ] **Step 9: `PaneLeafView`'a "süreç sonlandı" bandını ekle**

Spec §8: shell çıkınca panel açık kalır ve içinde `"İşlem sonlandı (çıkış kodu N)"` bandı görünür; Enter aynı panelde yeni oturum başlatır. Shell hiç başlatılamadıysa (Task 8 `createSession` içindeki `access(X_OK)` kontrolü `session.launchFailure`'a denenen yolu yazar) bandın metni ve düğmeleri kurtarma odaklıdır.

`/Users/ahmetbarut/Apps/Termora/Termora/Views/Terminal/PaneTreeView.swift` içindeki `private struct PaneLeafView`'ı **tamamen** şununla değiştir (dosyanın geri kalanı — `PaneTreeView`, `SplitContainerView`, `PaneDividerView`, `PaneFramesPreferenceKey` — aynen kalır):

```swift
private struct PaneLeafView: View {
    let paneID: UUID
    let sessionID: UUID
    let isActive: Bool
    let viewModel: WorkspaceViewModel
    let sessionManager: SessionManager

    /// The banner takes key focus when it appears, so Enter restarts the session
    /// without the user having to click first.
    @FocusState private var isBannerFocused: Bool

    /// Reading the @Observable session here makes the leaf redraw when the shell exits.
    private var session: TerminalSession? { sessionManager.session(id: sessionID) }

    private var exitStatus: ExitStatus? {
        guard case .exited(let status)? = session?.processState else { return nil }
        return status
    }

    var body: some View {
        TerminalHostView(sessionID: sessionID,
                         sessionManager: sessionManager,
                         isActive: isActive)
            .overlay(alignment: .top) {
                if let exitStatus {
                    banner(exitStatus: exitStatus, failedPath: session?.launchFailure)
                }
            }
            .overlay {
                // The dimming layer only exists while inactive, so an active pane
                // never intercepts clicks meant for the terminal (selection, links).
                // It sits above the banner: clicking an inactive pane focuses it first.
                if !isActive {
                    Color.black.opacity(0.15)
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.activatePane(paneID: paneID) }
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: PaneFramesPreferenceKey.self,
                        value: [paneID: proxy.frame(in: .named(PaneTreeView.coordinateSpaceName))]
                    )
                }
            )
    }

    /// Spec §8: the pane stays open after the process exits and offers a way back.
    @ViewBuilder
    private func banner(exitStatus: ExitStatus, failedPath: String?) -> some View {
        HStack(spacing: 8) {
            if let failedPath {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("'\(failedPath)' çalıştırılamadı")
                Spacer(minLength: 8)
                Button("Yeniden dene") {
                    viewModel.restartPaneSession(paneID: paneID)
                }
                Button("Varsayılan shell ile dene") {
                    viewModel.restartPaneSession(paneID: paneID, forceDefaultShell: true)
                }
            } else {
                Text("İşlem sonlandı (\(exitStatus.localizedSummary))")
                Spacer(minLength: 8)
                Button("Yeniden başlat") {
                    viewModel.restartPaneSession(paneID: paneID)
                }
            }
        }
        .font(.system(size: 11))
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .focusable()
        .focusEffectDisabled()
        .focused($isBannerFocused)
        .onKeyPress(.return) {
            viewModel.restartPaneSession(paneID: paneID)
            return .handled
        }
        .task { isBannerFocused = isActive }
        .onChange(of: isActive) { _, active in
            if active { isBannerFocused = true }
        }
        .accessibilityLabel(failedPath == nil
                            ? "İşlem sonlandı: \(exitStatus.localizedSummary)"
                            : "Shell çalıştırılamadı: \(failedPath ?? "")")
    }
}
```

Notlar:
- `focusable()`, `focusEffectDisabled()`, `onKeyPress(_:action:)` ve iki parametreli `onChange(of:)` macOS 14.0+ API'leridir.
- Bant yalnız `processState == .exited(...)` iken var olur; süreç yeniden başlayınca (`SessionManager.restartSession` `processState`'i `.running` yapar) kaybolur ve odak terminale döner.
- Karartma katmanı banttan SONRA eklenir; böylece pasif panelde bant düğmelerine değil, panele tıklanmış olur (önce odak, sonra düğme).

- [ ] **Step 10: Derle, PASS bekle**

```bash
xcodebuild build -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet 2>&1 | tail -20
```

Beklenen: `** BUILD SUCCEEDED **`.

- [ ] **Step 11: `MainWindowView`'da aktif sekme içeriğini `PaneTreeView` ile değiştir**

`/Users/ahmetbarut/Apps/Termora/Termora/Views/MainWindowView.swift` içindeki `terminalContent` hesaplanan özelliğinin **tamamını** aşağıdaki blokla değiştir (TabBar ve gövdenin geri kalanı aynen kalır). Görünümün özellikleri Task 12'de `private let services: AppServices` + `@State private var workspace: WorkspaceViewModel` olarak tanımlıdır; bu yüzden view model'e `workspace`, oturum yöneticisine `services.sessionManager` denir:

```swift
    @ViewBuilder
    private var terminalContent: some View {
        if let tab = workspace.activeTab {
            GeometryReader { root in
                PaneTreeView(node: tab.root,
                             tabID: tab.id,
                             activePaneID: tab.activePaneID,
                             viewModel: workspace,
                             sessionManager: services.sessionManager)
                    .coordinateSpace(.named(PaneTreeView.coordinateSpaceName))
                    .onPreferenceChange(PaneFramesPreferenceKey.self) { frames in
                        let converted = PaneFrameConverter.appKitFrames(
                            frames, containerHeight: root.size.height)
                        Task { @MainActor in
                            workspace.paneFrames = converted
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
        }
    }
```

`.coordinateSpace(.named(_:))` macOS 14.0+ API'sidir (deprecate olan `coordinateSpace(name:)` değil). Çerçeveler SwiftUI düzeninde toplanır, `PaneFrameConverter` ile AppKit düzenine (y yukarı) çevrilip `workspace.paneFrames`'e yazılır — `PaneGeometry` bu düzeni bekler.

- [ ] **Step 12: Derle, PASS bekle**

```bash
xcodebuild build -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet 2>&1 | tail -20
```

Beklenen: `** BUILD SUCCEEDED **`.

- [ ] **Step 13: `AppCommands`'a panel menüsünü ekle**

`/Users/ahmetbarut/Apps/Termora/Termora/App/AppCommands.swift` içinde, mevcut sekme komutlarından sonra (`body: some Commands` içinde, son `}` öncesine) yeni bir menü ekle:

```swift
        CommandMenu("Pane") {
            Button("Split Vertically") {
                workspace?.splitActivePane(axis: .vertical)
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(workspace == nil)

            Button("Split Horizontally") {
                workspace?.splitActivePane(axis: .horizontal)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(workspace == nil)

            Divider()

            Button("Close Pane") {
                workspace?.requestCloseActivePane()
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .disabled(workspace == nil)

            Divider()

            Button("Focus Pane Left") { workspace?.focusPane(.left) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(workspace == nil)
            Button("Focus Pane Right") { workspace?.focusPane(.right) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(workspace == nil)
            Button("Focus Pane Up") { workspace?.focusPane(.up) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(workspace == nil)
            Button("Focus Pane Down") { workspace?.focusPane(.down) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(workspace == nil)
        }
```

Not: ⌘W sözleşme gereği aktif **sekmeyi** kapatır (panel odaklı olsa bile), bu yüzden panel kapatma ⌘⇧W'ye bağlandı.

- [ ] **Step 14: Derle ve tüm testleri çalıştır, PASS bekle**

```bash
xcodebuild build -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet 2>&1 | tail -20
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests 2>&1 | tail -20
```

Beklenen: `** BUILD SUCCEEDED **` ve `** TEST SUCCEEDED **`.

- [ ] **Step 15: Elle doğrulama — uygulamayı çalıştır ve bölme davranışını kontrol et**

```bash
xcodebuild build -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -derivedDataPath /tmp/termora-dd -quiet && open /tmp/termora-dd/Build/Products/Debug/Termora.app
```

Kontrol listesi (her maddeyi gözle doğrula):
1. **⌘D** → pencere dikey ayraçla ikiye bölünür, paneller **yan yana**; sağdaki panel aktiftir (soldaki hafifçe karartılmıştır). `echo left` yazınca metin **sağ** panele gider.
2. **⌘⇧D** → aktif panel yatay ayraçla ikiye bölünür, paneller **üst üste**; toplam 3 panel görünür.
3. Bir kez daha **⌘D** ile 4 panele çık; her panelde `ls` çalıştır, hiçbir panelde çıktı kırpılması/boş alan olmamalı.
4. Ayracın üzerine gel → imleç dikey ayraçta **sol-sağ**, yatay ayraçta **yukarı-aşağı** ok halini alır; ayracı bırakınca normal imleç geri döner.
5. Ayracı sürükle → paneller anında yeniden boyutlanır, shell prompt'u yeni genişliğe sarar; ayrac panel genişliğinin **%15'i ve %85'i** dışına çıkmaz.
6. **⌘⌥←/→/↑/↓** → karartma (aktif panel vurgusu) yön tuşunun gösterdiği komşu panele geçer; kenarda o yönde panel yoksa odak değişmez.
7. Karartılmış bir panele **tıkla** → o panel aktif olur, klavye girişi oraya gider.
8. Aktif panelde metin seçmek için **sürükle** → seçim çalışır (aktif panelde tıklama terminale ulaşır, karartma katmanı yoktur).
9. Boşta bir panelde **⌘⇧W** → panel kapanır, kardeşi tüm alanı kaplar, odak kardeşe geçer.
10. Bir panelde `sleep 60` çalıştırıp **⌘⇧W** → Task 12'de `pendingClose`'a bağlanan onay diyaloğu açılır; **İptal** panel açık bırakır, **Kapat** paneli kapatır.
11. Tek panel kaldığında **⌘⇧W** → sekme kapatma davranışı devreye girer (sekme kapanır / onay istenir).
12. Bir panelde `exit` yaz → panel kapanmaz; terminalin üstünde **"İşlem sonlandı (çıkış kodu 0)"** bandı ve **Yeniden başlat** düğmesi belirir. **Enter**'a bas → aynı panelde yeni prompt gelir, scrollback sıfırlanır, bant kaybolur. (`exit 3` ile bandın metninin `çıkış kodu 3` olduğunu da doğrula.)
13. Ayarlar ▸ Genel'de shell yolunu geçersiz bir değere ayarla (ör. `/bin/yok`) ve ⌘D ile yeni panel aç → bant **"'/bin/yok' çalıştırılamadı"** metnini ve iki düğmeyi gösterir. **Varsayılan shell ile dene** → panelde varsayılan shell açılır (ayardaki bozuk yol yok sayılır); ayarı düzeltmeden kurtarma mümkündür.

- [ ] **Step 16: Commit**

```bash
git -C /Users/ahmetbarut/Apps/Termora add Termora/Views/Terminal/PaneTreeView.swift Termora/Views/MainWindowView.swift Termora/App/AppCommands.swift
git -C /Users/ahmetbarut/Apps/Termora commit -m "feat: render pane tree with dividers, split shortcuts and process-exited banner"
```

---

---

### Task 18: Ayarlar penceresi — Genel + Görünüm + canlı uygulama (M4)

**Files:**
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Models/SettingsLimits.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Services/FontCatalog.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Extensions/CursorStyleSetting+Display.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Views/Support/WindowChrome.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Views/Settings/ThemePreviewView.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Views/Settings/GeneralSettingsView.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Views/Settings/AppearanceSettingsView.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Views/Settings/SettingsWindowView.swift`
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/App/TermoraApp.swift`
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/Services/SessionManager.swift` (font çözümü `FontCatalog.resolvedFont`'a taşınır — Step 20)
- Modify: `/Users/ahmetbarut/Apps/Termora/TermoraTests/SessionManagerTests.swift` (font çözümleme testleri `FontCatalogTests`'e taşınır — Step 20)
- Delete: `/Users/ahmetbarut/Apps/Termora/Termora/Views/SettingsPlaceholderView.swift` (Task 10'un yer tutucusu gerçek ayarlar penceresiyle değişir)
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/SettingsLimitsTests.swift`
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/FontCatalogTests.swift`
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/AppearanceOptionsTests.swift`

**Interfaces:**

*Consumes:*
- Task 4: `enum ShellService { static func availableShells() -> [ShellInfo] }`, `struct ShellInfo: Equatable, Identifiable { var id: String { path }; let path: String; let displayName: String }`
- Task 5: `final class ThemeStore { let themes: [Theme]; func theme(id: String) -> Theme }`, `struct Theme: Codable, Identifiable, Equatable { var id: String; var name: String; ...; var ansi: [String] }`, `extension Theme { var backgroundNSColor: NSColor; var foregroundNSColor: NSColor; var cursorNSColor: NSColor }`, `extension NSColor { convenience init?(hexString: String) }`
- Task 6: `@MainActor @Observable final class SettingsStore { init(defaults: UserDefaults = .standard); var settings: AppSettings }`, `struct AppSettings: Codable, Equatable { var fontName: String?; var fontSize: Double; var lineSpacing: Double; var cursorStyle: CursorStyleSetting; var themeID: String; var windowOpacity: Double; var scrollbackLines: Int; var defaultShellPath: String?; var startupDirectory: String?; var showStatusBar: Bool }`, `enum CursorStyleSetting: String, Codable, CaseIterable`
- Task 7: `@MainActor @Observable final class ProfileStore { var profiles: [TerminalProfile] }` (yalnız `SettingsWindowView`'a taşınır; Profiller sekmesi Task 19'da eklenir)
- Task 8: `@MainActor @Observable final class SessionManager: SessionManaging, LocalProcessTerminalViewDelegate` — `func applyAppearanceToAllSessions()`, `applyAppearance(to view: TermoraTerminalView, sessionID: UUID)`, `static func resolveFont(name: String?, size: Double) -> NSFont` (bu görevin Step 20'sinde `FontCatalog.resolvedFont` ile değiştirilip silinir)
- Task 10: `struct SettingsPlaceholderView: View` (Step 7) + `TermoraApp` içindeki `Settings { SettingsPlaceholderView() }` sahnesi (Step 8) — bu görevin Step 22'sinde gerçek ayarlar penceresiyle değiştirilir ve yer tutucu dosya silinir
- Task 13/17: `Termora/App/TermoraApp.swift` içinde `WindowGroup { ... }` sahnesi, `.commands { AppCommands() }` modifier'ı ve `private let services = AppServices()` özelliği — servislere `services.settings`, `services.themes`, `services.profiles`, `services.sessionManager` ile erişilir; `TermoraApp` kapsamında çıplak `settings`/`themes`/`profiles`/`sessionManager` adları YOKTUR

*Produces:*
- `enum SettingsLimits { static let scrollbackRange: ClosedRange<Int>; static let fontSizeRange: ClosedRange<Double>; static let lineSpacingRange: ClosedRange<Double>; static let opacityRange: ClosedRange<Double>; static func clampScrollback(_ value: Int) -> Int; static func clampFontSize(_ value: Double) -> Double; static func clampLineSpacing(_ value: Double) -> Double; static func clampOpacity(_ value: Double) -> Double; static func scrollback(fromText text: String, fallback: Int) -> Int }`
- `enum FontCatalog { static let fallbackFamily: String; static func monospacedFamilies(from families: [String], isFixedPitch: (String) -> Bool) -> [String]; @MainActor static func isFixedPitchFamily(_ family: String) -> Bool; @MainActor static func availableMonospacedFamilies() -> [String]; @MainActor static func resolvedFont(name: String?, size: Double) -> NSFont }`
- `extension CursorStyleSetting { var displayName: String }`
- `struct WindowAccessor: NSViewRepresentable { let onWindow: (NSWindow) -> Void }`
- `struct VisualEffectBackground: NSViewRepresentable { var material: NSVisualEffectView.Material; var blendingMode: NSVisualEffectView.BlendingMode }`
- `extension View { func termoraWindowChrome(opacity: Double, backgroundColor: NSColor) -> some View; func syncingTerminalAppearance(settings: SettingsStore, sessionManager: SessionManager) -> some View }`
- `struct ThemePreviewView: View { let theme: Theme }`
- `struct GeneralSettingsView: View { @Bindable var settings: SettingsStore }`
- `struct AppearanceSettingsView: View { @Bindable var settings: SettingsStore; let themes: ThemeStore }`
- `struct SettingsWindowView: View { let settings: SettingsStore; let themes: ThemeStore; let profiles: ProfileStore }`

---

- [ ] **Step 1: `SettingsLimitsTests.swift` dosyasını yaz (RED)**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/SettingsLimitsTests.swift`:

```swift
import Testing
@testable import Termora

@Suite("Ayar sınırları")
struct SettingsLimitsTests {

    @Test func scrollbackClampsToRange() {
        #expect(SettingsLimits.clampScrollback(50) == 100)
        #expect(SettingsLimits.clampScrollback(100) == 100)
        #expect(SettingsLimits.clampScrollback(10_000) == 10_000)
        #expect(SettingsLimits.clampScrollback(100_000) == 100_000)
        #expect(SettingsLimits.clampScrollback(250_000) == 100_000)
    }

    @Test func scrollbackTextParsingFallsBackOnGarbage() {
        #expect(SettingsLimits.scrollback(fromText: "4200", fallback: 10_000) == 4200)
        #expect(SettingsLimits.scrollback(fromText: "  8000 ", fallback: 10_000) == 8000)
        #expect(SettingsLimits.scrollback(fromText: "", fallback: 10_000) == 10_000)
        #expect(SettingsLimits.scrollback(fromText: "abc", fallback: 10_000) == 10_000)
        #expect(SettingsLimits.scrollback(fromText: "999999", fallback: 10_000) == 100_000)
    }

    @Test func scrollbackTextFallbackIsItselfClamped() {
        #expect(SettingsLimits.scrollback(fromText: "abc", fallback: 5) == 100)
        #expect(SettingsLimits.scrollback(fromText: "abc", fallback: 500_000) == 100_000)
    }

    @Test func lineSpacingAndOpacityAndFontSizeClamp() {
        #expect(SettingsLimits.clampLineSpacing(0.5) == 1.0)
        #expect(SettingsLimits.clampLineSpacing(1.25) == 1.25)
        #expect(SettingsLimits.clampLineSpacing(9.0) == 1.6)
        #expect(SettingsLimits.clampOpacity(0.1) == 0.5)
        #expect(SettingsLimits.clampOpacity(0.75) == 0.75)
        #expect(SettingsLimits.clampOpacity(1.5) == 1.0)
        #expect(SettingsLimits.clampFontSize(2) == 8)
        #expect(SettingsLimits.clampFontSize(13) == 13)
        #expect(SettingsLimits.clampFontSize(99) == 32)
    }

    @Test func nonFiniteValuesFallBackToSafeDefaults() {
        #expect(SettingsLimits.clampFontSize(.nan) == 13)
        #expect(SettingsLimits.clampLineSpacing(.nan) == 1.0)
        #expect(SettingsLimits.clampOpacity(.nan) == 1.0)
        #expect(SettingsLimits.clampFontSize(.infinity) == 32)
    }
}
```

- [ ] **Step 2: Testi çalıştır, FAIL bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/SettingsLimitsTests 2>&1 | tail -20
```

Beklenen: derleme hatası — `error: cannot find 'SettingsLimits' in scope` (birden çok kez) ve son satırda `** TEST FAILED **`.

- [ ] **Step 3: `SettingsLimits.swift` dosyasını yaz (minimal implementasyon)**

`/Users/ahmetbarut/Apps/Termora/Termora/Models/SettingsLimits.swift`:

```swift
import Foundation

/// Kullanıcı ayarları için tek doğruluk kaynağı olan sayısal sınırlar.
/// Hem Ayarlar UI'ı hem de terminale uygulama yolu buradan geçer.
enum SettingsLimits {

    static let scrollbackRange: ClosedRange<Int> = 100...100_000
    static let fontSizeRange: ClosedRange<Double> = 8...32
    static let lineSpacingRange: ClosedRange<Double> = 1.0...1.6
    static let opacityRange: ClosedRange<Double> = 0.5...1.0

    static let defaultFontSize: Double = 13

    static func clampScrollback(_ value: Int) -> Int {
        min(max(value, scrollbackRange.lowerBound), scrollbackRange.upperBound)
    }

    static func clampFontSize(_ value: Double) -> Double {
        guard !value.isNaN else { return defaultFontSize }
        return min(max(value, fontSizeRange.lowerBound), fontSizeRange.upperBound)
    }

    static func clampLineSpacing(_ value: Double) -> Double {
        guard !value.isNaN else { return lineSpacingRange.lowerBound }
        return min(max(value, lineSpacingRange.lowerBound), lineSpacingRange.upperBound)
    }

    static func clampOpacity(_ value: Double) -> Double {
        guard !value.isNaN else { return opacityRange.upperBound }
        return min(max(value, opacityRange.lowerBound), opacityRange.upperBound)
    }

    /// Scrollback metin alanı için: ayrıştırılamayan girdi `fallback`'e düşer,
    /// her iki durumda da sonuç `scrollbackRange` içine sıkıştırılır.
    static func scrollback(fromText text: String, fallback: Int) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Int(trimmed) else { return clampScrollback(fallback) }
        return clampScrollback(parsed)
    }
}
```

- [ ] **Step 4: Testi çalıştır, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/SettingsLimitsTests 2>&1 | tail -20
```

Beklenen: `Suite "Ayar sınırları" passed after ... seconds.` ve `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora && git add -A && git commit -m "feat: add SettingsLimits clamping helpers for settings UI"
```

- [ ] **Step 6: `FontCatalogTests.swift` dosyasını yaz (RED)**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/FontCatalogTests.swift`:

```swift
import Testing
@testable import Termora

@Suite("Font kataloğu")
struct FontCatalogTests {

    @Test func onlyFixedPitchFamiliesSurvive() {
        let fixedPitch: Set<String> = ["Menlo", "SF Mono"]
        let result = FontCatalog.monospacedFamilies(
            from: ["Helvetica", "SF Mono", "Times New Roman", "Menlo"],
            isFixedPitch: { fixedPitch.contains($0) }
        )
        #expect(result == ["Menlo", "SF Mono"])
    }

    @Test func fallbackFamilyIsAlwaysPresent() {
        let result = FontCatalog.monospacedFamilies(
            from: ["Helvetica", "Times New Roman"],
            isFixedPitch: { _ in false }
        )
        #expect(result == ["Menlo"])
        #expect(FontCatalog.fallbackFamily == "Menlo")
    }

    @Test func duplicatesRemovedAndOrderIsCaseInsensitive() {
        let result = FontCatalog.monospacedFamilies(
            from: ["Zed Mono", "Menlo", "andale Mono", "Menlo"],
            isFixedPitch: { _ in true }
        )
        #expect(result == ["andale Mono", "Menlo", "Zed Mono"])
    }

    @Test func emptyInputStillYieldsUsableList() {
        let result = FontCatalog.monospacedFamilies(from: [], isFixedPitch: { _ in true })
        #expect(result == ["Menlo"])
    }

    // Step 20'de `SessionManager.resolveFont`'un yerini aldığı için font çözümlemesinin
    // karakterizasyon testleri de buraya taşınır.

    @Test func resolvedFontFallsBackWhenTheFamilyIsMissingOrUnknown() {
        #expect(FontCatalog.resolvedFont(name: nil, size: 13).pointSize == 13)
        #expect(FontCatalog.resolvedFont(name: "", size: 17).pointSize == 17)
        #expect(FontCatalog.resolvedFont(name: "ThereIsNoSuchFont-42", size: 17).pointSize == 17)
    }

    @Test func resolvedFontHonoursAnInstalledFamily() {
        let menlo = FontCatalog.resolvedFont(name: "Menlo", size: 15)
        #expect(menlo.familyName == "Menlo")
        #expect(menlo.pointSize == 15)
    }

    @Test func resolvedFontSizeIsClamped() {
        #expect(FontCatalog.resolvedFont(name: nil, size: 400).pointSize == SettingsLimits.fontSizeRange.upperBound)
        #expect(FontCatalog.resolvedFont(name: nil, size: 1).pointSize == SettingsLimits.fontSizeRange.lowerBound)
    }
}
```

- [ ] **Step 7: Testi çalıştır, FAIL bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/FontCatalogTests 2>&1 | tail -20
```

Beklenen: `error: cannot find 'FontCatalog' in scope` ve `** TEST FAILED **`.

- [ ] **Step 8: `FontCatalog.swift` dosyasını yaz (minimal implementasyon)**

`/Users/ahmetbarut/Apps/Termora/Termora/Services/FontCatalog.swift`:

```swift
import AppKit

/// Terminal için kullanılabilir sabit genişlikli (monospace) font ailelerini
/// listeler ve ayarlardaki aile adını gerçek bir `NSFont`'a çözer.
enum FontCatalog {

    /// Her macOS kurulumunda bulunan güvenli varsayılan.
    static let fallbackFamily = "Menlo"

    /// Saf çekirdek: dosya sistemi/AppKit dokunuşu yok, `isFixedPitch` dikişiyle test edilir.
    /// Tekrarlar atılır, `fallbackFamily` her zaman listede olur, sonuç harf duyarsız sıralanır.
    static func monospacedFamilies(from families: [String], isFixedPitch: (String) -> Bool) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for family in families where isFixedPitch(family) {
            if seen.insert(family).inserted {
                result.append(family)
            }
        }
        if seen.insert(fallbackFamily).inserted {
            result.append(fallbackFamily)
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    @MainActor
    static func isFixedPitchFamily(_ family: String) -> Bool {
        guard let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 12) else {
            return false
        }
        return font.isFixedPitch
    }

    @MainActor
    static func availableMonospacedFamilies() -> [String] {
        monospacedFamilies(
            from: NSFontManager.shared.availableFontFamilies,
            isFixedPitch: { isFixedPitchFamily($0) }
        )
    }

    /// Ayarlardaki aile adı + boyuttan gerçek fontu üretir; aile bulunamazsa Menlo'ya,
    /// o da yoksa sistem monospace fontuna düşer.
    @MainActor
    static func resolvedFont(name: String?, size: Double) -> NSFont {
        let clampedSize = SettingsLimits.clampFontSize(size)
        if let name, !name.isEmpty,
           let font = NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: clampedSize) {
            return font
        }
        if let font = NSFont(name: fallbackFamily, size: clampedSize) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: clampedSize, weight: .regular)
    }
}
```

- [ ] **Step 9: Testi çalıştır, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/FontCatalogTests 2>&1 | tail -20
```

Beklenen: `Suite "Font kataloğu" passed after ... seconds.` ve `** TEST SUCCEEDED **`.

- [ ] **Step 10: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora && git add -A && git commit -m "feat: add FontCatalog monospace filtering and font resolution"
```

- [ ] **Step 11: `AppearanceOptionsTests.swift` dosyasını yaz (RED)**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/AppearanceOptionsTests.swift`:

```swift
import Testing
@testable import Termora

@Suite("Görünüm seçenekleri")
struct AppearanceOptionsTests {

    @Test func everyCursorStyleHasUniqueNonEmptyDisplayName() {
        let names = CursorStyleSetting.allCases.map(\.displayName)
        #expect(names.count == 6)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
    }

    @Test func blockStylesAreDistinguishedByBlinking() {
        #expect(CursorStyleSetting.blinkBlock.displayName != CursorStyleSetting.steadyBlock.displayName)
        #expect(CursorStyleSetting.blinkBar.displayName != CursorStyleSetting.steadyBar.displayName)
        #expect(CursorStyleSetting.blinkUnderline.displayName != CursorStyleSetting.steadyUnderline.displayName)
    }
}
```

- [ ] **Step 12: Testi çalıştır, FAIL bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/AppearanceOptionsTests 2>&1 | tail -20
```

Beklenen: `error: value of type 'CursorStyleSetting' has no member 'displayName'` ve `** TEST FAILED **`.

- [ ] **Step 13: `CursorStyleSetting+Display.swift` dosyasını yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Extensions/CursorStyleSetting+Display.swift`:

```swift
import Foundation

extension CursorStyleSetting {
    /// Ayarlar penceresindeki imleç şekli seçicisinde görünen ad.
    var displayName: String {
        switch self {
        case .blinkBlock: return "Blok (yanıp sönen)"
        case .steadyBlock: return "Blok (sabit)"
        case .blinkUnderline: return "Alt çizgi (yanıp sönen)"
        case .steadyUnderline: return "Alt çizgi (sabit)"
        case .blinkBar: return "Çubuk (yanıp sönen)"
        case .steadyBar: return "Çubuk (sabit)"
        }
    }
}
```

- [ ] **Step 14: Testi çalıştır, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/AppearanceOptionsTests 2>&1 | tail -20
```

Beklenen: `Suite "Görünüm seçenekleri" passed after ... seconds.` ve `** TEST SUCCEEDED **`.

- [ ] **Step 15: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora && git add -A && git commit -m "feat: add localized display names for cursor styles"
```

- [ ] **Step 16: `WindowChrome.swift` dosyasını yaz (WindowAccessor + saydam arka plan + görünüm senkronu)**

`/Users/ahmetbarut/Apps/Termora/Termora/Views/Support/WindowChrome.swift`:

```swift
import AppKit
import SwiftUI

/// SwiftUI hiyerarşisinden barındıran `NSWindow`'u yakalar.
/// macOS 14'te `containerBackground(.window)` yok; pencere saydamlığı bu yolla ayarlanır.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> CatchingView {
        let view = CatchingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: CatchingView, context: Context) {
        nsView.onWindow = onWindow
        if let window = nsView.window {
            onWindow(window)
        }
    }

    final class CatchingView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window = self.window {
                onWindow?(window)
            }
        }
    }
}

/// Pencere arkasını bulanıklaştıran `NSVisualEffectView` sarmalayıcısı.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

private struct WindowChromeModifier: ViewModifier {
    let opacity: Double
    let backgroundColor: NSColor

    private var isTranslucent: Bool { opacity < 0.999 }

    func body(content: Content) -> some View {
        content
            .background {
                if isTranslucent {
                    VisualEffectBackground().ignoresSafeArea()
                } else {
                    Color(nsColor: backgroundColor).ignoresSafeArea()
                }
            }
            .background(
                WindowAccessor { window in
                    window.isOpaque = !isTranslucent
                    window.backgroundColor = isTranslucent ? .clear : backgroundColor
                }
            )
    }
}

private struct TerminalAppearanceSyncModifier: ViewModifier {
    let settings: SettingsStore
    let sessionManager: SessionManager

    func body(content: Content) -> some View {
        content.onChange(of: settings.settings) { _, _ in
            sessionManager.applyAppearanceToAllSessions()
        }
    }
}

extension View {
    /// Pencere saydamlığını ve arka planını `AppSettings.windowOpacity` + tema rengine göre kurar.
    func termoraWindowChrome(opacity: Double, backgroundColor: NSColor) -> some View {
        modifier(WindowChromeModifier(opacity: opacity, backgroundColor: backgroundColor))
    }

    /// Ayarlar değiştiğinde açık tüm terminallere görünümü yeniden uygular (tek yönlü akış).
    func syncingTerminalAppearance(settings: SettingsStore, sessionManager: SessionManager) -> some View {
        modifier(TerminalAppearanceSyncModifier(settings: settings, sessionManager: sessionManager))
    }
}
```

Derle:

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet
```

Beklenen: çıktı yok, çıkış kodu 0 (`-quiet` başarıda sessizdir).

- [ ] **Step 17: `ThemePreviewView.swift` dosyasını yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Views/Settings/ThemePreviewView.swift`:

```swift
import AppKit
import SwiftUI

/// Seçili temanın arka plan/metin renklerini ve 16 ANSI rengini swatch olarak gösterir.
struct ThemePreviewView: View {
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("user@termora ~ % ls -la")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(nsColor: theme.foregroundNSColor))

            HStack(spacing: 4) {
                ForEach(0..<8) { index in
                    swatch(at: index)
                }
            }
            HStack(spacing: 4) {
                ForEach(8..<16) { index in
                    swatch(at: index)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: theme.backgroundNSColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
    }

    private func swatch(at index: Int) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color(at: index))
            .frame(width: 18, height: 18)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color(nsColor: theme.foregroundNSColor).opacity(0.15))
            )
    }

    private func color(at index: Int) -> Color {
        guard theme.ansi.indices.contains(index),
              let nsColor = NSColor(hexString: theme.ansi[index]) else {
            return Color(nsColor: .systemGray)
        }
        return Color(nsColor: nsColor)
    }
}
```

Derle:

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet
```

Beklenen: çıktı yok, çıkış kodu 0.

- [ ] **Step 18: `GeneralSettingsView.swift` dosyasını yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Views/Settings/GeneralSettingsView.swift`:

```swift
import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: SettingsStore

    @State private var shells: [ShellInfo] = []
    @State private var scrollbackText: String = ""

    var body: some View {
        Form {
            Section("Kabuk") {
                Picker("Varsayılan kabuk", selection: $settings.settings.defaultShellPath) {
                    Text("Sistem varsayılanı").tag(nil as String?)
                    ForEach(shells) { shell in
                        Text(shell.displayName).tag(shell.path as String?)
                    }
                }
            }

            Section("Başlangıç klasörü") {
                HStack(spacing: 8) {
                    Text(settings.settings.startupDirectory ?? "Ana klasör (~)")
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Seç…") { chooseStartupDirectory() }
                    Button("Temizle") { settings.settings.startupDirectory = nil }
                        .disabled(settings.settings.startupDirectory == nil)
                }
            }

            Section("Terminal") {
                HStack(spacing: 8) {
                    Text("Kaydırma geçmişi (satır)")
                    Spacer()
                    TextField("", text: $scrollbackText)
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { commitScrollbackText() }
                    Stepper("", value: scrollbackBinding, in: SettingsLimits.scrollbackRange, step: 500)
                        .labelsHidden()
                }
                Text("100 – 100.000 arası. Aralık dışı değerler kırpılır.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Durum çubuğunu göster", isOn: $settings.settings.showStatusBar)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            shells = ShellService.availableShells()
            scrollbackText = String(settings.settings.scrollbackLines)
        }
        .onChange(of: settings.settings.scrollbackLines) { _, newValue in
            scrollbackText = String(newValue)
        }
    }

    private var scrollbackBinding: Binding<Int> {
        Binding(
            get: { settings.settings.scrollbackLines },
            set: { settings.settings.scrollbackLines = SettingsLimits.clampScrollback($0) }
        )
    }

    private func commitScrollbackText() {
        let value = SettingsLimits.scrollback(
            fromText: scrollbackText,
            fallback: settings.settings.scrollbackLines
        )
        settings.settings.scrollbackLines = value
        scrollbackText = String(value)
    }

    private func chooseStartupDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Seç"
        panel.message = "Yeni terminallerin açılacağı klasörü seçin."
        if let current = settings.settings.startupDirectory {
            panel.directoryURL = URL(fileURLWithPath: current)
        }
        if panel.runModal() == .OK, let url = panel.url {
            settings.settings.startupDirectory = url.path
        }
    }
}
```

Derle:

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet
```

Beklenen: çıktı yok, çıkış kodu 0.

- [ ] **Step 19: `AppearanceSettingsView.swift` dosyasını yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Views/Settings/AppearanceSettingsView.swift`:

```swift
import AppKit
import SwiftUI

struct AppearanceSettingsView: View {
    @Bindable var settings: SettingsStore
    let themes: ThemeStore

    @State private var fontFamilies: [String] = []

    var body: some View {
        Form {
            Section("Tema") {
                Picker("Tema", selection: $settings.settings.themeID) {
                    ForEach(themes.themes) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                ThemePreviewView(theme: themes.theme(id: settings.settings.themeID))
            }

            Section("Yazı tipi") {
                Picker("Aile", selection: $settings.settings.fontName) {
                    Text("Varsayılan (\(FontCatalog.fallbackFamily))").tag(nil as String?)
                    ForEach(fontFamilies, id: \.self) { family in
                        Text(family).tag(family as String?)
                    }
                }

                Stepper(value: fontSizeBinding, in: SettingsLimits.fontSizeRange, step: 1) {
                    Text("Boyut: \(Int(settings.settings.fontSize)) pt")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Slider(value: lineSpacingBinding, in: SettingsLimits.lineSpacingRange, step: 0.05) {
                        Text("Satır aralığı")
                    }
                    Text(String(format: "%.2f×", settings.settings.lineSpacing))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("İmleç ve pencere") {
                Picker("İmleç şekli", selection: $settings.settings.cursorStyle) {
                    ForEach(CursorStyleSetting.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Slider(value: opacityBinding, in: SettingsLimits.opacityRange, step: 0.05) {
                        Text("Pencere saydamlığı")
                    }
                    Text("%\(Int((settings.settings.windowOpacity * 100).rounded())) opaklık")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            fontFamilies = FontCatalog.availableMonospacedFamilies()
        }
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { settings.settings.fontSize },
            set: { settings.settings.fontSize = SettingsLimits.clampFontSize($0) }
        )
    }

    private var lineSpacingBinding: Binding<Double> {
        Binding(
            get: { settings.settings.lineSpacing },
            set: { settings.settings.lineSpacing = SettingsLimits.clampLineSpacing($0) }
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { settings.settings.windowOpacity },
            set: { settings.settings.windowOpacity = SettingsLimits.clampOpacity($0) }
        )
    }
}
```

Derle:

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet
```

Beklenen: çıktı yok, çıkış kodu 0.

- [ ] **Step 20: Terminale font uygulama yolunu `FontCatalog`'a bağla**

Step 19'daki seçici AİLE adı yazar ("SF Mono", "Menlo"), ama Task 8'in `SessionManager`'ı fontu `NSFont(name:size:)` ile, yani PostScript adı bekleyerek çözer: `NSFont(name: "SF Mono", size:)` **nil döner** ve kullanıcının seçtiği font sessizce sistem monospace'ine düşer. Üç düzenleme yapılır:

**(a)** `/Users/ahmetbarut/Apps/Termora/Termora/Services/SessionManager.swift` içindeki `applyAppearance(to:sessionID:)` gövdesinde şu satır:

```swift
        view.font = Self.resolveFont(name: current.fontName, size: current.fontSize)
```

şununla değiştirilir:

```swift
        view.font = FontCatalog.resolvedFont(name: current.fontName, size: current.fontSize)
```

**(b)** Aynı dosyadaki `static func resolveFont(name:size:)` metodu ve üstündeki doküman yorumu SİLİNİR — artık çağıranı yoktur.

**(c)** `/Users/ahmetbarut/Apps/Termora/TermoraTests/SessionManagerTests.swift` içindeki `fontResolutionFallsBackToTheMonospacedSystemFont` ve `fontResolutionHonoursAnInstalledFont` testleri SİLİNİR; karşılıkları Step 6'da `FontCatalogTests`'e yazıldı (`resolvedFontFallsBackWhenTheFamilyIsMissingOrUnknown`, `resolvedFontHonoursAnInstalledFamily`).

Not: Task 19 Step 11 bu görünüm uygulama bölümünü profil çözümleyicisiyle yeniden yazar ama `FontCatalog.resolvedFont` çağrısını korur.

Derle ve iki süiti birlikte koştur:

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/SessionManagerTests -only-testing:TermoraTests/FontCatalogTests 2>&1 | tail -20
```

Beklenen: `** TEST SUCCEEDED **` (silinen iki test artık `FontCatalogTests` altında sayılır).

- [ ] **Step 21: `SettingsWindowView.swift` dosyasını yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Views/Settings/SettingsWindowView.swift`:

```swift
import SwiftUI

struct SettingsWindowView: View {
    let settings: SettingsStore
    let themes: ThemeStore
    /// Profiller sekmesi Task 19'da bu depoyu kullanır.
    let profiles: ProfileStore

    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings)
                .tabItem { Label("Genel", systemImage: "gearshape") }

            AppearanceSettingsView(settings: settings, themes: themes)
                .tabItem { Label("Görünüm", systemImage: "paintpalette") }
        }
        .frame(width: 560, height: 480)
    }
}
```

Derle:

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet
```

Beklenen: çıktı yok, çıkış kodu 0.

- [ ] **Step 22: `TermoraApp.swift`'i bağla — Settings sahnesi + pencere saydamlığı + canlı uygulama**

`/Users/ahmetbarut/Apps/Termora/Termora/App/TermoraApp.swift` üzerinde iki düzenleme yapılır; Task 13/17'de yazılan `WindowGroup` içeriğinin kök görünüm çağrısına dokunulmaz. `TermoraApp`'in tek özelliği `services` olduğu için tüm servis erişimleri `services.` önekiyle yazılır.

**(a)** `WindowGroup { ... }` içindeki kök görünüm ifadesinin sonuna aşağıdaki iki modifier zinciri eklenir:

```swift
                .termoraWindowChrome(
                    opacity: SettingsLimits.clampOpacity(services.settings.settings.windowOpacity),
                    backgroundColor: services.themes.theme(id: services.settings.settings.themeID).backgroundNSColor
                )
                .syncingTerminalAppearance(settings: services.settings, sessionManager: services.sessionManager)
```

**(b)** `body: some Scene` içindeki mevcut `Settings { SettingsPlaceholderView() }` sahnesinin (Task 10 Step 8'de eklendi) gövdesi gerçek ayarlar penceresiyle değiştirilir — sahne bulunamazsa `WindowGroup { ... }` bloğunun ve ona bağlı `.commands { ... }` modifier'ının hemen ardına yeni sahne olarak eklenir:

```swift
        Settings {
            SettingsWindowView(settings: services.settings,
                               themes: services.themes,
                               profiles: services.profiles)
        }
```

**(c)** Yer tutucu artık referanssız kaldığı için silinir:

```bash
cd /Users/ahmetbarut/Apps/Termora && git rm Termora/Views/SettingsPlaceholderView.swift
```

Derle:

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet
```

Beklenen: çıktı yok, çıkış kodu 0.

**Elle doğrulama** — Xcode'da `Termora` şemasını ⌘R ile çalıştır ve sırayla:
1. `Termora > Ayarlar…` (⌘,) → pencere açılır, üstte **Genel** ve **Görünüm** sekmeleri görünür.
2. Genel sekmesi: "Varsayılan kabuk" açılır listesinde "Sistem varsayılanı" + en az `/bin/zsh` ve `/bin/bash` görünür. "Seç…" düğmesi klasör seçme paneli açar (dosyalar seçilemez), seçilen yol satırda yazar.
3. Genel sekmesi: Scroll geçmişi alanına `5` yazıp Enter → alan `100` olur; `999999` yazıp Enter → alan `100000` olur.
4. Görünüm sekmesi: Tema seçicisinden `Nord`'u seç → önizleme kutusunun arka planı ve 16 swatch anında değişir, **ve arkadaki açık terminal penceresi de anında yeni tema renklerine geçer**.
5. Görünüm sekmesi: Boyut Stepper'ını 16'ya çıkar → terminaldeki yazı anında büyür. Satır aralığını 1.4'e çek → satırlar açılır. İmleç şeklini "Çubuk (sabit)" yap → imleç anında ince çubuğa döner.
6. Görünüm sekmesi: Saydamlık kaydırıcısını %70'e çek → terminal penceresi arkasındaki masaüstü/pencereler bulanık olarak görünür; %100'e geri al → pencere tekrar opak olur.
7. Ayarlar penceresini kapat, uygulamayı kapatıp yeniden aç → seçilen tema/font/saydamlık korunmuş olmalı.

- [ ] **Step 23: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora && git add -A && git commit -m "feat: add settings window with general and appearance tabs"
```

---

---

### Task 19: Profiller CRUD + profille yeni sekme (M4)

**Files:**
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Models/EnvironmentEntry.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Models/ResolvedAppearance.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Views/Settings/ProfileEnvironmentEditor.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Views/Settings/ProfileEditorView.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Views/Settings/ProfilesSettingsView.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/App/ProfileCommands.swift`
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/Services/SessionManager.swift`
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/Views/Settings/SettingsWindowView.swift`
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/App/TermoraApp.swift`
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/EnvironmentEditingTests.swift`
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/AppearanceResolverTests.swift`
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/WorkspaceProfileTests.swift`
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/ProfileLaunchMockSessionManager.swift` (test dosyaları `TermoraTests/` kökünde durur; `Support/` alt klasörü yoktur)

**Interfaces:**

*Consumes:*
- Task 4: `enum ShellService { static func availableShells() -> [ShellInfo] }`, `struct ShellInfo`
- Task 5: `final class ThemeStore { let themes: [Theme]; func theme(id: String) -> Theme }`, `extension Theme { func swiftTermAnsiColors() -> [SwiftTerm.Color]; var backgroundNSColor/foregroundNSColor/cursorNSColor: NSColor }`
- Task 6: `struct AppSettings`, `enum CursorStyleSetting { var swiftTermStyle: SwiftTerm.CursorStyle }`, `@MainActor @Observable final class SettingsStore { var settings: AppSettings }`
- Task 7: `struct TerminalProfile: Codable, Identifiable, Equatable { var id: UUID; var name: String; var shellPath: String?; var startupDirectory: String?; var startupCommand: String?; var fontName: String?; var fontSize: Double?; var themeID: String?; var environment: [String: String] }`, `@MainActor @Observable final class ProfileStore { init(defaults: UserDefaults = .standard); var profiles: [TerminalProfile] }`
- Task 8: `@MainActor @Observable final class SessionManager: SessionManaging, LocalProcessTerminalViewDelegate` — `init(settings: SettingsStore, themes: ThemeStore, profiles: ProfileStore, escalationDelay: TimeInterval = 1.5)`; depolanan özellikler `private let settings: SettingsStore`, `private let themes: ThemeStore`, `private let profiles: ProfileStore`, `private var sessions: [UUID: TerminalSession]`, `@ObservationIgnored private var views: [UUID: TermoraTerminalView]`; `func applyAppearanceToAllSessions()`, `applyAppearance(to view: TermoraTerminalView, sessionID: UUID)`. **`profiles` Task 8'de zaten enjekte edilmiştir — bu görev init imzasına DOKUNMAZ, yalnız kullanır.**
- Task 8: `@MainActor protocol SessionManaging: AnyObject { func createSession(profile: TerminalProfile?, workingDirectory: String?) -> TerminalSession; func session(id: UUID) -> TerminalSession?; func terminateSession(id: UUID); func hasRunningProcess(sessionID: UUID) -> Bool; func restartSession(id: UUID, forceDefaultShell: Bool) }` — **beş üyenin tamamı zorunludur; bu görevdeki test sahtesi hepsini gerçeklemelidir**, `@Observable final class TerminalSession: Identifiable { init(id: UUID = UUID(), shellPath: String, profileID: UUID? = nil, workingDirectory: String? = nil); var shellPath: String; var workingDirectory: String?; var title: String; var processState: ProcessState; var launchFailure: String?; var restartGeneration: Int }`
- Task 11: `@MainActor @Observable final class WorkspaceViewModel { init(sessionManager: any SessionManaging, settings: SettingsStore, profiles: ProfileStore); private(set) var tabs: [TerminalTab]; var activeTab: TerminalTab?; func newTab(profile: TerminalProfile? = nil) }`, `@Observable final class TerminalTab { var root: PaneNode; var activePaneID: UUID }`
- Task 13: `extension FocusedValues { var workspace: WorkspaceViewModel? { get set } }`
- Task 14: `indirect enum PaneNode { var leaves: [(paneID: UUID, sessionID: UUID)] { get } }`
- Task 18: `enum SettingsLimits`, `enum FontCatalog { @MainActor static func availableMonospacedFamilies() -> [String]; @MainActor static func resolvedFont(name: String?, size: Double) -> NSFont }` (Task 18 Step 20 `SessionManager`'ın font çözümünü zaten buna bağladı), `extension CursorStyleSetting { var displayName: String }`, `struct SettingsWindowView { let settings: SettingsStore; let themes: ThemeStore; let profiles: ProfileStore }`
- Task 12/13: `struct TermoraApp: App` içinde `@State private var services = AppServices()` (bilerek `@State`; `let` olursa açık oturumlar kaybolur — Task 10 Step 8 / Task 12 Step 8) — servislere `services.settings`, `services.themes`, `services.profiles`, `services.sessionManager` ile erişilir; `TermoraApp` kapsamında çıplak `profiles` adı YOKTUR

*Produces:*
- `struct EnvironmentEntry: Identifiable, Equatable { let id: UUID; var key: String; var value: String; init(id: UUID = UUID(), key: String, value: String) }`
- `enum EnvironmentEditing { static func entries(from dictionary: [String: String]) -> [EnvironmentEntry]; static func dictionary(from entries: [EnvironmentEntry]) -> [String: String] }`
- `struct ResolvedAppearance: Equatable { let fontName: String?; let fontSize: Double; let themeID: String }`
- `enum AppearanceResolver { static func resolve(settings: AppSettings, profile: TerminalProfile?) -> ResolvedAppearance }`
- `extension SessionManager { func applyAppearance(to view: TermoraTerminalView, sessionID: UUID) }` (SessionManager gövdesine yazılır, extension değil)
- `struct ProfileEnvironmentEditor: View { @Binding var environment: [String: String] }`
- `struct ProfileEditorView: View { @Binding var profile: TerminalProfile; let shells: [ShellInfo]; let themes: ThemeStore; let fontFamilies: [String] }`
- `struct ProfilesSettingsView: View { @Bindable var profiles: ProfileStore; let themes: ThemeStore }`
- `struct ProfileCommands: Commands { let profiles: ProfileStore }`

---

- [ ] **Step 1: `EnvironmentEditingTests.swift` dosyasını yaz (RED)**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/EnvironmentEditingTests.swift`:

```swift
import Testing
@testable import Termora

@Suite("Profil ortam değişkeni düzenleme")
struct EnvironmentEditingTests {

    @Test func entriesAreSortedByKey() {
        let entries = EnvironmentEditing.entries(from: ["ZED": "1", "ALPHA": "2", "MID": "3"])
        #expect(entries.map(\.key) == ["ALPHA", "MID", "ZED"])
        #expect(entries.map(\.value) == ["2", "3", "1"])
    }

    @Test func entriesGetDistinctIdentities() {
        let entries = EnvironmentEditing.entries(from: ["A": "x", "B": "x"])
        #expect(Set(entries.map(\.id)).count == 2)
    }

    @Test func blankKeysAreDropped() {
        let entries = [
            EnvironmentEntry(key: "   ", value: "atılacak"),
            EnvironmentEntry(key: "", value: "bu da"),
            EnvironmentEntry(key: "EDITOR", value: "vim")
        ]
        #expect(EnvironmentEditing.dictionary(from: entries) == ["EDITOR": "vim"])
    }

    @Test func keysAreTrimmedAndLastDuplicateWins() {
        let entries = [
            EnvironmentEntry(key: " EDITOR ", value: "vi"),
            EnvironmentEntry(key: "EDITOR", value: "nvim")
        ]
        #expect(EnvironmentEditing.dictionary(from: entries) == ["EDITOR": "nvim"])
    }

    @Test func emptyValuesArePreserved() {
        let entries = [EnvironmentEntry(key: "NO_COLOR", value: "")]
        #expect(EnvironmentEditing.dictionary(from: entries) == ["NO_COLOR": ""])
    }

    @Test func roundTripPreservesPairs() {
        let original = ["A": "1", "B": "2", "C": "3"]
        let roundTripped = EnvironmentEditing.dictionary(from: EnvironmentEditing.entries(from: original))
        #expect(roundTripped == original)
    }
}
```

- [ ] **Step 2: Testi çalıştır, FAIL bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/EnvironmentEditingTests 2>&1 | tail -20
```

Beklenen: `error: cannot find 'EnvironmentEditing' in scope` ve `error: cannot find 'EnvironmentEntry' in scope`, son satırda `** TEST FAILED **`.

- [ ] **Step 3: `EnvironmentEntry.swift` dosyasını yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Models/EnvironmentEntry.swift`:

```swift
import Foundation

/// `TerminalProfile.environment` sözlüğünün UI'da sıralı ve düzenlenebilir hâli.
/// Sözlük sırasız olduğu için satırların kararlı kimliğe ihtiyacı vardır.
struct EnvironmentEntry: Identifiable, Equatable {
    let id: UUID
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}

enum EnvironmentEditing {

    /// Sözlüğü anahtara göre sıralı satır listesine çevirir.
    static func entries(from dictionary: [String: String]) -> [EnvironmentEntry] {
        dictionary.keys.sorted().map { key in
            EnvironmentEntry(key: key, value: dictionary[key] ?? "")
        }
    }

    /// Satırları sözlüğe çevirir: anahtarlar kırpılır, boş anahtarlı satırlar atılır,
    /// aynı anahtar birden çok kez varsa son satır kazanır.
    static func dictionary(from entries: [EnvironmentEntry]) -> [String: String] {
        var result: [String: String] = [:]
        for entry in entries {
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            result[key] = entry.value
        }
        return result
    }
}
```

- [ ] **Step 4: Testi çalıştır, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/EnvironmentEditingTests 2>&1 | tail -20
```

Beklenen: `Suite "Profil ortam değişkeni düzenleme" passed after ... seconds.` ve `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora && git add -A && git commit -m "feat: add EnvironmentEditing model for profile env editor"
```

- [ ] **Step 6: `AppearanceResolverTests.swift` dosyasını yaz (RED)**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/AppearanceResolverTests.swift`:

```swift
import Testing
@testable import Termora

@Suite("Profil görünüm çözümlemesi")
struct AppearanceResolverTests {

    private func baseSettings() -> AppSettings {
        var settings = AppSettings()
        settings.fontName = "Menlo"
        settings.fontSize = 13
        settings.themeID = "termora-dark"
        return settings
    }

    @Test func noProfileUsesGlobalSettings() {
        let resolved = AppearanceResolver.resolve(settings: baseSettings(), profile: nil)
        #expect(resolved == ResolvedAppearance(fontName: "Menlo", fontSize: 13, themeID: "termora-dark"))
    }

    @Test func profileOverridesWinOverGlobalSettings() {
        let profile = TerminalProfile(
            name: "Ops",
            fontName: "SF Mono",
            fontSize: 15,
            themeID: "nord"
        )
        let resolved = AppearanceResolver.resolve(settings: baseSettings(), profile: profile)
        #expect(resolved.fontName == "SF Mono")
        #expect(resolved.fontSize == 15)
        #expect(resolved.themeID == "nord")
    }

    @Test func nilProfileFieldsFallBackToSettingsIndividually() {
        let profile = TerminalProfile(name: "Sadece tema", themeID: "dracula")
        let resolved = AppearanceResolver.resolve(settings: baseSettings(), profile: profile)
        #expect(resolved.fontName == "Menlo")
        #expect(resolved.fontSize == 13)
        #expect(resolved.themeID == "dracula")
    }

    @Test func resolvedFontSizeIsClamped() {
        let profile = TerminalProfile(name: "Devasa", fontSize: 400)
        let resolved = AppearanceResolver.resolve(settings: baseSettings(), profile: profile)
        #expect(resolved.fontSize == SettingsLimits.fontSizeRange.upperBound)

        var tiny = baseSettings()
        tiny.fontSize = 1
        #expect(AppearanceResolver.resolve(settings: tiny, profile: nil).fontSize == SettingsLimits.fontSizeRange.lowerBound)
    }
}
```

- [ ] **Step 7: Testi çalıştır, FAIL bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/AppearanceResolverTests 2>&1 | tail -20
```

Beklenen: `error: cannot find 'AppearanceResolver' in scope` ve `error: cannot find 'ResolvedAppearance' in scope`, son satırda `** TEST FAILED **`.

- [ ] **Step 8: `ResolvedAppearance.swift` dosyasını yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Models/ResolvedAppearance.swift`:

```swift
import Foundation

/// Bir oturuma uygulanacak nihai görünüm: profil override'ları + genel ayarlar birleştirilmiş hâli.
struct ResolvedAppearance: Equatable {
    let fontName: String?
    let fontSize: Double
    let themeID: String
}

enum AppearanceResolver {

    /// Alan bazında çözümleme: profilde dolu olan her alan genel ayarı geçersiz kılar,
    /// nil olan alanlar genel ayardan gelir. Font boyutu her hâlde sınırlara kırpılır.
    static func resolve(settings: AppSettings, profile: TerminalProfile?) -> ResolvedAppearance {
        ResolvedAppearance(
            fontName: profile?.fontName ?? settings.fontName,
            fontSize: SettingsLimits.clampFontSize(profile?.fontSize ?? settings.fontSize),
            themeID: profile?.themeID ?? settings.themeID
        )
    }
}
```

- [ ] **Step 9: Testi çalıştır, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/AppearanceResolverTests 2>&1 | tail -20
```

Beklenen: `Suite "Profil görünüm çözümlemesi" passed after ... seconds.` ve `** TEST SUCCEEDED **`.

- [ ] **Step 10: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora && git add -A && git commit -m "feat: resolve terminal appearance with profile overrides"
```

- [ ] **Step 11: `SessionManager`'ın görünüm uygulama bölümünü resolver'a bağla**

`/Users/ahmetbarut/Apps/Termora/Termora/Services/SessionManager.swift` içinde YALNIZ İKİ METOT değiştirilir: `func applyAppearanceToAllSessions()` ve `applyAppearance(to:sessionID:)` (Task 18 Step 20'den sonraki hâlleriyle). Bunların yerine aşağıdaki blok yazılır ve sonuna `private func profile(forSession:)` eklenir.

> **DİKKAT — bölümün tamamını silme.** Aynı `// MARK: - Appearance` bölümünde `static func workingDirectory(fromHostReport:)` ve `private func resolveShellPath(profile:)` metotları da durur; bunlar OLDUĞU GİBİ KALIR. Silinirlerse `hostCurrentDirectoryUpdate`, `createSession`, `restartSession` çağrıları ve `SessionManagerTests`'in `hostDirectoryReportsAreParsedIntoPlainPaths` / `unusableHostDirectoryReportsAreIgnored` testleri derlenmez. (`static func resolveFont(name:size:)` zaten Task 18 Step 20(b)'de silinmiştir; dosyanın kalanına dokunulmaz.)

Bu adım **yalnız görünüm çözümünü** profil farkındalığına taşır:

- `init` imzasına DOKUNULMAZ — `profiles: ProfileStore` Task 8'de zaten enjekte edilmiş ve `private let profiles` olarak saklanmıştır; çağrı yerleri (AppServices, testler) değişmez.
- Metot adı Task 8'deki `applyAppearance(to:sessionID:)` ile aynı kalır, bu yüzden `createSession` içindeki çağrı olduğu gibi çalışır.
- View cache'inin adı Task 8'deki gibi `views`'tir (`terminalViews` DEĞİL).

Önce seçim rengi erişimcisinin ve SwiftTerm özelliğinin varlığını doğrula:

```bash
cd /Users/ahmetbarut/Apps/Termora && grep -n "selectionNSColor" Termora/Models/Theme.swift; grep -rn "var selectedTextBackgroundColor" ~/Library/Developer/Xcode/DerivedData/*/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Apple/AppleTerminalView.swift
```

İkisinden biri bulunamazsa aşağıdaki `view.selectedTextBackgroundColor = ...` satırı çıkarılır (tema `selection` alanı MVP'de uygulanmamış sayılır); diğer satırlar aynen kalır.

```swift
    // MARK: - Appearance
    // Bu MARK satırı Task 8'deki gibi kalır. Aşağıdaki iki metot mevcutlarının YERİNE geçer;
    // aynı bölümdeki `workingDirectory(fromHostReport:)` ve `resolveShellPath(profile:)` durur.

    func applyAppearanceToAllSessions() {
        for (sessionID, view) in views {
            applyAppearance(to: view, sessionID: sessionID)
        }
    }

    /// Tek bir terminale görünümü uygular. Oturumun profili varsa font/tema
    /// çözümünde profil önceliklidir; satır aralığı, imleç ve scrollback geneldir.
    func applyAppearance(to view: TermoraTerminalView, sessionID: UUID) {
        let appSettings = settings.settings
        let resolved = AppearanceResolver.resolve(settings: appSettings, profile: profile(forSession: sessionID))
        let theme = themes.theme(id: resolved.themeID)
        let opacity = SettingsLimits.clampOpacity(appSettings.windowOpacity)

        view.font = FontCatalog.resolvedFont(name: resolved.fontName, size: resolved.fontSize)
        view.lineSpacing = CGFloat(SettingsLimits.clampLineSpacing(appSettings.lineSpacing))
        view.nativeBackgroundColor = theme.backgroundNSColor.withAlphaComponent(CGFloat(opacity))
        view.nativeForegroundColor = theme.foregroundNSColor
        view.caretColor = theme.cursorNSColor
        view.selectedTextBackgroundColor = theme.selectionNSColor
        view.installColors(theme.swiftTermAnsiColors())

        // `TerminalView.changeScrollback` scroller'ı da günceller; `Terminal.changeScrollback` güncellemez.
        view.changeScrollback(SettingsLimits.clampScrollback(appSettings.scrollbackLines))
        view.getTerminal().setCursorStyle(appSettings.cursorStyle.swiftTermStyle)
    }

    private func profile(forSession sessionID: UUID) -> TerminalProfile? {
        guard let profileID = sessions[sessionID]?.profileID else { return nil }
        return profiles.profiles.first { $0.id == profileID }
    }
```

Derle:

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet
```

Beklenen: çıktı yok, çıkış kodu 0.

Regresyon kontrolü (Task 8 oturum testleri hâlâ geçmeli):

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/SessionManagerTests 2>&1 | tail -20
```

Beklenen: `** TEST SUCCEEDED **`.

- [ ] **Step 12: `WorkspaceProfileTests.swift` dosyasını yaz (RED — mock henüz yok)**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/WorkspaceProfileTests.swift`:

```swift
import Foundation
import Testing
@testable import Termora

@Suite("Profille yeni sekme")
@MainActor
struct WorkspaceProfileTests {

    private func makeWorkspace() -> (WorkspaceViewModel, ProfileLaunchMockSessionManager, ProfileStore) {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let settingsStore = SettingsStore(defaults: defaults)
        let profileStore = ProfileStore(defaults: defaults)
        let mock = ProfileLaunchMockSessionManager()
        let workspace = WorkspaceViewModel(
            sessionManager: mock,
            settings: settingsStore,
            profiles: profileStore
        )
        return (workspace, mock, profileStore)
    }

    @Test func newTabWithProfileForwardsProfileToSessionManager() {
        let (workspace, mock, _) = makeWorkspace()
        let profile = TerminalProfile(
            name: "Fish",
            shellPath: "/opt/homebrew/bin/fish",
            startupDirectory: "/tmp"
        )

        workspace.newTab(profile: profile)

        #expect(mock.createCalls.count == 1)
        #expect(mock.createCalls.last?.profile?.id == profile.id)
        #expect(mock.createCalls.last?.profile?.shellPath == "/opt/homebrew/bin/fish")
    }

    @Test func newTabWithProfileCreatesSessionWithProfileShellAndDirectory() throws {
        let (workspace, mock, _) = makeWorkspace()
        let profile = TerminalProfile(
            name: "Fish",
            shellPath: "/opt/homebrew/bin/fish",
            startupDirectory: "/tmp"
        )

        workspace.newTab(profile: profile)

        let tab = try #require(workspace.activeTab)
        let leaves = tab.root.leaves
        #expect(leaves.count == 1)
        let session = try #require(mock.session(id: leaves[0].sessionID))
        #expect(session.shellPath == "/opt/homebrew/bin/fish")
        #expect(session.workingDirectory == "/tmp")
        #expect(session.profileID == profile.id)
    }

    @Test func newTabWithoutProfileUsesDefaultShell() throws {
        let (workspace, mock, _) = makeWorkspace()

        workspace.newTab()

        #expect(mock.createCalls.count == 1)
        #expect(mock.createCalls.last?.profile == nil)
        let tab = try #require(workspace.activeTab)
        let session = try #require(mock.session(id: tab.root.leaves[0].sessionID))
        #expect(session.shellPath == mock.defaultShellPath)
        #expect(session.profileID == nil)
    }

    @Test func eachProfileTabGetsItsOwnSession() {
        let (workspace, mock, _) = makeWorkspace()
        let profile = TerminalProfile(name: "Fish", shellPath: "/opt/homebrew/bin/fish")

        workspace.newTab(profile: profile)
        workspace.newTab(profile: profile)

        #expect(mock.createCalls.count == 2)
        #expect(workspace.tabs.count == 2)
        let sessionIDs = workspace.tabs.flatMap { $0.root.leaves.map(\.sessionID) }
        #expect(Set(sessionIDs).count == 2)
    }
}
```

- [ ] **Step 13: Testi çalıştır, FAIL bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/WorkspaceProfileTests 2>&1 | tail -20
```

Beklenen: `error: cannot find 'ProfileLaunchMockSessionManager' in scope` ve `** TEST FAILED **`.

- [ ] **Step 14: `ProfileLaunchMockSessionManager.swift` dosyasını yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/ProfileLaunchMockSessionManager.swift`:

```swift
import Foundation
@testable import Termora

/// `SessionManaging`'in kayıt tutan sahtesi: gerçek PTY açmadan
/// `createSession` çağrılarının argümanlarını doğrulamayı sağlar.
///
/// Task 11'in `MockSessionManager`'ından ayrı durur çünkü burada gereken iki şeyi
/// modeller: çağrı argümanlarını ÇİFT olarak saklamak ve gerçek `SessionManager`'ın
/// `workingDirectory ?? profile?.startupDirectory` geri düşme zincirini taklit etmek.
/// Ortak üye adları (`defaultShellPath`, `busySessionIDs`, `terminatedSessionIDs`)
/// bilerek `MockSessionManager` ile aynı tutulur.
@MainActor
final class ProfileLaunchMockSessionManager: SessionManaging {

    struct CreateCall: Equatable {
        let profile: TerminalProfile?
        let workingDirectory: String?
    }

    private(set) var createCalls: [CreateCall] = []
    private(set) var terminatedSessionIDs: [UUID] = []
    private var sessionsByID: [UUID: TerminalSession] = [:]

    /// Profil kabuk belirtmediğinde kullanılacak yol (gerçek `SessionManager`'daki
    /// "profil → ayar → ShellService.defaultShellPath" zincirinin sahte karşılığı).
    var defaultShellPath = "/bin/zsh"

    /// Bu kümedeki oturumlar "çalışan işlem var" olarak raporlanır.
    var busySessionIDs: Set<UUID> = []

    func createSession(profile: TerminalProfile?, workingDirectory: String?) -> TerminalSession {
        createCalls.append(CreateCall(profile: profile, workingDirectory: workingDirectory))
        let session = TerminalSession(
            shellPath: profile?.shellPath ?? defaultShellPath,
            profileID: profile?.id,
            workingDirectory: workingDirectory ?? profile?.startupDirectory
        )
        sessionsByID[session.id] = session
        return session
    }

    func session(id: UUID) -> TerminalSession? {
        sessionsByID[id]
    }

    func terminateSession(id: UUID) {
        terminatedSessionIDs.append(id)
        sessionsByID[id] = nil
        busySessionIDs.remove(id)
    }

    func hasRunningProcess(sessionID: UUID) -> Bool {
        busySessionIDs.contains(sessionID)
    }

    /// `SessionManaging`'in beşinci üyesi (Task 8). Profil süiti yeniden başlatmayı test
    /// etmez ama protokol zorunlu kıldığı için burada da bulunmalı — yoksa
    /// `error: type 'ProfileLaunchMockSessionManager' does not conform to protocol 'SessionManaging'`
    /// ile TÜM test hedefi derlenmez. Gerçek `SessionManager` gibi AYNI oturum nesnesini
    /// korur, yalnız alanlarını tazeler.
    private(set) var restartedSessionIDs: [UUID] = []

    func restartSession(id: UUID, forceDefaultShell: Bool) {
        restartedSessionIDs.append(id)
        busySessionIDs.remove(id)
        guard let session = sessionsByID[id] else { return }
        if forceDefaultShell { session.shellPath = defaultShellPath }
        session.launchFailure = nil
        session.processState = .running
        session.restartGeneration += 1
    }
}
```

- [ ] **Step 15: Testi çalıştır, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/WorkspaceProfileTests 2>&1 | tail -20
```

Beklenen: `Suite "Profille yeni sekme" passed after ... seconds.` ve `** TEST SUCCEEDED **`.

- [ ] **Step 16: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora && git add -A && git commit -m "test: verify newTab(profile:) forwards profile to session manager"
```

- [ ] **Step 17: `ProfileEnvironmentEditor.swift` dosyasını yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Views/Settings/ProfileEnvironmentEditor.swift`:

```swift
import SwiftUI

/// Profilin ek ortam değişkenlerini iki kolonlu satırlar hâlinde düzenler.
/// Üst görünüm bu editöre `.id(profile.id)` verir; profil değişince satırlar sıfırdan yüklenir.
struct ProfileEnvironmentEditor: View {
    @Binding var environment: [String: String]

    @State private var entries: [EnvironmentEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Anahtar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 150, alignment: .leading)
                Text("Değer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if entries.isEmpty {
                Text("Bu profil için ek ortam değişkeni yok.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach($entries) { $entry in
                HStack(spacing: 8) {
                    TextField("KEY", text: $entry.key)
                        .frame(width: 150)
                    TextField("value", text: $entry.value)
                    Button {
                        remove(id: entry.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Bu değişkeni sil")
                }
            }

            HStack {
                Button {
                    entries.append(EnvironmentEntry(key: "", value: ""))
                } label: {
                    Label("Değişken ekle", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
            }

            Text("⚠️ Hassas değerleri (API anahtarı, parola) buraya koymayın — profiller UserDefaults'a düz metin olarak yazılır.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            entries = EnvironmentEditing.entries(from: environment)
        }
        .onChange(of: entries) { _, newValue in
            environment = EnvironmentEditing.dictionary(from: newValue)
        }
    }

    private func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }
}
```

Derle:

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet
```

Beklenen: çıktı yok, çıkış kodu 0.

- [ ] **Step 18: `ProfileEditorView.swift` dosyasını yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Views/Settings/ProfileEditorView.swift`:

```swift
import AppKit
import SwiftUI

struct ProfileEditorView: View {
    @Binding var profile: TerminalProfile
    let shells: [ShellInfo]
    let themes: ThemeStore
    let fontFamilies: [String]

    var body: some View {
        Form {
            Section("Kimlik") {
                TextField("Ad", text: $profile.name)
            }

            Section("Başlatma") {
                Picker("Kabuk", selection: $profile.shellPath) {
                    Text("Genel ayarı kullan").tag(nil as String?)
                    ForEach(shells) { shell in
                        Text(shell.displayName).tag(shell.path as String?)
                    }
                }

                HStack(spacing: 8) {
                    Text("Başlangıç klasörü")
                    Spacer()
                    Text(profile.startupDirectory ?? "Genel ayarı kullan")
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.secondary)
                    Button("Seç…") { chooseStartupDirectory() }
                    Button("Temizle") { profile.startupDirectory = nil }
                        .disabled(profile.startupDirectory == nil)
                }

                TextField(
                    "Başlangıç komutu",
                    text: startupCommandBinding,
                    prompt: Text("örn. tmux attach")
                )
            }

            Section("Görünüm geçersiz kılmaları") {
                Picker("Yazı tipi", selection: $profile.fontName) {
                    Text("Genel ayarı kullan").tag(nil as String?)
                    ForEach(fontFamilies, id: \.self) { family in
                        Text(family).tag(family as String?)
                    }
                }

                HStack(spacing: 8) {
                    Text("Yazı boyutu")
                    Spacer()
                    Text(profile.fontSize.map { "\(Int($0)) pt" } ?? "Genel ayar")
                        .foregroundStyle(.secondary)
                    Stepper("", value: fontSizeBinding, in: SettingsLimits.fontSizeRange, step: 1)
                        .labelsHidden()
                    Button("Temizle") { profile.fontSize = nil }
                        .disabled(profile.fontSize == nil)
                }

                Picker("Tema", selection: $profile.themeID) {
                    Text("Genel ayarı kullan").tag(nil as String?)
                    ForEach(themes.themes) { theme in
                        Text(theme.name).tag(theme.id as String?)
                    }
                }
            }

            Section("Ortam değişkenleri") {
                ProfileEnvironmentEditor(environment: $profile.environment)
                    .id(profile.id)
            }
        }
        .formStyle(.grouped)
    }

    private var startupCommandBinding: Binding<String> {
        Binding(
            get: { profile.startupCommand ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                profile.startupCommand = trimmed.isEmpty ? nil : newValue
            }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { profile.fontSize ?? SettingsLimits.defaultFontSize },
            set: { profile.fontSize = SettingsLimits.clampFontSize($0) }
        )
    }

    private func chooseStartupDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Seç"
        panel.message = "Bu profille açılan terminallerin başlangıç klasörünü seçin."
        if let current = profile.startupDirectory {
            panel.directoryURL = URL(fileURLWithPath: current)
        }
        if panel.runModal() == .OK, let url = panel.url {
            profile.startupDirectory = url.path
        }
    }
}
```

Derle:

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet
```

Beklenen: çıktı yok, çıkış kodu 0.

- [ ] **Step 19: `ProfilesSettingsView.swift` dosyasını yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Views/Settings/ProfilesSettingsView.swift`:

```swift
import SwiftUI

struct ProfilesSettingsView: View {
    @Bindable var profiles: ProfileStore
    let themes: ThemeStore

    @State private var selection: UUID?
    @State private var shells: [ShellInfo] = []
    @State private var fontFamilies: [String] = []

    /// `selection` geçersizleştiğinde okunan kararlı yer tutucu (yeni UUID üretmez).
    private static let placeholder = TerminalProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
        name: ""
    )

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(profiles.profiles) { profile in
                        Text(profile.name.isEmpty ? "Adsız profil" : profile.name)
                            .tag(profile.id)
                    }
                }

                Divider()

                HStack(spacing: 4) {
                    Button {
                        addProfile()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Yeni profil ekle")

                    Button {
                        removeSelectedProfile()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .help("Seçili profili sil")
                    .disabled(selection == nil)

                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 180)

            Divider()

            Group {
                if let editorBinding {
                    ProfileEditorView(
                        profile: editorBinding,
                        shells: shells,
                        themes: themes,
                        fontFamilies: fontFamilies
                    )
                } else {
                    VStack(spacing: 6) {
                        Text("Profil seçilmedi")
                            .font(.headline)
                        Text("Soldaki listeden bir profil seçin veya + ile yeni profil ekleyin.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            shells = ShellService.availableShells()
            fontFamilies = FontCatalog.availableMonospacedFamilies()
            if selection == nil {
                selection = profiles.profiles.first?.id
            }
        }
    }

    /// Kimlik üzerinden yazan binding: silme sonrası bayat indeks kullanılmaz.
    private var editorBinding: Binding<TerminalProfile>? {
        guard let id = selection, profiles.profiles.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { profiles.profiles.first { $0.id == id } ?? Self.placeholder },
            set: { newValue in
                guard let index = profiles.profiles.firstIndex(where: { $0.id == id }) else { return }
                profiles.profiles[index] = newValue
            }
        )
    }

    private func addProfile() {
        let profile = TerminalProfile(name: "Yeni Profil")
        profiles.profiles.append(profile)
        selection = profile.id
    }

    private func removeSelectedProfile() {
        guard let id = selection else { return }
        profiles.profiles.removeAll { $0.id == id }
        selection = profiles.profiles.first?.id
    }
}
```

Derle:

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet
```

Beklenen: çıktı yok, çıkış kodu 0.

- [ ] **Step 20: `SettingsWindowView`'a Profiller sekmesini ekle**

`/Users/ahmetbarut/Apps/Termora/Termora/Views/Settings/SettingsWindowView.swift` içindeki `TabView` bloğuna, `AppearanceSettingsView` satırından sonra eklenir:

```swift
            ProfilesSettingsView(profiles: profiles, themes: themes)
                .tabItem { Label("Profiller", systemImage: "person.crop.rectangle.stack") }
```

Derle:

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet
```

Beklenen: çıktı yok, çıkış kodu 0.

**Elle doğrulama** — ⌘R ile çalıştır, ⌘, ile Ayarlar'ı aç, **Profiller** sekmesine geç:
1. `+` düğmesine bas → solda "Yeni Profil" satırı belirir ve seçili olur, sağda form açılır.
2. Ad alanına `Fish` yaz → sol listedeki satır adı anında güncellenir.
3. Kabuk seçicisinden bir kabuk seç, "Seç…" ile `/tmp` klasörünü seç, başlangıç komutuna `echo hazir` yaz.
4. Ortam değişkenleri bölümünde "Değişken ekle" → satır belirir; anahtar `EDITOR`, değer `vim` yaz. Eksi düğmesiyle sil → satır kaybolur. Uyarı metni ("⚠️ Hassas değerleri…") görünür durumdadır.
5. Uygulamayı kapat, yeniden aç, Ayarlar > Profiller → profil ve tüm alanları korunmuş olmalı.
6. `-` düğmesiyle profili sil → liste boşalır, sağda "Profil seçilmedi" görünür (çökme olmamalı).

- [ ] **Step 21: `ProfileCommands.swift` dosyasını yaz ve `TermoraApp`'e bağla**

`/Users/ahmetbarut/Apps/Termora/Termora/App/ProfileCommands.swift`:

```swift
import SwiftUI

/// File menüsüne "Profille Yeni Sekme" alt menüsünü ekler.
/// Hedef pencere, `@FocusedValue(\.workspace)` ile key window'un view model'idir.
struct ProfileCommands: Commands {
    let profiles: ProfileStore

    @FocusedValue(\.workspace) private var workspace

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Menu("Profille Yeni Sekme") {
                ForEach(profiles.profiles) { profile in
                    Button(profile.name.isEmpty ? "Adsız profil" : profile.name) {
                        workspace?.newTab(profile: profile)
                    }
                }
            }
            .disabled(workspace == nil || profiles.profiles.isEmpty)
        }
    }
}
```

`/Users/ahmetbarut/Apps/Termora/Termora/App/TermoraApp.swift` içinde `WindowGroup`'a bağlı `.commands { ... }` bloğunun içine, Task 13'te eklenen `AppCommands()` satırının hemen ardına eklenir (`TermoraApp`'in tek özelliği `services` olduğu için profil deposuna `services.profiles` ile erişilir):

```swift
            ProfileCommands(profiles: services.profiles)
```

Derle:

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet
```

Beklenen: çıktı yok, çıkış kodu 0.

**Elle doğrulama** — ⌘R ile çalıştır:
1. Ayarlar > Profiller'de `Fish` adında, kabuğu `/bin/bash`, başlangıç klasörü `/tmp`, başlangıç komutu `echo hazir`, ortam değişkeni `TERMORA_TEST=1` olan bir profil oluştur; Ayarlar'ı kapat.
2. `File` menüsünü aç → "Profille Yeni Sekme" alt menüsünde `Fish` görünür.
3. `Fish`'e tıkla → yeni sekme açılır; terminalde `echo hazir` çalışmış ve `hazir` yazmıştır.
4. Yeni sekmede `pwd` çalıştır → `/tmp` yazmalı. `echo $TERMORA_TEST` → `1` yazmalı. `echo $0` → login shell (`-bash`) olmalı.
5. Profile bir tema override'ı ver (Ayarlar > Profiller > Tema: `Dracula`), Ayarlar'ı kapat, Görünüm sekmesinden genel temayı `Termora Light` yap → profille açılan sekme Dracula renklerinde kalır, diğer sekmeler Termora Light olur.
6. Hiç profil yokken `File` menüsü → "Profille Yeni Sekme" alt menüsü soluk (disabled) görünür.

- [ ] **Step 22: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora && git add -A && git commit -m "feat: add profile CRUD settings tab and new-tab-with-profile menu"
```

---

---

### Task 20: Arama çubuğu (M5)

**Files:**
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Models/SearchSummary.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Services/TerminalSearchRunner.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Views/SearchBarView.swift`
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/Models/TerminalTab.swift`
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/ViewModels/WorkspaceViewModel.swift`
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/Views/MainWindowView.swift`
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/App/AppCommands.swift`
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/SearchSummaryTests.swift`
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/WorkspaceSearchTests.swift`

**Interfaces:**

Consumes:
- `TerminalTab` (Task 11): `@Observable final class TerminalTab: Identifiable`, `var isSearchVisible: Bool`, `var root: PaneNode`, `var activePaneID: UUID`
- `PaneNode.sessionID(ofPane paneID: UUID) -> UUID?` (Task 14)
- `WorkspaceViewModel` (Task 11/16): `var activeTab: TerminalTab? { get }`, `private let sessionManager: any SessionManaging` (Task 11'de bu adla saklandı), `func newTab(profile: TerminalProfile? = nil)`
- `SessionManager` (Task 8): `func terminalView(for sessionID: UUID) -> TermoraTerminalView?`
- `SessionManaging` (Task 8): `func createSession(profile:workingDirectory:) -> TerminalSession`, `func session(id:) -> TerminalSession?`, `func terminateSession(id:)`, `func hasRunningProcess(sessionID:) -> Bool`, `func restartSession(id: UUID, forceDefaultShell: Bool)` — **beş üyenin tamamı zorunludur; Step 11'deki stub hepsini gerçeklemelidir**
- `MainWindowView` (M2 görevi), `AppCommands` + `@FocusedValue(\.workspace)` (Task 13)
- SwiftTerm: `TerminalView.findNext(_:options:scrollToResult:) -> Bool`, `findPrevious(_:options:scrollToResult:) -> Bool`, `searchMatchSummary(_:options:limit:) -> (index: Int, total: Int)`, `clearSearch()`, `SearchOptions(caseSensitive:regex:wholeWord:)` — **bu beş sembol planın "Ek: Kaynak Kodda Doğrulanmış SwiftTerm Sembolleri" listesinde YOK; imzaları Step 13'ün başındaki doğrulama alt adımında kaynaktan okunur ve gerekiyorsa kod ona uydurulur.**

Produces:
```swift
struct SearchSummary: Equatable { var index: Int; var total: Int; static let empty: SearchSummary }
enum SearchSummaryFormatter { static func text(_ summary: SearchSummary) -> String }
struct TerminalSearchQuery: Equatable { var term: String; var caseSensitive: Bool; var usesRegex: Bool; var wholeWord: Bool
                                        init(term: String, caseSensitive: Bool = false, usesRegex: Bool = false, wholeWord: Bool = false) }
@MainActor protocol TerminalSearchRunner: AnyObject {
    func findNext(sessionID: UUID, query: TerminalSearchQuery) -> Bool
    func findPrevious(sessionID: UUID, query: TerminalSearchQuery) -> Bool
    func matchSummary(sessionID: UUID, query: TerminalSearchQuery) -> SearchSummary
    func clearSearch(sessionID: UUID)
    func focusTerminal(sessionID: UUID)
}
extension SessionManager: TerminalSearchRunner {}
// TerminalTab'e eklenir: var searchQuery: TerminalSearchQuery; var searchSummary: SearchSummary
// WorkspaceViewModel'e eklenir:
//   func toggleSearchBar(); func closeSearch(); func refreshSearchSummary(); func findNextMatch(); func findPreviousMatch()
struct SearchBarView: View { init(tab: TerminalTab, workspace: WorkspaceViewModel) }
// AppCommands: ⌘F toggleSearchBar, ⌘G findNextMatch, ⌘⇧G findPreviousMatch
```

- [ ] **Step 1: Sayaç biçimleme testini yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/SearchSummaryTests.swift` oluştur:

```swift
import Testing
@testable import Termora

@Suite("SearchSummaryFormatter")
@MainActor
struct SearchSummaryFormatterTests {

    @Test func formatsActiveMatchOverTotal() {
        #expect(SearchSummaryFormatter.text(SearchSummary(index: 2, total: 14)) == "2/14")
        #expect(SearchSummaryFormatter.text(SearchSummary(index: 1, total: 1)) == "1/1")
    }

    @Test func formatsNoMatchesAsZeroZero() {
        #expect(SearchSummaryFormatter.text(SearchSummary(index: 0, total: 0)) == "0/0")
        #expect(SearchSummaryFormatter.text(.empty) == "0/0")
    }

    @Test func showsZeroIndexWhenThereIsNoActiveMatch() {
        // SwiftTerm searchMatchSummary, aktif eşleşme yoksa (0, total) döner.
        #expect(SearchSummaryFormatter.text(SearchSummary(index: 0, total: 14)) == "0/14")
    }

    @Test func clampsOutOfRangeIndex() {
        #expect(SearchSummaryFormatter.text(SearchSummary(index: -3, total: 5)) == "0/5")
        #expect(SearchSummaryFormatter.text(SearchSummary(index: 9, total: 5)) == "5/5")
    }
}
```

- [ ] **Step 2: Testi çalıştır, FAIL bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/SearchSummaryFormatterTests 2>&1 | tail -20
```

Beklenen: derleme hatası — `error: cannot find 'SearchSummaryFormatter' in scope` ve `error: cannot find 'SearchSummary' in scope`, ardından `** TEST FAILED **`.

- [ ] **Step 3: SearchSummary + formatter'ı yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Models/SearchSummary.swift`:

```swift
import Foundation

/// SwiftTerm `searchMatchSummary` çıktısının uygulama içi karşılığı.
/// `index` 1 tabanlıdır; aktif eşleşme yoksa 0'dır.
struct SearchSummary: Equatable {
    var index: Int
    var total: Int

    static let empty = SearchSummary(index: 0, total: 0)
}

/// Arama çubuğundaki "2/14" sayacını üretir.
enum SearchSummaryFormatter {
    static func text(_ summary: SearchSummary) -> String {
        guard summary.total > 0 else { return "0/0" }
        let index = min(max(summary.index, 0), summary.total)
        return "\(index)/\(summary.total)"
    }
}
```

- [ ] **Step 4: Testi çalıştır, PASS bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/SearchSummaryFormatterTests 2>&1 | tail -20
```

Beklenen: `Test Suite 'SearchSummaryFormatter' passed` ve `** TEST SUCCEEDED **` (4 test).

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora && git add Termora/Models/SearchSummary.swift TermoraTests/SearchSummaryTests.swift && git commit -m "feat: add search match summary formatter"
```

- [ ] **Step 6: TerminalTab arama durumu testini yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/SearchSummaryTests.swift` dosyasının sonuna ekle:

```swift
@Suite("TerminalTab search state")
@MainActor
struct TerminalTabSearchStateTests {

    @Test func newTabStartsWithEmptySearchState() {
        let paneID = UUID()
        let tab = TerminalTab(root: .leaf(paneID: paneID, sessionID: UUID()), activePaneID: paneID)

        #expect(tab.isSearchVisible == false)
        #expect(tab.searchQuery == TerminalSearchQuery(term: ""))
        #expect(tab.searchSummary == .empty)
    }

    @Test func queryCarriesOptionFlags() {
        let query = TerminalSearchQuery(term: "error", caseSensitive: true, usesRegex: false, wholeWord: true)

        #expect(query.term == "error")
        #expect(query.caseSensitive)
        #expect(query.wholeWord)
        #expect(query.usesRegex == false)
        #expect(query != TerminalSearchQuery(term: "error"))
    }
}
```

- [ ] **Step 7: Testi çalıştır, FAIL bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/TerminalTabSearchStateTests 2>&1 | tail -20
```

Beklenen: `error: cannot find 'TerminalSearchQuery' in scope`, `error: value of type 'TerminalTab' has no member 'searchQuery'` → `** TEST FAILED **`.

- [ ] **Step 8: TerminalSearchQuery'yi ve TerminalTab alanlarını ekle**

`/Users/ahmetbarut/Apps/Termora/Termora/Models/SearchSummary.swift` dosyasının sonuna ekle:

```swift
/// Arama isteğinin SwiftTerm'den bağımsız gösterimi (SwiftTerm sınırı dar tutulur).
struct TerminalSearchQuery: Equatable {
    var term: String
    var caseSensitive: Bool
    var usesRegex: Bool
    var wholeWord: Bool

    init(term: String, caseSensitive: Bool = false, usesRegex: Bool = false, wholeWord: Bool = false) {
        self.term = term
        self.caseSensitive = caseSensitive
        self.usesRegex = usesRegex
        self.wholeWord = wholeWord
    }
}
```

`/Users/ahmetbarut/Apps/Termora/Termora/Models/TerminalTab.swift` içinde, `var isSearchVisible: Bool = false` satırının hemen altına ekle:

```swift
    /// Arama çubuğundaki metin ve seçenekler (sekme başına ayrı tutulur).
    var searchQuery = TerminalSearchQuery(term: "")
    /// Son `searchMatchSummary` sonucu; çubuktaki "2/14" sayacını besler.
    var searchSummary: SearchSummary = .empty
```

- [ ] **Step 9: Testi çalıştır, PASS bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/TerminalTabSearchStateTests 2>&1 | tail -20
```

Beklenen: `** TEST SUCCEEDED **` (2 test).

- [ ] **Step 10: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora && git add Termora/Models/SearchSummary.swift Termora/Models/TerminalTab.swift TermoraTests/SearchSummaryTests.swift && git commit -m "feat: add per-tab search query state"
```

- [ ] **Step 11: WorkspaceViewModel arama yönlendirme testini yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/WorkspaceSearchTests.swift` oluştur:

```swift
import Foundation
import Testing
@testable import Termora

/// Hem oturum yöneticisi hem arama yürütücüsü rolünü üstlenen çift.
@MainActor
final class WorkspaceSearchStubManager: SessionManaging, TerminalSearchRunner {
    private var storage: [UUID: TerminalSession] = [:]
    var summaryToReturn = SearchSummary(index: 1, total: 3)
    private(set) var findNextCalls: [(sessionID: UUID, query: TerminalSearchQuery)] = []
    private(set) var findPreviousCalls: [(sessionID: UUID, query: TerminalSearchQuery)] = []
    private(set) var clearCalls: [UUID] = []
    private(set) var focusCalls: [UUID] = []

    func createSession(profile: TerminalProfile?, workingDirectory: String?) -> TerminalSession {
        let session = TerminalSession(shellPath: "/bin/zsh",
                                      profileID: profile?.id,
                                      workingDirectory: workingDirectory)
        storage[session.id] = session
        return session
    }
    func session(id: UUID) -> TerminalSession? { storage[id] }
    func terminateSession(id: UUID) { storage[id] = nil }
    func hasRunningProcess(sessionID: UUID) -> Bool { false }

    /// `SessionManaging`'in beşinci üyesi (Task 8). Arama süiti yeniden başlatmayı test
    /// etmez ama protokol zorunlu kıldığı için burada da bulunmalı; çağrı yalnız kaydedilir.
    private(set) var restartedSessionIDs: [UUID] = []
    func restartSession(id: UUID, forceDefaultShell: Bool) { restartedSessionIDs.append(id) }

    func findNext(sessionID: UUID, query: TerminalSearchQuery) -> Bool {
        findNextCalls.append((sessionID, query))
        return summaryToReturn.total > 0
    }
    func findPrevious(sessionID: UUID, query: TerminalSearchQuery) -> Bool {
        findPreviousCalls.append((sessionID, query))
        return summaryToReturn.total > 0
    }
    func matchSummary(sessionID: UUID, query: TerminalSearchQuery) -> SearchSummary { summaryToReturn }
    func clearSearch(sessionID: UUID) { clearCalls.append(sessionID) }
    func focusTerminal(sessionID: UUID) { focusCalls.append(sessionID) }
}

@Suite("WorkspaceViewModel search")
@MainActor
struct WorkspaceSearchTests {

    private func makeWorkspace() -> (WorkspaceViewModel, WorkspaceSearchStubManager) {
        let suiteName = "termora.search.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let stub = WorkspaceSearchStubManager()
        let workspace = WorkspaceViewModel(sessionManager: stub,
                                           settings: SettingsStore(defaults: defaults),
                                           profiles: ProfileStore(defaults: defaults))
        workspace.newTab()
        return (workspace, stub)
    }

    @Test func toggleShowsAndHidesSearchBar() {
        let (workspace, stub) = makeWorkspace()

        workspace.toggleSearchBar()
        #expect(workspace.activeTab?.isSearchVisible == true)

        workspace.toggleSearchBar()
        #expect(workspace.activeTab?.isSearchVisible == false)
        #expect(stub.clearCalls.count == 1)
        #expect(stub.focusCalls.count == 1)
    }

    @Test func findNextForwardsQueryOfActivePaneAndStoresSummary() {
        let (workspace, stub) = makeWorkspace()
        let sessionID = workspace.activeTab!.root.leaves.first!.sessionID
        workspace.activeTab?.searchQuery = TerminalSearchQuery(term: "error", caseSensitive: true, wholeWord: true)
        stub.summaryToReturn = SearchSummary(index: 2, total: 14)

        workspace.findNextMatch()

        #expect(stub.findNextCalls.count == 1)
        #expect(stub.findNextCalls.first?.sessionID == sessionID)
        #expect(stub.findNextCalls.first?.query.term == "error")
        #expect(stub.findNextCalls.first?.query.caseSensitive == true)
        #expect(stub.findNextCalls.first?.query.wholeWord == true)
        #expect(workspace.activeTab?.searchSummary == SearchSummary(index: 2, total: 14))
    }

    @Test func findPreviousForwardsQuery() {
        let (workspace, stub) = makeWorkspace()
        workspace.activeTab?.searchQuery = TerminalSearchQuery(term: "warn")

        workspace.findPreviousMatch()

        #expect(stub.findPreviousCalls.count == 1)
        #expect(stub.findPreviousCalls.first?.query.term == "warn")
    }

    @Test func emptyTermDoesNotSearchAndResetsSummary() {
        let (workspace, stub) = makeWorkspace()
        workspace.activeTab?.searchSummary = SearchSummary(index: 2, total: 14)
        workspace.activeTab?.searchQuery = TerminalSearchQuery(term: "")

        workspace.refreshSearchSummary()
        workspace.findNextMatch()

        #expect(stub.findNextCalls.isEmpty)
        #expect(workspace.activeTab?.searchSummary == .empty)
        #expect(stub.clearCalls.count == 1)
    }

    @Test func closeSearchClearsHighlightAndReturnsFocus() {
        let (workspace, stub) = makeWorkspace()
        let sessionID = workspace.activeTab!.root.leaves.first!.sessionID
        workspace.toggleSearchBar()
        workspace.activeTab?.searchQuery = TerminalSearchQuery(term: "abc")
        workspace.activeTab?.searchSummary = SearchSummary(index: 1, total: 4)

        workspace.closeSearch()

        #expect(workspace.activeTab?.isSearchVisible == false)
        #expect(workspace.activeTab?.searchSummary == .empty)
        #expect(stub.clearCalls == [sessionID])
        #expect(stub.focusCalls == [sessionID])
    }
}
```

- [ ] **Step 12: Testi çalıştır, FAIL bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/WorkspaceSearchTests 2>&1 | tail -20
```

Beklenen: `error: cannot find type 'TerminalSearchRunner' in scope` ve `error: value of type 'WorkspaceViewModel' has no member 'toggleSearchBar'` → `** TEST FAILED **`.

- [ ] **Step 13: TerminalSearchRunner protokolünü ve SessionManager uyumunu yaz**

**(a) Önce SwiftTerm arama API'sinin imzalarını kaynaktan doğrula.** Planın diğer SwiftTerm çağrılarının aksine bu beş sembol "Ek: Kaynak Kodda Doğrulanmış SwiftTerm Sembolleri" listesinde yok:

```bash
CHECKOUT=$(ls -d ~/Library/Developer/Xcode/DerivedData/Termora-*/SourcePackages/checkouts/SwiftTerm 2>/dev/null | head -1)
grep -rn "func findNext\|func findPrevious\|func searchMatchSummary\|func clearSearch\|struct SearchOptions\|public init(caseSensitive" "$CHECKOUT/Sources/SwiftTerm" | head -20
```

Çıktıya göre aşağıdaki kodu düzelt:
- `scrollToResult` parametresinin **varsayılan değeri yoksa** `findNext` / `findPrevious` çağrılarını `view.findNext(query.term, options: query.swiftTermOptions, scrollToResult: true)` biçimine çevir.
- `searchMatchSummary` dönüş etiketleri `(index:total:)` değilse `SearchSummary(index:total:)` dönüşümünü gerçek etiketlerle yaz; metot yoksa `matchSummary` gövdesini `findNext` sonucundan türetilen `SearchSummary(index: found ? 1 : 0, total: found ? 1 : 0)` ile doldurmak yerine `.empty` döndür ve Step 21 elle doğrulamasının 3-5. maddelerini "sayaç gösterilmiyor" notuyla işaretle.
- `SearchOptions` init etiketleri farklıysa `swiftTermOptions` gövdesini ona uydur.
- Doğrulanan imzaları planın sonundaki "Ek: Kaynak Kodda Doğrulanmış SwiftTerm Sembolleri" bölümüne ekle.

**(b)** `/Users/ahmetbarut/Apps/Termora/Termora/Services/TerminalSearchRunner.swift` oluştur:

```swift
import Foundation
import SwiftTerm

/// Arama işlemlerinin uygulama tarafındaki sınırı. Gerçek uygulayıcı `SessionManager`,
/// testlerde çift kullanılır; böylece WorkspaceViewModel SwiftTerm'ü hiç görmez.
@MainActor
protocol TerminalSearchRunner: AnyObject {
    func findNext(sessionID: UUID, query: TerminalSearchQuery) -> Bool
    func findPrevious(sessionID: UUID, query: TerminalSearchQuery) -> Bool
    func matchSummary(sessionID: UUID, query: TerminalSearchQuery) -> SearchSummary
    func clearSearch(sessionID: UUID)
    func focusTerminal(sessionID: UUID)
}

extension TerminalSearchQuery {
    /// SwiftTerm'ün arama seçeneklerine çevirir.
    var swiftTermOptions: SearchOptions {
        SearchOptions(caseSensitive: caseSensitive, regex: usesRegex, wholeWord: wholeWord)
    }
}

extension SessionManager: TerminalSearchRunner {
    func findNext(sessionID: UUID, query: TerminalSearchQuery) -> Bool {
        guard !query.term.isEmpty, let view = terminalView(for: sessionID) else { return false }
        return view.findNext(query.term, options: query.swiftTermOptions)
    }

    func findPrevious(sessionID: UUID, query: TerminalSearchQuery) -> Bool {
        guard !query.term.isEmpty, let view = terminalView(for: sessionID) else { return false }
        return view.findPrevious(query.term, options: query.swiftTermOptions)
    }

    func matchSummary(sessionID: UUID, query: TerminalSearchQuery) -> SearchSummary {
        guard !query.term.isEmpty, let view = terminalView(for: sessionID) else { return .empty }
        let result = view.searchMatchSummary(query.term, options: query.swiftTermOptions, limit: 1000)
        return SearchSummary(index: result.index, total: result.total)
    }

    func clearSearch(sessionID: UUID) {
        terminalView(for: sessionID)?.clearSearch()
    }

    func focusTerminal(sessionID: UUID) {
        guard let view = terminalView(for: sessionID) else { return }
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
    }
}
```

- [ ] **Step 14: WorkspaceViewModel arama metodlarını yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/ViewModels/WorkspaceViewModel.swift` içinde, sınıfın sonuna (kapanış süslü parantezinden önce) ekle:

```swift
    // MARK: - Arama (⌘F / ⌘G / ⌘⇧G)

    /// Aktif oturum yöneticisi arama yürütebiliyorsa onu verir; testlerdeki basit çiftlerde nil olur.
    private var searchRunner: (any TerminalSearchRunner)? {
        sessionManager as? any TerminalSearchRunner
    }

    /// Aktif sekmenin aktif panelinin oturum kimliği.
    private var activeSessionID: UUID? {
        guard let tab = activeTab else { return nil }
        return tab.root.sessionID(ofPane: tab.activePaneID)
    }

    func toggleSearchBar() {
        guard let tab = activeTab else { return }
        if tab.isSearchVisible {
            closeSearch()
        } else {
            tab.isSearchVisible = true
        }
    }

    func closeSearch() {
        guard let tab = activeTab else { return }
        tab.isSearchVisible = false
        tab.searchSummary = .empty
        guard let sessionID = activeSessionID else { return }
        searchRunner?.clearSearch(sessionID: sessionID)
        searchRunner?.focusTerminal(sessionID: sessionID)
    }

    /// Metin ya da seçenekler değiştiğinde sayacı tazeler.
    func refreshSearchSummary() {
        guard let tab = activeTab, let sessionID = activeSessionID else { return }
        guard !tab.searchQuery.term.isEmpty else {
            tab.searchSummary = .empty
            searchRunner?.clearSearch(sessionID: sessionID)
            return
        }
        tab.searchSummary = searchRunner?.matchSummary(sessionID: sessionID, query: tab.searchQuery) ?? .empty
    }

    func findNextMatch() {
        guard let tab = activeTab, let sessionID = activeSessionID, !tab.searchQuery.term.isEmpty else { return }
        _ = searchRunner?.findNext(sessionID: sessionID, query: tab.searchQuery)
        tab.searchSummary = searchRunner?.matchSummary(sessionID: sessionID, query: tab.searchQuery) ?? .empty
    }

    func findPreviousMatch() {
        guard let tab = activeTab, let sessionID = activeSessionID, !tab.searchQuery.term.isEmpty else { return }
        _ = searchRunner?.findPrevious(sessionID: sessionID, query: tab.searchQuery)
        tab.searchSummary = searchRunner?.matchSummary(sessionID: sessionID, query: tab.searchQuery) ?? .empty
    }
```

- [ ] **Step 15: Testi çalıştır, PASS bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/WorkspaceSearchTests 2>&1 | tail -20
```

Beklenen: `** TEST SUCCEEDED **` (5 test).

- [ ] **Step 16: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora && git add Termora/Services/TerminalSearchRunner.swift Termora/ViewModels/WorkspaceViewModel.swift TermoraTests/WorkspaceSearchTests.swift && git commit -m "feat: route terminal search through workspace view model"
```

- [ ] **Step 17: SearchBarView'ı yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Views/SearchBarView.swift` oluştur:

```swift
import SwiftUI

/// Sekmenin üstünde ⌘F ile açılan arama çubuğu.
struct SearchBarView: View {
    @Bindable var tab: TerminalTab
    let workspace: WorkspaceViewModel

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Ara", text: $tab.searchQuery.term)
                .textFieldStyle(.plain)
                .focused($isFieldFocused)
                .onSubmit { workspace.findNextMatch() }
                .frame(minWidth: 140)

            Text(SearchSummaryFormatter.text(tab.searchSummary))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 48, alignment: .trailing)

            Button { workspace.findPreviousMatch() } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .help("Önceki eşleşme (⌘⇧G)")
            .disabled(tab.searchQuery.term.isEmpty)

            Button { workspace.findNextMatch() } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .help("Sonraki eşleşme (⌘G)")
            .disabled(tab.searchQuery.term.isEmpty)

            Divider().frame(height: 14)

            Toggle("Aa", isOn: $tab.searchQuery.caseSensitive)
                .toggleStyle(.button)
                .help("Büyük/küçük harfe duyarlı")
            Toggle(".*", isOn: $tab.searchQuery.usesRegex)
                .toggleStyle(.button)
                .help("Düzenli ifade")
            Toggle("W", isOn: $tab.searchQuery.wholeWord)
                .toggleStyle(.button)
                .help("Yalnız tam kelime")

            Button { workspace.closeSearch() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Kapat (Esc)")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .onAppear { isFieldFocused = true }
        .onChange(of: tab.searchQuery) { _, _ in
            workspace.refreshSearchSummary()
        }
        .onExitCommand {
            workspace.closeSearch()
        }
    }
}
```

- [ ] **Step 18: MainWindowView'a arama çubuğunu yerleştir**

`/Users/ahmetbarut/Apps/Termora/Termora/Views/MainWindowView.swift` içindeki ana dikey yığında, `TabBarView` ile `PaneTreeView` arasına şu bloğu ekle:

```swift
            if let tab = workspace.activeTab, tab.isSearchVisible {
                SearchBarView(tab: tab, workspace: workspace)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
```

- [ ] **Step 19: AppCommands'a ⌘F / ⌘G / ⌘⇧G ekle**

`/Users/ahmetbarut/Apps/Termora/Termora/App/AppCommands.swift` içindeki `body` içine, mevcut `CommandGroup`ların yanına ekle:

```swift
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Bul…") {
                workspace?.toggleSearchBar()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(workspace == nil)

            Button("Sonrakini Bul") {
                workspace?.findNextMatch()
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(workspace == nil)

            Button("Öncekini Bul") {
                workspace?.findPreviousMatch()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(workspace == nil)
        }
```

- [ ] **Step 20: Derle**

```bash
xcodebuild build -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet
```

Beklenen: uyarı/hata yok, komut 0 ile döner (`BUILD SUCCEEDED` veya sessiz çıkış).

- [ ] **Step 21: Elle doğrulama**

Uygulamayı Xcode'dan (⌘R) veya şu komutla çalıştır:

```bash
open -n "$(xcodebuild -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/ {print $2; exit}')/Termora.app"
```

Terminalde şunu çalıştır ve gözlemleri doğrula:

1. `for i in $(seq 1 40); do echo "line $i: error code $i"; done` yaz.
2. ⌘F bas → sekme çubuğunun altında arama çubuğu açılır, imleç metin alanındadır.
3. `error` yaz → sayaç `1/40` (veya `0/40`) gösterir, ilk eşleşme seçili olarak vurgulanır.
4. ⌘G'ye üç kez bas → sayaç `2/40`, `3/40`, `4/40` ilerler ve terminal eşleşmeye kaydırılır.
5. ⌘⇧G bas → sayaç bir geri gider.
6. `Aa` düğmesine bas, `ERROR` yaz → sayaç `0/0`'a düşer (büyük/küçük harfe duyarlı).
7. `.*` düğmesine bas ve `line [0-9]+9` yaz → sayaç 4 civarı eşleşme gösterir.
8. Esc bas → çubuk kapanır, eşleşme vurgusu kalkar, klavye odağı terminale döner (hemen `echo ok` yazabilmelisin).

- [ ] **Step 22: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora && git add Termora/Views/SearchBarView.swift Termora/Views/MainWindowView.swift Termora/App/AppCommands.swift && git commit -m "feat: add terminal search bar with find next/previous commands"
```

---

---

### Task 21: Durum çubuğu + GitBranchReader (M5)

**Files:**
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Services/GitBranchReader.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Extensions/PathDisplay.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Services/TerminalProcessInfoProviding.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/Views/StatusBarView.swift`
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/Models/TerminalSession.swift`
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/Services/SessionManager.swift`
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/ViewModels/WorkspaceViewModel.swift`
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/Views/MainWindowView.swift`
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/GitBranchReaderTests.swift`
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/PathDisplayTests.swift`
- Test: `/Users/ahmetbarut/Apps/Termora/TermoraTests/StatusSnapshotTests.swift`

**Interfaces:**

Consumes:
- `TerminalSession` (Task 8): `var shellPath: String` (`let` DEĞİL — `restartSession` yeniden yazar), `var workingDirectory: String?`
- `SessionManaging` (Task 8): bu görev yalnız `func session(id: UUID) -> TerminalSession?` ve `func hasRunningProcess(sessionID: UUID) -> Bool` üyelerini KULLANIR, ama protokolün tamamı `func createSession(profile: TerminalProfile?, workingDirectory: String?) -> TerminalSession`, `func terminateSession(id: UUID)` ve `func restartSession(id: UUID, forceDefaultShell: Bool)` üyelerini de zorunlu kılar — **Step 11'deki stub beşini birden gerçeklemelidir**
- `SessionManager` (Task 8): `func terminalView(for sessionID: UUID) -> TermoraTerminalView?`, sınıf gövdesindeki `nonisolated func sizeChanged(source:newCols:newRows:)` delegate metodu (minimal gövdeyle; bu görevde doldurulur — `nonisolated` + `MainActor.assumeIsolated` kalıbı korunur)
- `TermoraTerminalView` (Task 8): `let sessionID: UUID`, SwiftTerm `process: LocalProcess!` → `process.shellPid`
- `ProcessProbe` (Task 9): `static func currentWorkingDirectory(pid: pid_t) -> String?`
- `SettingsStore` (Task 6): `var settings: AppSettings`, `AppSettings.showStatusBar`
- `WorkspaceViewModel` (Task 11/16): `var activeTab`, `private let sessionManager: any SessionManaging`, `private let settings: SettingsStore` (Task 11'de bu adlarla saklandı), `func syncAutomaticTitles()` + `var sessionTitleDigest: String` — Task 11'de otomatik başlık, `session.title` boşsa `session.workingDirectory`'nin son bileşenine düşer. `session.workingDirectory`'yi canlı tutan tek yazıcı bu görevdeki `statusSnapshot()`'tır (libproc, 1 Hz) ve `sessionTitleDigest` yalnız `session.title`'ı izlediği için cwd değişimi Task 12/13'teki `.onChange(of: sessionTitleDigest)` kancasını tetiklemez; bu yüzden `statusSnapshot()` cwd'yi tazeledikten sonra `syncAutomaticTitles()`'ı kendisi çağırır (Step 15) ve sonuç Step 21 madde 4'te doğrulanır.
- `PaneNode.sessionID(ofPane:)` (Task 14), `TerminalTab.root/activePaneID` (Task 11), `MainWindowView`

Produces:
```swift
enum GitBranchReader {
    static func branchName(forDirectory dir: String) -> String?
    static func branchName(fromHeadContents contents: String) -> String?
}
enum PathDisplay { static func abbreviate(_ path: String, home: String) -> String }
@MainActor protocol TerminalProcessInfoProviding: AnyObject { func shellPID(sessionID: UUID) -> pid_t? }
extension SessionManager: TerminalProcessInfoProviding {}
// TerminalSession'a eklenir: var terminalSize: (cols: Int, rows: Int)?
// WorkspaceViewModel'e eklenir:
struct StatusSnapshot: Equatable { var shellName: String; var workingDirectory: String; var branchName: String?
                                   var columns: Int; var rows: Int; var isBusy: Bool }
//   func statusSnapshot() -> StatusSnapshot?
//   var isStatusBarVisible: Bool { get }
struct StatusBarView: View { init(workspace: WorkspaceViewModel) }
```

- [ ] **Step 1: GitBranchReader testlerini yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/GitBranchReaderTests.swift` oluştur:

```swift
import Foundation
import Testing
@testable import Termora

@Suite("GitBranchReader")
@MainActor
struct GitBranchReaderTests {

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("termora-git-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeGitDirectory(head: String, in repo: URL) throws {
        let gitDir = repo.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try head.write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
    }

    @Test func readsBranchNameFromSymbolicRef() throws {
        let repo = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: repo) }
        try writeGitDirectory(head: "ref: refs/heads/main\n", in: repo)

        #expect(GitBranchReader.branchName(forDirectory: repo.path) == "main")
    }

    @Test func readsSlashedBranchName() throws {
        let repo = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: repo) }
        try writeGitDirectory(head: "ref: refs/heads/feature/status-bar\n", in: repo)

        #expect(GitBranchReader.branchName(forDirectory: repo.path) == "feature/status-bar")
    }

    @Test func shortensDetachedHeadToSevenCharacters() throws {
        let repo = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: repo) }
        try writeGitDirectory(head: "3f1c9a2b7d4e5f60718293a4b5c6d7e8f9012345\n", in: repo)

        #expect(GitBranchReader.branchName(forDirectory: repo.path) == "3f1c9a2")
    }

    @Test func walksUpFromNestedDirectory() throws {
        let repo = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: repo) }
        try writeGitDirectory(head: "ref: refs/heads/develop\n", in: repo)
        let nested = repo.appendingPathComponent("src/app/deep", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        #expect(GitBranchReader.branchName(forDirectory: nested.path) == "develop")
    }

    @Test func returnsNilWhenNoRepositoryUpToRoot() throws {
        let plain = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: plain) }

        #expect(GitBranchReader.branchName(forDirectory: plain.path) == nil)
    }

    @Test func followsGitdirFileOfWorktree() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let realGitDir = root.appendingPathComponent("real-git", isDirectory: true)
        try FileManager.default.createDirectory(at: realGitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/worktree-branch\n"
            .write(to: realGitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)

        let worktree = root.appendingPathComponent("wt", isDirectory: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try "gitdir: \(realGitDir.path)\n"
            .write(to: worktree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        #expect(GitBranchReader.branchName(forDirectory: worktree.path) == "worktree-branch")
    }

    @Test func rejectsGarbageHeadContents() {
        #expect(GitBranchReader.branchName(fromHeadContents: "") == nil)
        #expect(GitBranchReader.branchName(fromHeadContents: "ref: refs/tags/v1\n") == nil)
        #expect(GitBranchReader.branchName(fromHeadContents: "not-a-sha\n") == nil)
        #expect(GitBranchReader.branchName(fromHeadContents: "ref: refs/heads/\n") == nil)
    }
}
```

- [ ] **Step 2: Testi çalıştır, FAIL bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/GitBranchReaderTests 2>&1 | tail -20
```

Beklenen: `error: cannot find 'GitBranchReader' in scope` → `** TEST FAILED **`.

- [ ] **Step 3: GitBranchReader'ı yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Services/GitBranchReader.swift` oluştur:

```swift
import Foundation

/// Çalışma dizininden yukarı yürüyerek `.git/HEAD` okur ve dal adını çözer.
/// Git komutu çalıştırılmaz; yalnız dosya okunur (durum çubuğu 1 Hz'de çağırır).
enum GitBranchReader {

    /// `dir` ve üstündeki dizinlerde ilk bulunan deponun dal adı; yoksa nil.
    static func branchName(forDirectory dir: String) -> String? {
        var current = URL(fileURLWithPath: dir, isDirectory: true).standardizedFileURL
        while true {
            let gitPath = current.appendingPathComponent(".git")
            if let headURL = headURL(forGitPath: gitPath),
               let data = try? Data(contentsOf: headURL),
               let text = String(data: data, encoding: .utf8),
               let name = branchName(fromHeadContents: text) {
                return name
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path { return nil }
            current = parent
        }
    }

    /// `.git/HEAD` içeriğini ayrıştırır: "ref: refs/heads/X" → X, 40 karakterlik SHA → ilk 7.
    static func branchName(fromHeadContents contents: String) -> String? {
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("ref: ") {
            let ref = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            let headsPrefix = "refs/heads/"
            guard ref.hasPrefix(headsPrefix) else { return nil }
            let name = String(ref.dropFirst(headsPrefix.count))
            return name.isEmpty ? nil : name
        }

        guard trimmed.count == 40, trimmed.allSatisfy({ $0.isHexDigit }) else { return nil }
        return String(trimmed.prefix(7))
    }

    /// `.git` bir dizin ise HEAD doğrudan içindedir; bir dosya ise ("gitdir: ...") worktree'dir.
    private static func headURL(forGitPath gitPath: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitPath.path, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue {
            return gitPath.appendingPathComponent("HEAD")
        }
        guard let data = try? Data(contentsOf: gitPath),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "gitdir: "
        guard trimmed.hasPrefix(prefix) else { return nil }
        let raw = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        let base = raw.hasPrefix("/")
            ? URL(fileURLWithPath: raw, isDirectory: true)
            : gitPath.deletingLastPathComponent().appendingPathComponent(raw, isDirectory: true)
        return base.standardizedFileURL.appendingPathComponent("HEAD")
    }
}
```

- [ ] **Step 4: Testi çalıştır, PASS bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/GitBranchReaderTests 2>&1 | tail -20
```

Beklenen: `** TEST SUCCEEDED **` (7 test).

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora && git add Termora/Services/GitBranchReader.swift TermoraTests/GitBranchReaderTests.swift && git commit -m "feat: read git branch name from .git/HEAD"
```

- [ ] **Step 6: PathDisplay testini yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/PathDisplayTests.swift` oluştur:

```swift
import Testing
@testable import Termora

@Suite("PathDisplay")
@MainActor
struct PathDisplayTests {

    @Test func replacesHomePrefixWithTilde() {
        #expect(PathDisplay.abbreviate("/Users/ahmet/Apps/Termora", home: "/Users/ahmet") == "~/Apps/Termora")
    }

    @Test func homeItselfBecomesTilde() {
        #expect(PathDisplay.abbreviate("/Users/ahmet", home: "/Users/ahmet") == "~")
        #expect(PathDisplay.abbreviate("/Users/ahmet", home: "/Users/ahmet/") == "~")
    }

    @Test func doesNotMatchPartialDirectoryName() {
        #expect(PathDisplay.abbreviate("/Users/ahmetbarut/Apps", home: "/Users/ahmet") == "/Users/ahmetbarut/Apps")
    }

    @Test func leavesUnrelatedPathsUntouched() {
        #expect(PathDisplay.abbreviate("/tmp/build", home: "/Users/ahmet") == "/tmp/build")
        #expect(PathDisplay.abbreviate("/tmp/build", home: "") == "/tmp/build")
    }
}
```

- [ ] **Step 7: Testi çalıştır, FAIL bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/PathDisplayTests 2>&1 | tail -20
```

Beklenen: `error: cannot find 'PathDisplay' in scope` → `** TEST FAILED **`.

- [ ] **Step 8: PathDisplay'i yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Extensions/PathDisplay.swift` oluştur:

```swift
import Foundation

/// Durum çubuğunda yol gösterimi: ev dizini `~` ile kısaltılır.
enum PathDisplay {
    static func abbreviate(_ path: String, home: String) -> String {
        guard !home.isEmpty else { return path }
        var normalizedHome = home
        while normalizedHome.count > 1, normalizedHome.hasSuffix("/") {
            normalizedHome.removeLast()
        }
        if path == normalizedHome { return "~" }
        guard path.hasPrefix(normalizedHome + "/") else { return path }
        return "~" + path.dropFirst(normalizedHome.count)
    }
}
```

- [ ] **Step 9: Testi çalıştır, PASS bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/PathDisplayTests 2>&1 | tail -20
```

Beklenen: `** TEST SUCCEEDED **` (4 test).

- [ ] **Step 10: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora && git add Termora/Extensions/PathDisplay.swift TermoraTests/PathDisplayTests.swift && git commit -m "feat: abbreviate home directory in displayed paths"
```

- [ ] **Step 11: Durum anlık görüntüsü testini yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/StatusSnapshotTests.swift` oluştur:

```swift
import Foundation
import Testing
@testable import Termora

@MainActor
final class StatusStubSessionManager: SessionManaging {
    private var storage: [UUID: TerminalSession] = [:]
    var runningSessionIDs: Set<UUID> = []
    var shellPathForNewSessions = "/bin/zsh"

    func createSession(profile: TerminalProfile?, workingDirectory: String?) -> TerminalSession {
        let session = TerminalSession(shellPath: shellPathForNewSessions,
                                      profileID: profile?.id,
                                      workingDirectory: workingDirectory)
        storage[session.id] = session
        return session
    }
    func session(id: UUID) -> TerminalSession? { storage[id] }
    func terminateSession(id: UUID) { storage[id] = nil; runningSessionIDs.remove(id) }
    func hasRunningProcess(sessionID: UUID) -> Bool { runningSessionIDs.contains(sessionID) }
}

@Suite("WorkspaceViewModel status snapshot")
@MainActor
struct StatusSnapshotTests {

    private func makeWorkspace() -> (WorkspaceViewModel, StatusStubSessionManager, SettingsStore) {
        let suiteName = "termora.status.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let stub = StatusStubSessionManager()
        let settings = SettingsStore(defaults: defaults)
        let workspace = WorkspaceViewModel(sessionManager: stub,
                                           settings: settings,
                                           profiles: ProfileStore(defaults: defaults))
        workspace.newTab()
        return (workspace, stub, settings)
    }

    private func makeRepository(branch: String) throws -> URL {
        let repo = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("termora-status-\(UUID().uuidString)", isDirectory: true)
        let gitDir = repo.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/\(branch)\n"
            .write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        return repo
    }

    @Test func snapshotReportsShellBranchSizeAndBusyState() throws {
        let (workspace, stub, _) = makeWorkspace()
        let repo = try makeRepository(branch: "feature/status")
        defer { try? FileManager.default.removeItem(at: repo) }

        let sessionID = workspace.activeTab!.root.leaves.first!.sessionID
        let session = stub.session(id: sessionID)!
        session.workingDirectory = repo.path
        session.terminalSize = (cols: 100, rows: 30)
        stub.runningSessionIDs.insert(sessionID)

        let snapshot = workspace.statusSnapshot()

        #expect(snapshot?.shellName == "zsh")
        #expect(snapshot?.branchName == "feature/status")
        #expect(snapshot?.columns == 100)
        #expect(snapshot?.rows == 30)
        #expect(snapshot?.isBusy == true)
    }

    @Test func snapshotFallsBackWhenSizeAndDirectoryAreUnknown() {
        let (workspace, _, _) = makeWorkspace()

        let snapshot = workspace.statusSnapshot()

        #expect(snapshot?.workingDirectory == "—")
        #expect(snapshot?.branchName == nil)
        #expect(snapshot?.columns == 0)
        #expect(snapshot?.rows == 0)
        #expect(snapshot?.isBusy == false)
    }

    @Test func statusBarVisibilityFollowsSettings() {
        let (workspace, _, settings) = makeWorkspace()

        settings.settings.showStatusBar = true
        #expect(workspace.isStatusBarVisible)

        settings.settings.showStatusBar = false
        #expect(workspace.isStatusBarVisible == false)
    }

    @Test func terminalSizeStartsUnsetAndStoresColumnsAndRows() {
        // Not: (cols:rows:) tuple'ı Equatable değil; nil karşılaştırması alan üzerinden yapılır.
        let session = TerminalSession(shellPath: "/bin/zsh")
        #expect(session.terminalSize?.cols == nil)

        session.terminalSize = (cols: 80, rows: 24)
        #expect(session.terminalSize?.cols == 80)
        #expect(session.terminalSize?.rows == 24)
    }
}
```

- [ ] **Step 12: Testi çalıştır, FAIL bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/StatusSnapshotTests 2>&1 | tail -20
```

Beklenen: `error: value of type 'TerminalSession' has no member 'terminalSize'` ve `error: value of type 'WorkspaceViewModel' has no member 'statusSnapshot'` → `** TEST FAILED **`.

- [ ] **Step 13: TerminalSession'a terminalSize ekle ve SessionManager'da doldur**

`/Users/ahmetbarut/Apps/Termora/Termora/Models/TerminalSession.swift` içinde, `var processState: ProcessState = .running` satırının altına ekle:

```swift
    /// SwiftTerm `sizeChanged` delegesinden gelen son terminal boyutu.
    /// Tuple bilerek kullanıldı: Equatable değil ama @Observable için sorun değil.
    var terminalSize: (cols: Int, rows: Int)?
```

`/Users/ahmetbarut/Apps/Termora/Termora/Services/SessionManager.swift` içindeki `sizeChanged` delegate metodunu **tamamen** şununla değiştir (Task 8 Step 18'de minimal gövdeyle yazılmıştı; `nonisolated` işareti ve `MainActor.assumeIsolated` sarmalayıcısı Task 8'in dört delegate metodunda kullanılan kalıptır — proje `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` ile derlendiği için `LocalProcessTerminalViewDelegate` uyumu ancak böyle sağlanır, kalıptan sapma Swift 6'da hatadır):

```swift
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        MainActor.assumeIsolated {
            guard let view = source as? TermoraTerminalView,
                  let session = self.session(id: view.sessionID) else { return }
            session.terminalSize = (cols: newCols, rows: newRows)
        }
    }
```

- [ ] **Step 14: shellPID sağlayıcısını yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Services/TerminalProcessInfoProviding.swift` oluştur:

```swift
import Foundation
import Darwin

/// Durum çubuğunun ihtiyaç duyduğu süreç bilgisini SwiftTerm'e bağımlı olmadan sunar.
@MainActor
protocol TerminalProcessInfoProviding: AnyObject {
    func shellPID(sessionID: UUID) -> pid_t?
}

extension SessionManager: TerminalProcessInfoProviding {
    func shellPID(sessionID: UUID) -> pid_t? {
        guard let view = terminalView(for: sessionID),
              let process = view.process else { return nil }
        return process.shellPid
    }
}
```

- [ ] **Step 15: WorkspaceViewModel.statusSnapshot ve isStatusBarVisible'ı yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/ViewModels/WorkspaceViewModel.swift` içinde, sınıfın sonuna ekle:

```swift
    // MARK: - Durum çubuğu

    struct StatusSnapshot: Equatable {
        var shellName: String
        var workingDirectory: String
        var branchName: String?
        var columns: Int
        var rows: Int
        var isBusy: Bool
    }

    /// Durum çubuğu ayarlardan açık mı? (@Observable okuması sayesinde canlı günceller.)
    var isStatusBarVisible: Bool {
        settings.settings.showStatusBar
    }

    private var processInfoProvider: (any TerminalProcessInfoProviding)? {
        sessionManager as? any TerminalProcessInfoProviding
    }

    /// Aktif sekmenin aktif paneli için tek seferlik durum okuması. En fazla 1 Hz çağrılır.
    func statusSnapshot() -> StatusSnapshot? {
        guard let tab = activeTab,
              let sessionID = tab.root.sessionID(ofPane: tab.activePaneID),
              let session = sessionManager.session(id: sessionID) else { return nil }

        let probedDirectory = processInfoProvider
            .flatMap { $0.shellPID(sessionID: sessionID) }
            .flatMap { ProcessProbe.currentWorkingDirectory(pid: $0) }
        if let probedDirectory, probedDirectory != session.workingDirectory {
            session.workingDirectory = probedDirectory
            // Sekme başlığı da cwd'ye düşebiliyor (Task 11 `syncAutomaticTitles`), ama onu
            // tetikleyen `sessionTitleDigest` yalnız `session.title`'ı izler — cwd değişimi
            // MainWindowView'ın .onChange kancasını uyandırmaz. cwd'yi tazeleyen tek okuma
            // burası olduğu için başlıkları da burada eşitliyoruz (aynı 1 Hz bütçesi içinde).
            syncAutomaticTitles()
        }
        let directory = probedDirectory ?? session.workingDirectory
        let size = session.terminalSize ?? (cols: 0, rows: 0)

        return StatusSnapshot(
            shellName: (session.shellPath as NSString).lastPathComponent,
            workingDirectory: directory.map { PathDisplay.abbreviate($0, home: NSHomeDirectory()) } ?? "—",
            branchName: directory.flatMap { GitBranchReader.branchName(forDirectory: $0) },
            columns: size.cols,
            rows: size.rows,
            isBusy: sessionManager.hasRunningProcess(sessionID: sessionID)
        )
    }
```

- [ ] **Step 16: Testi çalıştır, PASS bekle**

```bash
xcodebuild test -project /Users/ahmetbarut/Apps/Termora/Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/StatusSnapshotTests 2>&1 | tail -20
```

Beklenen: `** TEST SUCCEEDED **` (4 test).

- [ ] **Step 17: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora && git add Termora/Models/TerminalSession.swift Termora/Services/SessionManager.swift Termora/Services/TerminalProcessInfoProviding.swift Termora/ViewModels/WorkspaceViewModel.swift TermoraTests/StatusSnapshotTests.swift && git commit -m "feat: expose terminal size and status snapshot for status bar"
```

- [ ] **Step 18: StatusBarView'ı yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/Views/StatusBarView.swift` oluştur (Task 21'in **Files:** bloğunda ilan edilen yol; `TabBarView.swift` / `SearchBarView.swift` ile aynı klasör):

```swift
import Combine
import SwiftUI

/// Aktif sekmenin aktif panelinin durumu: shell adı, çalışma dizini (~ kısaltmalı),
/// git dalı, terminal boyutu (cols×rows) ve işlem göstergesi.
///
/// Veri `WorkspaceViewModel.statusSnapshot()` ile çekilir. Spec §10 gereği en fazla 1 Hz
/// ve yalnız görünür sekme için okunur: `statusSnapshot()` `libproc` ile cwd sorgular ve
/// `.git/HEAD` okur — her yeniden çizimde çalıştırılamaz, bu yüzden değer `@State`'te tutulur.
struct StatusBarView: View {

    let workspace: WorkspaceViewModel

    @State private var snapshot: WorkspaceViewModel.StatusSnapshot?

    /// `@State` bilerek: `Timer.publish(...)` her `body` değerlendirmesinde YENİ bir publisher
    /// üretir; `let` özellik olarak tutulsaydı `onReceive` her yeniden çizimde yeniden abone
    /// olur ve 1 sn'lik sayaç sürekli baştan başlardı (sık çizimde hiç tetiklenmeyebilirdi).
    /// `.common` mode: menü açıkken ya da ayraç sürüklenirken de tetiklenir.
    /// Abonelik görünüm ağaçtan çıkınca iptal olur — çubuk kapalıyken zamanlayıcı çalışmaz.
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            content
                .padding(.horizontal, 10)
                .frame(height: 22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .onAppear { snapshot = workspace.statusSnapshot() }
        .onReceive(ticker) { _ in snapshot = workspace.statusSnapshot() }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot {
            HStack(spacing: 8) {
                item("terminal", snapshot.shellName)

                separator

                Text(snapshot.workingDirectory)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(snapshot.workingDirectory)

                if let branch = snapshot.branchName {
                    separator
                    item("arrow.triangle.branch", branch)
                }

                Spacer(minLength: 8)

                Text("\(snapshot.columns)×\(snapshot.rows)")
                    .monospacedDigit()
                    .help("Terminal boyutu (sütun × satır)")

                separator

                busyIndicator(isBusy: snapshot.isBusy)
            }
        } else {
            Color.clear
        }
    }

    private func item(_ systemImage: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(text).lineLimit(1)
        }
    }

    private var separator: some View {
        Divider().frame(height: 11)
    }

    private func busyIndicator(isBusy: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isBusy ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)
            Text(isBusy ? "çalışıyor" : "boşta")
        }
        .help(isBusy ? "Bu panelde çalışan bir işlem var" : "Bu panelde çalışan işlem yok")
    }
}
```

Not: Görünürlük kontrolü bilerek burada değil, `MainWindowView`'da (Step 19): `settings.showStatusBar` kapalıyken `StatusBarView` hiç kurulmaz, dolayısıyla zamanlayıcı da hiç dönmez.

- [ ] **Step 19: MainWindowView'a durum çubuğunu bağla**

`/Users/ahmetbarut/Apps/Termora/Termora/Views/MainWindowView.swift` içindeki kök `VStack(spacing: 0) { ... }` bloğunun **en sonuna** (panel ağacını çizen `terminalContent` / `if let tab = ...` bloğundan hemen sonra, `VStack`'in kapanış parantezinden önce) ekle:

```swift
            if workspace.isStatusBarVisible {
                StatusBarView(workspace: workspace)
            }
```

`MainWindowView`'ın view model özelliğinin adı plan boyunca `workspace`'tir (`private let services: AppServices` + `@State private var workspace: WorkspaceViewModel`); yukarıdaki blok bu adı olduğu gibi kullanır, arama/uyarlama gerekmez.

- [ ] **Step 20: Derle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet && echo BUILD_OK
```

Beklenen: `BUILD_OK`.

- [ ] **Step 21: Elle doğrulama — durum çubuğu**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -derivedDataPath /tmp/termora-dd -quiet && open -n /tmp/termora-dd/Build/Products/Debug/Termora.app
```

Açılan pencerede sırayla doğrula:

1. Pencerenin en altında ~22 pt yüksekliğinde, üstünde ince ayraç olan bir çubuk var; solda `zsh` (ya da varsayılan shell'in adı), yanında çalışma dizini, sağda `80×24` benzeri boyut ve `boşta` göstergesi görünüyor.
2. Terminale `cd ~` yaz → dizin alanı **`~`** olur (tam yol değil). `cd /tmp` → `/tmp` yazar (ev dizini altında olmadığı için kısaltılmaz).
3. `cd /Users/ahmetbarut/Apps/Termora` → **en geç 1 saniye içinde** dal simgesiyle birlikte `main` belirir. `cd /tmp` → dal göstergesi kaybolur.
4. **Sekme başlığı da cwd'yi izler** (spec §7 "başlıkta aktif klasör/işlem adı"): durum çubuğu **açıkken** `cd /tmp` yaz → sekme başlığı en geç ~1 sn içinde **`tmp`** olur; `cd ~/Apps/Termora` → **`Termora`** olur. Zinciri Step 15 kurar: `statusSnapshot()` cwd'yi libproc ile tazeler ve değiştiyse Task 11'in `syncAutomaticTitles()`'ını çağırır. Başlık kalıcı olarak `Terminal` kalıyorsa Task 11 Step 21'deki cwd yedeği uygulanmamıştır (stok zsh yalnız `TERM_PROGRAM=Apple_Terminal` iken OSC başlık yayar) — oraya dön. Sekmeyi elle adlandırdıysan otomatik başlık ezilmez; maddeyi adı sıfırlanmış bir sekmede dene. **Bilinen sınır:** durum çubuğu kapalıyken cwd'yi okuyan başka bir yer yoktur; başlık o sırada shell adında (`zsh`) kalır ve `showStatusBar` tekrar açılınca güncellenir.
5. `git checkout -b durum-cubugu-deneme` → gösterge `durum-cubugu-deneme` olur; `git checkout main && git branch -D durum-cubugu-deneme` → geri `main` olur.
6. Terminalde `tput cols; tput lines` çalıştır → çıktı, çubuktaki `cols×rows` ile birebir aynı olmalı. Pencereyi fareyle genişlet/daralt → sayılar değişir (SwiftTerm `sizeChanged` → `TerminalSession.terminalSize`).
7. `sleep 5` çalıştır → nokta yeşile döner ve yazı `çalışıyor` olur; komut bitince en geç 1 sn içinde `boşta`ya döner.
8. ⌘D ile paneli böl, sağ panelde `cd /` çalıştır → çubuk **aktif** panelin durumunu gösterir; ⌘⌥← ile sol panele geç → çubuk sol panelin dizinine döner.
9. ⌘, ile Ayarlar ▸ Genel'den durum çubuğunu kapat → çubuk anında kaybolur; tekrar aç → geri gelir (`isStatusBarVisible` @Observable okuması).
10. Boştaki uygulamanın CPU'sunu ölç — 1 Hz'lik zamanlayıcı sistemi yormamalı:

```bash
top -pid "$(pgrep -x Termora)" -l 6 -s 1 -stats pid,cpu,mem | awk '/^[0-9]+/ {print "cpu=" $2 "  mem=" $3}' | tail -5
```

Beklenen: `cpu` değerleri **%2'nin altında** (ilk örnek yok sayılır).

Uygulamayı kapat.

- [ ] **Step 22: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora && git add Termora/Views/StatusBarView.swift Termora/Views/MainWindowView.swift && git commit -m "feat: show shell, directory, git branch and terminal size in a status bar"
```

---

---

### Task 22: Kapanış onayları + performans doğrulaması + cila (M5)

**Files:**
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/App/WindowCloseCoordinator.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/Termora/App/TermoraAppDelegate.swift`
- Create: `/Users/ahmetbarut/Apps/Termora/README.md`
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/ViewModels/WorkspaceViewModel.swift`
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/Views/MainWindowView.swift`
- Modify: `/Users/ahmetbarut/Apps/Termora/Termora/App/TermoraApp.swift`
- Delete: `/Users/ahmetbarut/Apps/Termora/TermoraTests/TermoraTests.swift` (Xcode şablonu)
- Test (Modify): `/Users/ahmetbarut/Apps/Termora/TermoraTests/WorkspaceViewModelTests.swift`

**Interfaces:**

Consumes:
- Task 11 — `WorkspaceViewModel`: `var pendingClose: PendingClose?`, `struct PendingClose: Identifiable, Equatable { let id: UUID; let target: Target; enum Target: Equatable { case tab(UUID); case pane(paneID: UUID); case window } }` (kurulum her yerde `PendingClose(id: UUID(), target: …)`), `func confirmPendingClose()`, `func cancelPendingClose()`, `func closeAllTabs()` (internal — pencere kapatılırken `WindowCloseCoordinator` dışarıdan çağırır), `func hasAnyRunningProcess() -> Bool`, `private func closeTab(id: UUID)`
- Task 16 — `confirmPendingClose()`'un `.pane` dalı: `closePane(paneID:in:)` (tek argümanlı `closePane(paneID:)` Task 16 Step 8'de silindi)
- Task 11 test desteği — `@MainActor final class MockSessionManager: SessionManaging` (**tek dosya**: `/Users/ahmetbarut/Apps/Termora/TermoraTests/MockSessionManager.swift`; `Support/` alt klasörü yoktur): `var busySessionIDs: Set<UUID>`, `private(set) var terminatedSessionIDs: [UUID]`, `func terminateSession(id:)`
- Task 12/13 — `MainWindowView`: `private let services: AppServices` + `@State private var workspace: WorkspaceViewModel`, kök `VStack`, `.confirmationDialog(..., isPresented: pendingCloseBinding)`, `private var pendingCloseBinding: Binding<Bool>`
- Task 13/18/19 — `TermoraApp`: `@State private var services = AppServices()` + `WindowGroup { MainWindowView(services: services) }` + `.commands { AppCommands(); ProfileCommands(profiles: services.profiles) }` + `Settings { SettingsWindowView(settings: services.settings, themes: services.themes, profiles: services.profiles) }` (servislere yalnız `services.` önekiyle erişilir; çıplak `settings` / `themes` / `profiles` / `sessionManager` adları TermoraApp kapsamında yoktur)
- Task 18 — `struct WindowAccessor: NSViewRepresentable { let onWindow: (NSWindow) -> Void }` (`Termora/Views/Support/WindowChrome.swift`)

Produces:
```swift
// WorkspaceViewModel'e eklenir:
//   func requestCloseWindow(onApproved: @escaping @MainActor () -> Void) -> Bool
//   var pendingCloseMessage: String { get }
//   confirmPendingClose(): .window dalı closeAllTabs() sonrası onay callback'ini çağırır
//   cancelPendingClose(): bekleyen onay callback'ini düşürür
@MainActor
final class WindowCloseCoordinator: NSObject, NSWindowDelegate {
    static var live: [WindowCloseCoordinator] { get }
    static var firstBusy: WindowCloseCoordinator? { get }
    var hasRunningProcess: Bool { get }
    func attach(window: NSWindow, workspace: WorkspaceViewModel)
    func bringWindowForward()
    func requestTermination(onApproved: @escaping @MainActor () -> Void) -> Bool
}
@MainActor
final class TermoraAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply
}
```

---

- [ ] **Step 1: Pencere kapatma akışının testlerini yaz**

`/Users/ahmetbarut/Apps/Termora/TermoraTests/WorkspaceViewModelTests.swift` içine, `hasAnyRunningProcessReflectsSessionState` testinden sonra ekle:

```swift
    // MARK: - Pencere / uygulama kapatma

    @Test func hasAnyRunningProcessScansEveryTab() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        workspace.newTab()
        workspace.newTab()
        #expect(workspace.hasAnyRunningProcess() == false)

        let busySessionID = workspace.tabs[1].root.leaves[0].sessionID
        manager.busySessionIDs.insert(busySessionID)
        #expect(workspace.hasAnyRunningProcess())

        manager.terminateSession(id: busySessionID)
        #expect(workspace.hasAnyRunningProcess() == false)
    }

    @Test func requestCloseWindowAllowsClosingWhenNothingIsRunning() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        var approvedCount = 0

        let canCloseNow = workspace.requestCloseWindow { approvedCount += 1 }

        #expect(canCloseNow)
        #expect(workspace.pendingClose == nil)
        // Onay istenmediği için callback de çalışmaz; oturumları çağıran kapatır.
        #expect(approvedCount == 0)
        #expect(manager.terminatedSessionIDs.isEmpty)
    }

    @Test func requestCloseWindowAsksForConfirmationWhenSomethingIsRunning() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        workspace.newTab()
        manager.busySessionIDs.insert(workspace.tabs[1].root.leaves[0].sessionID)
        var approvedCount = 0

        let canCloseNow = workspace.requestCloseWindow { approvedCount += 1 }

        #expect(canCloseNow == false)
        #expect(workspace.pendingClose?.target == .window)
        #expect(approvedCount == 0)
        #expect(manager.terminatedSessionIDs.isEmpty)
        #expect(workspace.tabs.count == 2)
    }

    @Test func confirmingWindowCloseTerminatesSessionsThenRunsTheApproval() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        workspace.newTab()
        let sessionIDs = workspace.tabs.map { $0.root.leaves[0].sessionID }
        manager.busySessionIDs.insert(sessionIDs[0])
        var terminatedCountAtApproval = -1
        _ = workspace.requestCloseWindow { terminatedCountAtApproval = manager.terminatedSessionIDs.count }

        workspace.confirmPendingClose()

        // Onay callback'i, oturumlar kapatıldıktan SONRA çağrılmalı: pencere kapanırken
        // arkada canlı shell kalmamalı.
        #expect(terminatedCountAtApproval == 2)
        #expect(Set(manager.terminatedSessionIDs) == Set(sessionIDs))
        #expect(workspace.tabs.isEmpty)
        #expect(workspace.activeTabID == nil)
        #expect(workspace.pendingClose == nil)
    }

    @Test func cancellingWindowCloseKeepsSessionsAndDropsTheApproval() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        manager.busySessionIDs.insert(workspace.tabs[0].root.leaves[0].sessionID)
        var approvedCount = 0
        _ = workspace.requestCloseWindow { approvedCount += 1 }

        workspace.cancelPendingClose()

        #expect(workspace.pendingClose == nil)
        #expect(workspace.tabs.count == 1)
        #expect(manager.terminatedSessionIDs.isEmpty)
        #expect(approvedCount == 0)

        // Vazgeçilen onay unutulur: yeni bir istek olmadan callback bir daha çalışamaz.
        workspace.confirmPendingClose()
        #expect(approvedCount == 0)
    }

    @Test func pendingCloseMessageDescribesTheTarget() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        let tab = workspace.tabs[0]
        manager.busySessionIDs.insert(tab.root.leaves[0].sessionID)

        #expect(workspace.pendingCloseMessage.isEmpty)

        workspace.requestCloseTab(id: tab.id)
        #expect(workspace.pendingCloseMessage == "Bu sekmede çalışan bir işlem var. Sekme kapatılsın mı?")

        workspace.cancelPendingClose()
        _ = workspace.requestCloseWindow {}
        #expect(workspace.pendingCloseMessage == "Çalışan işlemler var. Tüm oturumlar kapatılsın mı?")
    }
```

- [ ] **Step 2: Testi çalıştır, FAIL bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/WorkspaceViewModelTests 2>&1 | tail -20
```

Beklenen: `error: value of type 'WorkspaceViewModel' has no member 'requestCloseWindow'` (ve `pendingCloseMessage` için aynısı) → `** TEST BUILD FAILED **`.

- [ ] **Step 3: WorkspaceViewModel'e pencere kapatma kancasını ekle**

`/Users/ahmetbarut/Apps/Termora/Termora/ViewModels/WorkspaceViewModel.swift` içinde, `hasAnyRunningProcess()` metodunun hemen ardına ekle:

```swift
    // MARK: - Pencere / uygulama kapatma

    /// `.window` hedefli onay verildiğinde çalıştırılacak eylem.
    /// `requestCloseWindow(onApproved:)` kurar; onay ya da iptal temizler.
    /// Kapatma kararı burada tutulduğu için akış AppKit olmadan test edilebilir.
    private var windowCloseApproval: (@MainActor () -> Void)?

    /// Pencere ya da uygulama kapatılmak isteniyor.
    /// - Parameter onApproved: Kullanıcı onaylarsa, oturumlar sonlandırıldıktan SONRA çağrılır.
    /// - Returns: Çalışan işlem yoksa `true` — çağıran kapanışa hemen devam edebilir.
    ///   Çalışan işlem varsa onay diyaloğu kurulur ve `false` döner.
    func requestCloseWindow(onApproved: @escaping @MainActor () -> Void) -> Bool {
        guard hasAnyRunningProcess() else { return true }
        windowCloseApproval = onApproved
        pendingClose = PendingClose(id: UUID(), target: .window)
        return false
    }

    /// Onay diyaloğunun başlığı; hedefe göre değişir (aynı diyalog üç akışta kullanılıyor).
    var pendingCloseMessage: String {
        switch pendingClose?.target {
        case .tab:
            return "Bu sekmede çalışan bir işlem var. Sekme kapatılsın mı?"
        case .pane:
            return "Bu panelde çalışan bir işlem var. Panel kapatılsın mı?"
        case .window:
            return "Çalışan işlemler var. Tüm oturumlar kapatılsın mı?"
        case nil:
            return ""
        }
    }
```

- [ ] **Step 4: confirmPendingClose / cancelPendingClose'u onay callback'ine bağla**

Aynı dosyada, Task 11'de yazılan (ve Task 16 Step 8'de `.pane` dalı eklenen) iki metodun gövdesini değiştir. **`.tab` ve `.pane` dalları Task 16'daki hâliyle aynen korunur** — özellikle `.pane` dalı iki argümanlı `closePane(paneID:in:)`'i çağırır; tek argümanlı `closePane(paneID:)` Task 16'da silindiğinden onu çağırmak `error: cannot find 'closePane(paneID:)'` verir:

```swift
    func confirmPendingClose() {
        guard let pending = pendingClose else { return }
        pendingClose = nil
        let approval = windowCloseApproval
        windowCloseApproval = nil
        switch pending.target {
        case let .tab(tabID):
            closeTab(id: tabID)
        case let .pane(paneID):
            guard let tab = tabs.first(where: { $0.root.sessionID(ofPane: paneID) != nil }) else { return }
            closePane(paneID: paneID, in: tab)
        case .window:
            // Önce oturumlar sonlandırılır, sonra pencere/uygulama kapatılır:
            // ters sırada shell'ler SessionManager cache'inde öksüz kalırdı.
            closeAllTabs()
            approval?()
        }
    }

    func cancelPendingClose() {
        windowCloseApproval = nil
        pendingClose = nil
    }
```

- [ ] **Step 5: Testi çalıştır, PASS bekle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -only-testing:TermoraTests/WorkspaceViewModelTests 2>&1 | tail -20
```

Beklenen: `** TEST SUCCEEDED **` (Task 11/13'ten gelen testler + bu görevin 6 testi).

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora && git add Termora/ViewModels/WorkspaceViewModel.swift TermoraTests/WorkspaceViewModelTests.swift && git commit -m "feat: add window close approval hook to WorkspaceViewModel"
```

- [ ] **Step 7: WindowCloseCoordinator'ı yaz**

`/Users/ahmetbarut/Apps/Termora/Termora/App/WindowCloseCoordinator.swift` oluştur:

```swift
import AppKit
import Foundation

/// Pencerenin kapat düğmesini (ve ⌘Q akışını) "çalışan işlem var mı?" onayına bağlar.
///
/// `NSWindow.delegate` zayıf tutulur; bu nesneyi `MainWindowView` bir `@State` içinde canlı
/// tutar. SwiftUI'nin kurduğu özgün delege korunur ve BURADA GERÇEKLENMEYEN tüm delege
/// mesajları ObjC iletimiyle ona aktarılır — aksi hâlde çerçevenin kendi pencere davranışları
/// (kapanış temizliği, geri yükleme) sessizce ölür.
@MainActor
final class WindowCloseCoordinator: NSObject, NSWindowDelegate {

    /// Canlı koordinatörler (zayıf tutulur). Uygulama kapanışında hangi pencerede iş
    /// çalıştığını bulmak için gerekir: `@FocusedValue` uygulama delegesinden okunamaz.
    private static let liveTable = NSHashTable<WindowCloseCoordinator>.weakObjects()

    static var live: [WindowCloseCoordinator] { liveTable.allObjects }

    static var firstBusy: WindowCloseCoordinator? {
        live.first { $0.hasRunningProcess }
    }

    private weak var window: NSWindow?
    private weak var workspace: WorkspaceViewModel?

    /// SwiftUI'nin kurduğu delege; işlemediğimiz mesajlar buna iletilir.
    private weak var previousDelegate: (any NSObjectProtocol)?

    /// Onay alındıktan sonraki `close()` çağrısında tekrar sormamak için bayrak.
    private var isClosingAfterApproval = false

    override init() {
        super.init()
        Self.liveTable.add(self)
    }

    /// Pencereyi bağlar. `WindowAccessor` her yerleşim turunda çağırabilir: idempotenttir.
    /// SwiftUI delegeyi sonradan geri alırsa bir sonraki çağrıda yeniden devralınır.
    func attach(window: NSWindow, workspace: WorkspaceViewModel) {
        self.workspace = workspace
        self.window = window
        guard window.delegate !== self else { return }
        if let existing = window.delegate {
            previousDelegate = existing
        }
        window.delegate = self
    }

    var hasRunningProcess: Bool {
        workspace?.hasAnyRunningProcess() ?? false
    }

    func bringWindowForward() {
        window?.makeKeyAndOrderFront(nil)
    }

    /// Uygulama kapanışı için onay ister; `true` dönerse beklemeden kapanılabilir.
    func requestTermination(onApproved: @escaping @MainActor () -> Void) -> Bool {
        guard let workspace else { return true }
        return workspace.requestCloseWindow(onApproved: onApproved)
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isClosingAfterApproval { return true }
        guard let workspace else { return true }

        let canCloseNow = workspace.requestCloseWindow { [weak self] in
            self?.closeAfterApproval()
        }
        guard canCloseNow else { return false }

        // Çalışan işlem yok: onay gerekmiyor, ama oturumlar yine de burada kapatılmalı.
        // SessionManager view cache'i uygulama ömürlüdür; kapatmazsak pencere gitse de
        // boştaki shell süreçleri yaşamaya devam eder.
        workspace.closeAllTabs()
        return true
    }

    private func closeAfterApproval() {
        isClosingAfterApproval = true
        // Diyalog kapanışıyla aynı run-loop turunda close() çağırmak sheet'i yarım bırakır.
        DispatchQueue.main.async { [weak self] in
            self?.window?.close()
        }
    }

    // MARK: - Delege iletimi

    // AppKit bu iki mesajı her zaman ana iş parçacığında gönderir; `assumeIsolated`
    // Task 8'de SwiftTerm delegeleri için kullanılan kalıbın aynısıdır.
    nonisolated override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return MainActor.assumeIsolated {
            previousDelegate?.responds(to: aSelector) ?? false
        }
    }

    nonisolated override func forwardingTarget(for aSelector: Selector!) -> Any? {
        MainActor.assumeIsolated { () -> (any NSObjectProtocol)? in
            guard previousDelegate?.responds(to: aSelector) == true else { return nil }
            return previousDelegate
        }
    }
}
```

- [ ] **Step 8: MainWindowView'a koordinatörü ve hedefe göre diyalog metnini bağla**

`/Users/ahmetbarut/Apps/Termora/Termora/Views/MainWindowView.swift` üzerinde üç düzenleme:

**(a)** `@State private var workspace: WorkspaceViewModel` satırının altına ekle:

```swift
    /// Pencere kapatma delegesi. `@State` tutulur çünkü `NSWindow.delegate` zayıftır;
    /// başka bir sahibi olmazsa ilk yerleşimden hemen sonra yok olur.
    @State private var closeCoordinator = WindowCloseCoordinator()
```

**(b)** `body` içindeki `.focusedSceneValue(\.workspace, workspace)` satırının hemen altına ekle:

```swift
        .background(
            WindowAccessor { window in
                closeCoordinator.attach(window: window, workspace: workspace)
            }
        )
```

**(c)** `.confirmationDialog(...)` çağrısının sabit başlığını hedefe göre değişen metinle değiştir (⌘Q ve panel kapatma akışlarında "Bu sekmede…" metni yanlıştı):

```swift
        .confirmationDialog(
            workspace.pendingCloseMessage,
            isPresented: pendingCloseBinding
        ) {
            Button("Kapat", role: .destructive) { workspace.confirmPendingClose() }
            Button("Vazgeç", role: .cancel) { workspace.cancelPendingClose() }
        }
```

- [ ] **Step 9: TermoraAppDelegate'i yaz ve TermoraApp'e bağla**

`/Users/ahmetbarut/Apps/Termora/Termora/App/TermoraAppDelegate.swift` oluştur:

```swift
import AppKit

/// ⌘Q akışı: herhangi bir pencerede çalışan işlem varsa önce onay ister.
///
/// `.terminateLater` BİLEREK kullanılmadı: AppKit o yanıtta run loop'u
/// `NSModalPanelRunLoopMode`'a alıp `reply(toApplicationShouldTerminate:)` bekler ve
/// SwiftUI'nin `confirmationDialog`'u bu modda güvenilir biçimde çizilmez (uygulama
/// diyalog görünmeden asılı kalır). Bunun yerine `.terminateCancel` dönülür; onay gelince
/// kapanış `NSApp.terminate(nil)` ile yeniden başlatılır. Onaylanan pencerenin oturumları
/// kapandığı için o pencere artık meşgul değildir; sırada başka meşgul pencere varsa onun
/// için de onay istenir, hiçbiri kalmayınca `.terminateNow` dönülür (sonsuz döngü yok).
@MainActor
final class TermoraAppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator = WindowCloseCoordinator.firstBusy else { return .terminateNow }

        // Onay sheet'i o pencereye iliştiği için pencere öne getirilir.
        coordinator.bringWindowForward()

        let canTerminateNow = coordinator.requestTermination {
            // Diyalog kapanırken terminate() çağırmak sheet'i yarım bırakır.
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        return canTerminateNow ? .terminateNow : .terminateCancel
    }
}
```

`/Users/ahmetbarut/Apps/Termora/Termora/App/TermoraApp.swift` içinde, `struct TermoraApp: App {` satırının hemen altına ekle (mevcut `@State private var services = AppServices()` özelliği ve sahneler aynen kalır; başka özellik eklenmez):

```swift
    @NSApplicationDelegateAdaptor(TermoraAppDelegate.self) private var appDelegate
```

- [ ] **Step 10: Derle**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet && echo BUILD_OK
```

Beklenen: `BUILD_OK`.

- [ ] **Step 11: Elle doğrulama — kapanış onayları**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -derivedDataPath /tmp/termora-dd -quiet && open -n /tmp/termora-dd/Build/Products/Debug/Termora.app
```

Her maddeyi gözle doğrula (kontrol komutlarını **başka bir terminal uygulamasında**, örneğin Terminal.app'te çalıştır):

1. Termora'da `sleep 300` başlat → pencerenin kırmızı kapat düğmesine tıkla → **"Çalışan işlemler var. Tüm oturumlar kapatılsın mı?"** diyaloğu çıkar (eski "Bu sekmede…" metni değil).
2. **Vazgeç** → pencere açık kalır; kontrol: `pgrep -f "sleep 300"` **dolu**.
3. Tekrar kapat düğmesi → **Kapat** → pencere kapanır; kontrol: `pgrep -f "sleep 300"` **boş** (çıkış kodu 1).
4. `File ▸ New Window` (⌘N) ile yeni pencere aç, hiçbir komut çalıştırmadan kapat düğmesine bas → onay **sorulmaz**, pencere hemen kapanır. Kontrol: `pgrep -P "$(pgrep -x Termora)"` → **boş** (boştaki shell'ler de kapandı, sızıntı yok).
5. Yeni pencerede `sleep 300` başlat → **⌘Q** → aynı onay diyaloğu çıkar; **Vazgeç** → uygulama açık kalır ve `sleep` sürer.
6. Tekrar **⌘Q** → **Kapat** → uygulama kapanır. Kontrol: `pgrep -x Termora` ve `pgrep -f "sleep 300"` **boş**.
7. Uygulamayı yeniden aç, hiçbir komut çalıştırmadan **⌘Q** → onaysız kapanır.
8. Uygulamayı aç, iki pencere aç (⌘N), yalnız ikinci pencerede `sleep 300` çalıştır, sonra birinci pencereye geç ve **⌘Q** → **meşgul pencere öne gelir** ve onayı o sorar; **Kapat** → uygulama kapanır, `pgrep -f "sleep 300"` boş.
9. Sekme kapatma onayının metni bozulmamış: bir sekmede `sleep 300` çalıştır → **⌘W** → "Bu sekmede çalışan bir işlem var. Sekme kapatılsın mı?"; bir panelde `sleep 300` + **⌘⇧W** → "Bu panelde çalışan bir işlem var. Panel kapatılsın mı?".

- [ ] **Step 12: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora && git add Termora/App/WindowCloseCoordinator.swift Termora/App/TermoraAppDelegate.swift Termora/App/TermoraApp.swift Termora/Views/MainWindowView.swift && git commit -m "feat: confirm window and app close while processes are running"
```

- [ ] **Step 13: Performans doğrulaması — açılış süresi (<1 sn)**

Spec §10 hedefi: **<1 sn açılış**. Ölçüm "uygulama başlatıldı → ilk canlı shell doğdu" arası; shell süreci Termora'nın çocuğu olarak ancak ilk terminal paneli kurulunca oluşur, dolayısıyla ilk kullanılabilir pencere için iyi bir vekildir.

```bash
cd /Users/ahmetbarut/Apps/Termora
xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -configuration Release -derivedDataPath /tmp/termora-dd -quiet && echo BUILD_OK
pkill -x Termora 2>/dev/null
python3 - /tmp/termora-dd/Build/Products/Release/Termora.app <<'PY'
import subprocess, sys, time

app = sys.argv[1]
def measure():
    t0 = time.monotonic()
    subprocess.run(["open", "-n", app], check=True)
    deadline = t0 + 20
    while time.monotonic() < deadline:
        pids = subprocess.run(["pgrep", "-x", "Termora"],
                              capture_output=True, text=True).stdout.split()
        if pids:
            kids = subprocess.run(["pgrep", "-P", pids[0]],
                                  capture_output=True, text=True).stdout.split()
            if kids:
                return time.monotonic() - t0
        time.sleep(0.01)
    return None

cold = measure()
print(f"cold : {cold:.2f} s" if cold else "cold : TIMEOUT")
subprocess.run(["pkill", "-x", "Termora"])
time.sleep(1.0)
warm = measure()
print(f"warm : {warm:.2f} s" if warm else "warm : TIMEOUT")
PY
```

Ölçüt: **warm < 1.00 s**. (cold ölçüm Launch Services/dyld ısınmasını da içerir; 1 sn'yi aşabilir, kabul.) Hedef tutmuyorsa `AppServices.init` içindeki store/tema yüklemeleri profillenir. Ölçülen değerleri commit mesajına ya da bu adımın altına not düş.

- [ ] **Step 14: Performans doğrulaması — ≥10 eşzamanlı oturum + yoğun çıktıda tuş gecikmesi**

Spec §10'un kalan iki hedefi burada ölçülür: **≥10 eşzamanlı oturum** (madde 1-2) ve **yoğun çıktı altında yazarken fark edilir gecikme yok** (madde 3-5). Uygulama açıkken:

1. **⌘T** ile toplam **10 sekme** aç, sonra 10. sekmede **⌘D** ile bir kez böl (toplam **11 oturum** — hedef ≥10). Her panelde prompt gelmeli, hiçbiri boş/siyah kalmamalı.
2. Oturum sayısını ve kaynak kullanımını ölç:

```bash
PID=$(pgrep -x Termora)
echo "shell sayısı: $(pgrep -P "$PID" | wc -l | tr -d ' ')"
top -pid "$PID" -l 6 -s 1 -stats pid,cpu,mem | awk '/^[0-9]+/ {print "cpu=" $2 "  mem=" $3}' | tail -5
```

Ölçüt: `shell sayısı: 11` (**≥10**), boştaki `cpu` **%3'ün altında**.

3. **Tuş gecikmesi için önce boştaki taban değeri ölç.** 1. sekmedeki panele odaklan ve orada şunu başlat (yazdığın satırı dosyaya akıtır):

```
cat > /tmp/termora-key.log
```

Ardından **başka bir terminal uygulamasında** (Terminal.app) ölçüm betiğini çalıştır — betik Termora'yı öne getirir, bir tuş + Enter gönderir ve karakterin PTY'nin öbür ucuna ulaşmasını bekler. (İlk çalıştırmada macOS, kontrol eden terminal için Erişilebilirlik izni ister; onayla.)

```bash
cat > /tmp/termora-keylatency.py <<'PY'
import os, subprocess, sys, time
log = "/tmp/termora-key.log"
open(log, "w").close()
subprocess.run(["osascript", "-e", 'tell application "Termora" to activate'], check=True)
time.sleep(0.5)
t0 = time.monotonic()
subprocess.run(["osascript",
                "-e", 'tell application "System Events" to keystroke "x"',
                "-e", 'tell application "System Events" to key code 36'], check=True)
while os.path.getsize(log) == 0 and time.monotonic() - t0 < 5:
    time.sleep(0.005)
size = os.path.getsize(log)
print(f"{sys.argv[1]}: {(time.monotonic()-t0)*1000:.0f} ms" if size else f"{sys.argv[1]}: TIMEOUT")
PY
python3 /tmp/termora-keylatency.py bosta
```

Taban değeri not et (AppleScript'in kendi ek yükü dahil, tipik olarak 100-200 ms).

4. 10. sekmede yoğun çıktı üret ve **çalışırken** aynı ölçümü yinele:

```
yes "termora stress test satiri" | head -n 3000000
```

Komut sürerken (yaklaşık 10 sn) 1. sekmeye dön (`cat` hâlâ çalışıyor) ve diğer terminalde:

```bash
python3 /tmp/termora-keylatency.py yogun-cikti
```

Ölçüt: **yoğun çıktı altındaki değer, boştaki tabanı en fazla 100 ms aşar ve mutlak olarak 400 ms'nin altındadır** (TIMEOUT = başarısız). Aynı sırada elle de sına: ⌘⇧] / ⌘⇧[ ile sekmeler arasında geç, başka bir sekmeye `echo merhaba` yaz, ⌘D ile böl ve ayracı sürükle, durum çubuğunda göstergenin `çalışıyor` olduğunu gör — **hiçbir aşamada donma yok**, kaydırma akıcı (PTY okuması SwiftTerm'de DispatchIO ile arka planda). Ölçülen iki değeri Step 19'daki kapanış commit'inin mesajına ya da bu adımın altına not düş. Bitince 1. sekmedeki `cat`'i Ctrl-D ile kapat.

5. Aynı anda ikinci bir terminalde CPU'yu örnekle:

```bash
top -pid "$(pgrep -x Termora)" -l 11 -s 1 -stats pid,cpu,mem | awk '/^[0-9]+/ {print "cpu=" $2 "  mem=" $3}' | tail -10
```

Ölçüt: çıktı akarken `cpu` tek çekirdeği doyurabilir ama komut bittikten sonra en geç 2 sn içinde **%3'ün altına** düşer; `mem` sürekli büyümez (scrollback sınırı iş görüyor).

6. Sekmeleri kapatıp uygulamayı kapat; `pgrep -P "$(pgrep -x Termora)"` boş, ardından `pgrep -x Termora` boş olmalı (artık süreç sızıntısı yok). Geçici ölçüm dosyalarını temizle: `rm -f /tmp/termora-key.log /tmp/termora-keylatency.py`.

- [ ] **Step 15: Cila — şablon dosyasını sil**

```bash
cd /Users/ahmetbarut/Apps/Termora
git rm TermoraTests/TermoraTests.swift
ls Termora/Services/SwiftTermLinkCheck.swift 2>/dev/null && echo "UYARI: Task 8 Step 10 bu dosyayı silmemiş" || echo "SwiftTermLinkCheck zaten silinmiş (Task 8)"
xcodebuild build -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' -quiet && echo BUILD_OK
```

Beklenen: `SwiftTermLinkCheck zaten silinmiş (Task 8)` ve `BUILD_OK`. `Termora/Services/SwiftTermLinkCheck.swift` **bu görevde silinmez** — Task 1'in geçici link doğrulaması Task 8'in commit adımında (`git rm`) kaldırılmıştır; burada yalnız gerçekten gittiği doğrulanır. Uyarı görürsen `git rm Termora/Services/SwiftTermLinkCheck.swift` ile temizle. `TermoraUITests` hedefindeki Xcode şablon testleri **kalır** (spec §11'deki açılış smoke testinin karşılığıdır; Task 13'ün `TabSmokeUITests`'i de aynı hedefte yaşar).

- [ ] **Step 16: README.md'yi yaz**

`/Users/ahmetbarut/Apps/Termora/README.md` oluştur:

````markdown
# Termora

macOS için native terminal uygulaması: sekmeler, bölünebilir paneller, arama, temalar ve
profiller. SwiftUI kabuğu + [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 1.15.0.

- Gereksinim: macOS 14.0+, Xcode 16+ (Swift 5, Swift Testing)
- Bağımlılık: SwiftTerm (SPM, ilk açılışta Xcode kendisi çözer)

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
| ⌘, | Ayarlar (Genel, Görünüm, Profiller) |

## Klasör düzeni

`Termora/App` uygulama girişi ve menüler · `Termora/Models` saf modeller ·
`Termora/ViewModels` pencere durumu · `Termora/Services` shell, oturum, tema, süreç
sorgulama · `Termora/Views` SwiftUI arayüzü · `TermoraTests` Swift Testing birim testleri.

Not: Uygulama sandbox'sız çalışır (yerel shell başlatabilmesi için) ve hiçbir ağ erişimi
yapmaz.
````

- [ ] **Step 17: Tüm test paketini çalıştır**

```bash
cd /Users/ahmetbarut/Apps/Termora && xcodebuild test -project Termora.xcodeproj -scheme Termora -destination 'platform=macOS' 2>&1 | tail -25
```

Beklenen: `** TEST SUCCEEDED **`. Bu çağrıda `-only-testing` yok: `TermoraTests` (tüm suite'ler) **ve** `TermoraUITests` şablon testleri koşar; UI testleri uygulamayı açıp kapattığı için toplam süre birkaç dakikayı bulabilir ve macOS ilk kez otomasyon izni sorabilir — sorarsa onayla. Bir birim testi kırıldıysa `-only-testing:TermoraTests/<Suite>` ile daraltıp düzelt; bu adım yeşil olmadan görev bitmez.

- [ ] **Step 18: Commit**

```bash
cd /Users/ahmetbarut/Apps/Termora && git add -A && git commit -m "chore: drop template files, add README with run and test instructions"
```

- [ ] **Step 19: M5 kapanış commit'i**

```bash
cd /Users/ahmetbarut/Apps/Termora
git status --short
git commit --allow-empty -m "chore: close milestone M5 after manual performance verification"
```

Beklenen: `git status --short` temiz; boş commit, spec §10'un üç ölçütünün de elle onaylandığını tarihçeye işaretler: **açılış (warm) < 1 sn** (Step 13), **≥10 eşzamanlı oturum** (Step 14 madde 1-2), **yoğun çıktı altında tuş gecikmesi tabanın en fazla 100 ms üstünde ve < 400 ms** (Step 14 madde 3-4). Üçünden biri tutmuyorsa bu commit atılmaz; önce ilgili adımın altındaki iyileştirme notu uygulanır.

---

---

## Ek: Kaynak Kodda Doğrulanmış SwiftTerm Sembolleri

- SwiftTerm.Color — public class Color: Hashable (Sources/SwiftTerm/Colors.swift, WebFetch ile doğrulandı)
- SwiftTerm.Color.red / .green / .blue — public var UInt16 (testlerde bileşen okumak için kullanılıyor)
- SwiftTerm.Color.== — public static func == (lhs: Color, rhs: Color) -> Bool (testlerde eşitlik karşılaştırması için kullanılıyor)
- TerminalView.send(txt: String) — public, Sources/SwiftTerm/Apple/AppleTerminalView.swift:2307 (extension TerminalView). Not: MacTerminalView.swift'teki private send(txt:) ile karıştırılmamalı; public olan Apple/AppleTerminalView.swift'tekidir.
- TerminalView.send(data: ArraySlice<UInt8>) — public, AppleTerminalView.swift:2289
- TerminalView.feed(text: String) — public, AppleTerminalView.swift:2255 (süreç başlamadan da yazılabilir; shell çalıştırılamadı bandı için kullanıldı)
- TerminalView.changeScrollback(_ newScrollback: Int?) — public, AppleTerminalView.swift:2277 (Terminal.changeScrollback'in üstünde; ayrıca scroller'ı da günceller)
- TerminalView.setFrameSize(_ newSize: NSSize) — open override, MacTerminalView.swift:966 (alt sınıfta override edilebilir)
- TerminalView.getTerminal() -> Terminal — public, AppleTerminalView.swift:218
- TerminalView.installColors(_ colors: [Color]) — public, AppleTerminalView.swift:412
- TerminalView.lineSpacing — @objc open var CGFloat, AppleTerminalView.swift:128
- TerminalView.nativeForegroundColor / nativeBackgroundColor — public var NSColor; getter tam olarak set edilen NSColor'ı döner (MacTerminalView.swift:671, 687) — alpha testlerinde bu doğrulandı
- TerminalView.acceptsFirstResponder — public override, MacTerminalView.swift:1030
- LocalProcessTerminalView.init(frame: CGRect) — public override; required init?(coder:) — public required (MacLocalTerminalView.swift:70-79); alt sınıf her ikisini de karşılamalı
- LocalProcessTerminalView.process — public internal(set) var LocalProcess!, MacLocalTerminalView.swift:68
- LocalProcessTerminalView.terminate() — public; yalnız process.terminate() (shellPid'e SIGTERM), MacLocalTerminalView.swift:184
- LocalProcess.send(data: ArraySlice<UInt8>) — public, LocalProcess.swift:215 (running false ise sessizce yutar)
- LocalProcess.running — public private(set) var Bool, LocalProcess.swift:473
- LocalProcess.init(delegate:dispatchQueue:) — dispatchQueue nil ise DispatchQueue.main (LocalProcess.swift:127); LocalProcessTerminalView.setup() bunu nil ile çağırır, dolayısıyla processTerminated/dataReceived ANA KUYRUKTA gelir — MainActor.assumeIsolated güvenli
- LocalProcess.processTerminated() — waitpid(shellPid, &n, WNOHANG) sonucu HAM status olarak delegate'e geçer (LocalProcess.swift:365-369)
- Terminal.setCursorStyle(_ style: CursorStyle) — public, Terminal.swift:3235
- Terminal.changeScrollback(_ newScrollback: Int?) — public, Terminal.swift:5550
- SearchOptions — public struct, Equatable; `public init(caseSensitive: Bool = false, regex: Bool = false, wholeWord: Bool = false)` (Sources/SwiftTerm/SearchOptions.swift:11-24). DİKKAT: alan adı `regex`, `usesRegex` DEĞİL (Task 20'de doğrulandı)
- TerminalView.findNext(_ term: String, options: SearchOptions = SearchOptions(), scrollToResult: Bool = true) -> Bool — @discardableResult public, TerminalViewSearch.swift:19. Üç parametrenin ikisi varsayılanlı; eşleşme yoksa seçimi temizler ve false döner
- TerminalView.findPrevious(_ term: String, options: SearchOptions = SearchOptions(), scrollToResult: Bool = true) -> Bool — @discardableResult public, TerminalViewSearch.swift:40
- TerminalView.searchMatchSummary(_ term: String, options: SearchOptions = SearchOptions(), limit: Int = 1000) -> (index: Int, total: Int) — public, TerminalViewSearch.swift:58. `index` 1 tabanlı, aktif eşleşme yoksa 0. İçeride `SearchService.findAll` çağırır (tüm tamponu tarar) ama `lastResult`'ı DEĞİŞTİRMEZ, dolayısıyla findNext'in hemen ardından çağrılabilir
- TerminalView.clearSearch() — public, TerminalViewSearch.swift:71; `search?.reset()` + `selection?.selectNone()`
- Not: alternatif ekranda (`isDisplayBufferAlternate`) `scrollToReveal` erken döner — vim/less içindeyken eşleşmeye kaydırma yapılmaz (TerminalViewSearch.swift:106)
