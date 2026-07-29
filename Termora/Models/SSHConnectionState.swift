import Foundation

/// briefs/3 "SSH Ekranı" bağlantı durumları.
enum SSHConnectionState: Equatable {
    case connecting
    case connected
    case disconnected
    case failed(exitCode: Int)

    var title: String {
        switch self {
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .failed: return "Failed"
        }
    }

    /// briefs/3 "Erişilebilirlik": *Sadece renkle durum anlatılmamalı.* Her durumun kendi
    /// sembolü var, böylece renk körü kullanıcı da ayırt eder.
    var symbolName: String {
        switch self {
        case .connecting: return "arrow.triangle.2.circlepath"
        case .connected: return "checkmark.circle.fill"
        case .disconnected: return "minus.circle"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    /// briefs/2 "SSH Yöneticisi": *Bağlantı kesildiğinde tekrar bağlanma seçeneği
    /// sunmalıdır.* Yalnız başarısız çıkışta anlamlı — kullanıcı `exit` yazarak kendi
    /// kapattıysa ona yeniden bağlanmayı teklif etmek, istemediği şeyi önermek olurdu.
    var canReconnect: Bool {
        if case .failed = self { return true }
        return false
    }
}

enum SSHConnectionTracker {

    /// `ssh` sürecinin adı. `autossh`/`mosh` gibi sarmalayıcılar bilerek dışarıda:
    /// yanlış pozitif bir "Connected" göstergesi, gösterge olmamasından kötüdür.
    static let processName = "ssh"

    /// Bir başlangıç komutunun `ssh` çalıştırıp çalıştırmadığı. Oturum açılırken
    /// `TerminalSession.didLaunchSSH` bununla işaretlenir.
    ///
    /// Son yol bileşenine bakılır: `SSHCommand` komutu TAM YOLLA üretiyor
    /// (`/usr/bin/ssh -- deploy`), çıplak ada bakmak Termora'nın kendi başlattığı her
    /// bağlantıyı kaçırırdı.
    static func isSSHCommandLine(_ command: String?) -> Bool {
        guard let first = command?.split(separator: " ", omittingEmptySubsequences: true).first else {
            return false
        }
        return (String(first) as NSString).lastPathComponent == processName
    }

    /// Bağlantı durumunu panelde ne çalıştığından türetir.
    ///
    /// Termora kendi SSH protokolünü konuşmaz (briefs/2: *sistem üzerindeki
    /// `/usr/bin/ssh` kullanılmalıdır*), bu yüzden ayrıca tutulacak bir bağlantı nesnesi
    /// yoktur. `nil` dönmesi "bu panel SSH ile ilgili değil" demektir.
    ///
    /// - Parameters:
    ///   - foregroundCommand: panelde şu an önplandaki komutun adı.
    ///   - didLaunchSSH: oturum Termora'nın SSH yöneticisinden açıldı mı.
    ///   - lastExitCode: shell integration'ın bildirdiği son çıkış kodu.
    static func state(foregroundCommand: String?,
                      didLaunchSSH: Bool,
                      lastExitCode: Int?) -> SSHConnectionState? {
        if foregroundCommand == processName { return .connected }
        // Elle yazılmış `ssh` bittiğinde geriye izlenecek bir bağlantı kalmaz: oturumun
        // kendisi SSH oturumu değildi.
        guard didLaunchSSH else { return nil }
        guard let lastExitCode else { return .connecting }
        return lastExitCode == 0 ? .disconnected : .failed(exitCode: lastExitCode)
    }
}
