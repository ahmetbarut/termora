import Foundation
import Testing
@testable import Termora

@Suite("SSHConfigParser")
struct SSHConfigParserTests {

    private func host(_ alias: String, in hosts: [SSHConfigHost]) throws -> SSHConfigHost {
        try #require(hosts.first { $0.alias == alias }, "\(alias) ayrıştırılan listede yok")
    }

    // MARK: - Temel ayrıştırma

    @Test func readsEveryFieldOfAHostBlock() throws {
        let contents = """
        Host pinro
            HostName pinro.app
            User deploy
            Port 2222
            IdentityFile ~/.ssh/pinro_ed25519
            ProxyJump bastion
        """

        let parsed = try host("pinro", in: SSHConfigParser.parse(contents).hosts)

        #expect(parsed.hostName == "pinro.app")
        #expect(parsed.user == "deploy")
        #expect(parsed.port == 2222)
        #expect(parsed.identityFile == "~/.ssh/pinro_ed25519")
        #expect(parsed.proxyJump == "bastion")
    }

    @Test func ignoresCommentsBlankLinesAndIndentation() throws {
        let contents = """
        # kişisel sunucular
        \t
              Host   pinro

        \t\tHostName   pinro.app
        # User root
              User deploy

        """

        let hosts = SSHConfigParser.parse(contents).hosts
        let parsed = try host("pinro", in: hosts)

        #expect(hosts.count == 1)
        #expect(parsed.hostName == "pinro.app")
        #expect(parsed.user == "deploy")
    }

    @Test func acceptsTheEqualsSeparatorAndIsCaseInsensitiveAboutKeys() throws {
        let contents = """
        HOST=pinro
        hostname=pinro.app
        PoRt = 2222
        """

        let parsed = try host("pinro", in: SSHConfigParser.parse(contents).hosts)

        #expect(parsed.hostName == "pinro.app")
        #expect(parsed.port == 2222)
    }

    @Test func stripsSurroundingQuotesFromValues() throws {
        let contents = """
        Host "pinro"
            HostName "pinro.app"
            IdentityFile "~/.ssh/my key"
        """

        let parsed = try host("pinro", in: SSHConfigParser.parse(contents).hosts)

        #expect(parsed.hostName == "pinro.app")
        #expect(parsed.identityFile == "~/.ssh/my key")
    }

    @Test func missingFieldsStayNil() throws {
        let parsed = try host("pinro", in: SSHConfigParser.parse("Host pinro").hosts)

        #expect(parsed.hostName == nil)
        #expect(parsed.user == nil)
        #expect(parsed.port == nil)
        #expect(parsed.identityFile == nil)
        #expect(parsed.proxyJump == nil)
    }

    @Test func unparsablePortIsDroppedInsteadOfGuessed() throws {
        let parsed = try host("pinro", in: SSHConfigParser.parse("Host pinro\n  Port abc").hosts)
        #expect(parsed.port == nil)
    }

    @Test func emptyContentsProduceNoHosts() {
        #expect(SSHConfigParser.parse("").hosts.isEmpty)
        #expect(SSHConfigParser.parse("\n\n# yalnız yorum\n").hosts.isEmpty)
    }

    // MARK: - Joker desenler

    /// `Host *` bağlanılabilir bir hedef DEĞİLDİR; listede görünmemeli.
    @Test func wildcardPatternsAreNotConnectableTargets() {
        let contents = """
        Host *
            ServerAliveInterval 60

        Host *.example.com
            User deploy

        Host web?
            User deploy

        Host !prod
            User deploy
        """

        #expect(SSHConfigParser.parse(contents).hosts.isEmpty)
    }

    @Test func keepsTheConcreteAliasesOfAMixedHostLine() {
        let contents = """
        Host web1 web* web2
            User deploy
        """

        let hosts = SSHConfigParser.parse(contents).hosts

        #expect(hosts.map(\.alias) == ["web1", "web2"])
        #expect(hosts.allSatisfy { $0.user == "deploy" })
    }

    /// Joker blok listelenmez ve ayarları da somut hostlara YAZILMAZ: bağlanırken
    /// `/usr/bin/ssh` config'i kendisi okur, bizim çıkarımımız yalnız gösterim içindir.
    @Test func wildcardBlockSettingsDoNotLeakIntoConcreteHosts() throws {
        let contents = """
        Host *
            User root

        Host pinro
            HostName pinro.app
        """

        let parsed = try host("pinro", in: SSHConfigParser.parse(contents).hosts)
        #expect(parsed.user == nil)
    }

    // MARK: - Blok sınırları

    @Test func matchBlockSettingsAreNotAttributedToThePreviousHost() throws {
        let contents = """
        Host pinro
            HostName pinro.app

        Match host bastion
            User jump
        """

        let hosts = SSHConfigParser.parse(contents).hosts
        let parsed = try host("pinro", in: hosts)

        #expect(hosts.count == 1)
        #expect(parsed.user == nil)
    }

    @Test func keysBeforeTheFirstHostAreIgnored() {
        let contents = """
        User global
        Host pinro
        """

        #expect(SSHConfigParser.parse(contents).hosts.count == 1)
    }

    /// ssh'ta İLK değer kazanır.
    @Test func theFirstValueOfARepeatedKeyWins() throws {
        let contents = """
        Host pinro
            HostName first.example.com
            HostName second.example.com
        """

        let parsed = try host("pinro", in: SSHConfigParser.parse(contents).hosts)
        #expect(parsed.hostName == "first.example.com")
    }

    @Test func aRepeatedAliasIsListedOnce() {
        let contents = """
        Host pinro
            HostName first.example.com

        Host pinro
            HostName second.example.com
        """

        let hosts = SSHConfigParser.hosts(configContents: contents, includeReader: { _ in [] })

        #expect(hosts.count == 1)
        #expect(hosts.first?.hostName == "first.example.com")
    }

    // MARK: - Include

    @Test func includePatternsAreReported() {
        let contents = """
        Include work/*.conf
        Host pinro
        """

        #expect(SSHConfigParser.parse(contents).includePatterns == ["work/*.conf"])
    }

    @Test func includedFilesContributeHostsInPlace() throws {
        let root = """
        Host first
        Include extra
        Host last
        """

        let hosts = SSHConfigParser.hosts(configContents: root) { pattern in
            pattern == "extra" ? ["Host middle\n  HostName middle.example.com"] : []
        }

        #expect(hosts.map(\.alias) == ["first", "middle", "last"])
        #expect(try host("middle", in: hosts).hostName == "middle.example.com")
    }

    @Test func includeRecursionIsBounded() {
        // Kendini içeren bir config uygulamayı DONDURMAMALI.
        let hosts = SSHConfigParser.hosts(configContents: "Include loop\nHost pinro") { _ in
            ["Include loop\nHost inner"]
        }

        #expect(hosts.contains { $0.alias == "pinro" })
        #expect(hosts.count < 32)
    }

    @Test func missingConfigFileYieldsAnEmptyListInsteadOfCrashing() {
        #expect(SSHConfigParser.hosts(configContents: nil, includeReader: { _ in [] }).isEmpty)
    }

    @Test func loadingAMissingUserConfigIsSafe() {
        let directory = NSTemporaryDirectory() + "termora-ssh-missing-\(UUID().uuidString)"
        #expect(SSHConfigParser.loadUserConfig(sshDirectory: directory).isEmpty)
    }

    @Test func loadingReadsTheConfigFileAndItsIncludes() throws {
        let directory = NSTemporaryDirectory() + "termora-ssh-\(UUID().uuidString)"
        let fileManager = FileManager.default
        try fileManager.createDirectory(atPath: directory + "/work", withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(atPath: directory) }

        try "Include work/*.conf\nHost pinro\n  HostName pinro.app\n"
            .write(toFile: directory + "/config", atomically: true, encoding: .utf8)
        try "Host jump\n  HostName bastion.example.com\n"
            .write(toFile: directory + "/work/jump.conf", atomically: true, encoding: .utf8)

        let hosts = SSHConfigParser.loadUserConfig(sshDirectory: directory)

        #expect(hosts.map(\.alias).sorted() == ["jump", "pinro"])
        #expect(try host("jump", in: hosts).hostName == "bastion.example.com")
    }
}
