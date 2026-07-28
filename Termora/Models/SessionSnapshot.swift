import CoreGraphics
import Foundation
import os

// briefs/2 "Oturum Geri Yükleme" / "Pencere Yönetimi":
// açık pencereler, sekmeler, split düzenleri, çalışma dizinleri, workspace bağlantıları
// ve pencere çerçevesi kaydedilir.
//
// Düzen için PARALEL bir model YOKTUR: sekme ağacı `WorkspaceTab` / `WorkspaceLayout`
// ile saklanır — workspace kayıtlarıyla tam olarak aynı tipler, aynı JSON şekli, aynı
// ileri uyumlu çözme kuralları.
//
// Oturum anlık görüntüsü asla ÇALIŞAN SÜRECİ tarif etmez: yalnız nereye `cd` yapılacağı
// yazılır. Yeniden açılışta taze shell'ler başlar (briefs/2: "çalışan shell işlemlerinin
// birebir devam edeceği vaat edilmemelidir").

/// Ekran koordinatlarında pencere çerçevesi (AppKit: orijin SOL ALT).
/// `CGRect` doğrudan `Codable` olmasına rağmen alanlar açıkça yazılır: `CGRect`'in
/// sentezlenmiş şekli iç içe `origin`/`size` sözlükleridir ve eksik alanda fırlatır.
struct SessionWindowFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        self.init(x: Double(rect.origin.x),
                  y: Double(rect.origin.y),
                  width: Double(rect.size.width),
                  height: Double(rect.size.height))
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    private enum CodingKeys: String, CodingKey {
        case x, y, width, height
    }
}

/// Kayıtlı bir sekme. `tab` alanı workspace kayıtlarındaki `WorkspaceTab`'ın AYNISIDIR
/// (kimlik, kullanıcı başlığı, panel ağacı). Yalnız aktif panel burada ek olarak tutulur:
/// odak açık düzenin durumudur, workspace tanımının değil.
struct SessionTabSnapshot: Codable, Equatable, Identifiable {
    var id: UUID { tab.id }
    var tab: WorkspaceTab
    var activePaneID: UUID?

    init(tab: WorkspaceTab, activePaneID: UUID? = nil) {
        self.tab = tab
        self.activePaneID = activePaneID
    }

    private enum CodingKeys: String, CodingKey {
        case tab, activePaneID
    }
}

/// Kayıtlı bir pencere: kendi sekmeleri, kendi çerçevesi (briefs/2 "Her pencerenin kendi
/// sekmeleri bulunmalı").
struct SessionWindowSnapshot: Codable, Equatable, Identifiable {
    var id: UUID
    var tabs: [SessionTabSnapshot]
    var activeTabID: UUID?
    /// Tam ekrandayken TAM EKRAN ÖNCESİ çerçeve yazılır; ekran boyutundaki çerçeveyi
    /// saklamak pencereyi bir daha asla eski boyutuna döndüremezdi.
    var frame: SessionWindowFrame?
    /// Kapanışta pencere tam ekranda mıydı? (Geri yükleme davranışı için bkz.
    /// `SessionWindowPlacement`.)
    var isFullScreen: Bool
    /// Pencerede açık olan workspace kaydı; yoksa nil.
    var workspaceID: UUID?

    init(id: UUID = UUID(),
         tabs: [SessionTabSnapshot] = [],
         activeTabID: UUID? = nil,
         frame: SessionWindowFrame? = nil,
         isFullScreen: Bool = false,
         workspaceID: UUID? = nil) {
        self.id = id
        self.tabs = tabs
        self.activeTabID = activeTabID
        self.frame = frame
        self.isFullScreen = isFullScreen
        self.workspaceID = workspaceID
    }

    private enum CodingKeys: String, CodingKey {
        case id, tabs, activeTabID, frame, isFullScreen, workspaceID
    }
}

/// Diske yazılan tüm oturum: uygulama kapanırken açık olan pencereler.
struct SessionSnapshot: Codable, Equatable {
    var windows: [SessionWindowSnapshot]
    var savedAt: Date?

    static let empty = SessionSnapshot()

    init(windows: [SessionWindowSnapshot] = [], savedAt: Date? = nil) {
        self.windows = windows
        self.savedAt = savedAt
    }

    private enum CodingKeys: String, CodingKey {
        case windows, savedAt
    }
}

// MARK: - İleri uyumlu çözme
//
// `Workspace.swift`'teki kuralın aynısı: sentezlenmiş `init(from:)` eksik anahtarda
// `keyNotFound` fırlatır, bu yüzden her tip kendi çözücüsünü yazar ve isteğe bağlı her
// alanı `decodeIfPresent` ile okur. Listeler `LenientArray` ile öğe öğe çözülür — tek
// bozuk sekme bütün pencereyi, tek bozuk pencere bütün oturumu düşürmez.

extension SessionWindowFrame {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Dört sayının hepsi olmadan çerçeve ANLAMSIZDIR: eksik bir boyutu uydurmak
        // pencereyi ekran dışına ya da sıfır boyuta düşürürdü. Eksikse çerçeve çözülemez
        // ve pencere varsayılan yerleşimiyle açılır.
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
    }
}

extension SessionTabSnapshot {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Düzen uydurulmaz (WorkspaceTab kendi kuralını uygular); sekme çözülemezse atlanır.
        tab = try container.decode(WorkspaceTab.self, forKey: .tab)
        activePaneID = try container.decodeIfPresent(UUID.self, forKey: .activePaneID)
    }
}

extension SessionWindowSnapshot {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Kimlik uydurulmaz: `record(_:)` upsert'i kimliğe dayanır, taze bir UUID aynı
        // pencerenin iki kez geri yüklenmesine yol açardı.
        id = try container.decode(UUID.self, forKey: .id)
        let decodedTabs = try container.decodeIfPresent(LenientArray<SessionTabSnapshot>.self, forKey: .tabs)
        if let failures = decodedTabs?.failures, !failures.isEmpty {
            // Çözücü nonisolated'dır; MainActor'a bağlı bir static logger'a dokunamaz.
            Logger(subsystem: "com.ahmetbarut.Termora", category: "SessionRestoreDecoding")
                .error("""
                    Skipped \(failures.count, privacy: .public) undecodable tab(s) while loading a session window: \
                    \(decodedTabs?.failureSummary ?? "", privacy: .public)
                    """)
        }
        tabs = decodedTabs?.elements ?? []
        activeTabID = try container.decodeIfPresent(UUID.self, forKey: .activeTabID)
        // Çerçeve yalnız GEOMETRİDİR: bozuksa pencere varsayılan yerinde açılır, sekmeler
        // yine de geri gelir. Bu yüzden hatası yutulur.
        frame = try? container.decodeIfPresent(SessionWindowFrame.self, forKey: .frame)
        isFullScreen = try container.decodeIfPresent(Bool.self, forKey: .isFullScreen) ?? false
        workspaceID = try container.decodeIfPresent(UUID.self, forKey: .workspaceID)
    }
}

extension SessionSnapshot {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedWindows = try container.decodeIfPresent(LenientArray<SessionWindowSnapshot>.self,
                                                           forKey: .windows)
        if let failures = decodedWindows?.failures, !failures.isEmpty {
            Logger(subsystem: "com.ahmetbarut.Termora", category: "SessionRestoreDecoding")
                .error("""
                    Skipped \(failures.count, privacy: .public) undecodable window(s) while loading the session: \
                    \(decodedWindows?.failureSummary ?? "", privacy: .public)
                    """)
        }
        windows = decodedWindows?.elements ?? []
        savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt)
    }
}

// MARK: - Geri yükleme planı

/// Kayıtlı bir pencereyi kurulabilir bir plana çeviren SAF dönüşüm.
///
/// İKİ güvenlik kuralı burada uygulanır (briefs/2):
/// 1. **Başlangıç komutu ÇALIŞTIRILMAZ.** Komutlar plandan söküldüğü için geri yükleme
///    yolunda çalıştırılabilecek bir komut KALMAZ — elle düzenlenmiş ya da eski bir
///    blob komut taşısa bile. Tek çıkış noktası burasıdır.
/// 2. Süreç devamlılığı taklit edilmez: plan yalnız "hangi panel, hangi dizin" der.
enum SessionRestorePlan {

    struct Tab: Equatable {
        var id: UUID
        var title: String?
        /// Temizlenmiş düzen: her panelin `startupCommand`'i nil, `startupDirectory`'si
        /// diskte GERÇEKTEN var olan bir dizin (yoksa nil → varsayılana düşülür).
        var layout: WorkspaceLayout
        var activePaneID: UUID?
    }

    /// Diskte gerçekten var olan bir DİZİN mi? Geri yüklemede varsayılan denetim budur.
    static func directoryExistsOnDisk(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    static func tabs(for window: SessionWindowSnapshot,
                     directoryExists: (String) -> Bool = directoryExistsOnDisk) -> [Tab] {
        window.tabs.map { snapshot in
            let layout = sanitized(snapshot.tab.layout, directoryExists: directoryExists)
            // Aktif panel ağaçtan DOĞRULANIR: kayıttaki kimlik artık ağaçta yoksa
            // (bozuk sekme atlanmış olabilir) ilk panele düşülür — hiçbir sekme
            // odaksız kalmaz.
            let paneIDs = layout.panes.map(\.id)
            let active = snapshot.activePaneID.flatMap { paneIDs.contains($0) ? $0 : nil }
                ?? paneIDs.first
            return Tab(id: snapshot.tab.id,
                       title: snapshot.tab.title,
                       layout: layout,
                       activePaneID: active)
        }
    }

    private static func sanitized(_ layout: WorkspaceLayout,
                                  directoryExists: (String) -> Bool) -> WorkspaceLayout {
        switch layout {
        case let .pane(pane):
            return .pane(WorkspacePane(id: pane.id,
                                       startupDirectory: resolvedDirectory(pane.startupDirectory,
                                                                           directoryExists: directoryExists),
                                       startupCommand: nil))
        case let .split(axis, ratio, first, second):
            return .split(axis: axis,
                          ratio: ratio,
                          first: sanitized(first, directoryExists: directoryExists),
                          second: sanitized(second, directoryExists: directoryExists))
        }
    }

    /// Silinmiş klasör ÇÖKERTMEZ: dizin artık yoksa nil dönülür ve panel, `SessionManager`'ın
    /// normal geri düşüşüyle (ayarlardaki başlangıç dizini, o da yoksa ev dizini) açılır.
    private static func resolvedDirectory(_ saved: String?,
                                          directoryExists: (String) -> Bool) -> String? {
        guard let trimmed = saved?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              directoryExists(trimmed) else { return nil }
        return trimmed
    }
}

// MARK: - Pencere yerleşimi

/// Kayıtlı çerçeveyi GÜVENLİ bir çerçeveye çeviren saf hesap (briefs/2 "Pencere boyutu ve
/// konumu hatırlanmalı").
///
/// Neden gerekli: harici monitör çıkarıldığında ya da ekran çözünürlüğü değiştiğinde
/// kayıtlı çerçeve görünür alanın tamamen dışında kalabilir; olduğu gibi uygulanırsa
/// pencere "açılır ama görünmez".
enum SessionWindowPlacement {

    /// Tam ekran durumu geri yüklenirken uygulanmaz — bkz. `shouldEnterFullScreen`.
    /// - Parameters:
    ///   - visibleScreenFrames: `NSScreen.visibleFrame` listesi (menü çubuğu/Dock hariç).
    ///   - minimumSize: pencerenin kullanılabilir kaldığı en küçük boyut.
    /// - Returns: Uygulanacak çerçeve; nil → kayıt yok/kullanılamaz, varsayılan yerleşim korunur.
    static func frame(for saved: SessionWindowFrame?,
                      visibleScreenFrames: [CGRect],
                      minimumSize: CGSize) -> CGRect? {
        guard let saved else { return nil }
        let rect = saved.cgRect
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite,
              rect.width > 0, rect.height > 0 else { return nil }

        let usable = visibleScreenFrames.filter { $0.width > 0 && $0.height > 0 }
        guard let host = usable.max(by: { overlapArea(rect, $0) < overlapArea(rect, $1) }) else { return nil }

        // Boyut önce alt sınıra, sonra ekrana sığacak şekilde kırpılır. Sıra önemli:
        // ekran alt sınırdan küçükse (çok küçük harici ekran) ekran kazanır, yoksa
        // pencere ekrandan taşardı.
        let size = CGSize(width: min(max(rect.width, minimumSize.width), host.width),
                          height: min(max(rect.height, minimumSize.height), host.height))

        // Pencerenin dörtte birinden azı görünür kalıyorsa konum artık "hatırlanmaya"
        // değmez: kullanıcı pencereyi bulamaz. Ekranın ortasına alınır.
        var origin = rect.origin
        if overlapArea(rect, host) < 0.25 * Double(rect.width * rect.height) {
            origin = CGPoint(x: host.midX - size.width / 2, y: host.midY - size.height / 2)
        }
        return CGRect(x: min(max(origin.x, host.minX), host.maxX - size.width),
                      y: min(max(origin.y, host.minY), host.maxY - size.height),
                      width: size.width,
                      height: size.height)
    }

    /// Açılışta tam ekrana GİRİLMEZ (ürün kararı, briefs/2 yalnız "tam ekran desteklenmeli"
    /// diyor): kullanıcının onayı olmadan yeni bir Space açmak diğer pencerelerini gizler
    /// ve terminal ~1 sn boyunca kullanılamaz. Bayrak yine de saklanır ve tam ekran ÖNCESİ
    /// çerçeve geri yüklenir; böylece pencere tanıdık boyutunda gelir.
    static func shouldEnterFullScreen(restoring window: SessionWindowSnapshot) -> Bool { false }

    private static func overlapArea(_ rect: CGRect, _ other: CGRect) -> Double {
        let intersection = rect.intersection(other)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        return Double(intersection.width * intersection.height)
    }
}
