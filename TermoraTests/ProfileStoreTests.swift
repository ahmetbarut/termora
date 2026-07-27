import Foundation
import Testing
@testable import Termora

@MainActor
@Suite struct ProfileStoreTests {
    private static func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "ProfileStoreTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    @Test func freshStoreStartsEmpty() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        #expect(ProfileStore(defaults: defaults).profiles.isEmpty)
    }

    @Test func crudOperationsPersistAcrossReloads() throws {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ProfileStore(defaults: defaults)

        // Create
        let work = TerminalProfile(name: "Work")
        let deploy = TerminalProfile(name: "Deploy")
        store.profiles.append(work)
        store.profiles.append(deploy)
        #expect(ProfileStore(defaults: defaults).profiles == [work, deploy])

        // Update
        var updatedWork = work
        updatedWork.shellPath = "/bin/bash"
        updatedWork.environment = ["CI": "1"]
        let index = try #require(store.profiles.firstIndex(where: { $0.id == work.id }))
        store.profiles[index] = updatedWork
        #expect(ProfileStore(defaults: defaults).profiles == [updatedWork, deploy])

        // Delete
        store.profiles.removeAll { $0.id == deploy.id }
        #expect(ProfileStore(defaults: defaults).profiles == [updatedWork])
    }
}
