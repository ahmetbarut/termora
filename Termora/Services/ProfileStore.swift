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
        if let decoded = try? JSONDecoder().decode([TerminalProfile].self, from: data) {
            self.profiles = decoded
        } else {
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
