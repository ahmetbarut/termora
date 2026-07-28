import Foundation
import Observation
import os

/// Kayıtlı SSH profillerini UserDefaults'a JSON blob olarak yazan gözlemlenebilir depo.
/// `ProfileStore` / `WorkspaceStore` ile aynı kalıp: her mutasyon `didSet` üzerinden
/// kalıcılaşır, öğe öğe çözülür (tek bozuk kayıt listeyi silmez), blob'un kendisi
/// bozuksa yedek anahtara taşınıp boş listeye düşülür.
///
/// GÜVENLİK (briefs/2): burada YALNIZ private key'in YOLU durur. Anahtar içeriği ve
/// parola hiçbir zaman bu depoya girmez — `SSHHost` böyle bir alan tanımlamaz.
@MainActor
@Observable
final class SSHHostStore {
    static let storageKey = "sshHosts.v1"
    static let backupKey = "sshHosts.v1.corrupt-backup"

    /// Nesne grafiğinin kökü `AppServices`'tir; ancak SSH ekranı ve komut paleti bu
    /// depoyu oradan alamıyor (o dosya bu görevin kapsamı dışında). Paylaşılan örnek,
    /// ayarlar penceresiyle uygulamanın geri kalanının AYNI listeyi görmesini sağlayan
    /// dikiştir. Testler her zaman kendi `UserDefaults` süitleriyle kendi deposunu kurar.
    static let shared = SSHHostStore()

    private static let logger = Logger(subsystem: "com.ahmetbarut.Termora", category: "SSHHostStore")

    var hosts: [SSHHost] {
        didSet { persist() }
    }

    /// `~/.ssh/config` içinden okunan hostlar. Init'te OKUNMAZ: dosya sistemine dokunmak
    /// çağıranın açık isteğiyle olur (`reloadConfigHosts` / `ensureConfigHostsLoaded`).
    private(set) var configHosts: [SSHConfigHost] = []
    private(set) var hasLoadedConfigHosts = false

    private let defaults: UserDefaults
    private let configLoader: () -> [SSHConfigHost]

    /// `configLoader` varsayılanı init'in İÇİNDE kurulur: varsayılan argüman ifadeleri
    /// yalıtımsız bağlamda değerlendirilir, `SSHConfigParser.loadUserConfig()` ise
    /// MainActor'a bağlıdır — varsayılan olarak yazılırsa Swift 6 dilinde HATA olur.
    init(defaults: UserDefaults = .standard,
         configLoader: (() -> [SSHConfigHost])? = nil) {
        self.defaults = defaults
        self.configLoader = configLoader ?? { SSHConfigParser.loadUserConfig() }
        guard let data = defaults.data(forKey: Self.storageKey) else {
            self.hosts = []
            return
        }
        do {
            // Öğe öğe çözülür: tek bozuk profil bütün listeyi silmemeli. Blob'a
            // DOKUNULMAZ — atlanan kaydın ham verisi bir sonraki yazmaya kadar diskte
            // kalsın ki ileriki bir sürüm okuyabilsin.
            let decoded = try JSONDecoder().decode(LenientArray<SSHHost>.self, from: data)
            if !decoded.failures.isEmpty {
                Self.logger.error("""
                    Skipped \(decoded.failures.count, privacy: .public) undecodable SSH host(s), \
                    kept \(decoded.elements.count, privacy: .public): \(decoded.failureSummary, privacy: .public)
                    """)
            }
            self.hosts = decoded.elements
        } catch {
            defaults.set(data, forKey: Self.backupKey)
            defaults.removeObject(forKey: Self.storageKey)
            Self.logger.error("Corrupt SSH hosts blob moved to \(Self.backupKey, privacy: .public); falling back to empty list")
            self.hosts = []
        }
    }

    // MARK: - Kayıtlı profiller

    /// Aynı kimlikli kayıt varsa yerinde günceller, yoksa sona ekler.
    func upsert(_ host: SSHHost) {
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[index] = host
        } else {
            hosts.append(host)
        }
    }

    func remove(id: UUID) {
        hosts.removeAll { $0.id == id }
    }

    /// Bağlantının BAŞLATILDIĞI anı damgalar. Tarih dışarıdan verilir; testte sabitlenir.
    func markConnected(id: UUID, at date: Date) {
        guard let index = hosts.firstIndex(where: { $0.id == id }) else { return }
        hosts[index].lastConnectedAt = date
    }

    /// Hedef kayıtlı bir profilse damgalar; config hostları diske yazılmaz (o dosya
    /// kullanıcınındır, Termora ona DOKUNMAZ).
    func recordLaunch(of target: SSHTarget, at date: Date) {
        guard case let .profile(host) = target else { return }
        markConnected(id: host.id, at: date)
    }

    // MARK: - ~/.ssh/config

    func reloadConfigHosts() {
        configHosts = configLoader()
        hasLoadedConfigHosts = true
    }

    /// İlk çağrıda okur, sonrakilerde dokunmaz. Komut paleti gibi sık çizilen yüzeyler
    /// her karede diske gitmesin diye.
    func ensureConfigHostsLoaded() {
        guard !hasLoadedConfigHosts else { return }
        reloadConfigHosts()
    }

    // MARK: - Bağlanılabilir hedefler

    /// Kayıtlı profiller + config hostları. Kayıtlı profiller önce gelir: kullanıcının
    /// kendi düzenlediği kayıt, türetilmiş listeden önceliklidir.
    var targets: [SSHTarget] {
        hosts.map(SSHTarget.profile) + configHosts.map(SSHTarget.configHost)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(hosts) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
