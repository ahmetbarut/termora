import Foundation
import Testing
@testable import Termora

/// briefs/3 workspace oluşturma akışı: 1) proje klasörü 2) terminal düzeni
/// 3) başlangıç komutları 4) kaydet. Akışın DURUMU saf bir değerdir; editör görünümü
/// yalnız bu değeri bağlar.
@Suite("Workspace oluşturma taslağı")
struct WorkspaceDraftTests {

    // MARK: - 1. Adım: proje klasörü

    @Test func aFreshDraftStartsEmptyAndCannotBeSaved() {
        let draft = WorkspaceDraft.newWorkspace()
        #expect(draft.name.isEmpty)
        #expect(draft.directory.isEmpty)
        #expect(draft.isSaveEnabled == false)
    }

    /// Klasör seçimi adı da doldurur: kullanıcı çoğu zaman klasör adını yazacaktı.
    @Test func choosingAFolderSeedsTheName() {
        var draft = WorkspaceDraft.newWorkspace()
        draft.chooseDirectory("/Users/dev/Projects/api-gateway")
        #expect(draft.directory == "/Users/dev/Projects/api-gateway")
        #expect(draft.name == "api-gateway")
        #expect(draft.isSaveEnabled)
    }

    @Test func aNameTheUserTypedIsNotOverwrittenByTheNextFolder() {
        var draft = WorkspaceDraft.newWorkspace()
        draft.chooseDirectory("/Users/dev/api")
        draft.name = "Payments API"
        draft.chooseDirectory("/Users/dev/billing")
        #expect(draft.name == "Payments API")
        #expect(draft.directory == "/Users/dev/billing")
    }

    /// Ad hâlâ klasörden türemişse yeni klasör onu tazeler.
    @Test func aSeededNameFollowsTheFolder() {
        var draft = WorkspaceDraft.newWorkspace()
        draft.chooseDirectory("/Users/dev/api")
        draft.chooseDirectory("/Users/dev/billing")
        #expect(draft.name == "billing")
    }

    @Test func aWhitespaceOnlyNameBlocksSaving() {
        var draft = WorkspaceDraft.newWorkspace()
        draft.chooseDirectory("/Users/dev/api")
        draft.name = "   "
        #expect(draft.isSaveEnabled == false)
    }

    @Test func trailingSlashesDoNotProduceAnEmptyName() {
        var draft = WorkspaceDraft.newWorkspace()
        draft.chooseDirectory("/Users/dev/api/")
        #expect(draft.name == "api")
    }

    // MARK: - 2. Adım: terminal düzeni

    @Test func aNewDraftStartsWithASinglePane() {
        let draft = WorkspaceDraft.newWorkspace()
        #expect(draft.tabs.count == 1)
        #expect(draft.paneCount == 1)
    }

    @Test func adoptingTheOpenWindowLayoutReplacesTheDraftLayout() {
        var draft = WorkspaceDraft.newWorkspace()
        let captured = [
            WorkspaceTab(title: "Server", layout: .split(axis: .vertical,
                                                         ratio: 0.5,
                                                         first: .pane(WorkspacePane()),
                                                         second: .pane(WorkspacePane()))),
            WorkspaceTab(title: nil, layout: .pane(WorkspacePane())),
        ]
        draft.useLayout(from: captured)

        #expect(draft.tabs.count == 2)
        #expect(draft.paneCount == 3)
        #expect(draft.layoutSummary == "2 tabs · 3 panes")
    }

    /// Kapalı/boş bir pencereden yakalanan düzen taslağı silmemeli.
    @Test func anEmptyCaptureIsIgnored() {
        var draft = WorkspaceDraft.newWorkspace()
        draft.useLayout(from: [])
        #expect(draft.paneCount == 1)
    }

    /// Kullanıcı önce komutu yazıp sonra düzeni yakalarsa emeği çöpe gitmemeli:
    /// komutlar panel sırasına göre taşınır.
    @Test func commandsAlreadyTypedSurviveALayoutCapture() throws {
        var draft = WorkspaceDraft.newWorkspace()
        let firstPane = try #require(draft.paneEditors.first)
        draft.setStartupCommand("npm run dev", paneID: firstPane.paneID)

        draft.useLayout(from: [WorkspaceTab(title: "Server",
                                            layout: .split(axis: .vertical,
                                                           ratio: 0.5,
                                                           first: .pane(WorkspacePane()),
                                                           second: .pane(WorkspacePane())))])

        #expect(draft.paneEditors.first?.command == "npm run dev")
        #expect(draft.paneEditors.last?.command == "")
    }

    // MARK: - 3. Adım: başlangıç komutları

    @Test func eachPaneGetsItsOwnEditorRowWithALabel() {
        var draft = WorkspaceDraft.newWorkspace()
        draft.useLayout(from: [
            WorkspaceTab(title: "Server", layout: .split(axis: .vertical,
                                                         ratio: 0.5,
                                                         first: .pane(WorkspacePane()),
                                                         second: .pane(WorkspacePane()))),
            WorkspaceTab(title: nil, layout: .pane(WorkspacePane())),
        ])

        let editors = draft.paneEditors
        #expect(editors.count == 3)
        #expect(editors.map(\.label) == ["Server · Pane 1", "Server · Pane 2", "Tab 2"])
        #expect(Set(editors.map(\.paneID)).count == 3)
    }

    @Test func writingACommandStoresItOnThatPaneOnly() throws {
        var draft = WorkspaceDraft.newWorkspace()
        draft.useLayout(from: [WorkspaceTab(layout: .split(axis: .horizontal,
                                                           ratio: 0.5,
                                                           first: .pane(WorkspacePane()),
                                                           second: .pane(WorkspacePane())))])
        let second = try #require(draft.paneEditors.last?.paneID)

        draft.setStartupCommand("npm test", paneID: second)

        #expect(draft.paneEditors.first?.command == "")
        #expect(draft.paneEditors.last?.command == "npm test")
        #expect(draft.startupCommandCount == 1)
    }

    @Test func clearingACommandRemovesItRatherThanStoringBlankText() throws {
        var draft = WorkspaceDraft.newWorkspace()
        let pane = try #require(draft.paneEditors.first?.paneID)
        draft.setStartupCommand("npm run dev", paneID: pane)
        draft.setStartupCommand("   ", paneID: pane)

        #expect(draft.startupCommandCount == 0)
        #expect(WorkspaceOpenPlan.startupCommands(for: draft.makeWorkspace()).isEmpty)
    }

    @Test func writingToAnUnknownPaneChangesNothing() {
        var draft = WorkspaceDraft.newWorkspace()
        let before = draft
        draft.setStartupCommand("npm run dev", paneID: UUID())
        #expect(draft == before)
    }

    // MARK: - 4. Adım: kaydet

    @Test func savingProducesAWorkspaceWithTrimmedFieldsAndTheDraftLayout() throws {
        var draft = WorkspaceDraft.newWorkspace()
        draft.chooseDirectory("/Users/dev/api")
        draft.name = "  Payments API  "
        let pane = try #require(draft.paneEditors.first?.paneID)
        draft.setStartupCommand(" npm run dev ", paneID: pane)

        let workspace = draft.makeWorkspace()

        #expect(workspace.name == "Payments API")
        #expect(workspace.directory == "/Users/dev/api")
        #expect(workspace.paneCount == 1)
        #expect(WorkspaceOpenPlan.startupCommands(for: workspace) == ["npm run dev"])
    }

    /// Aynı taslak iki kez kaydedilirse depoda İKİ kayıt oluşmamalı: kimlik sabittir.
    @Test func savingTwiceKeepsTheSameIdentity() {
        let draft = WorkspaceDraft.newWorkspace()
        #expect(draft.makeWorkspace().id == draft.makeWorkspace().id)
    }

    // MARK: - Düzenleme

    @Test func editingLoadsEveryFieldOfTheStoredWorkspace() throws {
        let workspace = Workspace(name: "API",
                                  directory: "/Users/dev/api",
                                  tabs: [WorkspaceTab(title: "Server",
                                                      layout: .pane(WorkspacePane(startupCommand: "npm run dev")))],
                                  trustsStartupCommands: true)
        let draft = WorkspaceDraft(editing: workspace)

        #expect(draft.name == "API")
        #expect(draft.directory == "/Users/dev/api")
        #expect(draft.trustsStartupCommands)
        #expect(draft.paneEditors.first?.command == "npm run dev")
        #expect(draft.isEditingExistingWorkspace)
        #expect(draft.makeWorkspace().id == workspace.id)
    }

    /// Düzenleyip kaydetmek "son açılma" damgasını ve gizli alanları SİLMEMELİ.
    @Test func editingPreservesFieldsTheFormNeverShows() {
        let opened = Date(timeIntervalSince1970: 900_000)
        let profileID = UUID()
        let workspace = Workspace(name: "API",
                                  directory: "/Users/dev/api",
                                  tabs: [WorkspaceTab(layout: .pane(WorkspacePane()))],
                                  environment: ["RAILS_ENV": "development"],
                                  profileID: profileID,
                                  themeID: "termora-dark",
                                  lastOpenedAt: opened)

        var draft = WorkspaceDraft(editing: workspace)
        draft.name = "Payments"
        let saved = draft.makeWorkspace()

        #expect(saved.name == "Payments")
        #expect(saved.lastOpenedAt == opened)
        #expect(saved.environment == ["RAILS_ENV": "development"])
        #expect(saved.profileID == profileID)
        #expect(saved.themeID == "termora-dark")
    }

    @Test func aNewDraftIsNotMarkedAsEditing() {
        #expect(WorkspaceDraft.newWorkspace().isEditingExistingWorkspace == false)
    }

    // MARK: - Gelişmiş ayarlar ilk ekranda görünmez

    /// briefs/3: "Gelişmiş ayarlar ilk ekranda gösterilmemelidir." Güven bayrağı
    /// varsayılan olarak KAPALI ve gelişmiş bölümdedir.
    @Test func trustIsOffByDefaultAndLivesBehindTheAdvancedSection() {
        #expect(WorkspaceDraft.newWorkspace().trustsStartupCommands == false)
        #expect(WorkspaceEditorSection.advanced.isCollapsedByDefault)
        #expect(WorkspaceEditorSection.folder.isCollapsedByDefault == false)
        #expect(WorkspaceEditorSection.layout.isCollapsedByDefault == false)
        #expect(WorkspaceEditorSection.commands.isCollapsedByDefault == false)
    }

    /// Adımlar briefs/3'teki sırayla numaralanır.
    @Test func theFormFollowsTheBriefsStepOrder() {
        #expect(WorkspaceEditorSection.allCases.map(\.title)
                == ["Project Folder", "Terminal Layout", "Startup Commands", "Advanced"])
    }
}
