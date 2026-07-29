import Foundation
import Observation
import os

/// Kayıtlı komutların tek sahibi (briefs/3 "Sidebar" ▸ Saved Commands).
///
/// `ProfileStore` ile aynı kalıp: öğe öğe çözülür, tek bozuk kayıt bütün listeyi
/// silmez.
@MainActor
@Observable
final class SavedCommandStore {
    static let storageKey = "savedCommands.v1"
    static let backupKey = "savedCommands.v1.corrupt-backup"

    private static let logger = Logger(subsystem: "com.ahmetbarut.Termora",
                                       category: "SavedCommandStore")

    private(set) var commands: [SavedCommand] = [] {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        do {
            // Öğe öğe: tek bozuk kayıt bütün listeyi silmemeli. Blob'a DOKUNULMAZ —
            // atlanan kaydın ham verisi diskte kalsın ki ileriki bir sürüm okuyabilsin.
            let decoded = try JSONDecoder().decode(LenientArray<SavedCommand>.self, from: data)
            if !decoded.failures.isEmpty {
                Self.logger.error("""
                    Skipped \(decoded.failures.count, privacy: .public) undecodable saved \
                    command(s), kept \(decoded.elements.count, privacy: .public)
                    """)
            }
            commands = decoded.elements
        } catch {
            defaults.set(data, forKey: Self.backupKey)
            defaults.removeObject(forKey: Self.storageKey)
            Self.logger.error("Corrupt saved-commands blob moved to \(Self.backupKey, privacy: .public)")
        }
    }

    /// Boş komut KAYDEDİLMEZ: tıklanınca hiçbir şey yapmayan bir satır, olmayan bir
    /// satırdan kötüdür.
    func add(_ command: SavedCommand) {
        guard !command.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        commands.append(command)
    }

    func update(_ command: SavedCommand) {
        guard let index = commands.firstIndex(where: { $0.id == command.id }) else { return }
        guard !command.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        commands[index] = command
    }

    func remove(id: UUID) {
        commands.removeAll { $0.id == id }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(commands) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
