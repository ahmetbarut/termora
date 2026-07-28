import Foundation
import Testing
@testable import Termora

@MainActor
@Suite struct WorkspaceStoreTests {
    private static func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "WorkspaceStoreTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private static func makeWorkspace(name: String, directory: String = "/p") -> Workspace {
        Workspace(name: name, directory: directory,
                  tabs: [WorkspaceTab(title: name, layout: .pane(WorkspacePane()))])
    }

    @Test func freshStoreStartsEmpty() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        #expect(WorkspaceStore(defaults: defaults).workspaces.isEmpty)
    }

    @Test func upsertAppendsThenUpdatesInPlaceAndPersists() throws {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WorkspaceStore(defaults: defaults)
        let pinro = Self.makeWorkspace(name: "Pinro")
        let termora = Self.makeWorkspace(name: "Termora")

        store.upsert(pinro)
        store.upsert(termora)
        #expect(WorkspaceStore(defaults: defaults).workspaces == [pinro, termora])

        var renamed = pinro
        renamed.name = "Pinro API"
        renamed.environment = ["APP_ENV": "local"]
        store.upsert(renamed)

        #expect(store.workspaces.count == 2)
        #expect(store.workspaces.first == renamed)
        #expect(WorkspaceStore(defaults: defaults).workspaces == [renamed, termora])
    }

    @Test func removeDeletesOnlyTheMatchingWorkspace() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WorkspaceStore(defaults: defaults)
        let pinro = Self.makeWorkspace(name: "Pinro")
        let termora = Self.makeWorkspace(name: "Termora")
        store.upsert(pinro)
        store.upsert(termora)

        store.remove(id: pinro.id)
        #expect(store.workspaces == [termora])
        #expect(WorkspaceStore(defaults: defaults).workspaces == [termora])

        store.remove(id: UUID())
        #expect(store.workspaces == [termora])
    }

    @Test func markOpenedStampsTheInjectedDateAndPersists() throws {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WorkspaceStore(defaults: defaults)
        let pinro = Self.makeWorkspace(name: "Pinro")
        store.upsert(pinro)
        #expect(store.workspaces.first?.lastOpenedAt == nil)

        let opened = Date(timeIntervalSince1970: 1_700_000_000)
        store.markOpened(id: pinro.id, at: opened)

        #expect(store.workspaces.first?.lastOpenedAt == opened)
        #expect(WorkspaceStore(defaults: defaults).workspaces.first?.lastOpenedAt == opened)
    }

    @Test func markOpenedIgnoresUnknownIdentifier() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WorkspaceStore(defaults: defaults)
        let pinro = Self.makeWorkspace(name: "Pinro")
        store.upsert(pinro)

        store.markOpened(id: UUID(), at: Date(timeIntervalSince1970: 1))
        #expect(store.workspaces == [pinro])
    }

    @Test func nestedLayoutSurvivesReload() throws {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WorkspaceStore(defaults: defaults)
        let workspace = Workspace(
            name: "Pinro",
            directory: "/Users/dev/pinro",
            tabs: [WorkspaceTab(title: "Services", layout: .split(
                axis: .vertical,
                ratio: 0.45,
                first: .pane(WorkspacePane(startupDirectory: "/Users/dev/pinro/api",
                                           startupCommand: "php artisan serve")),
                second: .split(
                    axis: .horizontal,
                    ratio: 0.6,
                    first: .pane(WorkspacePane(startupCommand: "php artisan queue:work")),
                    second: .pane(WorkspacePane()))))],
            environment: ["APP_ENV": "local"],
            themeID: "termora-dark",
            trustsStartupCommands: true)
        store.upsert(workspace)

        let reloaded = WorkspaceStore(defaults: defaults)
        #expect(reloaded.workspaces == [workspace])
        #expect(reloaded.workspaces.first?.paneCount == 3)
    }

    @Test func corruptBlobFallsBackToEmptyAndIsBackedUp() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let garbage = Data("[{broken".utf8)
        defaults.set(garbage, forKey: WorkspaceStore.storageKey)

        let store = WorkspaceStore(defaults: defaults)
        #expect(store.workspaces.isEmpty)
        #expect(defaults.data(forKey: WorkspaceStore.backupKey) == garbage)
        #expect(defaults.data(forKey: WorkspaceStore.storageKey) == nil)
    }

    @Test func storeRecoveredFromCorruptBlobStaysUsable() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(Data("not json".utf8), forKey: WorkspaceStore.storageKey)
        let store = WorkspaceStore(defaults: defaults)

        let fresh = Self.makeWorkspace(name: "Fresh")
        store.upsert(fresh)
        #expect(WorkspaceStore(defaults: defaults).workspaces == [fresh])
    }
}
