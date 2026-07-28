import Darwin
import Foundation
import CoreGraphics
import Observation

/// Optional capability of a session manager: the command currently running in the
/// foreground of a session's pseudo-terminal (`npm`, `vim`, …), or nil while the shell
/// itself is in the foreground. Test doubles adopt it directly; the live `SessionManager`
/// does not, so `WorkspaceViewModel` falls back to reading the shell pid via libproc.
@MainActor
protocol ForegroundProcessNaming: AnyObject {
    func foregroundProcessName(sessionID: UUID) -> String?
}

/// Pure priority chain for a tab's automatic title (brief 3, "Tab Bar"):
/// the running foreground command, then whatever the shell reports over OSC, then the
/// working directory, then the profile, and the shell name as a last resort.
/// (The user's own name outranks all of these and is applied by `TerminalTab.displayTitle`.)
enum TabTitleResolver {

    static func automaticTitle(foregroundProcessName: String?,
                               shellReportedTitle: String,
                               workingDirectory: String?,
                               profileName: String?,
                               shellPath: String) -> String {
        if let command = nonBlank(foregroundProcessName) { return command }
        if let reported = nonBlank(shellReportedTitle) { return reported }
        if let directory = nonBlank(workingDirectory) {
            let basename = (directory as NSString).lastPathComponent
            return basename.isEmpty ? "/" : basename
        }
        if let profileName = nonBlank(profileName) { return profileName }
        return (shellPath as NSString).lastPathComponent
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// Onay bekleyen workspace açılışı. Kullanıcıya çalıştırılacak komutlar gösterilir;
/// onay verilmeden hiçbir shell başlatılmaz (briefs/2 güvenlik kuralı).
struct PendingWorkspaceLaunch: Identifiable, Equatable {
    var id: UUID
    var workspace: Workspace
    /// Onay ekranında listelenecek komutlar.
    var commands: [String]
}

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
            /// Workspace açılışı pencerenin TÜM sekmelerini değiştirir; çalışan işlem
            /// varsa aynı koruma devreye girer, ayrı bir onay akışı kurulmaz.
            case workspaceSwitch(name: String)
        }
    }

    private let sessionManager: any SessionManaging
    let settings: SettingsStore
    let profiles: ProfileStore
    /// Workspace kayıtları. Workspace ekranı olmayan bağlamlarda (eski testler) nil olabilir;
    /// o durumda açılış çalışır ama "son açılma" damgası ve güven bayrağı kalıcılaşmaz.
    let workspaces: WorkspaceStore?
    /// `lastOpenedAt` damgasının kaynağı; testte sabitlenebilsin diye enjekte edilir.
    private let now: () -> Date

    private(set) var tabs: [TerminalTab] = []
    var activeTabID: UUID?
    var pendingClose: PendingClose?

    /// Bu pencerenin oturum kaydındaki kimliği. Geri yüklenen pencere kayıttaki kimliği
    /// DEVRALIR (`restoreSession`); aksi hâlde `SessionRestoreStore.record` upsert'i şaşar
    /// ve aynı pencere her açılışta bir kez daha kaydedilirdi.
    private(set) var sessionWindowID = UUID()

    /// Pencerede o an açık olan workspace kaydı; hiç açılmadıysa nil.
    /// Yalnız oturum kaydında saklanır — geri yüklemede workspace'in ORTAMI ve profili
    /// yeniden uygulanmaz (bkz. `restoreSession`).
    private(set) var openWorkspaceID: UUID?

    /// Onay bekleyen workspace açılışı; nil ise bekleyen yok.
    private(set) var pendingWorkspaceLaunch: PendingWorkspaceLaunch?

    /// PaneTreeView'ın preference key ile bildirdiği panel çerçeveleri (AppKit koordinatları).
    var paneFrames: [UUID: CGRect] = [:]

    var activeTab: TerminalTab? {
        guard let activeTabID else { return nil }
        return tabs.first { $0.id == activeTabID }
    }

    init(sessionManager: any SessionManaging,
         settings: SettingsStore,
         profiles: ProfileStore,
         workspaces: WorkspaceStore? = nil,
         now: @escaping () -> Date = Date.init) {
        self.sessionManager = sessionManager
        self.settings = settings
        self.profiles = profiles
        self.workspaces = workspaces
        self.now = now
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
        let approval = windowCloseApproval
        windowCloseApproval = nil
        switch pending.target {
        case let .tab(tabID):
            closeTab(id: tabID)
        case let .pane(paneID):
            guard let tab = tabs.first(where: { $0.root.sessionID(ofPane: paneID) != nil }) else { return }
            closePane(paneID: paneID, in: tab)
        case .window, .workspaceSwitch:
            // Önce oturumlar sonlandırılır, sonra pencere kapatılır / yeni düzen kurulur:
            // ters sırada shell'ler SessionManager cache'inde öksüz kalırdı.
            closeAllTabs()
            approval?()
        }
    }

    func cancelPendingClose() {
        windowCloseApproval = nil
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

    // MARK: - Pencere / uygulama kapatma

    /// `.window` hedefli onay verildiğinde çalıştırılacak eylem.
    /// `requestCloseWindow(onApproved:)` kurar; onay ya da iptal temizler.
    /// Kapatma kararı burada tutulduğu için akış AppKit olmadan test edilebilir.
    private var windowCloseApproval: (@MainActor () -> Void)?

    /// Pencere ya da uygulama kapatılmak isteniyor.
    /// - Parameter onApproved: Kullanıcı onaylarsa, oturumlar sonlandırıldıktan SONRA çağrılır.
    /// - Returns: Çalışan işlem yoksa `true` — çağıran kapanışa hemen devam edebilir.
    ///   Çalışan işlem varsa onay diyaloğu kurulur ve `false` döner.
    func requestCloseWindow(onApproved: @escaping @MainActor () -> Void) -> Bool {
        guard hasAnyRunningProcess() else { return true }
        windowCloseApproval = onApproved
        pendingClose = PendingClose(id: UUID(), target: .window)
        return false
    }

    /// Onay diyaloğunun soru başlığı; hedefe göre değişir (aynı diyalog üç akışta kullanılıyor).
    var pendingCloseTitle: String {
        switch pendingClose?.target {
        case .tab: return "Do you want to close this tab?"
        case .pane: return "Do you want to close this pane?"
        case .window: return "Do you want to close this window?"
        case let .workspaceSwitch(name): return "Do you want to open the workspace “\(name)”?"
        case nil: return ""
        }
    }

    /// Diyaloğun gövdesi. Çalışan komutun adı biliniyorsa yazılır; bilinmiyorsa
    /// (ör. süreç bilgisi okunamıyorsa) uydurulmaz, genel ifade kullanılır.
    var pendingCloseMessage: String {
        switch pendingClose?.target {
        case let .tab(tabID):
            guard let tab = tabs.first(where: { $0.id == tabID }) else { return "" }
            let sessionIDs = tab.root.leaves.map(\.sessionID)
            return runningProcessSentence(sessionIDs: sessionIDs, fallback: "A process is still running in this tab.")
        case let .pane(paneID):
            guard let tab = tabs.first(where: { $0.root.sessionID(ofPane: paneID) != nil }),
                  let sessionID = tab.root.sessionID(ofPane: paneID) else { return "" }
            return runningProcessSentence(sessionIDs: [sessionID], fallback: "A process is still running in this pane.")
        case .window:
            return "Processes are still running in this window."
        case let .workspaceSwitch(name):
            // Sonuç açıkça yazılır: workspace açmak bu penceredeki sekmeleri kapatır.
            let sessionIDs = tabs.flatMap { $0.root.leaves.map(\.sessionID) }
            let running = sessionIDs
                .first { sessionManager.hasRunningProcess(sessionID: $0) }
                .flatMap { foregroundProcessName(sessionID: $0) }
            if let running, !running.isEmpty {
                return "A process is still running: \(running). Opening “\(name)” closes the tabs in this window."
            }
            return "Processes are still running in this window. Opening “\(name)” closes them."
        case nil:
            return ""
        }
    }

    /// Onay butonunun etiketi. Belirsiz "OK"/"Yes" yerine eylemin adı yazılır (brief 3).
    var pendingCloseConfirmLabel: String {
        switch pendingClose?.target {
        case .tab: return "Close Tab"
        case .pane: return "Close Pane"
        case .window: return "Close Window"
        case .workspaceSwitch: return "Open Workspace"
        case nil: return ""
        }
    }

    private func runningProcessSentence(sessionIDs: [UUID], fallback: String) -> String {
        let name = sessionIDs
            .first { sessionManager.hasRunningProcess(sessionID: $0) }
            .flatMap { foregroundProcessName(sessionID: $0) }
        guard let name, !name.isEmpty else { return fallback }
        return "A process is still running: \(name)"
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

    // MARK: - Sekme sıralama (sürükle-bırak)

    /// SwiftUI `.onMove` semantiği: `destination`, taşıma ÖNCESİ dizideki araya-ekleme
    /// noktasıdır ve `tabs.count` (sona ekleme) dahil geçerlidir. Aktif sekme değişmez.
    func moveTab(from source: IndexSet, to destination: Int) {
        guard !source.isEmpty,
              source.allSatisfy({ tabs.indices.contains($0) }),
              (0...tabs.count).contains(destination) else { return }

        // `Array.move(fromOffsets:toOffset:)` SwiftUI'den gelir; view model çerçeveden
        // bağımsız kalsın diye aynı semantik elle kurulur.
        let moving = source.sorted().map { tabs[$0] }
        let remaining = tabs.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertIndex = destination - source.filter { $0 < destination }.count
        tabs = remaining
        tabs.insert(contentsOf: moving, at: insertIndex)
    }

    /// Sürükle-bırak yardımcısı: sürüklenen sekme, hedef sekmenin dizinine yerleşir.
    /// Görünüm katmanının araya-ekleme aritmetiğini tekrar etmemesi için burada durur.
    func moveTab(id draggedID: UUID, toSlotOf targetID: UUID) {
        guard let from = tabs.firstIndex(where: { $0.id == draggedID }),
              let to = tabs.firstIndex(where: { $0.id == targetID }),
              from != to else { return }
        moveTab(from: IndexSet(integer: from), to: to > from ? to + 1 : to)
    }

    // MARK: - Başlıklar

    /// nil veya yalnız boşluktan oluşan ad otomatik başlığa döner.
    func renameTab(id: UUID, to newName: String?) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        let trimmed = newName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        tab.customTitle = trimmed.isEmpty ? nil : trimmed
    }

    /// Aktif panelin başlığını sekmeye yansıtır. Öncelik `TabTitleResolver`'da (brief 3):
    /// çalışan foreground işlem → shell'in OSC ile bildirdiği başlık → çalışma dizininin son
    /// bileşeni → profil adı → shell adı.
    /// (Stok macOS zsh'ı `TERM_PROGRAM=Termora` iken OSC başlık YAYMAZ; geri düşüş olmadan
    /// tüm sekmeler kalıcı olarak "Terminal" yazardı — spec §7.)
    /// Oturum kapandıysa son bilinen başlık korunur.
    func syncAutomaticTitles() {
        for tab in tabs {
            guard let sessionID = tab.root.sessionID(ofPane: tab.activePaneID),
                  let session = sessionManager.session(id: sessionID) else { continue }

            let resolved = TabTitleResolver.automaticTitle(
                foregroundProcessName: foregroundProcessName(sessionID: sessionID),
                shellReportedTitle: session.title,
                workingDirectory: session.workingDirectory,
                // newTab(profile:) sekmeye profil adını tohumlar; senkron onu ezmemeli.
                profileName: profileName(for: session),
                shellPath: session.shellPath
            )
            // Hiçbir aday yoksa son bilinen başlık korunur; boş başlık yazılmaz.
            if !resolved.isEmpty {
                tab.automaticTitle = resolved
            }
        }
    }

    /// Oturumda o an ön planda olan komutun adı. Yönetici bu bilgiyi doğrudan verebiliyorsa
    /// (testler) ondan, veremiyorsa shell pid'i üzerinden libproc ile okunur.
    private func foregroundProcessName(sessionID: UUID) -> String? {
        if let namer = sessionManager as? any ForegroundProcessNaming {
            return namer.foregroundProcessName(sessionID: sessionID)
        }
        guard let shellPID = processInfoProvider?.shellPID(sessionID: sessionID) else { return nil }
        return ForegroundProcessProbe.foregroundCommandName(shellPID: shellPID)
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

    // MARK: - Durum çubuğu

    struct StatusSnapshot: Equatable {
        var shellName: String
        var workingDirectory: String
        var branchName: String?
        var columns: Int
        var rows: Int
        var isBusy: Bool
    }

    /// Durum çubuğu ayarlardan açık mı? (@Observable okuması sayesinde canlı günceller.)
    var isStatusBarVisible: Bool {
        settings.settings.showStatusBar
    }

    private var processInfoProvider: (any TerminalProcessInfoProviding)? {
        sessionManager as? any TerminalProcessInfoProviding
    }

    /// Aktif sekmenin aktif paneli için tek seferlik durum okuması. En fazla 1 Hz çağrılır.
    func statusSnapshot() -> StatusSnapshot? {
        guard let tab = activeTab,
              let sessionID = tab.root.sessionID(ofPane: tab.activePaneID),
              let session = sessionManager.session(id: sessionID) else { return nil }

        let probedDirectory = processInfoProvider
            .flatMap { $0.shellPID(sessionID: sessionID) }
            .flatMap { ProcessProbe.currentWorkingDirectory(pid: $0) }
        if let probedDirectory, probedDirectory != session.workingDirectory {
            session.workingDirectory = probedDirectory
            // libproc ile cwd'yi tazeleyen TEK yer burası; sekme başlığı da cwd'ye düşebiliyor
            // (Task 11 `syncAutomaticTitles`). `sessionTitleDigest` cwd'yi de kapsadığı için
            // MainWindowView'ın .onChange kancası zaten uyanır, ama başlığı aynı run-loop
            // turunda kesinleştirmek için burada da eşitliyoruz (aynı 1 Hz bütçesi içinde).
            syncAutomaticTitles()
        }
        let directory = probedDirectory ?? session.workingDirectory
        let size = session.terminalSize ?? (cols: 0, rows: 0)

        return StatusSnapshot(
            shellName: (session.shellPath as NSString).lastPathComponent,
            workingDirectory: directory.map { PathDisplay.abbreviate($0, home: NSHomeDirectory()) } ?? "—",
            branchName: directory.flatMap { GitBranchReader.branchName(forDirectory: $0) },
            columns: size.cols,
            rows: size.rows,
            isBusy: sessionManager.hasRunningProcess(sessionID: sessionID)
        )
    }

    // MARK: - Workspace yakalama

    /// Açık sekme/panel düzenini isimli bir workspace olarak yakalar.
    /// Kalıcılaştırmaz: kaydı `WorkspaceStore`'a yazmak çağıranın işidir (aynı yakalama
    /// hem "Save as Workspace" hem "Update Workspace" akışında kullanılır).
    /// Yalnız kullanıcının verdiği sekme adı saklanır; otomatik başlıklar oturuma bağlıdır
    /// ve bir sonraki açılışta zaten yeniden hesaplanır.
    func captureWorkspace(name: String, directory: String) -> Workspace {
        let capturedTabs = tabs.map { tab in
            let directories = workingDirectories(in: tab.root)
            return WorkspaceTab(
                title: tab.customTitle,
                layout: WorkspaceSnapshot.layout(from: tab.root) { directories[$0] }
            )
        }
        return Workspace(name: name, directory: directory, tabs: capturedTabs)
    }

    /// Ağaçtaki oturumların çalışma dizinleri. Sözlük önden toplanır: `WorkspaceSnapshot`
    /// saf bir dönüşüm olduğu için oturum yöneticisini hiç görmemelidir.
    private func workingDirectories(in node: PaneNode) -> [UUID: String] {
        var result: [UUID: String] = [:]
        for leaf in node.leaves {
            result[leaf.sessionID] = sessionManager.session(id: leaf.sessionID)?.workingDirectory
        }
        return result
    }

    // MARK: - Workspace açma

    /// Workspace'i açar: mevcut sekmeler kapanır, kayıtlı düzen kurulur, dizinlere geçilir.
    /// Başlangıç komutu varsa ve kayıt güvenilir işaretlenmemişse ÖNCE onay istenir —
    /// bu noktada hiçbir shell başlatılmaz (briefs/2 güvenlik kuralı).
    func openWorkspace(_ workspace: Workspace) {
        // Ekranda başka bir onay varsa araya girilmez: `pendingClose`'u ezmek bekleyen
        // kapatma eylemini (ve pencere kapatma geri çağrısını) sessizce düşürürdü.
        guard pendingClose == nil, pendingWorkspaceLaunch == nil else { return }

        let commands = WorkspaceOpenPlan.startupCommands(for: workspace)
        guard commands.isEmpty || workspace.trustsStartupCommands else {
            pendingWorkspaceLaunch = PendingWorkspaceLaunch(id: UUID(),
                                                           workspace: workspace,
                                                           commands: commands)
            return
        }
        // Buraya yalnız çalıştırılacak komut yokken ya da kullanıcı bu workspace'e
        // kalıcı güven vermişken gelinir; her iki durumda da komut çalıştırmak serbesttir.
        replaceOpenTabs(with: workspace, runStartupCommands: true)
    }

    /// Onay verildi: komutlar çalışır. `trustFromNowOn` ise kayıt güvenilir işaretlenir
    /// ve bir daha sorulmaz.
    func confirmWorkspaceLaunch(trustFromNowOn: Bool) {
        guard let pending = pendingWorkspaceLaunch else { return }
        pendingWorkspaceLaunch = nil

        var workspace = pending.workspace
        if trustFromNowOn {
            workspace.trustsStartupCommands = true
            // Depoya yalnız güven bayrağı yazılır: kayıt bu arada Workspaces ekranından
            // değişmiş olabilir, tüm nesneyi geri yazmak o değişikliği silerdi.
            if let store = workspaces,
               let index = store.workspaces.firstIndex(where: { $0.id == workspace.id }) {
                store.workspaces[index].trustsStartupCommands = true
            }
        }
        replaceOpenTabs(with: workspace, runStartupCommands: true)
    }

    /// Onay reddedildi: hiçbir şey değişmez, hiçbir komut çalışmaz.
    func cancelWorkspaceLaunch() {
        pendingWorkspaceLaunch = nil
    }

    /// "Open Without Commands": düzen kurulur ama hiçbir başlangıç komutu çalışmaz.
    /// Kayıt diskte değişmez — kullanıcı bu SEFERLİK komutsuz açmayı seçti, workspace'in
    /// tanımını değiştirmedi.
    func openWorkspaceWithoutStartupCommands() {
        guard let pending = pendingWorkspaceLaunch else { return }
        pendingWorkspaceLaunch = nil
        let stripped = WorkspaceStartupCommands.removingStartupCommands(from: pending.workspace)
        replaceOpenTabs(with: stripped, runStartupCommands: false)
    }

    /// Pencereyi workspace'in düzeniyle değiştirir. Çalışan işlem varsa karar MEVCUT
    /// onay akışına devredilir: düzen ancak kullanıcı onayladıktan sonra kurulur.
    private func replaceOpenTabs(with workspace: Workspace, runStartupCommands: Bool) {
        guard hasAnyRunningProcess() else {
            closeAllTabs()
            buildTabs(for: workspace, runStartupCommands: runStartupCommands)
            return
        }
        windowCloseApproval = { [weak self] in
            self?.buildTabs(for: workspace, runStartupCommands: runStartupCommands)
        }
        pendingClose = PendingClose(id: UUID(), target: .workspaceSwitch(name: workspace.name))
    }

    /// Kayıtlı düzeni kurar: her panel için yeni bir shell başlar ve kendi dizinine geçer.
    /// Çağrıldığında pencere boştur (`closeAllTabs` ya da onaylı kapatma çalışmıştır).
    private func buildTabs(for workspace: Workspace, runStartupCommands: Bool) {
        var opened: [TerminalTab] = []
        for planned in WorkspaceSnapshot.plan(for: workspace) {
            let panes = Dictionary(planned.panes.map { ($0.paneID, $0) },
                                   uniquingKeysWith: { first, _ in first })
            let root = paneNode(from: planned.layout,
                                panes: panes,
                                workspace: workspace,
                                runStartupCommands: runStartupCommands)
            guard let firstPaneID = root.leaves.first?.paneID else { continue }
            let tab = TerminalTab(root: root, activePaneID: firstPaneID)
            tab.customTitle = planned.title
            opened.append(tab)
        }

        tabs = opened
        activeTabID = opened.first?.id
        if tabs.isEmpty {
            // Terminal uygulaması konvansiyonu (`closeTab` ile aynı): pencere boş kalmaz.
            newTab()
        }
        syncAutomaticTitles()
        openWorkspaceID = workspace.id
        workspaces?.markOpened(id: workspace.id, at: now())
    }

    /// Kayıtlı düzeni canlı ağaca çevirir; her yaprak için oturum açar.
    /// Panel kimlikleri korunur (yakala → aç → yakala aynı düzeni verir), split kimlikleri
    /// saklanmadığı için yeniden üretilir.
    private func paneNode(from layout: WorkspaceLayout,
                          panes: [UUID: WorkspaceOpenPlan.Pane],
                          workspace: Workspace,
                          runStartupCommands: Bool) -> PaneNode {
        switch layout {
        case let .pane(pane):
            let planned = panes[pane.id]
            let profile = launchProfile(
                for: workspace,
                startupCommand: runStartupCommands ? planned?.startupCommand : nil
            )
            let session = sessionManager.createSession(profile: profile,
                                                       workingDirectory: nonBlank(planned?.directory))
            return .leaf(paneID: pane.id, sessionID: session.id)

        case let .split(axis, ratio, first, second):
            return .split(
                id: UUID(),
                axis: axis,
                ratio: ratio,
                first: paneNode(from: first, panes: panes, workspace: workspace,
                                runStartupCommands: runStartupCommands),
                second: paneNode(from: second, panes: panes, workspace: workspace,
                                 runStartupCommands: runStartupCommands))
        }
    }

    /// Bir panelin hangi profille açılacağı. `SessionManager` kabuğu, ortamı ve başlangıç
    /// komutunu profilden okuduğu için workspace'in kendi ortamı ve panelin komutu bu
    /// profile bindirilir. Hiçbiri yoksa nil döner ve panel varsayılan kabukla açılır.
    private func launchProfile(for workspace: Workspace, startupCommand: String?) -> TerminalProfile? {
        let base = workspace.profileID.flatMap { id in profiles.profiles.first { $0.id == id } }
        guard base != nil || startupCommand != nil || !workspace.environment.isEmpty else { return nil }

        // Kayıtlı profil yoksa yalnız bu açılışa özel geçici bir profil kurulur. Kimliği
        // workspace'in kimliğidir: ProfileStore'da karşılığı yoktur, bu yüzden görünüm
        // ayarları global kalır ama oturum hangi workspace'ten geldiği izlenebilir.
        var profile = base ?? TerminalProfile(id: workspace.id, name: workspace.name)
        profile.environment.merge(workspace.environment) { _, fromWorkspace in fromWorkspace }
        if let startupCommand { profile.startupCommand = startupCommand }
        return profile
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    // MARK: - Oturum geri yükleme (briefs/2)

    /// Pencerenin o anki hâlini diske yazılabilir bir anlık görüntüye çevirir.
    ///
    /// Sekme KİMLİKLERİ korunur (workspace yakalamadan farkı budur): `activeTabID` ancak
    /// kimlikler hayatta kalırsa geri yüklemede bir şeye işaret eder. Panel dizinleri canlı
    /// oturumlardan okunur — kullanıcı `cd` yaptıysa kayda giden dizin de odur.
    func captureSessionWindow(frame: SessionWindowFrame? = nil,
                              isFullScreen: Bool = false) -> SessionWindowSnapshot {
        let captured = tabs.map { tab -> SessionTabSnapshot in
            let directories = liveWorkingDirectories(in: tab.root)
            return SessionTabSnapshot(
                tab: WorkspaceTab(id: tab.id,
                                  title: tab.customTitle,
                                  layout: WorkspaceSnapshot.layout(from: tab.root) { directories[$0] }),
                activePaneID: tab.activePaneID)
        }
        return SessionWindowSnapshot(id: sessionWindowID,
                                     tabs: captured,
                                     activeTabID: activeTabID,
                                     frame: frame,
                                     isFullScreen: isFullScreen,
                                     workspaceID: openWorkspaceID)
    }

    /// Kayıtlı bir pencereyi kurar: her panel için YENİ bir shell başlar ve kayıtlı dizine
    /// geçilir. Süreç devamlılığı taklit EDİLMEZ (briefs/2).
    ///
    /// Güvenlik (briefs/2): hiçbir başlangıç komutu çalıştırılmaz. İki kilit birlikte durur —
    /// `SessionRestorePlan` komutları düzenden söker, buradaki `createSession` çağrısı da
    /// profili her zaman `nil` geçer. `SessionManager` komutu YALNIZ profilden okuduğu için
    /// bu yolda çalıştırılabilecek bir komut kalmaz; workspace'in profili/ortamı da bilerek
    /// yeniden uygulanmaz (profilin kendi `startupCommand`'i geri kapıyı açardı).
    ///
    /// - Returns: en az bir sekme kurulduysa `true`; kayıt boşsa hiçbir şeye dokunulmaz.
    @discardableResult
    func restoreSession(from window: SessionWindowSnapshot,
                        directoryExists: (String) -> Bool = SessionRestorePlan.directoryExistsOnDisk) -> Bool {
        let planned = SessionRestorePlan.tabs(for: window, directoryExists: directoryExists)
        guard !planned.isEmpty else { return false }

        var opened: [TerminalTab] = []
        for plan in planned {
            let root = restoredPaneNode(from: plan.layout)
            guard let firstPaneID = root.leaves.first?.paneID else { continue }
            let tab = TerminalTab(id: plan.id,
                                  root: root,
                                  activePaneID: plan.activePaneID ?? firstPaneID)
            tab.customTitle = plan.title
            opened.append(tab)
        }
        guard !opened.isEmpty else { return false }

        tabs = opened
        // Kayıttaki aktif sekme doğrulanır: çözülemeyen bir sekme atlanmış olabilir ve
        // hiçbir sekmeye işaret etmeyen bir kimlik pencereyi boş gösterirdi.
        activeTabID = opened.first { $0.id == window.activeTabID }?.id ?? opened.first?.id
        sessionWindowID = window.id
        openWorkspaceID = window.workspaceID
        syncAutomaticTitles()
        return true
    }

    /// Temizlenmiş düzeni canlı ağaca çevirir. Split kimlikleri saklanmadığı için yeniden
    /// üretilir; panel kimlikleri korunur, böylece yakala → geri yükle → yakala aynı düzeni verir.
    private func restoredPaneNode(from layout: WorkspaceLayout) -> PaneNode {
        switch layout {
        case let .pane(pane):
            // Profil DAİMA nil: bkz. `restoreSession` güvenlik notu.
            let session = sessionManager.createSession(profile: nil,
                                                       workingDirectory: pane.startupDirectory)
            return .leaf(paneID: pane.id, sessionID: session.id)
        case let .split(axis, ratio, first, second):
            return .split(id: UUID(),
                          axis: axis,
                          ratio: ratio,
                          first: restoredPaneNode(from: first),
                          second: restoredPaneNode(from: second))
        }
    }

    /// Ağaçtaki oturumların GÜNCEL çalışma dizinleri. Aktif olmayan panellerin `cd`'si
    /// `TerminalSession.workingDirectory`'ye yansımamış olabilir (durum çubuğu yalnız aktif
    /// paneli 1 Hz'de yoklar), bu yüzden kayıt alınırken her panel için pid üzerinden
    /// tazelenir. Yoklama başarısızsa oturumun bildiği son dizin kullanılır.
    private func liveWorkingDirectories(in node: PaneNode) -> [UUID: String] {
        var result: [UUID: String] = [:]
        for leaf in node.leaves {
            let probed = processInfoProvider
                .flatMap { $0.shellPID(sessionID: leaf.sessionID) }
                .flatMap { ProcessProbe.currentWorkingDirectory(pid: $0) }
            result[leaf.sessionID] = probed ?? sessionManager.session(id: leaf.sessionID)?.workingDirectory
        }
        return result
    }
}
