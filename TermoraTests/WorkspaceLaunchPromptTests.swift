import Foundation
import Testing
@testable import Termora

/// Başlangıç komutu onayının METNİ ve düğme adları (briefs/2 güvenlik kuralı + briefs/3
/// "Uygulama Metin Dili": belirsiz `OK`/`Yes` yasak, düğme eylemi adlandırır).
@Suite("Workspace başlangıç komutu onayı")
struct WorkspaceLaunchPromptTests {

    // MARK: - Metin

    @Test func theTitleNamesTheWorkspaceAndAsksAQuestion() {
        let title = WorkspaceLaunchPrompt.title(workspaceName: "API")
        #expect(title.contains("API"))
        #expect(title.hasSuffix("?"))
    }

    @Test func aBlankWorkspaceNameStillProducesAReadableTitle() {
        let title = WorkspaceLaunchPrompt.title(workspaceName: "  ")
        #expect(title.contains(WorkspaceCardModel.untitledName))
    }

    /// Kullanıcı NE çalışacağını görmeden onay veremez: mesaj komut sayısını söyler,
    /// komutların kendisi ayrıca listelenir.
    @Test func theMessageStatesHowManyCommandsWillRun() {
        #expect(WorkspaceLaunchPrompt.message(commandCount: 1).contains("1 command"))
        #expect(WorkspaceLaunchPrompt.message(commandCount: 3).contains("3 commands"))
    }

    @Test func theMessageExplainsThatNothingHasStartedYet() {
        let message = WorkspaceLaunchPrompt.message(commandCount: 2).lowercased()
        #expect(message.contains("before"))
    }

    // MARK: - Düğmeler

    @Test func everyButtonNamesItsAction() {
        #expect(WorkspaceLaunchPrompt.runTitle == "Run Commands")
        #expect(WorkspaceLaunchPrompt.skipTitle == "Open Without Commands")
        #expect(WorkspaceLaunchPrompt.cancelTitle == "Cancel")
    }

    @Test func noButtonIsAnAmbiguousOKOrYes() {
        let ambiguous: Set<String> = ["OK", "Ok", "Yes", "No"]
        for title in WorkspaceLaunchPrompt.allButtonTitles {
            #expect(!ambiguous.contains(title), "Belirsiz düğme adı: \(title)")
            #expect(!title.isEmpty)
        }
        #expect(Set(WorkspaceLaunchPrompt.allButtonTitles).count
                == WorkspaceLaunchPrompt.allButtonTitles.count)
    }

    @Test func theTrustOptionSaysWhatItChangesForever() {
        #expect(WorkspaceLaunchPrompt.trustToggleTitle == "Always trust this workspace")
        #expect(WorkspaceLaunchPrompt.trustToggleHelp.lowercased().contains("without asking"))
    }

    // MARK: - Aynı anda iki diyalog açılmamalı

    /// MainWindowView'da kapatma onayı ZATEN var. İkisi aynı anda istenirse kapatma onayı
    /// kazanır: bekleyen kapatma eyleminin (ve pencere kapatma geri çağrısının) üstüne
    /// ikinci bir diyalog binemez.
    @Test func closeConfirmationWinsWhenBothWouldBePresented() {
        #expect(WorkspaceDialogPresentation.current(hasPendingClose: true, hasPendingLaunch: true)
                == .closeConfirmation)
    }

    @Test func eachPendingStateShowsItsOwnDialog() {
        #expect(WorkspaceDialogPresentation.current(hasPendingClose: true, hasPendingLaunch: false)
                == .closeConfirmation)
        #expect(WorkspaceDialogPresentation.current(hasPendingClose: false, hasPendingLaunch: true)
                == .startupCommands)
        #expect(WorkspaceDialogPresentation.current(hasPendingClose: false, hasPendingLaunch: false)
                == .none)
    }

    @Test func neverMoreThanOneDialogIsVisible() {
        for close in [true, false] {
            for launch in [true, false] {
                let presentation = WorkspaceDialogPresentation.current(hasPendingClose: close,
                                                                      hasPendingLaunch: launch)
                let visible = [presentation == .closeConfirmation, presentation == .startupCommands]
                #expect(visible.filter { $0 }.count <= 1)
            }
        }
    }

    // MARK: - "Open Without Commands"

    /// Komutsuz açış için workspace'in KOPYASI temizlenir: kayıt diskte değişmez,
    /// kimlikler korunur (aksi hâlde `markOpened` kaydı bulamazdı).
    @Test func strippingCommandsKeepsIdentityLayoutAndDirectories() throws {
        let paneA = WorkspacePane(startupDirectory: "/Users/dev/api", startupCommand: "npm run dev")
        let paneB = WorkspacePane(startupDirectory: nil, startupCommand: "npm test")
        let workspace = Workspace(name: "API",
                                  directory: "/Users/dev/api",
                                  tabs: [WorkspaceTab(title: "Server",
                                                      layout: .split(axis: .vertical,
                                                                     ratio: 0.4,
                                                                     first: .pane(paneA),
                                                                     second: .pane(paneB)))],
                                  trustsStartupCommands: false)

        let stripped = WorkspaceStartupCommands.removingStartupCommands(from: workspace)

        #expect(stripped.id == workspace.id)
        #expect(stripped.name == workspace.name)
        #expect(stripped.directory == workspace.directory)
        #expect(stripped.paneCount == workspace.paneCount)
        #expect(WorkspaceOpenPlan.startupCommands(for: stripped).isEmpty)

        let tab = try #require(stripped.tabs.first)
        #expect(tab.title == "Server")
        guard case let .split(axis, ratio, first, second) = tab.layout else {
            Issue.record("düzen korunmadı: \(tab.layout)")
            return
        }
        #expect(axis == .vertical)
        #expect(Double(ratio) == 0.4)
        #expect(first.panes.first?.id == paneA.id)
        #expect(first.panes.first?.startupDirectory == "/Users/dev/api")
        #expect(second.panes.first?.id == paneB.id)
    }

    /// Komutsuz açış geçici bir karardır; kalıcı güven vermez.
    @Test func strippingCommandsDoesNotGrantTrust() {
        let workspace = Workspace(name: "API",
                                  directory: "/Users/dev/api",
                                  tabs: [WorkspaceTab(layout: .pane(WorkspacePane(startupCommand: "rm -rf /")))],
                                  trustsStartupCommands: false)
        #expect(WorkspaceStartupCommands.removingStartupCommands(from: workspace)
                .trustsStartupCommands == false)
    }

    @Test func aWorkspaceWithoutCommandsIsUnchanged() {
        let workspace = Workspace(name: "API",
                                  directory: "/Users/dev/api",
                                  tabs: [WorkspaceTab(layout: .pane(WorkspacePane()))])
        #expect(WorkspaceStartupCommands.removingStartupCommands(from: workspace) == workspace)
    }
}
