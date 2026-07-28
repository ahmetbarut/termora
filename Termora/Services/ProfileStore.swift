import Foundation
import Observation
import os

@MainActor
@Observable
final class ProfileStore {
    static let storageKey = "profiles.v1"
    static let backupKey = "profiles.v1.corrupt-backup"

    private static let logger = Logger(subsystem: "com.ahmetbarut.Termora", category: "ProfileStore")

    var profiles: [TerminalProfile] {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.storageKey) else {
            self.profiles = []
            return
        }
        do {
            // Öğe öğe çözülür: tek bozuk profil bütün listeyi silmemeli. Blob'a
            // DOKUNULMAZ (yedeğe taşınmaz, silinmez) — atlanan kaydın ham verisi, bir
            // sonraki yazmaya kadar diskte kalsın ki ileriki bir sürüm okuyabilsin.
            let decoded = try JSONDecoder().decode(LenientArray<TerminalProfile>.self, from: data)
            if !decoded.failures.isEmpty {
                Self.logger.error("""
                    Skipped \(decoded.failures.count, privacy: .public) undecodable profile(s), \
                    kept \(decoded.elements.count, privacy: .public): \(decoded.failureSummary, privacy: .public)
                    """)
            }
            self.profiles = decoded.elements
        } catch {
            // Blob'un kendisi bozuk (geçersiz JSON ya da dizi değil): eski davranış aynen.
            defaults.set(data, forKey: Self.backupKey)
            defaults.removeObject(forKey: Self.storageKey)
            Self.logger.error("Corrupt profiles blob moved to \(Self.backupKey, privacy: .public); falling back to empty list")
            self.profiles = []
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
