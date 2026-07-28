import CoreGraphics
import Foundation
import Testing
@testable import Termora

/// Oturum anlık görüntüsünün kalıcılık sözleşmesi ve geri yükleme planı
/// (briefs/2 "Oturum Geri Yükleme" + "Pencere Yönetimi").
@Suite struct SessionSnapshotTests {

    // MARK: - Yardımcılar

    private func nestedWindow() -> SessionWindowSnapshot {
        // ((A | B) üstünde C) — iç içe split; round-trip'i kilitler.
        let a = WorkspacePane(startupDirectory: "/Users/dev/api")
        let b = WorkspacePane(startupDirectory: "/Users/dev/api/logs")
        let c = WorkspacePane(startupDirectory: "/Users/dev/web")
        let layout = WorkspaceLayout.split(
            axis: .horizontal,
            ratio: 0.3,
            first: .split(axis: .vertical, ratio: 0.7, first: .pane(a), second: .pane(b)),
            second: .pane(c))
        return SessionWindowSnapshot(
            tabs: [SessionTabSnapshot(tab: WorkspaceTab(title: "Server", layout: layout),
                                      activePaneID: b.id)],
            activeTabID: nil,
            frame: SessionWindowFrame(x: 120, y: 80, width: 1000, height: 640),
            isFullScreen: false,
            workspaceID: UUID())
    }

    // MARK: - Round-trip

    @Test func nestedSplitLayoutSurvivesEncodeAndDecode() throws {
        var window = nestedWindow()
        window.activeTabID = window.tabs.first?.id
        let snapshot = SessionSnapshot(windows: [window], savedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)

        #expect(decoded == snapshot)
        let decodedTab = try #require(decoded.windows.first?.tabs.first)
        #expect(decodedTab.tab.layout == window.tabs.first?.tab.layout)
        #expect(decodedTab.tab.layout.panes.count == 3)
        #expect(decodedTab.activePaneID == window.tabs.first?.activePaneID)
        #expect(decoded.windows.first?.workspaceID == window.workspaceID)
    }

    @Test func windowFrameRoundTripsExactly() throws {
        let frame = SessionWindowFrame(CGRect(x: -40.5, y: 12, width: 1440, height: 900))
        let decoded = try JSONDecoder().decode(SessionWindowFrame.self,
                                               from: try JSONEncoder().encode(frame))
        #expect(decoded == frame)
        // Trap: CGFloat/Double karşılaştırması AnyHashable kutulaması yüzünden patlar.
        #expect(Double(decoded.cgRect.origin.x) == -40.5)
        #expect(Double(decoded.cgRect.width) == 1440)
    }

    @Test func everyWindowKeepsItsOwnTabs() throws {
        let first = SessionWindowSnapshot(tabs: [SessionTabSnapshot(tab: WorkspaceTab(title: "A", layout: .pane(WorkspacePane())))])
        let second = SessionWindowSnapshot(tabs: [
            SessionTabSnapshot(tab: WorkspaceTab(title: "B", layout: .pane(WorkspacePane()))),
            SessionTabSnapshot(tab: WorkspaceTab(title: "C", layout: .pane(WorkspacePane())))
        ])
        let snapshot = SessionSnapshot(windows: [first, second])

        let decoded = try JSONDecoder().decode(SessionSnapshot.self,
                                               from: try JSONEncoder().encode(snapshot))

        #expect(decoded.windows.count == 2)
        #expect(decoded.windows.first?.tabs.map(\.tab.title) == ["A"])
        #expect(decoded.windows.last?.tabs.map(\.tab.title) == ["B", "C"])
    }

    // MARK: - İleri uyumlu çözme

    @Test func blobWithoutOptionalFieldsStillDecodes() throws {
        let legacy = Data("""
        {"windows":[{"id":"\(UUID().uuidString)"}]}
        """.utf8)

        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: legacy)

        #expect(decoded.windows.count == 1)
        #expect(decoded.windows.first?.tabs.isEmpty == true)
        #expect(decoded.windows.first?.isFullScreen == false)
        #expect(decoded.windows.first?.frame == nil)
        #expect(decoded.savedAt == nil)
    }

    @Test func oneUndecodableWindowDoesNotDropTheOthers() throws {
        let good = SessionWindowSnapshot(tabs: [SessionTabSnapshot(tab: WorkspaceTab(title: "A", layout: .pane(WorkspacePane())))])
        let goodJSON = String(decoding: try JSONEncoder().encode(good), as: UTF8.self)
        // Kimliksiz pencere çözülemez; yanındaki sağlam kayıt korunmalı.
        let blob = Data("""
        {"windows":[{"tabs":[]},\(goodJSON)]}
        """.utf8)

        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: blob)

        #expect(decoded.windows.count == 1)
        #expect(decoded.windows.first?.tabs.first?.tab.title == "A")
    }

    @Test func oneUndecodableTabDoesNotDropTheWindow() throws {
        let good = SessionTabSnapshot(tab: WorkspaceTab(title: "Keep", layout: .pane(WorkspacePane())))
        let goodJSON = String(decoding: try JSONEncoder().encode(good), as: UTF8.self)
        let blob = Data("""
        {"windows":[{"id":"\(UUID().uuidString)","tabs":[{"tab":{"id":"\(UUID().uuidString)"}},\(goodJSON)]}]}
        """.utf8)

        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: blob)

        #expect(decoded.windows.count == 1)
        #expect(decoded.windows.first?.tabs.map(\.tab.title) == ["Keep"])
    }

    @Test func aBrokenFrameDoesNotCostTheTabs() throws {
        let blob = Data("""
        {"windows":[{"id":"\(UUID().uuidString)","frame":{"x":10,"y":20},"tabs":[]}]}
        """.utf8)

        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: blob)

        #expect(decoded.windows.count == 1)
        #expect(decoded.windows.first?.frame == nil)
    }

    // MARK: - Geri yükleme planı: GÜVENLİK

    @Test func planStripsEveryStartupCommand() throws {
        // Elle düzenlenmiş / eski bir blob komut taşısa bile plana geçemez.
        let layout = WorkspaceLayout.split(
            axis: .vertical,
            ratio: 0.5,
            first: .pane(WorkspacePane(startupDirectory: "/tmp", startupCommand: "rm -rf /")),
            second: .pane(WorkspacePane(startupDirectory: "/tmp", startupCommand: "npm run dev")))
        let window = SessionWindowSnapshot(tabs: [SessionTabSnapshot(tab: WorkspaceTab(layout: layout))])

        let plan = SessionRestorePlan.tabs(for: window, directoryExists: { _ in true })

        #expect(plan.flatMap(\.layout.panes).allSatisfy { $0.startupCommand == nil })
    }

    // MARK: - Geri yükleme planı: dizinler

    @Test func planKeepsDirectoriesThatStillExist() throws {
        let window = nestedWindow()

        let plan = SessionRestorePlan.tabs(for: window, directoryExists: { _ in true })

        let directories = plan.flatMap(\.layout.panes).map(\.startupDirectory)
        #expect(directories == ["/Users/dev/api", "/Users/dev/api/logs", "/Users/dev/web"])
    }

    @Test func planDropsDirectoriesThatWereDeleted() throws {
        let window = nestedWindow()

        // Yalnız "/Users/dev/web" hâlâ var: silinmiş klasörler nil'e düşer, çökme yok.
        let plan = SessionRestorePlan.tabs(for: window, directoryExists: { $0 == "/Users/dev/web" })

        let directories = plan.flatMap(\.layout.panes).map(\.startupDirectory)
        #expect(directories == [nil, nil, "/Users/dev/web"])
    }

    @Test func planIgnoresBlankDirectories() throws {
        let window = SessionWindowSnapshot(tabs: [
            SessionTabSnapshot(tab: WorkspaceTab(layout: .pane(WorkspacePane(startupDirectory: "   "))))
        ])

        let plan = SessionRestorePlan.tabs(for: window, directoryExists: { _ in true })

        #expect(plan.first?.layout.panes.first?.startupDirectory == nil)
    }

    @Test func planPreservesNestedSplitGeometryAndPaneIdentity() throws {
        let window = nestedWindow()

        let plan = SessionRestorePlan.tabs(for: window, directoryExists: { _ in true })

        let tab = try #require(plan.first)
        #expect(tab.title == "Server")
        #expect(tab.id == window.tabs.first?.tab.id)
        guard case let .split(outerAxis, outerRatio, inner, _) = tab.layout else {
            Issue.record("expected a split root, got \(tab.layout)")
            return
        }
        #expect(outerAxis == .horizontal)
        #expect(Double(outerRatio) == 0.3)
        guard case let .split(innerAxis, innerRatio, _, _) = inner else {
            Issue.record("expected a nested split, got \(inner)")
            return
        }
        #expect(innerAxis == .vertical)
        #expect(Double(innerRatio) == 0.7)
        #expect(tab.layout.panes.map(\.id) == window.tabs.first?.tab.layout.panes.map(\.id))
    }

    @Test func planFallsBackToTheFirstPaneWhenTheActiveOneIsGone() throws {
        let window = SessionWindowSnapshot(tabs: [
            SessionTabSnapshot(tab: WorkspaceTab(layout: .pane(WorkspacePane())),
                               activePaneID: UUID())
        ])

        let plan = SessionRestorePlan.tabs(for: window, directoryExists: { _ in true })

        #expect(plan.first?.activePaneID == plan.first?.layout.panes.first?.id)
    }

    // MARK: - Pencere yerleşimi

    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let minimum = CGSize(width: 720, height: 480)

    @Test func aFrameFullyOnScreenIsRestoredUnchanged() throws {
        let saved = SessionWindowFrame(x: 100, y: 60, width: 1200, height: 700)

        let placed = try #require(SessionWindowPlacement.frame(for: saved,
                                                              visibleScreenFrames: [screen],
                                                              minimumSize: minimum))

        #expect(Double(placed.origin.x) == 100)
        #expect(Double(placed.origin.y) == 60)
        #expect(Double(placed.width) == 1200)
        #expect(Double(placed.height) == 700)
    }

    @Test func aFrameOnADisconnectedMonitorIsCentredOnAnAvailableScreen() throws {
        // Harici ekran çıkarıldı: kayıtlı konum artık hiçbir ekranla kesişmiyor.
        let saved = SessionWindowFrame(x: 4000, y: 3000, width: 1000, height: 600)

        let placed = try #require(SessionWindowPlacement.frame(for: saved,
                                                              visibleScreenFrames: [screen],
                                                              minimumSize: minimum))

        #expect(screen.contains(placed))
        #expect(Double(placed.midX) == Double(screen.midX))
        #expect(Double(placed.midY) == Double(screen.midY))
    }

    @Test func aWindowHangingOffTheEdgeIsPulledBackOnScreen() throws {
        let saved = SessionWindowFrame(x: 1800, y: 900, width: 1000, height: 600)

        let placed = try #require(SessionWindowPlacement.frame(for: saved,
                                                              visibleScreenFrames: [screen],
                                                              minimumSize: minimum))

        #expect(screen.contains(placed))
        #expect(Double(placed.width) == 1000)
    }

    @Test func aTinySavedFrameGrowsToTheUsableMinimum() throws {
        let saved = SessionWindowFrame(x: 10, y: 10, width: 120, height: 90)

        let placed = try #require(SessionWindowPlacement.frame(for: saved,
                                                              visibleScreenFrames: [screen],
                                                              minimumSize: minimum))

        #expect(Double(placed.width) == 720)
        #expect(Double(placed.height) == 480)
    }

    @Test func aFrameLargerThanTheScreenIsClampedToIt() throws {
        let saved = SessionWindowFrame(x: -200, y: -200, width: 4000, height: 3000)

        let placed = try #require(SessionWindowPlacement.frame(for: saved,
                                                              visibleScreenFrames: [screen],
                                                              minimumSize: minimum))

        #expect(Double(placed.width) == Double(screen.width))
        #expect(Double(placed.height) == Double(screen.height))
        #expect(screen.contains(placed))
    }

    @Test func theScreenWithTheLargestOverlapWins() throws {
        let secondary = CGRect(x: 1920, y: 0, width: 1440, height: 900)
        let saved = SessionWindowFrame(x: 2100, y: 100, width: 800, height: 500)

        let placed = try #require(SessionWindowPlacement.frame(for: saved,
                                                              visibleScreenFrames: [screen, secondary],
                                                              minimumSize: minimum))

        #expect(secondary.contains(placed))
        #expect(Double(placed.origin.x) == 2100)
    }

    @Test func noSavedFrameOrNoScreenLeavesTheDefaultPlacement() {
        #expect(SessionWindowPlacement.frame(for: nil,
                                             visibleScreenFrames: [screen],
                                             minimumSize: minimum) == nil)
        #expect(SessionWindowPlacement.frame(for: SessionWindowFrame(x: 0, y: 0, width: 800, height: 600),
                                             visibleScreenFrames: [],
                                             minimumSize: minimum) == nil)
        #expect(SessionWindowPlacement.frame(for: SessionWindowFrame(x: 0, y: 0, width: 0, height: 600),
                                             visibleScreenFrames: [screen],
                                             minimumSize: minimum) == nil)
    }

    /// Ürün kararı: açılışta tam ekrana GİRİLMEZ; tam ekran öncesi çerçeve geri gelir.
    @Test func restoringNeverForcesFullScreen() {
        var window = SessionWindowSnapshot()
        window.isFullScreen = true
        #expect(SessionWindowPlacement.shouldEnterFullScreen(restoring: window) == false)
    }
}
