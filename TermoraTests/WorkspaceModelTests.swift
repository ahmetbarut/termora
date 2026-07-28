import Foundation
import Testing
@testable import Termora

@Suite struct WorkspaceModelTests {

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @Test func emptyWorkspaceHasNoTabsAndNoPanes() {
        let workspace = Workspace(name: "Pinro", directory: "/Users/dev/Projects/pinro")
        #expect(workspace.tabs.isEmpty)
        #expect(workspace.paneCount == 0)
        #expect(workspace.environment.isEmpty)
        #expect(workspace.trustsStartupCommands == false)
        #expect(workspace.lastOpenedAt == nil)
    }

    @Test func paneCountSumsEveryPaneAcrossTabs() {
        let single = WorkspaceTab(title: "Backend", layout: .pane(WorkspacePane()))
        let threeUp = WorkspaceTab(
            title: "Services",
            layout: .split(
                axis: .vertical,
                ratio: 0.5,
                first: .pane(WorkspacePane()),
                second: .split(
                    axis: .horizontal,
                    ratio: 0.4,
                    first: .pane(WorkspacePane()),
                    second: .pane(WorkspacePane()))))

        let workspace = Workspace(name: "Pinro", directory: "/p", tabs: [single, threeUp])
        #expect(workspace.paneCount == 4)
    }

    @Test func layoutPanesAreListedInFirstThenSecondOrder() {
        let a = WorkspacePane(startupCommand: "a")
        let b = WorkspacePane(startupCommand: "b")
        let c = WorkspacePane(startupCommand: "c")
        let layout = WorkspaceLayout.split(
            axis: .horizontal,
            ratio: 0.6,
            first: .pane(a),
            second: .split(axis: .vertical, ratio: 0.5, first: .pane(b), second: .pane(c)))

        #expect(layout.panes.map(\.startupCommand) == ["a", "b", "c"])
    }

    @Test func nestedLayoutRoundTripsThroughCodable() throws {
        let layout = WorkspaceLayout.split(
            axis: .vertical,
            ratio: 0.35,
            first: .pane(WorkspacePane(startupDirectory: "/srv", startupCommand: "npm run dev")),
            second: .split(
                axis: .horizontal,
                ratio: 0.75,
                first: .pane(WorkspacePane()),
                second: .split(
                    axis: .vertical,
                    ratio: 0.2,
                    first: .pane(WorkspacePane(startupDirectory: "/srv/api")),
                    second: .pane(WorkspacePane(startupCommand: "php artisan queue:work")))))

        #expect(try roundTrip(layout) == layout)
    }

    @Test func workspaceRoundTripsEveryStoredField() throws {
        let opened = Date(timeIntervalSince1970: 1_700_000_000)
        let workspace = Workspace(
            name: "Pinro",
            directory: "/Users/dev/Projects/pinro",
            tabs: [
                WorkspaceTab(title: "Backend", layout: .pane(WorkspacePane(startupCommand: "php artisan serve"))),
                WorkspaceTab(title: nil, layout: .split(
                    axis: .horizontal,
                    ratio: 0.5,
                    first: .pane(WorkspacePane(startupDirectory: "/Users/dev/Projects/pinro/web")),
                    second: .pane(WorkspacePane())))
            ],
            environment: ["APP_ENV": "local", "PATH_EXTRA": "/opt/bin"],
            profileID: UUID(),
            themeID: "termora-dark",
            trustsStartupCommands: true,
            lastOpenedAt: opened)

        let decoded = try roundTrip(workspace)
        #expect(decoded == workspace)
        #expect(decoded.lastOpenedAt == opened)
        #expect(decoded.paneCount == 3)
    }

    @Test func tabTitleStaysNilWhenNotNamed() throws {
        let tab = WorkspaceTab(layout: .pane(WorkspacePane()))
        #expect(tab.title == nil)
        #expect(try roundTrip(tab) == tab)
    }
}
