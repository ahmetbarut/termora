import Foundation
import CoreGraphics
import Observation

/// Pencere başına bir tane. Sekme ve panel operasyonlarının tek sahibi.
/// Menü kısayolları @FocusedValue üzerinden key window'un örneğine ulaşır.
@MainActor
@Observable
final class WorkspaceViewModel {

    /// Çalışan işlem yüzünden onay bekleyen kapatma isteği.
    struct PendingClose: Identifiable, Equatable {
        let id: UUID
        let target: Target

        enum Target: Equatable {
            case tab(UUID)
            case pane(paneID: UUID)
            case window
        }
    }

    private let sessionManager: any SessionManaging
    let settings: SettingsStore
    let profiles: ProfileStore

    private(set) var tabs: [TerminalTab] = []
    var activeTabID: UUID?
    var pendingClose: PendingClose?

    /// PaneTreeView'ın preference key ile bildirdiği panel çerçeveleri (AppKit koordinatları).
    var paneFrames: [UUID: CGRect] = [:]

    var activeTab: TerminalTab? {
        guard let activeTabID else { return nil }
        return tabs.first { $0.id == activeTabID }
    }

    init(sessionManager: any SessionManaging, settings: SettingsStore, profiles: ProfileStore) {
        self.sessionManager = sessionManager
        self.settings = settings
        self.profiles = profiles
    }

    // MARK: - Sekme açma

    func newTab(profile: TerminalProfile? = nil) {
        let session = sessionManager.createSession(profile: profile, workingDirectory: nil)
        let paneID = UUID()
        let tab = TerminalTab(
            root: .leaf(paneID: paneID, sessionID: session.id),
            activePaneID: paneID
        )
        if let profile {
            tab.automaticTitle = profile.name
        }
        tabs.append(tab)
        activeTabID = tab.id
    }

    // MARK: - Sekme kapatma

    /// Sekmede çalışan bir işlem varsa onay ister, yoksa doğrudan kapatır.
    func requestCloseTab(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        let busy = tab.root.leaves.contains { sessionManager.hasRunningProcess(sessionID: $0.sessionID) }
        if busy {
            pendingClose = PendingClose(id: UUID(), target: .tab(id))
        } else {
            closeTab(id: id)
        }
    }

    func confirmPendingClose() {
        guard let pending = pendingClose else { return }
        pendingClose = nil
        switch pending.target {
        case let .tab(tabID):
            closeTab(id: tabID)
        case let .pane(paneID):
            closePane(paneID: paneID)
        case .window:
            closeAllTabs()
        }
    }

    func cancelPendingClose() {
        pendingClose = nil
    }

    /// Pencere kapatılırken: onay alınmışsa tüm oturumları sonlandırır.
    func closeAllTabs() {
        for tab in tabs {
            for leaf in tab.root.leaves {
                sessionManager.terminateSession(id: leaf.sessionID)
            }
        }
        tabs.removeAll()
        activeTabID = nil
    }

    func hasAnyRunningProcess() -> Bool {
        tabs.contains { tab in
            tab.root.leaves.contains { sessionManager.hasRunningProcess(sessionID: $0.sessionID) }
        }
    }

    private func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        for leaf in tabs[index].root.leaves {
            sessionManager.terminateSession(id: leaf.sessionID)
        }
        tabs.remove(at: index)

        if tabs.isEmpty {
            // Terminal uygulaması konvansiyonu: pencere boş kalmaz, yeni oturum açılır.
            newTab()
        } else if activeTabID == id {
            activeTabID = tabs[min(index, tabs.count - 1)].id
        }
    }

    /// M2 değişmezi: her sekmede tek panel vardır, dolayısıyla paneli kapatmak sekmeyi kapatır.
    /// Task 16 bunu PaneNode.removing(paneID:) ile ağaç budamasına genişletir.
    private func closePane(paneID: UUID) {
        guard let tab = tabs.first(where: { $0.root.sessionID(ofPane: paneID) != nil }) else { return }
        closeTab(id: tab.id)
    }

    // MARK: - Sekme seçimi

    /// 0 tabanlı index (⌘1 → 0). Sınır dışı index yok sayılır.
    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeTabID = tabs[index].id
    }

    func nextTab() {
        guard let index = activeIndex else { return }
        activeTabID = tabs[(index + 1) % tabs.count].id
    }

    func previousTab() {
        guard let index = activeIndex else { return }
        activeTabID = tabs[(index - 1 + tabs.count) % tabs.count].id
    }

    private var activeIndex: Int? {
        guard let activeTabID else { return nil }
        return tabs.firstIndex { $0.id == activeTabID }
    }

    // MARK: - Başlıklar

    /// nil veya yalnız boşluktan oluşan ad otomatik başlığa döner.
    func renameTab(id: UUID, to newName: String?) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        let trimmed = newName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        tab.customTitle = trimmed.isEmpty ? nil : trimmed
    }

    /// Aktif panelin başlığını sekmeye yansıtır. Geri düşüş zinciri:
    /// shell'in OSC ile bildirdiği başlık → çalışma dizininin son bileşeni → profil adı → shell adı.
    /// (Stok macOS zsh'ı `TERM_PROGRAM=Termora` iken OSC başlık YAYMAZ; geri düşüş olmadan
    /// tüm sekmeler kalıcı olarak "Terminal" yazardı — spec §7.)
    /// Oturum kapandıysa son bilinen başlık korunur.
    func syncAutomaticTitles() {
        for tab in tabs {
            guard let sessionID = tab.root.sessionID(ofPane: tab.activePaneID),
                  let session = sessionManager.session(id: sessionID) else { continue }

            if !session.title.isEmpty {
                tab.automaticTitle = session.title
            } else if let directory = session.workingDirectory, !directory.isEmpty {
                let basename = (directory as NSString).lastPathComponent
                tab.automaticTitle = basename.isEmpty ? "/" : basename
            } else if let profileName = profileName(for: session), !profileName.isEmpty {
                // newTab(profile:) sekmeye profil adını tohumlar; senkron onu ezmemeli.
                tab.automaticTitle = profileName
            } else {
                tab.automaticTitle = (session.shellPath as NSString).lastPathComponent
            }
        }
    }

    private func profileName(for session: TerminalSession) -> String? {
        guard let profileID = session.profileID else { return nil }
        return profiles.profiles.first { $0.id == profileID }?.name
    }

    /// Observation köprüsü: MainWindowView bu değeri .onChange ile izleyip
    /// syncAutomaticTitles() çağırır (oturum başlıkları @Observable üzerinden okunur).
    /// Çalışma dizini de karışıma girer, çünkü başlık geri düşüşü ona da bakar
    /// (yalnız `title` izlenseydi cwd değişince sekme başlığı güncellenmezdi).
    var sessionTitleDigest: String {
        tabs.map { tab in
            tab.root.leaves
                .compactMap { leaf -> String? in
                    guard let session = sessionManager.session(id: leaf.sessionID) else { return nil }
                    return session.title + "\u{1D}" + (session.workingDirectory ?? "")
                }
                .joined(separator: "\u{1F}")
        }
        .joined(separator: "\u{1E}")
    }
}
