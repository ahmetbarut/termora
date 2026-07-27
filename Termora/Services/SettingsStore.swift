import Foundation
import Observation

/// Uygulama ayarlarini UserDefaults'a JSON blob olarak yazan gozlemlenebilir depo.
/// `settings` alanindaki her mutasyon `didSet` uzerinden kalicilastirilir; init
/// icindeki ilk atama init accessor'dan gectigi icin `didSet` tetiklenmez.
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
