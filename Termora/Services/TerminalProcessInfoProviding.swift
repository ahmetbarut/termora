import Darwin
import Foundation
// `view.process` (LocalProcessTerminalView) ve `LocalProcess.shellPid` SwiftTerm'de tanımlı;
// import olmadan "property is not available due to missing import" hatası verir.
import SwiftTerm

/// Durum çubuğunun ihtiyaç duyduğu süreç bilgisini SwiftTerm'e bağımlı olmadan sunar.
/// WorkspaceViewModel yalnız `SessionManaging`'i tanır; canlı cwd okuması için gereken
/// shell pid'ini bu isteğe bağlı yetenek üzerinden ister (test double'ları uymaz).
@MainActor
protocol TerminalProcessInfoProviding: AnyObject {
    func shellPID(sessionID: UUID) -> pid_t?
}

extension SessionManager: TerminalProcessInfoProviding {
    func shellPID(sessionID: UUID) -> pid_t? {
        guard let view = terminalView(for: sessionID),
              let process = view.process else { return nil }
        return process.shellPid
    }
}
