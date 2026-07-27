import Testing
@testable import Termora

@Suite("ShellService")
struct ShellServiceTests {

    // MARK: availableShells saf cekirdek

    @Test("/etc/shells parse: yorum ve bos satirlar atlanir, bosluk kirpilir")
    func parsesEtcShells() {
        let fixture = """
        # List of acceptable shells for chpass(1).
        # Ftpd will not allow users to connect who are not using
        /bin/bash

          /bin/zsh
        /bin/csh
        """
        let shells = ShellService.availableShells(
            etcShellsContents: fixture,
            homebrewCandidates: [],
            isExecutable: { _ in true }
        )
        #expect(shells.map(\.path) == ["/bin/bash", "/bin/zsh", "/bin/csh"])
    }

    @Test("homebrew adaylari listeye eklenir, isExecutable suzer")
    func homebrewCandidatesAndFilter() {
        let fixture = """
        /bin/bash
        /bin/csh
        /bin/zsh
        """
        let shells = ShellService.availableShells(
            etcShellsContents: fixture,
            homebrewCandidates: ["/opt/homebrew/bin/fish", "/usr/local/bin/fish"],
            isExecutable: { $0 != "/bin/csh" && $0 != "/usr/local/bin/fish" }
        )
        #expect(shells.map(\.path) == ["/bin/bash", "/bin/zsh", "/opt/homebrew/bin/fish"])
        #expect(shells.map(\.displayName) == ["bash", "zsh", "fish"])
    }

    @Test("tekillestirme: ayni yol iki kez gecmez")
    func deduplicates() {
        let fixture = """
        /bin/zsh
        /opt/homebrew/bin/fish
        """
        let shells = ShellService.availableShells(
            etcShellsContents: fixture,
            homebrewCandidates: ["/opt/homebrew/bin/fish"],
            isExecutable: { _ in true }
        )
        #expect(shells.map(\.path) == ["/bin/zsh", "/opt/homebrew/bin/fish"])
    }

    @Test("etcShellsContents nil -> yalniz homebrew adaylari")
    func nilEtcShells() {
        let shells = ShellService.availableShells(
            etcShellsContents: nil,
            homebrewCandidates: ["/opt/homebrew/bin/fish"],
            isExecutable: { _ in true }
        )
        #expect(shells.map(\.path) == ["/opt/homebrew/bin/fish"])
    }

    // MARK: ShellInfo

    @Test("ShellInfo.id == path")
    func shellInfoIdentity() {
        let info = ShellInfo(path: "/bin/zsh", displayName: "zsh")
        #expect(info.id == "/bin/zsh")
    }

    // MARK: loginArgv0

    @Test("loginArgv0: son bilesen basina tire")
    func loginArgv0() {
        #expect(ShellService.loginArgv0(forShellPath: "/bin/zsh") == "-zsh")
        #expect(ShellService.loginArgv0(forShellPath: "/opt/homebrew/bin/fish") == "-fish")
        #expect(ShellService.loginArgv0(forShellPath: "/bin/bash") == "-bash")
    }

    // MARK: defaultShellPath (gercek sistem smoke)

    @Test("defaultShellPath mutlak yol doner")
    func defaultShellIsAbsolute() {
        let path = ShellService.defaultShellPath()
        #expect(path.hasPrefix("/"))
        #expect(!path.isEmpty)
    }

    @Test("gercek availableShells en az bir shell bulur ve hepsi calistirilabilir yoldadir")
    func realAvailableShellsSmoke() {
        let shells = ShellService.availableShells()
        #expect(!shells.isEmpty) // macOS'ta /etc/shells her zaman vardir
        #expect(shells.allSatisfy { $0.path.hasPrefix("/") })
    }
}
