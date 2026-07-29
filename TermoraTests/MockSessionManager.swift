import Foundation
@testable import Termora

/// SessionManaging'in test double'ı. Task 11, Task 16 ve Task 17 testleri bunu paylaşır.
/// Üye adları kanoniktir; sonraki görevler tam olarak bu adları kullanır.
@MainActor
final class MockSessionManager: SessionManaging {

    /// Bu kümedeki oturumlar "çalışan işlem var" olarak raporlanır.
    var busySessionIDs: Set<UUID> = []

    /// createSession'ın üreteceği varsayılan shell yolu (profil belirtmezse).
    var defaultShellPath: String = "/bin/zsh"

    private(set) var sessions: [UUID: TerminalSession] = [:]
    private(set) var createdSessions: [TerminalSession] = []
    private(set) var terminatedSessionIDs: [UUID] = []
    private(set) var createdProfiles: [TerminalProfile?] = []
    private(set) var createdWorkingDirectories: [String?] = []
    private(set) var restartedSessionIDs: [UUID] = []

    /// Oturumlar açılırken çalıştırılması istenen başlangıç komutları, çağrı sırasıyla.
    /// Gerçek `SessionManager` komutu profilden okuyup shell'e gönderdiği için (bkz.
    /// `startShell`), workspace açılışında komutun çalışıp çalışmadığı buradan doğrulanır.
    var createdStartupCommands: [String?] {
        createdProfiles.map { $0?.startupCommand }
    }

    func createSession(profile: TerminalProfile?, workingDirectory: String?) -> TerminalSession {
        createdProfiles.append(profile)
        createdWorkingDirectories.append(workingDirectory)
        let session = TerminalSession(
            shellPath: profile?.shellPath ?? defaultShellPath,
            profileID: profile?.id,
            workingDirectory: workingDirectory
        )
        sessions[session.id] = session
        createdSessions.append(session)
        return session
    }

    func session(id: UUID) -> TerminalSession? {
        sessions[id]
    }

    func terminateSession(id: UUID) {
        terminatedSessionIDs.append(id)
        sessions[id] = nil
        busySessionIDs.remove(id)
    }

    /// Gerçek yönetici gibi AYNI sessionID ile taze bir oturum kurar; çağrı sırası kaydedilir.
    func restartSession(id: UUID, forceDefaultShell: Bool) {
        restartedSessionIDs.append(id)
        guard let old = sessions[id] else { return }
        sessions[id] = TerminalSession(
            id: id,
            shellPath: forceDefaultShell ? defaultShellPath : old.shellPath,
            profileID: forceDefaultShell ? nil : old.profileID,
            workingDirectory: old.workingDirectory
        )
        busySessionIDs.remove(id)
    }

    func hasRunningProcess(sessionID: UUID) -> Bool {
        busySessionIDs.contains(sessionID)
    }

    /// Oturuma yazılan girdiler, çağrı sırasıyla.
    private(set) var sentInput: [(text: String, sessionID: UUID)] = []

    func sendInput(_ text: String, toSession id: UUID) {
        sentInput.append((text: text, sessionID: id))
    }
}