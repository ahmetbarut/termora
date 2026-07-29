import Foundation

/// briefs/2 "Hata Raporlama": çökme raporunun TAMAMI.
///
/// Brief bir izin listesi değil bir yasak listesi veriyor — terminal çıktısı, yazılan
/// komutlar, dosya içerikleri, ortam değişkenleri, API anahtarları ve SSH bilgileri
/// raporda bulunmamalı. Bu tip o yasağı YAPISAL olarak uygular: adı geçen hiçbir şey
/// için alan yok, yani bir gün biri yanlışlıkla eklemek istese derleyici karşısına çıkar.
struct CrashReport: Equatable {
    let appVersion: String
    let buildNumber: String
    let systemVersion: String
    let architecture: String
    let stackTrace: String

    /// Gönderilecek metin.
    ///
    /// Ev dizini yolları kısaltılır: stack trace'te dosya yolu görünebilir ve kullanıcı
    /// adı onunla birlikte sızar.
    var text: String {
        """
        Termora \(appVersion) (\(buildNumber))
        System: \(systemVersion)
        Architecture: \(architecture)

        \(Self.redactingHomePaths(stackTrace))
        """
    }

    /// Kullanıcının gördüğü metin, gönderilecek metnin AYNISI.
    ///
    /// Ayrı bir önizleme biçimi olsaydı gösterilenle gönderilen zamanla ayrışabilir ve
    /// brief'in "gönderilecek içerik incelenebilmeli" vaadi sessizce boşa çıkardı.
    var previewText: String { text }

    private static func redactingHomePaths(_ trace: String) -> String {
        trace.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    /// Çalışan uygulamadan rapor kurar.
    static func current(stackTrace: String) -> CrashReport {
        CrashReport(
            appVersion: AppIdentity.version,
            buildNumber: AppIdentity.build,
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: machineArchitecture(),
            stackTrace: stackTrace
        )
    }

    private static func machineArchitecture() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
    }
}
