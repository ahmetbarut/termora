import Foundation
import Testing
@testable import Termora

@MainActor
@Suite struct TerminalProfileTests {
    @Test func codableRoundTripPreservesAllFields() throws {
        var profile = TerminalProfile(name: "Work")
        profile.shellPath = "/opt/homebrew/bin/fish"
        profile.startupDirectory = "/Users/me/Projects"
        profile.startupCommand = "git status"
        profile.fontName = "JetBrainsMono-Regular"
        profile.fontSize = 14
        profile.themeID = "nord"
        profile.environment = ["FOO": "bar"]

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(TerminalProfile.self, from: data)
        #expect(decoded == profile)
        #expect(decoded.id == profile.id)
    }

    @Test func minimalProfileHasExpectedDefaults() {
        let profile = TerminalProfile(name: "Minimal")
        #expect(profile.name == "Minimal")
        #expect(profile.shellPath == nil)
        #expect(profile.startupDirectory == nil)
        #expect(profile.startupCommand == nil)
        #expect(profile.fontName == nil)
        #expect(profile.fontSize == nil)
        #expect(profile.themeID == nil)
        #expect(profile.environment.isEmpty)
    }

    @Test func newProfilesGetDistinctIDs() {
        #expect(TerminalProfile(name: "A").id != TerminalProfile(name: "B").id)
    }

    @Test func environmentDictionaryRoundTripsThroughCodable() throws {
        var profile = TerminalProfile(name: "Deploy")
        profile.environment = ["DEPLOY_ENV": "staging", "EDITOR": "vim", "EMPTY": ""]
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(TerminalProfile.self, from: data)
        #expect(decoded.environment == ["DEPLOY_ENV": "staging", "EDITOR": "vim", "EMPTY": ""])
    }
}
