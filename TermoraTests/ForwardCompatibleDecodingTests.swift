import Foundation
import Testing
@testable import Termora

/// Kalıcı modellerin ileri/geri uyumlu çözülmesi.
///
/// Sentezlenmiş `init(from:)` özellik varsayılanlarını YOK SAYAR: alan JSON'da yoksa
/// `keyNotFound` fırlatır. Böyle bir modele yeni alan eklendiğinde kullanıcının diskteki
/// eski blob'u "bozuk" sayılır, depoların yedekle-ve-sıfırla yolu devreye girer ve
/// ayarlar / profiller / workspace'ler sessizce sıfırlanır. Bu paket o yolu kapatır.
@MainActor
@Suite struct ForwardCompatibleDecodingTests {

    private static let idA = "11111111-1111-1111-1111-111111111111"
    private static let idB = "22222222-2222-2222-2222-222222222222"
    private static let idC = "33333333-3333-3333-3333-333333333333"

    private func json(_ text: String) -> Data { Data(text.utf8) }

    // MARK: - AppSettings

    /// Alan içermeyen blob bile çözülmeli: her alan varsayılanına düşer.
    @Test func appSettingsDecodesEmptyObjectAsDefaults() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: json("{}"))
        #expect(decoded == AppSettings())
    }

    /// Yeni sürümde yazılmış blob eski sürümde okunabilmeli: bilinmeyen alanlar yok sayılır.
    @Test func appSettingsIgnoresUnknownFieldsFromNewerVersions() throws {
        let future = json(#"{"themeID":"nord","fontSize":17,"telemetryOptIn":true,"futureSection":{"a":[1,2]}}"#)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: future)
        #expect(decoded.themeID == "nord")
        #expect(decoded.fontSize == 17)
        #expect(decoded.scrollbackLines == AppSettings().scrollbackLines)
    }

    // MARK: - TerminalProfile

    /// Eski blob (`environment` alanı henüz yokken yazılmış) çözülmeli ve
    /// DİĞER ALANLAR KORUNMALI.
    @Test func terminalProfileDecodesLegacyBlobWithoutEnvironment() throws {
        let legacy = json(#"{"id":"\#(Self.idA)","name":"Work","shellPath":"/bin/zsh","fontSize":14}"#)
        let decoded = try JSONDecoder().decode(TerminalProfile.self, from: legacy)
        #expect(decoded.id == UUID(uuidString: Self.idA))
        #expect(decoded.name == "Work")
        #expect(decoded.shellPath == "/bin/zsh")
        #expect(decoded.fontSize == 14)
        #expect(decoded.environment.isEmpty)
        #expect(decoded.themeID == nil)
    }

    @Test func terminalProfileIgnoresUnknownFieldsFromNewerVersions() throws {
        let future = json(#"{"id":"\#(Self.idA)","name":"Work","badgeColor":"red","sshTarget":{"host":"h"}}"#)
        let decoded = try JSONDecoder().decode(TerminalProfile.self, from: future)
        #expect(decoded.name == "Work")
    }

    /// `id` uydurulmaz: taze bir UUID, `Workspace.profileID` bağlarını sessizce koparır.
    @Test func terminalProfileWithoutIdentifierIsRejected() {
        let broken = json(#"{"name":"Work"}"#)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(TerminalProfile.self, from: broken)
        }
    }

    /// `name` uydurulmaz: kullanıcıya var olmayan bir ad göstermek yanlış bilgi olur.
    @Test func terminalProfileWithoutNameIsRejected() {
        let broken = json(#"{"id":"\#(Self.idA)"}"#)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(TerminalProfile.self, from: broken)
        }
    }

    // MARK: - Workspace ve iç içe tipler

    @Test func workspaceDecodesLegacyBlobWithOnlyRequiredFields() throws {
        let legacy = json(#"{"id":"\#(Self.idA)","name":"Pinro","directory":"/p"}"#)
        let decoded = try JSONDecoder().decode(Workspace.self, from: legacy)
        #expect(decoded.name == "Pinro")
        #expect(decoded.directory == "/p")
        #expect(decoded.tabs.isEmpty)
        #expect(decoded.environment.isEmpty)
        #expect(decoded.trustsStartupCommands == false)
        #expect(decoded.lastOpenedAt == nil)
    }

    @Test func workspaceIgnoresUnknownFieldsFromNewerVersions() throws {
        let future = json(#"{"id":"\#(Self.idA)","name":"Pinro","directory":"/p","icon":"folder","pinnedAt":12}"#)
        let decoded = try JSONDecoder().decode(Workspace.self, from: future)
        #expect(decoded.name == "Pinro")
    }

    @Test func workspaceWithoutRequiredFieldsIsRejected() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Workspace.self, from: json(#"{"name":"Pinro","directory":"/p"}"#))
        }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Workspace.self, from: json(#"{"id":"\#(Self.idA)","directory":"/p"}"#))
        }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Workspace.self, from: json(#"{"id":"\#(Self.idA)","name":"Pinro"}"#))
        }
    }

    @Test func workspacePaneDecodesWithoutOptionalFields() throws {
        let legacy = json(#"{"id":"\#(Self.idA)"}"#)
        let decoded = try JSONDecoder().decode(WorkspacePane.self, from: legacy)
        #expect(decoded.startupDirectory == nil)
        #expect(decoded.startupCommand == nil)
    }

    @Test func workspaceTabDecodesWithoutTitle() throws {
        let legacy = json(#"{"id":"\#(Self.idA)","layout":{"pane":{"_0":{"id":"\#(Self.idB)","startupCommand":"npm run dev"}}}}"#)
        let decoded = try JSONDecoder().decode(WorkspaceTab.self, from: legacy)
        #expect(decoded.title == nil)
        #expect(decoded.layout.panes.first?.startupCommand == "npm run dev")
    }

    /// Kalıcılık sözleşmesi: sekme düzeninin JSON şekli değişirse diskteki bütün
    /// workspace'ler okunamaz hâle gelir. Şekil burada kilitlenir.
    @Test func workspaceLayoutWireFormatIsStable() throws {
        let layout = WorkspaceLayout.split(
            axis: .vertical,
            ratio: 0.35,
            first: .pane(WorkspacePane(id: UUID(uuidString: Self.idA)!, startupCommand: "a")),
            second: .pane(WorkspacePane(id: UUID(uuidString: Self.idB)!)))
        let encoded = try JSONEncoder().encode(layout)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let split = try #require(object["split"] as? [String: Any])
        #expect(split["axis"] as? String == "vertical")
        #expect(split["ratio"] as? Double == 0.35)
        let first = try #require(split["first"] as? [String: Any])
        let pane = try #require(first["pane"] as? [String: Any])
        let payload = try #require(pane["_0"] as? [String: Any])
        #expect(payload["startupCommand"] as? String == "a")
        #expect(try JSONDecoder().decode(WorkspaceLayout.self, from: encoded) == layout)
    }

    /// Bilinmeyen düzen case'i (gelecekte eklenen üçlü bölme gibi) YAKLAŞTIRILMAZ:
    /// panelleri uydurmak kullanıcının başlangıç komutlarını sessizce düşürürdü.
    /// Çözüm başarısız olur, kaydı çağıran taraf atlar.
    @Test func unknownLayoutCaseIsRejectedInsteadOfBeingGuessed() {
        let future = json(#"{"triple":{"axis":"vertical","ratios":[0.3,0.3,0.4]}}"#)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(WorkspaceLayout.self, from: future)
        }
    }

    /// Bölme geometrisi (eksen/oran) veri değil sunum: eksikse varsayılana düşer,
    /// paneller KORUNUR.
    @Test func splitLayoutFallsBackToDefaultGeometryWhenMissing() throws {
        let legacy = json(#"{"split":{"first":{"pane":{"_0":{"id":"\#(Self.idA)"}}},"second":{"pane":{"_0":{"id":"\#(Self.idB)"}}}}}"#)
        let decoded = try JSONDecoder().decode(WorkspaceLayout.self, from: legacy)
        #expect(decoded.panes.count == 2)
        guard case let .split(axis, ratio, _, _) = decoded else {
            Issue.record("Expected a split layout")
            return
        }
        #expect(axis == .vertical)
        #expect(ratio == 0.5)
    }

    /// Tek bozuk sekme workspace'i düşürmez: çözülebilen sekmeler korunur.
    @Test func workspaceKeepsDecodableTabsAndSkipsBrokenOne() throws {
        let good1 = #"{"id":"\#(Self.idA)","title":"A","layout":{"pane":{"_0":{"id":"\#(Self.idA)"}}}}"#
        let broken = #"{"title":"B","layout":{"pane":{"_0":{"id":"\#(Self.idB)"}}}}"#
        let good2 = #"{"id":"\#(Self.idC)","title":"C","layout":{"pane":{"_0":{"id":"\#(Self.idC)"}}}}"#
        let blob = json(#"{"id":"\#(Self.idA)","name":"Pinro","directory":"/p","tabs":[\#(good1),\#(broken),\#(good2)]}"#)

        let decoded = try JSONDecoder().decode(Workspace.self, from: blob)
        #expect(decoded.tabs.map(\.title) == ["A", "C"])
        #expect(decoded.name == "Pinro")
    }

    /// Bilinmeyen düzen case'i yalnız o sekmeyi düşürür, workspace'i değil.
    @Test func workspaceSurvivesTabWithUnknownLayoutCase() throws {
        let futureTab = #"{"id":"\#(Self.idB)","title":"Future","layout":{"triple":{}}}"#
        let goodTab = #"{"id":"\#(Self.idC)","title":"C","layout":{"pane":{"_0":{"id":"\#(Self.idC)"}}}}"#
        let blob = json(#"{"id":"\#(Self.idA)","name":"Pinro","directory":"/p","tabs":[\#(futureTab),\#(goodTab)]}"#)

        let decoded = try JSONDecoder().decode(Workspace.self, from: blob)
        #expect(decoded.tabs.map(\.title) == ["C"])
    }

    // MARK: - ProfileStore: kısmi bozulma

    @Test func profileStoreKeepsDecodableProfilesWhenOneIsBroken() throws {
        let (defaults, suiteName) = Self.makeDefaults("ProfileStorePartial")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let blob = json("""
        [{"id":"\(Self.idA)","name":"Work"},
         {"name":"Broken"},
         {"id":"\(Self.idC)","name":"Deploy"}]
        """)
        defaults.set(blob, forKey: ProfileStore.storageKey)

        let store = ProfileStore(defaults: defaults)
        #expect(store.profiles.map(\.name) == ["Work", "Deploy"])
        // Kısmi bozulma "bozuk blob" değildir: yedekle-ve-sıfırla yolu tetiklenmez.
        #expect(defaults.data(forKey: ProfileStore.storageKey) == blob)
        #expect(defaults.data(forKey: ProfileStore.backupKey) == nil)
    }

    /// Eski profiller (yeni alan yok) tam listeyle korunmalı.
    @Test func profileStoreLoadsLegacyProfilesWithoutNewFields() throws {
        let (defaults, suiteName) = Self.makeDefaults("ProfileStoreLegacy")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(json(#"[{"id":"\#(Self.idA)","name":"Work"}]"#), forKey: ProfileStore.storageKey)
        let store = ProfileStore(defaults: defaults)
        #expect(store.profiles.count == 1)
        #expect(store.profiles.first?.environment.isEmpty == true)
    }

    /// Regresyon: sözdizimi geçersizse mevcut yedekle-ve-varsayılana-dön yolu aynen kalır.
    @Test func profileStoreStillBacksUpSyntacticallyInvalidBlob() {
        let (defaults, suiteName) = Self.makeDefaults("ProfileStoreGarbage")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let garbage = json("[{broken")
        defaults.set(garbage, forKey: ProfileStore.storageKey)

        let store = ProfileStore(defaults: defaults)
        #expect(store.profiles.isEmpty)
        #expect(defaults.data(forKey: ProfileStore.backupKey) == garbage)
        #expect(defaults.data(forKey: ProfileStore.storageKey) == nil)
    }

    /// Geçerli JSON ama dizi değil → yine bozuk sayılır (yedekle + sıfırla).
    @Test func profileStoreBacksUpValidJsonThatIsNotAnArray() {
        let (defaults, suiteName) = Self.makeDefaults("ProfileStoreNotArray")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let object = json(#"{"profiles":[]}"#)
        defaults.set(object, forKey: ProfileStore.storageKey)

        let store = ProfileStore(defaults: defaults)
        #expect(store.profiles.isEmpty)
        #expect(defaults.data(forKey: ProfileStore.backupKey) == object)
        #expect(defaults.data(forKey: ProfileStore.storageKey) == nil)
    }

    // MARK: - WorkspaceStore: kısmi bozulma

    @Test func workspaceStoreKeepsDecodableWorkspacesWhenMiddleOneIsBroken() throws {
        let (defaults, suiteName) = Self.makeDefaults("WorkspaceStorePartial")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let blob = json("""
        [{"id":"\(Self.idA)","name":"Pinro","directory":"/a"},
         {"id":"\(Self.idB)","directory":"/b"},
         {"id":"\(Self.idC)","name":"Termora","directory":"/c"}]
        """)
        defaults.set(blob, forKey: WorkspaceStore.storageKey)

        let store = WorkspaceStore(defaults: defaults)
        #expect(store.workspaces.map(\.name) == ["Pinro", "Termora"])
        #expect(defaults.data(forKey: WorkspaceStore.backupKey) == nil)
    }

    /// Çözülebilen workspace'ler bir sonraki yazmadan sonra da kalıcı olmalı.
    @Test func workspaceStoreStaysUsableAfterSkippingBrokenRecord() throws {
        let (defaults, suiteName) = Self.makeDefaults("WorkspaceStoreUsable")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let blob = json("""
        [{"id":"\(Self.idA)","name":"Pinro","directory":"/a"},
         {"id":"\(Self.idB)","directory":"/b"}]
        """)
        defaults.set(blob, forKey: WorkspaceStore.storageKey)

        let store = WorkspaceStore(defaults: defaults)
        let fresh = Workspace(name: "Fresh", directory: "/f")
        store.upsert(fresh)

        let reloaded = WorkspaceStore(defaults: defaults)
        #expect(reloaded.workspaces.map(\.name) == ["Pinro", "Fresh"])
    }

    /// Regresyon: tamamen çöp JSON → yedekle + sıfırla.
    @Test func workspaceStoreStillBacksUpSyntacticallyInvalidBlob() {
        let (defaults, suiteName) = Self.makeDefaults("WorkspaceStoreGarbage")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let garbage = json("not json at all")
        defaults.set(garbage, forKey: WorkspaceStore.storageKey)

        let store = WorkspaceStore(defaults: defaults)
        #expect(store.workspaces.isEmpty)
        #expect(defaults.data(forKey: WorkspaceStore.backupKey) == garbage)
        #expect(defaults.data(forKey: WorkspaceStore.storageKey) == nil)
    }

    // MARK: - SettingsStore

    /// Eski ayar blob'u (yeni alan yok) sıfırlanmamalı: varsayılana düşen alan dışında
    /// her şey korunur ve yedekleme yolu TETİKLENMEZ.
    @Test func settingsStoreLoadsLegacyBlobWithoutResetting() throws {
        let (defaults, suiteName) = Self.makeDefaults("SettingsStoreLegacy")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacy = json(#"{"fontSize":15,"themeID":"nord"}"#)
        defaults.set(legacy, forKey: SettingsStore.storageKey)

        let store = SettingsStore(defaults: defaults)
        #expect(store.settings.themeID == "nord")
        #expect(store.settings.fontSize == 15)
        #expect(store.settings.hasCompletedOnboarding == false)
        #expect(defaults.data(forKey: SettingsStore.backupKey) == nil)
    }

    private static func makeDefaults(_ label: String) -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "\(label)-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}
