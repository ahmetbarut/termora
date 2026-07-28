import Foundation

/// `termora://open?path=…` şemasının SAF ayrıştırıcısı (briefs/2 "Hızlı Açma").
///
/// # Tehdit modeli
///
/// Bu şema uygulamanın DIŞINDAN tetiklenir: herhangi bir web sayfasındaki bir bağlantı,
/// bir e-posta ya da başka bir uygulama Termora'yı bu URL ile uyandırabilir. Girdi
/// tamamen düşmanca kabul edilir.
///
/// Kurallar:
/// 1. **Komut çalıştırma YOKTUR.** Şemanın tek yeteneği bir klasörü yeni sekmede açmaktır.
///    `command`, `exec`, `run`, `args`, `startupCommand` gibi bir parametre desteklenmez ve
///    ASLA desteklenmeyecektir. Böyle bir parametre *yok sayılmaz*, URL'in TAMAMINI
///    reddettirir — sessizce yok saymak saldırgana "bir sonraki sürümde tutar mı?" denemesi
///    için ücretsiz bir kapı bırakır ve geçerli bir yolun yanına iliştirilen komutun fark
///    edilmeden düşmesine yol açar.
/// 2. Yalnız `open` eylemi vardır; bilinmeyen eylem reddedilir.
/// 3. Yol yüzde kodlamasından çözülür, `~` genişletilir, `.`/`..` çözülür ve sonuç mutlak
///    olmak zorundadır.
/// 4. Yol GERÇEKTEN var olan bir KLASÖR olmalıdır; dosya yolu ve olmayan yol reddedilir.
///
/// Açılan klasör kabuğa bir komut olarak GEÇMEZ: `SessionManager` onu
/// `startProcess(currentDirectory:)`e verir (chdir), yani yol adının içindeki kabuk
/// meta karakterleri yorumlanamaz.
///
/// `nonisolated`: saf ayrıştırma, paylaşılan durum yok (bkz. `QuickOpenPath`).
nonisolated enum TermoraURL {

    /// Info.plist'teki `CFBundleURLSchemes` ile AYNI olmalı.
    static let scheme = "termora"
    static let openAction = "open"
    static let pathParameter = "path"

    /// Şemanın desteklediği TEK istek. Yeni bir case eklemek ürün kararıdır — komut
    /// çalıştıran bir case buraya asla eklenmez.
    enum Request: Equatable {
        case openFolder(path: String)
    }

    /// URL'in neden reddedildiği. Çağıran bunu loglar; kullanıcıya modal bir hata
    /// gösterilmez (dışarıdan tetiklenen bir istek, kullanıcıya diyalog gösterme hakkı
    /// kazandırmaz — bu da bir taciz vektörü olurdu).
    enum Rejection: Error, Equatable {
        case notATermoraURL
        case unsupportedAction(String)
        /// GÜVENLİK: `path` dışındaki her parametre. Adı log'a yazılır.
        case unsupportedParameter(String)
        case missingPathParameter
        case ambiguousPath
        case blankPath
        case notAnAbsolutePath
        case notAFolder

        /// Sistem log'una yazılabilir SABİT etiket.
        ///
        /// İliştirilmiş metin (parametre adı, eylem adı) tamamen SALDIRGAN KONTROLÜNDEDİR;
        /// serbest metni log'a geçirmek log enjeksiyonuna ve sınırsız büyümeye açık kapı
        /// bırakır. Bu yüzden yalnız case adı yazılır.
        var logLabel: String {
            switch self {
            case .notATermoraURL: return "notATermoraURL"
            case .unsupportedAction: return "unsupportedAction"
            case .unsupportedParameter: return "unsupportedParameter"
            case .missingPathParameter: return "missingPathParameter"
            case .ambiguousPath: return "ambiguousPath"
            case .blankPath: return "blankPath"
            case .notAnAbsolutePath: return "notAnAbsolutePath"
            case .notAFolder: return "notAFolder"
            }
        }
    }

    /// - Parameter isDirectory: dosya sistemi kontrolü; testlerde sabitlenir.
    static func parse(_ url: URL,
                      home: String = NSHomeDirectory(),
                      isDirectory: (String) -> Bool = QuickOpenPath.directoryExistsOnDisk)
        -> Result<Request, Rejection> {

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme else {
            return .failure(.notATermoraURL)
        }

        // `termora://open?…` ve `termora:open?…` aynı isteği anlatır: ilkinde eylem host,
        // ikincisinde yol bileşenidir. Eylemin ARDINDAN gelen bileşenler (örn.
        // `termora://open/etc/passwd`) tanınmaz — sessizce atmak, URL'in gerçekte ne
        // istediğini gizlerdi.
        let action = ((components.host ?? "") + components.path)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard action.lowercased() == openAction else {
            return .failure(.unsupportedAction(action))
        }

        var pathValues: [String] = []
        for item in components.queryItems ?? [] {
            guard item.name.lowercased() == pathParameter else {
                return .failure(.unsupportedParameter(item.name))
            }
            pathValues.append(item.value ?? "")
        }

        guard !pathValues.isEmpty else { return .failure(.missingPathParameter) }
        guard pathValues.count == 1, let raw = pathValues.first else {
            // Hangi yolun geçerli olduğu belirsiz: hızlı açma tahmin yürütmez.
            return .failure(.ambiguousPath)
        }
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.blankPath)
        }
        guard let normalized = QuickOpenPath.normalize(raw, home: home) else {
            return .failure(.notAnAbsolutePath)
        }
        guard isDirectory(normalized) else { return .failure(.notAFolder) }

        return .success(.openFolder(path: normalized))
    }
}

/// macOS Servisler menüsündeki "Open in Termora" girdisi (briefs/2: Finder için
/// "Open in Termora").
///
/// Tam bir Finder Sync uzantısı AYRI BİR HEDEF ister; Servisler menüsü aynı işi tek bir
/// Info.plist girdisi ve tek bir `@objc` yöntemle yapar. Finder'da bir klasöre sağ
/// tıklandığında Services ▸ Open in Termora görünür.
///
/// Pano içeriği de dışarıdan gelen bir girdidir: `termora://` ile AYNI süzgeçten geçer.
nonisolated enum FinderService {

    /// Info.plist'teki `NSServices ▸ NSMessage` ile AYNI olmalı; sağlayıcı yöntemin adı
    /// bu ada `:` eklenerek türetilir (`openFolderInTermora:userData:error:`).
    static let messageName = "openFolderInTermora"

    /// Info.plist'teki `NSMenuItem ▸ default` ile aynı metin.
    static let menuItemTitle = "Open in Termora"

    /// Panodan gelen URL'lerden açılabilir klasör yollarını süzer.
    /// Dosyalar, dosya olmayan URL'ler ve tekrar edenler elenir; seçim sırası korunur.
    static func folderPaths(from urls: [URL],
                            home: String = NSHomeDirectory(),
                            isDirectory: (String) -> Bool = QuickOpenPath.directoryExistsOnDisk)
        -> [String] {

        var seen: Set<String> = []
        var paths: [String] = []
        for url in urls where url.isFileURL {
            guard let normalized = QuickOpenPath.normalize(url.path, home: home),
                  isDirectory(normalized),
                  seen.insert(normalized).inserted else { continue }
            paths.append(normalized)
        }
        return paths
    }
}
