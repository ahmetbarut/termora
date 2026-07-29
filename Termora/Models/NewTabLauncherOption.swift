import Foundation

/// briefs/3 "Yeni Sekme Ekranı"nın seçenekleri, brief'in saydığı sırayla.
enum NewTabLauncherOption: String, CaseIterable, Identifiable, Sendable {
    case defaultShell
    case openFolder
    case openWorkspace
    case connectSSH
    case recentSessions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .defaultShell: "Default Shell"
        case .openFolder: "Open Folder"
        case .openWorkspace: "Open Workspace"
        case .connectSSH: "Connect SSH"
        case .recentSessions: "Recent Sessions"
        }
    }

    var symbolName: String {
        switch self {
        case .defaultShell: "terminal"
        case .openFolder: "folder"
        case .openWorkspace: "square.grid.2x2"
        case .connectSSH: "network"
        case .recentSessions: "clock"
        }
    }

    /// Tek cümle: ne olacağını söyler. briefs/3 "Uygulama Metin Dili" — kısa, yönlendiren.
    var explanation: String {
        switch self {
        case .defaultShell: "Start your login shell, the way ⌘T normally does."
        case .openFolder: "Pick a folder and start a shell there."
        case .openWorkspace: "Restore a saved layout with its startup commands."
        case .connectSSH: "Open a saved host or one from your ssh config."
        case .recentSessions: "Reopen a folder you worked in recently."
        }
    }

    /// Seçeneğin paletteki karşılığı. "Default Shell" ve "Open Folder" paletten
    /// geçmez — biri doğrudan shell açar, diğeri klasör seçici.
    var paletteCategory: CommandPaletteCategory {
        switch self {
        case .openWorkspace: .workspaces
        case .connectSSH: .ssh
        default: .folders
        }
    }

    /// briefs/3 "Klavye Öncelikli Kullanım": her seçeneğin bir rakam kısayolu var.
    /// Fare zorunluluk değil alternatiftir.
    var shortcutDigit: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }
}

/// Hangi seçeneklerin sunulacak bir şeyi var.
///
/// Kayıtsız seçenek GİZLENMEZ, devre dışı görünür — briefs/3 "Sağ Tık Menüleri" ile
/// aynı kural. Gizlemek, kullanıcıya özelliğin var olmadığını düşündürürdü.
struct NewTabLauncherAvailability {
    let hasWorkspaces: Bool
    let hasSSHHosts: Bool
    let hasRecentFolders: Bool

    func isEnabled(_ option: NewTabLauncherOption) -> Bool {
        switch option {
        // Bu ikisi kayıt gerektirmez: biri login shell'i başlatır, diğeri klasör seçici açar.
        case .defaultShell, .openFolder: true
        case .openWorkspace: hasWorkspaces
        case .connectSSH: hasSSHHosts
        case .recentSessions: hasRecentFolders
        }
    }
}
