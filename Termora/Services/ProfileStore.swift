import Foundation
import Observation

@MainActor
@Observable
final class ProfileStore {
    static let storageKey = "profiles.v1"
    static let backupKey = "profiles.v1.corrupt-backup"

    var profiles: [TerminalProfile] {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([TerminalProfile].self, from: data) {
            self.profiles = decoded
        } else {
            self.profiles = []
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
