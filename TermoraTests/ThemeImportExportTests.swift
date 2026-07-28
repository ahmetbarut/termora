import Foundation
import Testing
@testable import Termora

private final class FixtureBundleAnchor {}

/// brief 3 "Tema Sistemi → Kullanıcı özel tema dosyası içe ve dışa aktarabilmelidir".
///
/// Burada disk var: kullanıcı temaları paket temalarından AYRI bir klasörde yaşar,
/// uygulama yeniden açıldığında geri gelir, paket temaları salt okunur kalır.
@MainActor
@Suite("Tema içe/dışa aktarma")
struct ThemeImportExportTests {

    private var fixtureBundle: Bundle { Bundle(for: FixtureBundleAnchor.self) }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("termora-themes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ json: String, named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(json.utf8).write(to: url)
        return url
    }

    private static let auroraJSON = """
    {
      "id": "aurora",
      "name": "Aurora",
      "background": "#04121B",
      "foreground": "#E6F4FF",
      "cursor": "#4EE3F2",
      "selection": "#1F5FBF",
      "ansi": ["#0B1F2A", "#FF6B6B", "#3BE87B", "#FFD84D",
               "#66B8FF", "#D98BFF", "#4EE3F2", "#D0D0D0"]
    }
    """

    private func store(userThemes directory: URL) -> ThemeStore {
        ThemeStore(bundle: fixtureBundle, userThemesDirectory: directory)
    }

    // MARK: - İçe aktarma

    @Test func importsAThemeFileAndListsItWithTheBundledOnes() throws {
        let directory = try makeDirectory()
        let store = store(userThemes: directory)
        let file = try write(Self.auroraJSON, named: "aurora.json", in: directory.deletingLastPathComponent())

        let result = try store.importTheme(from: file)

        #expect(result.theme.id == "aurora")
        #expect(result.disposition == .added)
        #expect(store.userThemes.map(\.id) == ["aurora"])
        #expect(store.themes.contains { $0.id == "aurora" })
        #expect(store.theme(id: "aurora").name == "Aurora")
    }

    @Test func animportedThemeSurvivesARestart() throws {
        let directory = try makeDirectory()
        let file = try write(Self.auroraJSON, named: "aurora.json", in: directory.deletingLastPathComponent())
        try store(userThemes: directory).importTheme(from: file)

        let reopened = store(userThemes: directory)
        #expect(reopened.userThemes.map(\.id) == ["aurora"])
        #expect(reopened.theme(id: "aurora").background == "#04121B")
    }

    @Test func importedThemesAreUserThemesAndBundledThemesStayReadOnly() throws {
        let directory = try makeDirectory()
        let store = store(userThemes: directory)
        let file = try write(Self.auroraJSON, named: "aurora.json", in: directory.deletingLastPathComponent())
        try store.importTheme(from: file)

        #expect(store.isBuiltIn(id: "fixture-valid"))
        #expect(!store.isBuiltIn(id: "aurora"))
        #expect(store.builtInThemes.allSatisfy { !store.userThemes.map(\.id).contains($0.id) })
    }

    /// Aynı id'li KULLANICI teması: dosya kaynağın kendisidir, yerine yazılır.
    /// Aksi hâlde her yeniden içe aktarma listeye kopya eklerdi.
    @Test func importingTheSameIdentifierAgainReplacesTheUserTheme() throws {
        let directory = try makeDirectory()
        let store = store(userThemes: directory)
        let inbox = directory.deletingLastPathComponent()
        try store.importTheme(from: try write(Self.auroraJSON, named: "aurora.json", in: inbox))

        let edited = Self.auroraJSON.replacingOccurrences(of: "\"Aurora\"", with: "\"Aurora Deep\"")
        let result = try store.importTheme(from: try write(edited, named: "aurora-2.json", in: inbox))

        #expect(result.disposition == .replacedUserTheme)
        #expect(store.userThemes.count == 1)
        #expect(store.theme(id: "aurora").name == "Aurora Deep")
    }

    /// Paket teması SALT OKUNURDUR: aynı id'yle gelen dosya onu ezmez, yeni kimlik alır.
    @Test func importingOverABundledIdentifierKeepsTheBundledThemeAndRenamesTheImport() throws {
        let directory = try makeDirectory()
        let store = store(userThemes: directory)
        let clash = Self.auroraJSON.replacingOccurrences(of: "\"aurora\"", with: "\"fixture-valid\"")
        let file = try write(clash, named: "clash.json", in: directory.deletingLastPathComponent())

        let result = try store.importTheme(from: file)

        #expect(result.disposition == .addedWithGeneratedID(requestedID: "fixture-valid"))
        #expect(result.theme.id == "fixture-valid-2")
        #expect(store.theme(id: "fixture-valid").name == "Fixture Valid")
        #expect(store.theme(id: "fixture-valid-2").name == "Aurora")
    }

    @Test func importReportsWhatFailedInsteadOfSwallowingIt() throws {
        let directory = try makeDirectory()
        let store = store(userThemes: directory)
        let file = try write("{ \"name\": \"Half\" }", named: "half.json",
                             in: directory.deletingLastPathComponent())

        #expect(throws: ThemeFileError.self) { try store.importTheme(from: file) }
        #expect(store.userThemes.isEmpty)

        do {
            try store.importTheme(from: file)
        } catch let error as ThemeFileError {
            #expect(error.fileName == "half.json")
            #expect(error.reason == .missingField("background"))
        }
    }

    @Test func importingAMissingFileExplainsThatItCouldNotBeRead() throws {
        let directory = try makeDirectory()
        let store = store(userThemes: directory)
        let missing = directory.deletingLastPathComponent().appendingPathComponent("gone.json")

        do {
            try store.importTheme(from: missing)
            Issue.record("Var olmayan dosya hatasız içe aktarıldı")
        } catch let error as ThemeFileError {
            guard case .unreadableFile = error.reason else {
                Issue.record("Beklenen .unreadableFile, gelen \(error.reason)")
                return
            }
            #expect(error.fileName == "gone.json")
        }
    }

    // MARK: - Dışa aktarma

    @Test func exportsTheSelectedThemeAsAFileThatCanBeImportedAgain() throws {
        let directory = try makeDirectory()
        let store = store(userThemes: directory)
        let destination = directory.deletingLastPathComponent()
            .appendingPathComponent("exported-\(UUID().uuidString).json")

        try store.exportTheme(store.theme(id: "fixture-valid"), to: destination)

        #expect(FileManager.default.fileExists(atPath: destination.path))
        let reimported = try store.importTheme(from: destination)
        #expect(reimported.theme.ansi == store.theme(id: "fixture-valid").ansi)
        // Paket kimliğiyle çakıştığı için yeni kimlik alır, paket teması yerinde kalır.
        #expect(reimported.theme.id == "fixture-valid-2")
    }

    @Test func exportFailureExplainsItself() throws {
        let directory = try makeDirectory()
        let store = store(userThemes: directory)
        let unwritable = URL(fileURLWithPath: "/no-such-directory-\(UUID().uuidString)/theme.json")

        do {
            try store.exportTheme(store.theme(id: "fixture-valid"), to: unwritable)
            Issue.record("Yazılamayan yola dışa aktarma hatasız bitti")
        } catch let error as ThemeFileError {
            guard case .couldNotSave = error.reason else {
                Issue.record("Beklenen .couldNotSave, gelen \(error.reason)")
                return
            }
            #expect(error.title == "Theme not exported")
        }
    }

    // MARK: - Silme

    @Test func removingAUserThemeDeletesItsFileAndLeavesBundledThemesAlone() throws {
        let directory = try makeDirectory()
        let store = store(userThemes: directory)
        let file = try write(Self.auroraJSON, named: "aurora.json", in: directory.deletingLastPathComponent())
        try store.importTheme(from: file)

        store.removeUserTheme(id: "aurora")

        #expect(store.userThemes.isEmpty)
        #expect(!store.themes.contains { $0.id == "aurora" })
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)

        // Paket teması silinemez.
        store.removeUserTheme(id: "fixture-valid")
        #expect(store.theme(id: "fixture-valid").id == "fixture-valid")
    }

    // MARK: - Klasördeki bozuk / çakışan dosyalar

    @Test func aBrokenFileInTheUserFolderIsSkippedAndTheRestStillLoad() throws {
        let directory = try makeDirectory()
        _ = try write(Self.auroraJSON, named: "aurora.json", in: directory)
        _ = try write("{ oops", named: "broken.json", in: directory)

        #expect(store(userThemes: directory).userThemes.map(\.id) == ["aurora"])
    }

    /// Picker `id`'yi tag olarak kullanır: iki tema aynı kimliği taşırsa seçim bozulur.
    /// Elle klasöre atılmış çakışan dosya listeye alınmaz.
    @Test func themeIdentifiersStayUniqueEvenIfTheFolderHasAClashingFile() throws {
        let directory = try makeDirectory()
        let clash = Self.auroraJSON.replacingOccurrences(of: "\"aurora\"", with: "\"fixture-valid\"")
        _ = try write(clash, named: "clash.json", in: directory)
        _ = try write(Self.auroraJSON, named: "aurora.json", in: directory)

        let store = store(userThemes: directory)
        let ids = store.themes.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(store.theme(id: "fixture-valid").name == "Fixture Valid")
    }

    @Test func themesAreSortedByNameAcrossBothSources() throws {
        let directory = try makeDirectory()
        _ = try write(Self.auroraJSON, named: "aurora.json", in: directory)
        let names = store(userThemes: directory).themes.map(\.name)
        #expect(names == names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    // MARK: - Çakışma çözümü (saf)

    @Test func resolverAppendsAThemeNobodyElseClaims() {
        let imported = ThemeStore.fallback
        let resolution = ThemeImportResolver.resolve(imported,
                                                     builtInIDs: ["nord"],
                                                     userThemes: [])
        #expect(resolution.disposition == .added)
        #expect(resolution.userThemes.map(\.id) == [imported.id])
    }

    @Test func resolverReplacesTheUserThemeThatHasTheSameIdentifierInPlace() throws {
        var first = ThemeStore.fallback
        first.id = "aurora"
        first.name = "Aurora"
        var second = ThemeStore.fallback
        second.id = "b"
        var updated = first
        updated.name = "Aurora Deep"

        let resolution = ThemeImportResolver.resolve(updated,
                                                     builtInIDs: ["nord"],
                                                     userThemes: [first, second])
        #expect(resolution.disposition == .replacedUserTheme)
        #expect(resolution.userThemes.map(\.id) == ["aurora", "b"])
        #expect(resolution.userThemes.first?.name == "Aurora Deep")
    }

    @Test func resolverKeepsCountingUntilTheGeneratedIdentifierIsFree() {
        var imported = ThemeStore.fallback
        imported.id = "nord"
        var taken = ThemeStore.fallback
        taken.id = "nord-2"

        let resolution = ThemeImportResolver.resolve(imported,
                                                     builtInIDs: ["nord"],
                                                     userThemes: [taken])
        #expect(resolution.disposition == .addedWithGeneratedID(requestedID: "nord"))
        #expect(resolution.theme.id == "nord-3")
        #expect(resolution.userThemes.count == 2)
    }

    /// Kullanıcıya ne olduğu SÖYLENİR: sessiz "başarılı" mesajı yeniden adlandırmayı gizlerdi.
    @Test func everyDispositionHasAStatusSentenceNamingTheTheme() {
        var theme = ThemeStore.fallback
        theme.id = "aurora-2"
        theme.name = "Aurora"
        let cases: [ThemeImportDisposition] = [
            .added, .replacedUserTheme, .addedWithGeneratedID(requestedID: "aurora"),
        ]
        for disposition in cases {
            let result = ThemeImportResult(theme: theme, disposition: disposition)
            #expect(result.statusMessage.contains("Aurora"), "\(disposition) tema adını anmıyor")
            #expect(!result.statusMessage.isEmpty)
        }
        #expect(ThemeImportResult(theme: theme, disposition: .addedWithGeneratedID(requestedID: "aurora"))
            .statusMessage.contains("aurora-2"))
    }
}
