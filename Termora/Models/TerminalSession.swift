//
//  TerminalSession.swift
//  Termora
//

import Foundation
import Observation

/// Lifecycle of the shell process behind a session.
enum ProcessState: Equatable {
    case running
    case exited(ExitStatus)
}

/// One shell process plus everything the UI shows about it.
/// The AppKit view that renders it lives in `SessionManager`'s cache, not here:
/// the session outlives any particular SwiftUI representable.
@Observable
final class TerminalSession: Identifiable {
    let id: UUID
    let profileID: UUID?

    /// Not `let`: `SessionManager.restartSession(id:forceDefaultShell:)` may bring the session
    /// back up on the default shell after a broken path, and the status bar must then show the
    /// shell that is actually running.
    var shellPath: String

    var workingDirectory: String?
    var title: String = ""
    var processState: ProcessState = .running

    /// SwiftTerm `sizeChanged` delegesinden gelen son terminal boyutu.
    /// Tuple bilerek kullanıldı: Equatable değil ama @Observable için sorun değil.
    var terminalSize: (cols: Int, rows: Int)?

    /// The shell path that could not be executed, or nil after a successful start.
    /// Spec §8: the pane draws an in-pane error banner with a "try the default shell" action.
    var launchFailure: String?

    /// Shell integration kuruluysa son BİTEN komutun çıkış kodu (OSC 133 `D`).
    ///
    /// Kancalar kurulu değilse ya da kabuk kodu bildirmediyse nil kalır. 0 varsayılmaz:
    /// başarısız bir komutu başarılı göstermek, kullanıcının ekranda gördüğünü yalanlardı.
    var lastCommandExitCode: Int?

    /// Shell integration'ın bu oturumda GERÇEKTEN çalıştığının kanıtı: kabuk en az bir
    /// işaret yaydı. Ayarlardaki "kurulu" bilgisi rc dosyasına bakar; bu ise kabuğun
    /// kendisine. İkisi ayrışabilir (kullanıcı kurdu ama sekmeyi yeniden açmadı).
    var didReceiveShellIntegrationMarker = false

    /// briefs/2 "Komut Blokları": bu oturumda çalışmış komutlar, çıktıları ve sonuçları.
    ///
    /// Oturumla birlikte yaşar ve DİSKE YAZILMAZ (briefs/2 "Gizlilik": terminal geçmişi
    /// kalıcılaştırılmaz). Shell integration kurulu değilse boş kalır — Termora komut
    /// sınırlarını tahmin etmez.
    var commandBlocks = CommandBlockRecorder()

    /// Oturum Termora'nın SSH yöneticisinden açıldı mı (briefs/2 "SSH Yöneticisi").
    ///
    /// Bağlantı durumu paneldeki süreçten türetilir, ama `ssh` bittikten SONRA geriye
    /// bakacak bir iz gerekir: bu bayrak olmasa kopan bir bağlantı sıradan bir shell'den
    /// ayırt edilemez ve "Reconnect" hiç sunulamazdı.
    var didLaunchSSH: Bool = false

    /// Bumped by `SessionManager.restartSession(id:forceDefaultShell:)`, which installs a brand
    /// new AppKit view for the same session id. SwiftUI would otherwise keep showing the dead
    /// one, so the pane keys its `TerminalHostView` on this value. Only `SessionManager` writes it.
    var restartGeneration: Int = 0

    init(
        id: UUID = UUID(),
        shellPath: String,
        profileID: UUID? = nil,
        workingDirectory: String? = nil
    ) {
        self.id = id
        self.shellPath = shellPath
        self.profileID = profileID
        self.workingDirectory = workingDirectory
    }
}
