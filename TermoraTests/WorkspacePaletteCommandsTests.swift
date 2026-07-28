import AppKit
import Foundation
import Testing
@testable import Termora

/// briefs/3 "Komut Paleti Tasarımı → Sonuç kategorileri: Workspaces".
/// Kayıtlı workspace'ler palette listelenir ve Enter onları açar.
@MainActor
@Suite("Komut paletinde Workspaces kategorisi")
struct WorkspacePaletteCommandsTests {

    private struct Subject {
        let viewModel: WorkspaceViewModel
        let store: WorkspaceStore
        let sessions: MockSessionManager
        let settings: SettingsStore
        let themes: ThemeStore
    }

    private func makeSubject(workspaces: [Workspace] = []) -> Subject {
        let defaults = UserDefaults(suiteName: "WorkspacePalette.\(UUID().uuidString)")!
        let store = WorkspaceStore(defaults: defaults)
        store.workspaces = workspaces
        let sessions = MockSessionManager()
        let settings = SettingsStore(defaults: defaults)
        let viewModel = WorkspaceViewModel(sessionManager: sessions,
                                           settings: settings,
                                           profiles: ProfileStore(defaults: defaults),
                                           workspaces: store)
        viewModel.newTab()
        return Subject(viewModel: viewModel,
                       store: store,
                       sessions: sessions,
                       settings: settings,
                       themes: ThemeStore(bundle: .main))
    }

    private func items(_ subject: Subject) -> [CommandPaletteItem] {
        CommandPaletteCatalog.items(workspace: subject.viewModel,
                                    settings: subject.settings,
                                    themes: subject.themes,
                                    openSettings: {})
    }

    private func workspaceItems(_ subject: Subject) -> [CommandPaletteItem] {
        items(subject).filter { $0.category == .workspaces }
    }

    private func simpleWorkspace(_ name: String,
                                 directory: String = "/Users/dev/api",
                                 command: String? = nil,
                                 trusts: Bool = false) -> Workspace {
        Workspace(name: name,
                  directory: directory,
                  tabs: [WorkspaceTab(layout: .pane(WorkspacePane(startupCommand: command)))],
                  trustsStartupCommands: trusts)
    }

    // MARK: - Listeleme

    @Test func everyStoredWorkspaceGetsACommandInBriefOrder() {
        let subject = makeSubject(workspaces: [simpleWorkspace("API"), simpleWorkspace("Web")])
        #expect(workspaceItems(subject).map(\.title) == ["API", "Web"])
    }

    @Test func commandIdentifiersAreStableAndUnique() {
        let stored = [simpleWorkspace("API"), simpleWorkspace("Web")]
        let subject = makeSubject(workspaces: stored)
        let ids = items(subject).map(\.id)

        #expect(Set(ids).count == ids.count)
        #expect(workspaceItems(subject).map(\.id)
                == stored.map { "workspace.\($0.id.uuidString)" })
    }

    @Test func aBlankWorkspaceNameStillHasASearchableTitle() {
        let subject = makeSubject(workspaces: [simpleWorkspace("  ")])
        #expect(workspaceItems(subject).first?.title == WorkspaceCardModel.untitledName)
    }

    @Test func theWorkspaceCategoryIconResolves() {
        #expect(NSImage(systemSymbolName: CommandPaletteCategory.workspaces.symbolName,
                        accessibilityDescription: nil) != nil)
        let subject = makeSubject(workspaces: [simpleWorkspace("API")])
        for item in workspaceItems(subject) {
            #expect(NSImage(systemSymbolName: item.symbolName, accessibilityDescription: nil) != nil)
        }
    }

    /// Boş kategori çizilmez: kayıt yokken palette "Workspaces" başlığı hiç görünmemeli.
    @Test func noStoredWorkspacesMeansNoWorkspaceCategory() {
        let subject = makeSubject()
        #expect(workspaceItems(subject).isEmpty)
        #expect(Set(items(subject).map(\.category)) == [.actions, .settings, .themes])
    }

    /// Workspaces, briefs/3 kategori sırasında Actions'tan hemen sonra gelir.
    @Test func workspacesAreListedRightAfterActions() throws {
        let subject = makeSubject(workspaces: [simpleWorkspace("API")])
        let categories = items(subject).map(\.category)
        let lastAction = try #require(categories.lastIndex(of: .actions))
        let firstWorkspace = try #require(categories.firstIndex(of: .workspaces))
        #expect(firstWorkspace == lastAction + 1)
    }

    // MARK: - Enter ile açma

    @Test func runningTheCommandOpensTheWorkspaceLayout() throws {
        let workspace = Workspace(name: "API",
                                  directory: "/Users/dev/api",
                                  tabs: [WorkspaceTab(title: "Server",
                                                      layout: .pane(WorkspacePane()))])
        let subject = makeSubject(workspaces: [workspace])

        try #require(workspaceItems(subject).first).action()

        #expect(subject.viewModel.tabs.count == 1)
        #expect(subject.viewModel.tabs.first?.customTitle == "Server")
        #expect(subject.sessions.createdWorkingDirectories.last == "/Users/dev/api")
    }

    /// briefs/2 güvenlik kuralı palette de geçerlidir: onaysız komut ÇALIŞMAZ.
    @Test func aWorkspaceWithCommandsAsksBeforeRunningAnything() throws {
        let subject = makeSubject(workspaces: [simpleWorkspace("API", command: "npm run dev")])
        let before = subject.sessions.createdSessions.count

        try #require(workspaceItems(subject).first).action()

        #expect(subject.viewModel.pendingWorkspaceLaunch?.commands == ["npm run dev"])
        #expect(subject.sessions.createdSessions.count == before)
        #expect(subject.sessions.createdStartupCommands.contains("npm run dev") == false)
    }

    @Test func aTrustedWorkspaceRunsItsCommandsWithoutAsking() throws {
        let subject = makeSubject(workspaces: [simpleWorkspace("API", command: "npm run dev", trusts: true)])

        try #require(workspaceItems(subject).first).action()

        #expect(subject.viewModel.pendingWorkspaceLaunch == nil)
        #expect(subject.sessions.createdStartupCommands.contains("npm run dev"))
    }

    /// Depo değişince palet de değişir (katalog her açılışta yeniden kurulur).
    @Test func thePaletteFollowsTheStore() {
        let subject = makeSubject(workspaces: [simpleWorkspace("API")])
        subject.store.upsert(simpleWorkspace("Web"))
        #expect(workspaceItems(subject).map(\.title) == ["API", "Web"])

        subject.store.workspaces.removeAll()
        #expect(workspaceItems(subject).isEmpty)
    }
}
