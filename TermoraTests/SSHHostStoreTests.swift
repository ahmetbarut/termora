import Foundation
import Testing
@testable import Termora

@Suite("SSHHostStore")
@MainActor
struct SSHHostStoreTests {

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "termora.ssh.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeHost(name: String = "Pinro", hostName: String = "pinro.app") -> SSHHost {
        SSHHost(name: name, hostName: hostName)
    }

    // MARK: - Kalıcılık

    @Test func savedHostsSurviveARestart() throws {
        let defaults = try makeDefaults()
        let store = SSHHostStore(defaults: defaults, configLoader: { [] })

        store.upsert(SSHHost(name: "Pinro",
                             hostName: "pinro.app",
                             port: 2222,
                             user: "deploy",
                             authenticationMethod: .privateKey,
                             identityFile: "~/.ssh/pinro_ed25519",
                             tags: ["prod"],
                             colorHex: "#169CFF",
                             proxyJump: "bastion"))

        let reopened = SSHHostStore(defaults: defaults, configLoader: { [] })
        let restored = try #require(reopened.hosts.first)

        #expect(reopened.hosts.count == 1)
        #expect(restored.name == "Pinro")
        #expect(restored.port == 2222)
        #expect(restored.user == "deploy")
        #expect(restored.authenticationMethod == .privateKey)
        #expect(restored.identityFile == "~/.ssh/pinro_ed25519")
        #expect(restored.tags == ["prod"])
        #expect(restored.colorHex == "#169CFF")
        #expect(restored.proxyJump == "bastion")
    }

    @Test func upsertUpdatesInPlaceAndKeepsTheOrder() throws {
        let defaults = try makeDefaults()
        let store = SSHHostStore(defaults: defaults, configLoader: { [] })
        let first = makeHost(name: "First", hostName: "first.example.com")
        let second = makeHost(name: "Second", hostName: "second.example.com")
        store.upsert(first)
        store.upsert(second)

        var edited = first
        edited.name = "Renamed"
        store.upsert(edited)

        #expect(store.hosts.map(\.name) == ["Renamed", "Second"])
    }

    @Test func removeDropsOnlyTheRequestedHost() throws {
        let defaults = try makeDefaults()
        let store = SSHHostStore(defaults: defaults, configLoader: { [] })
        let first = makeHost(name: "First")
        let second = makeHost(name: "Second")
        store.upsert(first)
        store.upsert(second)

        store.remove(id: first.id)

        #expect(store.hosts.map(\.name) == ["Second"])
    }

    @Test func markConnectedStampsTheGivenDate() throws {
        let defaults = try makeDefaults()
        let store = SSHHostStore(defaults: defaults, configLoader: { [] })
        let host = makeHost()
        store.upsert(host)
        let moment = Date(timeIntervalSince1970: 1_700_000_000)

        store.markConnected(id: host.id, at: moment)

        #expect(store.hosts.first?.lastConnectedAt == moment)
    }

    /// Config hostları kullanıcının DOSYASINDAN gelir; Termora o dosyaya yazmaz, bu
    /// yüzden onlar için damga da tutulmaz.
    @Test func recordingALaunchOnlyTouchesSavedProfiles() throws {
        let defaults = try makeDefaults()
        let store = SSHHostStore(defaults: defaults,
                                 configLoader: { [SSHConfigHost(alias: "pinro")] })
        let host = makeHost()
        store.upsert(host)
        store.reloadConfigHosts()
        let moment = Date(timeIntervalSince1970: 1_700_000_000)

        store.recordLaunch(of: .configHost(SSHConfigHost(alias: "pinro")), at: moment)
        #expect(store.hosts.first?.lastConnectedAt == nil)

        store.recordLaunch(of: .profile(host), at: moment)
        #expect(store.hosts.first?.lastConnectedAt == moment)
    }

    // MARK: - Bozuk veri

    @Test func aCorruptBlobIsBackedUpInsteadOfLosingTheKey() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("bu JSON değil".utf8), forKey: SSHHostStore.storageKey)

        let store = SSHHostStore(defaults: defaults, configLoader: { [] })

        #expect(store.hosts.isEmpty)
        #expect(defaults.data(forKey: SSHHostStore.backupKey) != nil)
        #expect(defaults.data(forKey: SSHHostStore.storageKey) == nil)
    }

    @Test func oneUndecodableRecordDoesNotDeleteTheOthers() throws {
        let defaults = try makeDefaults()
        let json = """
        [
          {"id":"\(UUID().uuidString)","name":"Good","hostName":"good.example.com"},
          {"name":"Missing id","hostName":"bad.example.com"},
          {"id":"\(UUID().uuidString)","name":"Also good","hostName":"other.example.com"}
        ]
        """
        defaults.set(Data(json.utf8), forKey: SSHHostStore.storageKey)

        let store = SSHHostStore(defaults: defaults, configLoader: { [] })

        #expect(store.hosts.map(\.name) == ["Good", "Also good"])
        // Blob'a dokunulmaz: atlanan kaydın ham verisi diskte kalır.
        #expect(defaults.data(forKey: SSHHostStore.backupKey) == nil)
    }

    /// İleri uyumluluk: yeni bir sürümün yazdığı bilinmeyen alanlar kaydı DÜŞÜRMEZ,
    /// eksik isteğe bağlı alanlar da varsayılana düşer.
    @Test func decodingToleratesUnknownAndMissingFields() throws {
        let defaults = try makeDefaults()
        let json = """
        [{"id":"\(UUID().uuidString)","name":"Pinro","hostName":"pinro.app",
          "someFutureField":{"nested":true},"authenticationMethod":"quantum"}]
        """
        defaults.set(Data(json.utf8), forKey: SSHHostStore.storageKey)

        let store = SSHHostStore(defaults: defaults, configLoader: { [] })
        let host = try #require(store.hosts.first)

        #expect(host.name == "Pinro")
        // Bilinmeyen yöntem varsayılana düşer, kayıt kaybolmaz.
        #expect(host.authenticationMethod == .automatic)
        #expect(host.tags.isEmpty)
        #expect(host.lastConnectedAt == nil)
    }

    /// briefs/2: private key İÇERİĞİ uygulama veritabanına kopyalanmamalı.
    @Test func onlyTheKeyPathIsWrittenToDisk() throws {
        let defaults = try makeDefaults()
        let store = SSHHostStore(defaults: defaults, configLoader: { [] })
        store.upsert(SSHHost(name: "Pinro",
                             hostName: "pinro.app",
                             authenticationMethod: .privateKey,
                             identityFile: "~/.ssh/pinro_ed25519"))

        let data = try #require(defaults.data(forKey: SSHHostStore.storageKey))
        let records = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let record = try #require(records.first)

        #expect(record["identityFile"] as? String == "~/.ssh/pinro_ed25519")
        // Diskteki kayıt yalnız bu alanları tanır: anahtar içeriği ya da parola için
        // kutu YOK.
        let allowedKeys: Set<String> = ["id", "name", "hostName", "port", "user",
                                        "authenticationMethod", "identityFile",
                                        "startupDirectory", "startupCommand", "tags",
                                        "colorHex", "proxyJump", "lastConnectedAt"]
        #expect(Set(record.keys).isSubset(of: allowedKeys))
    }

    // MARK: - Config hostları

    @Test func configHostsAreNotReadUntilAsked() throws {
        let defaults = try makeDefaults()
        let counter = LoadCounter()
        let store = SSHHostStore(defaults: defaults, configLoader: {
            counter.value += 1
            return [SSHConfigHost(alias: "pinro")]
        })

        #expect(counter.value == 0)
        #expect(store.configHosts.isEmpty)

        store.ensureConfigHostsLoaded()
        store.ensureConfigHostsLoaded()

        #expect(counter.value == 1)
        #expect(store.configHosts.map(\.alias) == ["pinro"])
    }

    @Test func targetsListSavedProfilesBeforeConfigHosts() throws {
        let defaults = try makeDefaults()
        let store = SSHHostStore(defaults: defaults,
                                 configLoader: { [SSHConfigHost(alias: "from-config")] })
        store.upsert(makeHost(name: "Saved"))
        store.reloadConfigHosts()

        #expect(store.targets.map(\.displayName) == ["Saved", "from-config"])
    }

    @MainActor
    private final class LoadCounter {
        var value = 0
    }
}
