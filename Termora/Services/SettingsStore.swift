import Foundation
import Observation
import os

/// Uygulama ayarlarini UserDefaults'a JSON blob olarak yazan gozlemlenebilir depo.
/// `settings` alanindaki her mutasyon `didSet` uzerinden kalicilastirilir; init
/// icindeki ilk atama init accessor'dan gectigi icin `didSet` tetiklenmez.
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
