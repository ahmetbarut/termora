import AppKit
import Foundation
import Testing
@testable import Termora

/// briefs/3 "Komut Paleti Tasarımı → Sonuç kategorileri: SSH".
/// Kayıtlı profiller ve `~/.ssh/config` hostları palette listelenir; Enter onları
/// YENİ BİR SEKMEDE `/usr/bin/ssh` ile açar.
@MainActor
@Suite("Komut paletinde SSH kategorisi")
struct SSHPaletteCommandsTests {

    private struct Subject {
        let viewModel: WorkspaceViewModel
        let ssh: SSHHostStore
        let sessions: MockSessionManager
        let settings: SettingsStore
        let themes: ThemeStore
    }

    private static let launchMoment = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeSubject(hosts: [SSHHost] = [],
                             configHosts: [SSHConfigHost] = []) throws -> Subject {
        let suiteName = "SSHPalette.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let ssh = SSHHostStore(defaults: defaults, configLoader: { configHosts })
        ssh.hosts = hosts
        if !configHosts.isEmpty { ssh.reloadConfigHosts() }

        let sessions = MockSessionManager()
        let settings = SettingsStore(defaults: defaults)
        let viewModel = WorkspaceViewModel(sessionManager: sessions,
                                           settings: settings,
                                           profiles: ProfileStore(defaults: defaults))
        viewModel.newTab()
        return Subject(viewModel: viewModel,
                       ssh: ssh,
                       sessions: sessions,
                       settings: settings,
                       themes: ThemeStore(bundle: .main))
    }

    private func items(_ subject: Subject, ssh: SSHHostStore?) -> [CommandPaletteItem] {
        CommandPaletteCatalog.items(workspace: subject.viewModel,
                                    settings: subject.settings,
                                    themes: subject.themes,
                                    ssh: ssh,
                                    now: { Self.launchMoment },
                                    openSettings: {})
    }

    private func sshItems(_ subject: Subject) -> [CommandPaletteItem] {
        items(subject, ssh: subject.ssh).filter { $0.category == .ssh }
    }

    private func host(_ name: String, hostName: String = "pinro.app") -> SSHHost {
        SSHHost(name: name, hostName: hostName, user: "deploy")
    }

    // MARK: - Listeleme

    /// Depo bağlı değilse (SSH'ı hiç kullanmayan bağlamlar) kategori hiç çizilmez.
    @Test func withoutAStoreThereIsNoSSHCategory() throws {
        let subject = try makeSubject(hosts: [host("Pinro")])
        #expect(items(subject, ssh: nil).contains { $0.category == .ssh } == false)
    }

    /// Boş kategori çizilmez: kayıt da config hostu da yokken "SSH" başlığı görünmemeli.
    @Test func noTargetsMeansNoSSHCategory() throws {
        let subject = try makeSubject()
        #expect(sshItems(subject).isEmpty)
    }

    @Test func listsSavedProfilesAndConfigHosts() throws {
        let subject = try makeSubject(hosts: [host("Pinro Production")],
                                      configHosts: [SSHConfigHost(alias: "bastion")])

        #expect(sshItems(subject).map(\.title) == ["Pinro Production", "bastion"])
    }

    @Test func everySSHCommandHasAUniqueIdentifierAndAResolvableSymbol() throws {
        let subject = try makeSubject(hosts: [host("Pinro"), host("Staging")],
                                      configHosts: [SSHConfigHost(alias: "bastion")])
        let all = items(subject, ssh: subject.ssh)

        #expect(Set(all.map(\.id)).count == all.count)
        for item in sshItems(subject) {
            #expect(NSImage(systemSymbolName: item.symbolName, accessibilityDescription: nil) != nil)
        }
    }

    /// briefs/3 kategori sırası: Actions → Workspaces → SSH → Settings.
    @Test func sshIsListedAfterWorkspacesAndBeforeSettings() throws {
        let subject = try makeSubject(hosts: [host("Pinro")])
        let categories = items(subject, ssh: subject.ssh).map(\.category)
        let firstSSH = try #require(categories.firstIndex(of: .ssh))
        let firstSettings = try #require(categories.firstIndex(of: .settings))

        #expect(firstSSH < firstSettings)
        #expect(CommandPaletteCategory.ssh.listOrder == 2)
        #expect(CommandPaletteCategory.ssh.title == "SSH")
    }

    // MARK: - Enter ile bağlanma

    @Test func runningTheCommandOpensANewTabRunningSSH() throws {
        let subject = try makeSubject(hosts: [host("Pinro")])
        let tabsBefore = subject.viewModel.tabs.count

        try #require(sshItems(subject).first).action()

        #expect(subject.viewModel.tabs.count == tabsBefore + 1)
        #expect(subject.sessions.createdStartupCommands.last == "/usr/bin/ssh -- deploy@pinro.app")
    }

    /// Açık sekmeler kapanmaz: bağlanmak pencereyi sıfırlayan bir işlem DEĞİLDİR.
    @Test func connectingLeavesTheOpenTabsAlone() throws {
        let subject = try makeSubject(hosts: [host("Pinro")])

        try #require(sshItems(subject).first).action()

        #expect(subject.sessions.terminatedSessionIDs.isEmpty)
    }

    @Test func theNewTabIsNamedAfterTheTarget() throws {
        let subject = try makeSubject(hosts: [host("Pinro Production")])

        try #require(sshItems(subject).first).action()

        #expect(subject.viewModel.activeTab?.displayTitle == "Pinro Production")
    }

    @Test func connectingStampsTheLastConnectionTimeOnTheSavedProfile() throws {
        let subject = try makeSubject(hosts: [host("Pinro")])

        try #require(sshItems(subject).first).action()

        #expect(subject.ssh.hosts.first?.lastConnectedAt == Self.launchMoment)
    }

    /// Config hostuna bağlanmak kullanıcının dosyasına HİÇBİR ŞEY yazmaz.
    @Test func connectingToAConfigHostRunsTheAliasAlone() throws {
        let subject = try makeSubject(configHosts: [SSHConfigHost(alias: "bastion",
                                                                 hostName: "bastion.example.com",
                                                                 user: "jump")])

        try #require(sshItems(subject).first).action()

        #expect(subject.sessions.createdStartupCommands.last == "/usr/bin/ssh -- bastion")
        #expect(subject.ssh.hosts.isEmpty)
    }

    /// Kullanıcı alanına yazılmış kabuk metni komutu BÖLEMEZ.
    @Test func aHostileHostNameStaysInsideOneQuotedArgument() throws {
        let subject = try makeSubject(hosts: [host("Evil", hostName: "pinro.app; rm -rf ~")])

        try #require(sshItems(subject).first).action()

        #expect(subject.sessions.createdStartupCommands.last
                == "/usr/bin/ssh -- 'deploy@pinro.app; rm -rf ~'")
    }
}
