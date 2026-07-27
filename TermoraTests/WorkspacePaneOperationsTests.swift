//
//  WorkspacePaneOperationsTests.swift
//  TermoraTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Termora

@MainActor
@Suite("WorkspacePaneOperations")
struct WorkspacePaneOperationsTests {

    // MARK: - Fixture

    private struct Fixture {
        let viewModel: WorkspaceViewModel
        let sessions: MockSessionManager
    }

    private func makeFixture() -> Fixture {
        let sessions = MockSessionManager()
        let settingsDefaults = UserDefaults(suiteName: "termora.test.settings.\(UUID().uuidString)")!
        let profileDefaults = UserDefaults(suiteName: "termora.test.profiles.\(UUID().uuidString)")!
        let viewModel = WorkspaceViewModel(sessionManager: sessions,
                                           settings: SettingsStore(defaults: settingsDefaults),
                                           profiles: ProfileStore(defaults: profileDefaults))
        if viewModel.tabs.isEmpty {
            viewModel.newTab()
        }
        return Fixture(viewModel: viewModel, sessions: sessions)
    }

    private func splitID(of node: PaneNode) -> UUID? {
        if case let .split(id, _, _, _, _) = node { return id }
        return nil
    }

    // MARK: - splitActivePane

    @Test("splitActivePane yeni oturum yaratır ve odağı yeni panele taşır")
    func splitCreatesSessionAndMovesFocus() {
        let fixture = makeFixture()
        guard let tab = fixture.viewModel.activeTab else {
            Issue.record("aktif sekme yok")
            return
        }
        let originalPaneID = tab.activePaneID
        let sessionCountBefore = fixture.sessions.createdSessions.count

        fixture.viewModel.splitActivePane(axis: .vertical)

        #expect(fixture.sessions.createdSessions.count == sessionCountBefore + 1)
        let leaves = tab.root.leaves
        #expect(leaves.count == 2)
        #expect(leaves.first?.paneID == originalPaneID)
        #expect(tab.activePaneID != originalPaneID)
        #expect(tab.activePaneID == leaves.last?.paneID)
        #expect(tab.root.sessionID(ofPane: tab.activePaneID) == fixture.sessions.createdSessions.last?.id)

        if case let .split(_, axis, ratio, _, _) = tab.root {
            #expect(axis == .vertical)
            #expect(ratio == 0.5)
        } else {
            Issue.record("kök split olmalıydı")
        }
    }

    @Test("splitActivePane yeni panele aktif panelin çalışma dizinini devreder")
    func splitInheritsWorkingDirectory() {
        let fixture = makeFixture()
        fixture.sessions.createdSessions.first?.workingDirectory = "/tmp/termora-fixture"

        fixture.viewModel.splitActivePane(axis: .horizontal)

        #expect(fixture.sessions.createdSessions.last?.workingDirectory == "/tmp/termora-fixture")
    }

    @Test("art arda bölme derin ağaç üretir")
    func repeatedSplitsBuildTree() {
        let fixture = makeFixture()
        fixture.viewModel.splitActivePane(axis: .vertical)
        fixture.viewModel.splitActivePane(axis: .horizontal)

        #expect(fixture.viewModel.activeTab?.root.leaves.count == 3)
        #expect(fixture.sessions.createdSessions.count == 3)
    }

// MARK: - requestCloseActivePane

    @Test("boşta panel kapatılınca kardeş yükselir ve odak kardeşe geçer")
    func closeIdlePaneCollapsesTree() {
        let fixture = makeFixture()
        guard let tab = fixture.viewModel.activeTab else {
            Issue.record("aktif sekme yok")
            return
        }
        let firstPaneID = tab.activePaneID
        fixture.viewModel.splitActivePane(axis: .vertical)
        let secondPaneID = tab.activePaneID
        guard let secondSessionID = tab.root.sessionID(ofPane: secondPaneID) else {
            Issue.record("yeni panelin oturumu bulunamadı")
            return
        }

        fixture.viewModel.requestCloseActivePane()

        #expect(fixture.viewModel.pendingClose == nil)
        #expect(tab.root == .leaf(paneID: firstPaneID,
                                  sessionID: tab.root.sessionID(ofPane: firstPaneID)!))
        #expect(tab.activePaneID == firstPaneID)
        #expect(fixture.sessions.terminatedSessionIDs == [secondSessionID])
        #expect(fixture.viewModel.paneFrames[secondPaneID] == nil)
        #expect(fixture.viewModel.tabs.count == 1)
    }

    @Test("çalışan işlemli panel kapatma onay ister ve ağacı değiştirmez")
    func closeBusyPaneRequestsConfirmation() {
        let fixture = makeFixture()
        guard let tab = fixture.viewModel.activeTab else {
            Issue.record("aktif sekme yok")
            return
        }
        fixture.viewModel.splitActivePane(axis: .vertical)
        let busyPaneID = tab.activePaneID
        let busySessionID = tab.root.sessionID(ofPane: busyPaneID)!
        fixture.sessions.busySessionIDs.insert(busySessionID)
        let treeBefore = tab.root

        fixture.viewModel.requestCloseActivePane()

        #expect(fixture.viewModel.pendingClose?.target == .pane(paneID: busyPaneID))
        #expect(tab.root == treeBefore)
        #expect(fixture.sessions.terminatedSessionIDs.isEmpty)
    }

    @Test("onay verilince panel kapanır")
    func confirmClosesPane() {
        let fixture = makeFixture()
        guard let tab = fixture.viewModel.activeTab else {
            Issue.record("aktif sekme yok")
            return
        }
        let firstPaneID = tab.activePaneID
        fixture.viewModel.splitActivePane(axis: .vertical)
        let busyPaneID = tab.activePaneID
        let busySessionID = tab.root.sessionID(ofPane: busyPaneID)!
        fixture.sessions.busySessionIDs.insert(busySessionID)
        fixture.viewModel.requestCloseActivePane()

        fixture.viewModel.confirmPendingClose()

        #expect(fixture.viewModel.pendingClose == nil)
        #expect(tab.root.leaves.count == 1)
        #expect(tab.activePaneID == firstPaneID)
        #expect(fixture.sessions.terminatedSessionIDs == [busySessionID])
    }

    @Test("iptal edilince panel açık kalır")
    func cancelKeepsPane() {
        let fixture = makeFixture()
        guard let tab = fixture.viewModel.activeTab else {
            Issue.record("aktif sekme yok")
            return
        }
        fixture.viewModel.splitActivePane(axis: .vertical)
        let busySessionID = tab.root.sessionID(ofPane: tab.activePaneID)!
        fixture.sessions.busySessionIDs.insert(busySessionID)
        fixture.viewModel.requestCloseActivePane()

        fixture.viewModel.cancelPendingClose()

        #expect(fixture.viewModel.pendingClose == nil)
        #expect(tab.root.leaves.count == 2)
        #expect(fixture.sessions.terminatedSessionIDs.isEmpty)
    }

    @Test("tek panelli sekmede panel kapatma sekme kapatmaya delege eder")
    func closingOnlyPaneClosesTab() {
        let fixture = makeFixture()
        guard let tab = fixture.viewModel.activeTab else {
            Issue.record("aktif sekme yok")
            return
        }
        let onlySessionID = tab.root.sessionID(ofPane: tab.activePaneID)!
        fixture.sessions.busySessionIDs.insert(onlySessionID)

        fixture.viewModel.requestCloseActivePane()

        #expect(fixture.viewModel.pendingClose?.target == .tab(tab.id))
        #expect(fixture.viewModel.tabs.count == 1)
    }

// MARK: - focusPane / activatePane / updateSplitRatio

    @Test("focusPane paneFrames geometrisine göre komşuya geçer")
    func focusPaneUsesGeometry() {
        let fixture = makeFixture()
        guard let tab = fixture.viewModel.activeTab else {
            Issue.record("aktif sekme yok")
            return
        }
        let leftPaneID = tab.activePaneID
        fixture.viewModel.splitActivePane(axis: .vertical)
        let rightPaneID = tab.activePaneID

        fixture.viewModel.paneFrames = [
            leftPaneID: CGRect(x: 0, y: 0, width: 100, height: 200),
            rightPaneID: CGRect(x: 100, y: 0, width: 100, height: 200)
        ]

        fixture.viewModel.focusPane(.left)
        #expect(tab.activePaneID == leftPaneID)

        fixture.viewModel.focusPane(.up)
        #expect(tab.activePaneID == leftPaneID)   // o yönde komşu yok → değişmez

        fixture.viewModel.focusPane(.right)
        #expect(tab.activePaneID == rightPaneID)
    }

    @Test("focusPane çerçeve bilgisi yokken odağı değiştirmez")
    func focusPaneWithoutFramesIsNoop() {
        let fixture = makeFixture()
        guard let tab = fixture.viewModel.activeTab else {
            Issue.record("aktif sekme yok")
            return
        }
        fixture.viewModel.splitActivePane(axis: .vertical)
        let activeBefore = tab.activePaneID

        fixture.viewModel.focusPane(.left)

        #expect(tab.activePaneID == activeBefore)
    }

    @Test("activatePane yalnız mevcut paneller için odağı değiştirir")
    func activatePaneValidatesID() {
        let fixture = makeFixture()
        guard let tab = fixture.viewModel.activeTab else {
            Issue.record("aktif sekme yok")
            return
        }
        let firstPaneID = tab.activePaneID
        fixture.viewModel.splitActivePane(axis: .vertical)

        fixture.viewModel.activatePane(paneID: firstPaneID)
        #expect(tab.activePaneID == firstPaneID)

        fixture.viewModel.activatePane(paneID: UUID())
        #expect(tab.activePaneID == firstPaneID)
    }

    @Test("updateSplitRatio ağacı günceller ve sınırları uygular")
    func updateSplitRatioAppliesClamp() {
        let fixture = makeFixture()
        guard let tab = fixture.viewModel.activeTab else {
            Issue.record("aktif sekme yok")
            return
        }
        fixture.viewModel.splitActivePane(axis: .vertical)
        guard let id = splitID(of: tab.root) else {
            Issue.record("split id okunamadı")
            return
        }

        fixture.viewModel.updateSplitRatio(tabID: tab.id, splitID: id, ratio: 0.25)
        if case let .split(_, _, ratio, _, _) = tab.root {
            #expect(ratio == 0.25)
        } else {
            Issue.record("split bekleniyordu")
        }

        fixture.viewModel.updateSplitRatio(tabID: tab.id, splitID: id, ratio: 0.95)
        if case let .split(_, _, ratio, _, _) = tab.root {
            #expect(ratio == 0.85)
        } else {
            Issue.record("split bekleniyordu")
        }

        fixture.viewModel.updateSplitRatio(tabID: UUID(), splitID: id, ratio: 0.2)
        if case let .split(_, _, ratio, _, _) = tab.root {
            #expect(ratio == 0.85)   // bilinmeyen sekme → değişiklik yok
        } else {
            Issue.record("split bekleniyordu")
        }
    }

// MARK: - restartPaneSession

    @Test("restartPaneSession panelin oturumunu SessionManager'a yeniden başlatır")
    func restartPaneSessionForwardsToSessionManager() {
        let fixture = makeFixture()
        guard let tab = fixture.viewModel.activeTab else {
            Issue.record("aktif sekme yok")
            return
        }
        let paneID = tab.activePaneID
        guard let sessionID = tab.root.sessionID(ofPane: paneID) else {
            Issue.record("panelin oturumu bulunamadı")
            return
        }

        fixture.viewModel.restartPaneSession(paneID: paneID)

        #expect(fixture.sessions.restartedSessionIDs == [sessionID])
        // Ağaç ve odak değişmez: aynı panelde yeni oturum başlar.
        #expect(tab.root.sessionID(ofPane: paneID) == sessionID)
        #expect(tab.activePaneID == paneID)
        #expect(fixture.sessions.terminatedSessionIDs.isEmpty)
    }

    @Test("varsayılan shell ile yeniden başlatma da aynı oturuma yönlenir")
    func restartWithDefaultShellTargetsTheSameSession() {
        let fixture = makeFixture()
        guard let tab = fixture.viewModel.activeTab else {
            Issue.record("aktif sekme yok")
            return
        }
        fixture.viewModel.splitActivePane(axis: .vertical)
        let paneID = tab.activePaneID
        guard let sessionID = tab.root.sessionID(ofPane: paneID) else {
            Issue.record("panelin oturumu bulunamadı")
            return
        }

        fixture.viewModel.restartPaneSession(paneID: paneID, forceDefaultShell: true)

        #expect(fixture.sessions.restartedSessionIDs == [sessionID])
    }

    @Test("bilinmeyen panel için restartPaneSession sessizce hiçbir şey yapmaz")
    func restartUnknownPaneIsNoop() {
        let fixture = makeFixture()

        fixture.viewModel.restartPaneSession(paneID: UUID())

        #expect(fixture.sessions.restartedSessionIDs.isEmpty)
    }
}
