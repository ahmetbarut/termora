import Foundation
import Observation
import os

/// Workspace'leri UserDefaults'a JSON blob olarak yazan gözlemlenebilir depo.
/// `SettingsStore` / `ProfileStore` ile aynı kalıp: her mutasyon `didSet` üzerinden
/// kalıcılaşır, bozuk blob yedek anahtara taşınıp boş listeye düşülür.
@MainActor
@Observable
final class WorkspaceStore {
    static let storageKey = "workspaces.v1"
    static let backupKey = "workspaces.v1.corrupt-backup"

    private static let logger = Logger(subsystem: "com.ahmetbarut.Termora", category: "WorkspaceStore")

    var workspaces: [Workspace] {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.storageKey) else {
            self.workspaces = []
            return
        }
        do {
            // Öğe öğe çözülür: tek bozuk workspace bütün listeyi silmemeli. Blob'a
            // DOKUNULMAZ (yedeğe taşınmaz, silinmez) — atlanan kaydın ham verisi, bir
            // sonraki yazmaya kadar diskte kalsın ki ileriki bir sürüm okuyabilsin.
            let decoded = try JSONDecoder().decode(LenientArray<Workspace>.self, from: data)
            if !decoded.failures.isEmpty {
                Self.logger.error("""
                    Skipped \(decoded.failures.count, privacy: .public) undecodable workspace(s), \
                    kept \(decoded.elements.count, privacy: .public): \(decoded.failureSummary, privacy: .public)
                    """)
            }
            self.workspaces = decoded.elements
        } catch {
            // Blob'un kendisi bozuk (geçersiz JSON ya da dizi değil): eski davranış aynen.
            defaults.set(data, forKey: Self.backupKey)
            defaults.removeObject(forKey: Self.storageKey)
            Self.logger.error("Corrupt workspaces blob moved to \(Self.backupKey, privacy: .public); falling back to empty list")
            self.workspaces = []
        }
    }

    /// Aynı kimlikli kayıt varsa yerinde günceller, yoksa sona ekler.
    func upsert(_ workspace: Workspace) {
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[index] = workspace
        } else {
            workspaces.append(workspace)
        }
    }

    func remove(id: UUID) {
        workspaces.removeAll { $0.id == id }
    }

    /// Son kullanım tarihini damgalar. Tarih dışarıdan verilir; testte sabitlenebilir.
    func markOpened(id: UUID, at date: Date) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[index].lastOpenedAt = date
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(workspaces) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
