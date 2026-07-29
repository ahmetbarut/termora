import Foundation
import Testing
@testable import Termora

/// briefs/3 "Sidebar" ▸ Saved Commands: sık kullanılan komutları kaydet, bul, terminale
/// yolla.
@MainActor
@Suite("Kayıtlı komutlar")
struct SavedCommandTests {

    private func makeStore() -> SavedCommandStore {
        let suite = "termora.saved.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SavedCommandStore(defaults: defaults)
    }

    @Test func aNewStoreIsEmpty() {
        #expect(makeStore().commands.isEmpty)
    }

    @Test func aSavedCommandSurvivesAReload() {
        let suite = "termora.saved.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let store = SavedCommandStore(defaults: defaults)
        store.add(SavedCommand(name: "Deploy", command: "make deploy",
                               details: "Ships main", workingDirectory: "/work"))

        let reloaded = SavedCommandStore(defaults: defaults)
        #expect(reloaded.commands.count == 1)
        let saved = try! #require(reloaded.commands.first)
        #expect(saved.name == "Deploy")
        #expect(saved.command == "make deploy")
        #expect(saved.details == "Ships main")
        #expect(saved.workingDirectory == "/work")
    }

    /// Adsız kayıt komutun kendisiyle anılır: listede boş bir satır, kullanıcının
    /// neyi kaydettiğini göremediği bir satırdır.
    @Test func acommandWithoutANameShowsTheCommandItself() {
        let unnamed = SavedCommand(name: "  ", command: "git status")
        #expect(unnamed.displayName == "git status")

        let named = SavedCommand(name: "Status", command: "git status")
        #expect(named.displayName == "Status")
    }

    @Test func updatingReplacesTheCommandInPlace() {
        let store = makeStore()
        let original = SavedCommand(name: "Build", command: "make")
        store.add(original)

        var edited = original
        edited.command = "make -j8"
        store.update(edited)

        #expect(store.commands.count == 1)
        #expect(store.commands.first?.command == "make -j8")
    }

    @Test func removingTakesItOutOfTheList() {
        let store = makeStore()
        let command = SavedCommand(name: "Temp", command: "echo hi")
        store.add(command)

        store.remove(id: command.id)

        #expect(store.commands.isEmpty)
    }

    /// Boş komut KAYDEDİLMEZ: tıklanınca hiçbir şey yapmayan bir satır, olmayan bir
    /// satırdan kötüdür.
    @Test func anEmptyCommandIsNotSaved() {
        let store = makeStore()
        store.add(SavedCommand(name: "Nothing", command: "   "))
        #expect(store.commands.isEmpty)
    }

    /// briefs/2 "Tehlikeli Komut Koruması": riskli komut kaydedilebilir ama bunu
    /// SÖYLER. Kaydı engellemek kullanıcının kendi aracını elinden almak olurdu;
    /// sessizce kabul etmek ise uyarısız bir tuzak bırakmak.
    @Test func aRiskyCommandIsSavedButFlagged() {
        let store = makeStore()
        let risky = SavedCommand(name: "Nuke", command: "rm -rf /")
        store.add(risky)

        #expect(store.commands.count == 1)
        #expect(store.commands.first?.isRisky == true)
        #expect(SavedCommand(name: "Safe", command: "ls -la").isRisky == false)
    }

    /// Etiketler virgülle yazılır ve boşlukları kırpılır; boş etiket düşer.
    @Test func tagsAreParsedFromAPlainTextField() {
        let command = SavedCommand(name: "Deploy", command: "make deploy",
                                   tags: ["  ci ", "", "release"])
        #expect(command.tags == ["ci", "release"])
    }

    /// Arama ada, komuta ve etikete bakar: kullanıcı hangisini hatırlıyorsa onunla
    /// bulabilmeli.
    @Test func searchMatchesNameCommandAndTags() {
        let deploy = SavedCommand(name: "Ship it", command: "make deploy", tags: ["release"])

        #expect(deploy.matches("ship"))
        #expect(deploy.matches("deploy"))
        #expect(deploy.matches("release"))
        #expect(deploy.matches("compile") == false)
    }
}
