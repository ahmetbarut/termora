import Foundation

// MARK: - Durum

/// briefs/2 komut bloğu: "Başarılı, başarısız veya devam ediyor durumu".
///
/// Brief üç durum sayar, burada DÖRT var. Dördüncüsü (`.finished`) bir özellik değil bir
/// dürüstlük: kabuk `D` işaretini çıkış kodu OLMADAN da yayabilir. O hâlde 0 varsaymak
/// başarısız bir komutu yeşil göstermek, 1 varsaymak başarılıyı kırmızı göstermek olurdu.
///
/// Renk ASLA tek gösterge değildir (briefs/2 "Erişilebilirlik"): her durum kendi
/// sözcüğünü, kendi SF Symbol şeklini ve kendi VoiceOver cümlesini taşır.
enum CommandBlockState: Equatable {
    case running
    case succeeded
    case failed(exitCode: Int)
    /// Komut bitti ama kabuk çıkış kodu bildirmedi.
    case finished

    /// Rozet metni.
    var label: String {
        switch self {
        case .running: "Running"
        case .succeeded: "Succeeded"
        case .failed: "Failed"
        case .finished: "Finished"
        }
    }

    /// Şekiller bilerek birbirinden UZAK: dolu daire / onay / çarpı / soru. Renk
    /// algılanmasa bile dördü siluetinden ayırt edilir.
    var symbolName: String {
        switch self {
        case .running: "circle.dotted"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        // Onay işareti KULLANILMAZ: kodu bilinmeyen bir komutu başarılı göstermek olurdu.
        case .finished: "questionmark.circle"
        }
    }

    var colorToken: DesignTokens.ColorToken {
        switch self {
        case .running: DesignTokens.accentBlue
        case .succeeded: DesignTokens.success
        case .failed: DesignTokens.danger
        case .finished: DesignTokens.textSecondary
        }
    }

    /// VoiceOver: durum ve —biliniyorsa— çıkış kodu TEK cümlede duyulur. Kod ekranda
    /// küçük bir rozette durur; sesli kullanıcı onu başka türlü duyamaz.
    var accessibilityLabel: String {
        switch self {
        case .running: "Running"
        case .succeeded: "Succeeded with exit code 0"
        case let .failed(exitCode): "Failed with exit code \(exitCode)"
        case .finished: "Finished; the shell reported no exit code"
        }
    }
}

// MARK: - Süre metni

/// Blok başlığındaki çalışma süresi.
///
/// `CommandDurationFormatter.short` bildirimler için yazıldı ve saniyenin altını "0s"
/// diye okur — bildirimde doğru (30 sn'den kısa komut zaten duyurulmaz), blokta yanlış:
/// blokların ÇOĞU saniyenin altındadır ve hepsinin "0s" yazması ölçümü anlamsız kılardı.
enum CommandBlockDuration {
    /// Saniyenin ALTI milisaniye, üstü bildirimlerdeki biçimin AYNISI. Aynı süre iki
    /// ekranda iki türlü okunmamalı.
    static func text(_ duration: TimeInterval) -> String {
        // `Int(Double.nan)` tuzak atar; ölçülemeyen süre sıfırdır.
        guard duration.isFinite, duration > 0 else { return "0 ms" }
        guard duration >= 1 else { return "\(Int((duration * 1000).rounded())) ms" }
        return CommandDurationFormatter.short(duration)
    }
}

// MARK: - Saat metni

/// Blokların başlangıç/bitiş saati.
///
/// `DateFormatter` sabit `en_US_POSIX` yerelinde kurulur: brief 3 arayüz dilini İngilizce'ye
/// sabitliyor ve kullanıcının bölge ayarı 12/24 saat biçimini değiştirseydi aynı ekran
/// makineye göre farklı okunurdu.
enum CommandBlockClock {
    /// `nonisolated`: bu proje `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` ile derleniyor
    /// ve işaretlenmemiş her bildirim MainActor'a bağlanırdı. Saat metni saf bir dönüşüm;
    /// Markdown dışa aktarma gibi yalıtımsız yollardan da çağrılabilmeli.
    nonisolated private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static func text(_ date: Date) -> String { formatter.string(from: date) }
}

// MARK: - Blok

/// briefs/2 "Komut Blokları": tek bir komut, çıktısı ve onunla ilgili her şey.
///
/// Diske YAZILMAZ (briefs/2 "Gizlilik": terminal geçmişi kalıcılaştırılmaz). Bu tip
/// bilerek `Codable` değil — kalıcılaştırmayı bir gün kazara mümkün kılan yol açılmasın.
struct CommandBlock: Identifiable, Equatable {
    let id: UUID

    /// Kullanıcının girdiği komut. `nil`: kanca metni bildirmedi (başka bir terminalin
    /// OSC 133 kancası, ya da `base64` bulunamayan bir sistem). Termora metni UYDURMAZ.
    var command: String?

    /// Komutun ekrana yazdığı metin, kaçış dizilerinden arındırılmış hâli.
    var output: String

    var startedAt: Date

    /// `nil` iken komut hâlâ çalışıyordur.
    var finishedAt: Date?

    var exitCode: Int?

    var workingDirectory: String?

    /// Çıktı üst sınıra dayandığı için BAŞI atıldı mı. Kullanıcı eksik bir çıktıya
    /// baktığını bilmelidir; sessizce kırpmak, hatanın ilk satırını yutup onu yanlış
    /// yere bakmaya göndermek olurdu.
    var didTruncateOutput: Bool

    init(id: UUID = UUID(),
         command: String? = nil,
         output: String = "",
         startedAt: Date,
         finishedAt: Date? = nil,
         exitCode: Int? = nil,
         workingDirectory: String? = nil,
         didTruncateOutput: Bool = false) {
        self.id = id
        self.command = command
        self.output = output
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.exitCode = exitCode
        self.workingDirectory = workingDirectory
        self.didTruncateOutput = didTruncateOutput
    }

    var state: CommandBlockState {
        guard finishedAt != nil else { return .running }
        guard let exitCode else { return .finished }
        return exitCode == 0 ? .succeeded : .failed(exitCode: exitCode)
    }

    var isRunning: Bool { finishedAt == nil }

    /// Çalışan bir komutun süresi `now`'a göre ölçülür; biten komutunki sabittir.
    /// Negatif süre SIFIRA kırpılır: duvar saati geri atlayabilir (NTP, uyku/uyanma) ve
    /// "-3s" diye bir süre yoktur.
    func duration(now: Date) -> TimeInterval {
        max(0, (finishedAt ?? now).timeIntervalSince(startedAt))
    }
}
