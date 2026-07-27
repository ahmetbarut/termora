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
            guard let tab = tabs.first(where: { $0.root.sessionID(ofPane: paneID) != nil }) else { return }
            closePane(paneID: paneID, in: tab)
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

    // MARK: - Pane operations

    /// Splits the active pane; the new pane becomes active and inherits the current
    /// pane's working directory.
    func splitActivePane(axis: SplitAxis) {
        guard let tab = activeTab else { return }
        let session = sessionManager.createSession(profile: nil,
                                                   workingDirectory: workingDirectoryOfActivePane(in: tab))
        let newPaneID = UUID()
        tab.root = tab.root.splitting(paneID: tab.activePaneID,
                                      axis: axis,
                                      newPaneID: newPaneID,
                                      newSessionID: session.id)
        tab.activePaneID = newPaneID
    }

    private func workingDirectoryOfActivePane(in tab: TerminalTab) -> String? {
        guard let sessionID = tab.root.sessionID(ofPane: tab.activePaneID) else { return nil }
        return sessionManager.session(id: sessionID)?.workingDirectory
    }

    /// Closes the active pane. A single-pane tab is closed as a tab instead.
    /// Panes with a running foreground job ask for confirmation first.
    func requestCloseActivePane() {
        guard let tab = activeTab else { return }
        guard tab.root.leaves.count > 1 else {
            requestCloseTab(id: tab.id)
            return
        }
        let paneID = tab.activePaneID
        guard let sessionID = tab.root.sessionID(ofPane: paneID) else { return }

        if sessionManager.hasRunningProcess(sessionID: sessionID) {
            pendingClose = PendingClose(id: UUID(), target: .pane(paneID: paneID))
            return
        }
        closePane(paneID: paneID, in: tab)
    }

    /// Removes a pane from its tab: the sibling subtree takes over the space and,
    /// when the closed pane was active, focus moves to the sibling.
    private func closePane(paneID: UUID, in tab: TerminalTab) {
        guard let sessionID = tab.root.sessionID(ofPane: paneID),
              let sibling = tab.root.siblingLeafPaneID(of: paneID),
              let newRoot = tab.root.removing(paneID: paneID) else { return }

        sessionManager.terminateSession(id: sessionID)
        tab.root = newRoot
        if tab.activePaneID == paneID {
            tab.activePaneID = sibling
        }
        paneFrames[paneID] = nil
    }

    /// Moves focus to the neighbouring pane in the given direction, if any.
    func focusPane(_ direction: FocusDirection) {
        guard let tab = activeTab else { return }
        let visiblePaneIDs = Set(tab.root.leaves.map { $0.paneID })
        let frames = paneFrames.filter { visiblePaneIDs.contains($0.key) }
        guard let target = PaneGeometry.neighbor(of: tab.activePaneID,
                                                 direction: direction,
                                                 frames: frames) else { return }
        tab.activePaneID = target
    }

    /// Focuses a pane directly (click on an inactive pane).
    func activatePane(paneID: UUID) {
        guard let tab = activeTab, tab.root.sessionID(ofPane: paneID) != nil else { return }
        tab.activePaneID = paneID
    }

    /// Applies a divider drag to the layout tree (ratio is clamped by `PaneNode`).
    func updateSplitRatio(tabID: UUID, splitID: UUID, ratio: Double) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        tab.root = tab.root.updatingRatio(splitID: splitID, ratio: ratio)
    }

    /// Starts a fresh shell in the pane that is already on screen (spec §8: the pane
    /// stays open after the process exits). `forceDefaultShell` ignores the configured
    /// shell path — the recovery action for an unlaunchable shell.
    func restartPaneSession(paneID: UUID, forceDefaultShell: Bool = false) {
        guard let tab = activeTab,
              let sessionID = tab.root.sessionID(ofPane: paneID) else { return }
        sessionManager.restartSession(id: sessionID, forceDefaultShell: forceDefaultShell)
        tab.activePaneID = paneID
    }

    // MARK: - Arama (⌘F / ⌘G / ⌘⇧G)

    /// Aktif oturum yöneticisi arama yürütebiliyorsa onu verir; testlerdeki basit çiftlerde nil olur.
    private var searchRunner: (any TerminalSearchRunner)? {
        sessionManager as? any TerminalSearchRunner
    }

    /// Aktif sekmenin aktif panelinin oturum kimliği.
    private var activeSessionID: UUID? {
        guard let tab = activeTab else { return nil }
        return tab.root.sessionID(ofPane: tab.activePaneID)
    }

    func toggleSearchBar() {
        guard let tab = activeTab else { return }
        if tab.isSearchVisible {
            closeSearch()
        } else {
            tab.isSearchVisible = true
            // Terim sekmede korunur ama sayaç kapanışta sıfırlanır; yeniden açılışta
            // tazelenmezse gerçekte eşleşme varken çubuk "0/0" yalanını söyler.
            // Boş terimde tazeleme yok: temizlenecek bir vurgu da yok.
            if !tab.searchQuery.term.isEmpty {
                refreshSearchSummary()
            }
        }
    }

    func closeSearch() {
        guard let tab = activeTab else { return }
        tab.isSearchVisible = false
        tab.searchSummary = .empty
        guard let sessionID = activeSessionID else { return }
        searchRunner?.clearSearch(sessionID: sessionID)
        searchRunner?.focusTerminal(sessionID: sessionID)
    }

    /// Metin ya da seçenekler değiştiğinde sayacı tazeler.
    func refreshSearchSummary() {
        guard let tab = activeTab, let sessionID = activeSessionID else { return }
        guard !tab.searchQuery.term.isEmpty else {
            tab.searchSummary = .empty
            searchRunner?.clearSearch(sessionID: sessionID)
            return
        }
        tab.searchSummary = searchRunner?.matchSummary(sessionID: sessionID, query: tab.searchQuery) ?? .empty
    }

    func findNextMatch() {
        guard let tab = activeTab, let sessionID = activeSessionID, !tab.searchQuery.term.isEmpty else { return }
        _ = searchRunner?.findNext(sessionID: sessionID, query: tab.searchQuery)
        tab.searchSummary = searchRunner?.matchSummary(sessionID: sessionID, query: tab.searchQuery) ?? .empty
    }

    func findPreviousMatch() {
        guard let tab = activeTab, let sessionID = activeSessionID, !tab.searchQuery.term.isEmpty else { return }
        _ = searchRunner?.findPrevious(sessionID: sessionID, query: tab.searchQuery)
        tab.searchSummary = searchRunner?.matchSummary(sessionID: sessionID, query: tab.searchQuery) ?? .empty
    }
}
