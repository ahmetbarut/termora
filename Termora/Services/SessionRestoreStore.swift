import Foundation
import Observation
import os

/// Önceki oturumu UserDefaults'a JSON blob olarak yazan gözlemlenebilir depo
/// (briefs/2 "Oturum Geri Yükleme").
///
/// `SettingsStore` / `WorkspaceStore` ile aynı kalıp: bozuk blob yedek anahtara taşınır ve
/// boş oturuma düşülür. Farkı: bu depo aynı zamanda AÇILIŞ KUYRUĞUNU tutar — geri yüklenecek
/// pencereler bir kez okunur, her pencere sırayla kendi payını "alır". Kuyruk kalıcı değildir;
/// yalnız bu uygulama çalışması boyunca yaşar.
@MainActor
@Observable
final class SessionRestoreStore {
    static let storageKey = "session-restore.v1"
    static let backupKey = "session-restore.v1.corrupt-backup"

    private static let logger = Logger(subsystem: "com.ahmetbarut.Termora", category: "SessionRestoreStore")

    private(set) var snapshot: SessionSnapshot

    private let defaults: UserDefaults

    /// Açılışta geri yüklenmeyi bekleyen pencereler. Gözlem dışı: kuyruk UI çizmez,
    /// yalnız pencereler arasında paylaştırılır.
    @ObservationIgnored private var pendingWindows: [SessionWindowSnapshot] = []

    /// Ek pencere açma hakkı bir KEZ verilir. Aksi hâlde geri yükleme için açılan her
    /// pencere yeniden pencere açmak isterdi ve uygulama pencere üretir dururdu.
    @ObservationIgnored private var hasClaimedAdditionalWindows = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.storageKey) else {
            self.snapshot = .empty
            return
        }
        if let decoded = try? JSONDecoder().decode(SessionSnapshot.self, from: data) {
            self.snapshot = decoded
        } else {
            defaults.set(data, forKey: Self.backupKey)
            defaults.removeObject(forKey: Self.storageKey)
            Self.logger.error("Corrupt session blob moved to \(Self.backupKey, privacy: .public); falling back to no restore")
            self.snapshot = .empty
        }
    }

    // MARK: - Yazma

    /// Tek bir pencereyi günceller/ekler. Pencere KAPANIRKEN çağrılır: uygulama sonradan
    /// çökerse bile o pencerenin son hâli diskte kalır.
    func record(_ window: SessionWindowSnapshot, at date: Date = Date()) {
        var updated = snapshot
        if let index = updated.windows.firstIndex(where: { $0.id == window.id }) {
            updated.windows[index] = window
        } else {
            updated.windows.append(window)
        }
        updated.savedAt = date
        write(updated)
    }

    /// Uygulama kapanışındaki KESİN yazma: o an açık olan pencereler listesi budur.
    /// Daha önce kapatılmış pencerelerin `record` ile bıraktığı kayıtlar böylece düşer —
    /// kullanıcının bilerek kapattığı pencere bir daha açılmaz.
    func replaceAll(with windows: [SessionWindowSnapshot], at date: Date = Date()) {
        write(SessionSnapshot(windows: windows, savedAt: date))
    }

    /// Kaydı siler. Ayar kapalıyken çağrılır: kapalı bir özellik kullanıcının çalışma
    /// dizinlerini diskte tutmamalı (briefs/2 "Gizlilik").
    func clear() {
        snapshot = .empty
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func write(_ newValue: SessionSnapshot) {
        snapshot = newValue
        guard let data = try? JSONEncoder().encode(newValue) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    // MARK: - Açılış kuyruğu

    /// Açılışta bir kez çağrılır. Ayar KAPALIYSA kuyruk boş kalır ve hiçbir şey geri
    /// yüklenmez — diskte kayıt olsa bile.
    func prepareRestore(isEnabled: Bool) {
        guard isEnabled else {
            pendingWindows = []
            return
        }
        // Sekmesi olmayan pencere geri yüklenmez: boş bir pencere açmak kullanıcıya
        // hiçbir şey kazandırmaz, normal "yeni sekme" akışı zaten devreye girer.
        pendingWindows = snapshot.windows.filter { !$0.tabs.isEmpty }
    }

    /// Sıradaki pencereyi alır; kuyruk boşsa nil.
    func claimWindow() -> SessionWindowSnapshot? {
        pendingWindows.isEmpty ? nil : pendingWindows.removeFirst()
    }

    var pendingWindowCount: Int { pendingWindows.count }

    /// İlk pencerenin açması gereken EK pencere sayısı. Yalnız ilk çağrıda gerçek sayıyı
    /// döner, sonrasında hep 0.
    func claimAdditionalWindowCount() -> Int {
        guard !hasClaimedAdditionalWindows else { return 0 }
        hasClaimedAdditionalWindows = true
        return pendingWindows.count
    }
}
