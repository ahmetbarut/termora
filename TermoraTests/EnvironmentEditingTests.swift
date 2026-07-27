import Testing
@testable import Termora

@Suite("Profil ortam değişkeni düzenleme")
struct EnvironmentEditingTests {

    @Test func entriesAreSortedByKey() {
        let entries = EnvironmentEditing.entries(from: ["ZED": "1", "ALPHA": "2", "MID": "3"])
        #expect(entries.map(\.key) == ["ALPHA", "MID", "ZED"])
        #expect(entries.map(\.value) == ["2", "3", "1"])
    }

    @Test func entriesGetDistinctIdentities() {
        let entries = EnvironmentEditing.entries(from: ["A": "x", "B": "x"])
        #expect(Set(entries.map(\.id)).count == 2)
    }

    @Test func blankKeysAreDropped() {
        let entries = [
            EnvironmentEntry(key: "   ", value: "atılacak"),
            EnvironmentEntry(key: "", value: "bu da"),
            EnvironmentEntry(key: "EDITOR", value: "vim")
        ]
        #expect(EnvironmentEditing.dictionary(from: entries) == ["EDITOR": "vim"])
    }

    @Test func keysAreTrimmedAndLastDuplicateWins() {
        let entries = [
            EnvironmentEntry(key: " EDITOR ", value: "vi"),
            EnvironmentEntry(key: "EDITOR", value: "nvim")
        ]
        #expect(EnvironmentEditing.dictionary(from: entries) == ["EDITOR": "nvim"])
    }

    @Test func emptyValuesArePreserved() {
        let entries = [EnvironmentEntry(key: "NO_COLOR", value: "")]
        #expect(EnvironmentEditing.dictionary(from: entries) == ["NO_COLOR": ""])
    }

    @Test func roundTripPreservesPairs() {
        let original = ["A": "1", "B": "2", "C": "3"]
        let roundTripped = EnvironmentEditing.dictionary(from: EnvironmentEditing.entries(from: original))
        #expect(roundTripped == original)
    }
}
