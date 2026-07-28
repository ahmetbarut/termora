import Foundation
import Testing
@testable import Termora

@Suite struct WorkspaceSnapshotTests {

    // MARK: - Capture: PaneNode -> WorkspaceLayout

    @Test func singleLeafCapturesTheSessionDirectory() throws {
        let paneID = UUID()
        let sessionID = UUID()
        let node = PaneNode.leaf(paneID: paneID, sessionID: sessionID)

        let layout = WorkspaceSnapshot.layout(from: node) { $0 == sessionID ? "/Users/dev/api" : nil }

        guard case let .pane(pane) = layout else {
            Issue.record("expected a pane layout, got \(layout)")
            return
        }
        #expect(pane.id == paneID)
        #expect(pane.startupDirectory == "/Users/dev/api")
        #expect(pane.startupCommand == nil)
    }

    @Test func unknownSessionCapturesNilDirectory() throws {
        let node = PaneNode.leaf(paneID: UUID(), sessionID: UUID())
        let layout = WorkspaceSnapshot.layout(from: node) { _ in nil }

        guard case let .pane(pane) = layout else {
            Issue.record("expected a pane layout, got \(layout)")
            return
        }
        #expect(pane.startupDirectory == nil)
    }

    @Test func nestedTreeKeepsAxisRatioAndOrder() throws {
        let left = (pane: UUID(), session: UUID())
        let topRight = (pane: UUID(), session: UUID())
        let bottomRight = (pane: UUID(), session: UUID())
        let directories = [
            left.session: "/w/left",
            topRight.session: "/w/top",
            bottomRight.session: "/w/bottom"
        ]

        let node = PaneNode.split(
            id: UUID(),
            axis: .vertical,
            ratio: 0.4,
            first: .leaf(paneID: left.pane, sessionID: left.session),
            second: .split(
                id: UUID(),
                axis: .horizontal,
                ratio: 0.7,
                first: .leaf(paneID: topRight.pane, sessionID: topRight.session),
                second: .leaf(paneID: bottomRight.pane, sessionID: bottomRight.session)))

        let layout = WorkspaceSnapshot.layout(from: node) { directories[$0] }

        let expected = WorkspaceLayout.split(
            axis: .vertical,
            ratio: 0.4,
            first: .pane(WorkspacePane(id: left.pane, startupDirectory: "/w/left")),
            second: .split(
                axis: .horizontal,
                ratio: 0.7,
                first: .pane(WorkspacePane(id: topRight.pane, startupDirectory: "/w/top")),
                second: .pane(WorkspacePane(id: bottomRight.pane, startupDirectory: "/w/bottom"))))

        #expect(layout == expected)
        #expect(layout.panes.map(\.startupDirectory) == ["/w/left", "/w/top", "/w/bottom"])
    }

    @Test func capturedLayoutSurvivesEncodingWithoutSessionIdentifiers() throws {
        let node = PaneNode.split(
            id: UUID(),
            axis: .horizontal,
            ratio: 0.5,
            first: .leaf(paneID: UUID(), sessionID: UUID()),
            second: .leaf(paneID: UUID(), sessionID: UUID()))

        let layout = WorkspaceSnapshot.layout(from: node) { _ in "/w" }
        let data = try JSONEncoder().encode(layout)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("sessionID") == false)
        #expect(try JSONDecoder().decode(WorkspaceLayout.self, from: data) == layout)
    }

    // MARK: - Restore: Workspace -> open plan

    @Test func planFallsBackToWorkspaceDirectoryWhenPaneHasNone() throws {
        let named = WorkspacePane(startupDirectory: "/Users/dev/pinro/web")
        let unnamed = WorkspacePane()
        let workspace = Workspace(
            name: "Pinro",
            directory: "/Users/dev/pinro",
            tabs: [WorkspaceTab(title: "Split", layout: .split(
                axis: .vertical, ratio: 0.5, first: .pane(named), second: .pane(unnamed)))])

        let tab = try #require(WorkspaceSnapshot.plan(for: workspace).first)
        #expect(tab.title == "Split")
        #expect(tab.panes == [
            WorkspaceOpenPlan.Pane(paneID: named.id, directory: "/Users/dev/pinro/web", startupCommand: nil),
            WorkspaceOpenPlan.Pane(paneID: unnamed.id, directory: "/Users/dev/pinro", startupCommand: nil)
        ])
        #expect(tab.layout == workspace.tabs.first?.layout)
    }

    @Test func blankPaneDirectoryFallsBackToWorkspaceDirectory() throws {
        let pane = WorkspacePane(startupDirectory: "   ", startupCommand: "  ")
        let workspace = Workspace(name: "W", directory: "/root",
                                  tabs: [WorkspaceTab(layout: .pane(pane))])

        let planned = try #require(WorkspaceSnapshot.plan(for: workspace).first?.panes.first)
        #expect(planned.directory == "/root")
        #expect(planned.startupCommand == nil)
    }

    @Test func planCarriesStartupCommandsPerPane() throws {
        let workspace = Workspace(
            name: "Pinro",
            directory: "/p",
            tabs: [
                WorkspaceTab(title: "Backend", layout: .pane(WorkspacePane(startupCommand: "php artisan serve"))),
                WorkspaceTab(title: "Queue", layout: .pane(WorkspacePane(startupCommand: "php artisan queue:work")))
            ])

        let plan = WorkspaceSnapshot.plan(for: workspace)
        #expect(plan.count == 2)
        #expect(plan.map(\.title) == ["Backend", "Queue"])
        #expect(plan.flatMap(\.panes).map(\.startupCommand) == ["php artisan serve", "php artisan queue:work"])
    }

    @Test func planForWorkspaceWithoutTabsIsEmpty() {
        let workspace = Workspace(name: "Empty", directory: "/p")
        #expect(WorkspaceSnapshot.plan(for: workspace).isEmpty)
    }

    // MARK: - Startup command confirmation

    @Test func startupCommandsAreListedInTabThenPaneOrder() {
        let workspace = Workspace(
            name: "Pinro",
            directory: "/p",
            tabs: [
                WorkspaceTab(title: "Backend", layout: .split(
                    axis: .horizontal,
                    ratio: 0.5,
                    first: .pane(WorkspacePane(startupCommand: "php artisan serve")),
                    second: .pane(WorkspacePane()))),
                WorkspaceTab(title: "Frontend", layout: .pane(WorkspacePane(startupCommand: "npm run dev")))
            ])

        #expect(WorkspaceOpenPlan.startupCommands(for: workspace) == ["php artisan serve", "npm run dev"])
    }

    @Test func startupCommandsAreEmptyWhenNothingWouldRun() {
        let workspace = Workspace(
            name: "Pinro",
            directory: "/p",
            tabs: [WorkspaceTab(layout: .pane(WorkspacePane(startupDirectory: "/p/api")))])

        #expect(WorkspaceOpenPlan.startupCommands(for: workspace).isEmpty)
    }

    @Test func capturedThenRestoredLayoutKeepsPaneShape() throws {
        let panes = (0..<3).map { _ in (pane: UUID(), session: UUID()) }
        let node = PaneNode.split(
            id: UUID(),
            axis: .vertical,
            ratio: 0.3,
            first: .leaf(paneID: panes[0].pane, sessionID: panes[0].session),
            second: .split(
                id: UUID(),
                axis: .horizontal,
                ratio: 0.6,
                first: .leaf(paneID: panes[1].pane, sessionID: panes[1].session),
                second: .leaf(paneID: panes[2].pane, sessionID: panes[2].session)))

        let layout = WorkspaceSnapshot.layout(from: node) { _ in nil }
        let workspace = Workspace(name: "Round", directory: "/home",
                                  tabs: [WorkspaceTab(title: "One", layout: layout)])

        let planned = try #require(WorkspaceSnapshot.plan(for: workspace).first)
        #expect(planned.panes.map(\.paneID) == panes.map(\.pane))
        #expect(planned.panes.allSatisfy { $0.directory == "/home" })
    }
}
