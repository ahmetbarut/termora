import Foundation
@testable import Termora

/// `SessionManaging`'in kayıt tutan sahtesi: gerçek PTY açmadan
/// `createSession` çağrılarının argümanlarını doğrulamayı sağlar.
///
/// Task 11'in `MockSessionManager`'ından ayrı durur çünkü burada gereken iki şeyi
/// modeller: çağrı argümanlarını ÇİFT olarak saklamak ve gerçek `SessionManager`'ın
/// `workingDirectory ?? profile?.startupDirectory` geri düşme zincirini taklit etmek.
/// Ortak üye adları (`defaultShellPath`, `busySessionIDs`, `terminatedSessionIDs`)
/// bilerek `MockSessionManager` ile aynı tutulur.
@MainActor
final class ProfileLaunchMockSessionManager: SessionManaging {

    struct CreateCall: Equatable {
        let profile: TerminalProfile?
        let workingDirectory: String?
    }

    private(set) var createCalls: [CreateCall] = []
    private(set) var terminatedSessionIDs: [UUID] = []
    private var sessionsByID: [UUID: TerminalSession] = [:]

    /// Profil kabuk belirtmediğinde kullanılacak yol (gerçek `SessionManager`'daki
    /// "profil → ayar → ShellService.defaultShellPath" zincirinin sahte karşılığı).
    var defaultShellPath = "/bin/zsh"

    /// Bu kümedeki oturumlar "çalışan işlem var" olarak raporlanır.
    var busySessionIDs: Set<UUID> = []

    func createSession(profile: TerminalProfile?, workingDirectory: String?) -> TerminalSession {
        createCalls.append(CreateCall(profile: profile, workingDirectory: workingDirectory))
        let session = TerminalSession(
            shellPath: profile?.shellPath ?? defaultShellPath,
            profileID: profile?.id,
            workingDirectory: workingDirectory ?? profile?.startupDirectory
        )
        sessionsByID[session.id] = session
        return session
    }

    func session(id: UUID) -> TerminalSession? {
        sessionsByID[id]
    }

    func terminateSession(id: UUID) {
        terminatedSessionIDs.append(id)
        sessionsByID[id] = nil
        busySessionIDs.remove(id)
    }

    func hasRunningProcess(sessionID: UUID) -> Bool {
        busySessionIDs.contains(sessionID)
    }

    /// `SessionManaging`'in beşinci üyesi (Task 8). Profil süiti yeniden başlatmayı test
    /// etmez ama protokol zorunlu kıldığı için burada da bulunmalı — yoksa
    /// `error: type 'ProfileLaunchMockSessionManager' does not conform to protocol 'SessionManaging'`
    /// ile TÜM test hedefi derlenmez. Gerçek `SessionManager` gibi AYNI oturum nesnesini
    /// korur, yalnız alanlarını tazeler.
    private(set) var restartedSessionIDs: [UUID] = []

    func restartSession(id: UUID, forceDefaultShell: Bool) {
        restartedSessionIDs.append(id)
        busySessionIDs.remove(id)
        guard let session = sessionsByID[id] else { return }
        if forceDefaultShell { session.shellPath = defaultShellPath }
        session.launchFailure = nil
        session.processState = .running
        session.restartGeneration += 1
    }

    /// Bu süit girdi yazmayı ölçmez; üye protokolü tamamlamak için var.
    func sendInput(_ text: String, toSession id: UUID) {}
}
