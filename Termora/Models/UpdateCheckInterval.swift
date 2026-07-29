import Foundation

/// Otomatik güncelleme kontrolünün sıklığı (briefs/2 "Ayarlar Ekranı" ▸ Updates).
///
/// Seçenekler bilerek AZ: bir terminal uygulamasının güncelleme sıklığı, kullanıcının
/// üzerinde ince ayar yapmak isteyeceği bir şey değil. Hiçbiri bir saatin altına inmez —
/// Sparkle daha sık kontrolü zaten reddeder.
nonisolated enum UpdateCheckInterval: String, CaseIterable, Codable, Identifiable, Sendable {
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .daily: 86_400
        case .weekly: 7 * 86_400
        case .monthly: 30 * 86_400
        }
    }
}

/// Güncelleyicinin ayarlanabilir yüzü.
///
/// Sparkle'ın `SPUUpdater` tipi doğrudan kullanılmaz: bu üç özellik, güncelleme
/// davranışının tamamı ve testte casusla değiştirilebilir olmaları, "ne gönderiliyor"
/// sorusunun sınanabilmesi demek.
@MainActor
protocol UpdaterDriving: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var updateCheckInterval: TimeInterval { get set }
    /// Sparkle'ın isteğe bağlı makine profili (CPU, model, dil, macOS sürümü).
    var sendsSystemProfile: Bool { get set }
    func checkForUpdates()
}

/// Güncelleyicinin değiştirilemez kuralları.
nonisolated enum UpdaterConfiguration {
    /// briefs/2 "Gizlilik" ▸ *Güncelleme kontrolü telemetri toplamıyor.*
    ///
    /// Sabit, ayar değil: kullanıcıya sunulan her anahtar bir gün yanlışlıkla açık
    /// gelebilir. Makine profili gönderilmiyorsa bunun tek güvenilir yolu, gönderme
    /// ihtimalinin hiç bulunmamasıdır.
    static let sendsSystemProfile = false

    /// Appcast adresinin Info.plist anahtarı. Yoksa güncelleyici HİÇ başlatılmaz.
    static let feedURLKey = "SUFeedURL"
    /// EdDSA açık anahtarının Info.plist anahtarı. Sparkle imzayı bununla doğrular;
    /// yoksa imzasız paket kurulabilirdi, o yüzden ikisi birlikte aranır.
    static let publicKeyKey = "SUPublicEDKey"
}
