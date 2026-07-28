import Foundation
import Testing
@testable import Termora

@Suite("SSHCommand")
struct SSHCommandTests {

    private func makeHost(name: String = "Pinro",
                          hostName: String = "pinro.app",
                          port: Int? = nil,
                          user: String? = nil,
                          authenticationMethod: SSHAuthenticationMethod = .automatic,
                          identityFile: String? = nil,
                          startupDirectory: String? = nil,
                          startupCommand: String? = nil,
                          proxyJump: String? = nil) -> SSHHost {
        SSHHost(name: name,
                hostName: hostName,
                port: port,
                user: user,
                authenticationMethod: authenticationMethod,
                identityFile: identityFile,
                startupDirectory: startupDirectory,
                startupCommand: startupCommand,
                proxyJump: proxyJump)
    }

    /// Seçenek DEĞERLERİ (`-p 2222` içindeki "2222") seçenek değildir; bu yardımcı
    /// yalnız ssh'ın seçenek olarak okuyacağı öğeleri döndürür.
    private func optionElements(_ arguments: [String]) -> [String] {
        var options: [String] = []
        var index = arguments.startIndex
        var sawSeparator = false
        while index < arguments.endIndex {
            let element = arguments[index]
            if element == "--" {
                sawSeparator = true
                index = arguments.index(after: index)
                continue
            }
            if !sawSeparator, ["-p", "-i", "-J", "-o", "-F", "-l"].contains(element) {
                options.append(element)
                index = arguments.index(index, offsetBy: 2, limitedBy: arguments.endIndex) ?? arguments.endIndex
                continue
            }
            if !sawSeparator, element.hasPrefix("-") {
                options.append(element)
            }
            index = arguments.index(after: index)
        }
        return options
    }

    // MARK: - Argüman üretimi

    @Test func theSystemSSHBinaryIsUsed() {
        #expect(SSHCommand.executablePath == "/usr/bin/ssh")
        #expect(SSHCommand.arguments(for: makeHost()).first == "/usr/bin/ssh")
    }

    @Test func aBareHostNeedsNothingButItsHostName() {
        #expect(SSHCommand.arguments(for: makeHost()) == ["/usr/bin/ssh", "--", "pinro.app"])
    }

    @Test func theUserIsJoinedToTheHostName() {
        let arguments = SSHCommand.arguments(for: makeHost(user: "deploy"))
        #expect(arguments == ["/usr/bin/ssh", "--", "deploy@pinro.app"])
    }

    @Test func blankFieldsAreTreatedAsAbsent() {
        let arguments = SSHCommand.arguments(for: makeHost(user: "   ",
                                                           identityFile: "  ",
                                                           startupDirectory: " ",
                                                           startupCommand: "\n",
                                                           proxyJump: ""))
        #expect(arguments == ["/usr/bin/ssh", "--", "pinro.app"])
    }

    @Test func thePortIsPassedWithDashP() {
        let arguments = SSHCommand.arguments(for: makeHost(port: 2222))
        #expect(arguments == ["/usr/bin/ssh", "-p", "2222", "--", "pinro.app"])
    }

    @Test func anImpossiblePortIsDroppedInsteadOfSent() {
        #expect(SSHCommand.arguments(for: makeHost(port: 0)) == ["/usr/bin/ssh", "--", "pinro.app"])
        #expect(SSHCommand.arguments(for: makeHost(port: -1)) == ["/usr/bin/ssh", "--", "pinro.app"])
        #expect(SSHCommand.arguments(for: makeHost(port: 70_000)) == ["/usr/bin/ssh", "--", "pinro.app"])
    }

    @Test func thePrivateKeyPathIsPassedWithDashI() {
        let arguments = SSHCommand.arguments(for: makeHost(authenticationMethod: .privateKey,
                                                           identityFile: "~/.ssh/pinro_ed25519"))
        #expect(arguments == ["/usr/bin/ssh", "-i", "~/.ssh/pinro_ed25519", "--", "pinro.app"])
    }

    /// Anahtar yolu yalnız "Private key" yöntemi seçiliyken gönderilir; başka yöntemde
    /// sessizce anahtar dayatmak kullanıcının seçtiği yöntemi ezerdi.
    @Test func thePrivateKeyPathIsOnlySentForTheKeyMethod() {
        let arguments = SSHCommand.arguments(for: makeHost(authenticationMethod: .password,
                                                           identityFile: "~/.ssh/pinro_ed25519"))
        #expect(arguments == ["/usr/bin/ssh", "--", "pinro.app"])
    }

    @Test func proxyJumpIsPassedWithDashJ() {
        let arguments = SSHCommand.arguments(for: makeHost(proxyJump: "deploy@bastion.example.com"))
        #expect(arguments == ["/usr/bin/ssh", "-J", "deploy@bastion.example.com", "--", "pinro.app"])
    }

    @Test func everyOptionComesBeforeTheDestinationInAStableOrder() {
        let arguments = SSHCommand.arguments(for: makeHost(port: 2222,
                                                           user: "deploy",
                                                           authenticationMethod: .privateKey,
                                                           identityFile: "/keys/id_ed25519",
                                                           proxyJump: "bastion"))
        #expect(arguments == ["/usr/bin/ssh",
                              "-p", "2222",
                              "-i", "/keys/id_ed25519",
                              "-J", "bastion",
                              "--",
                              "deploy@pinro.app"])
    }

    /// `--` olmadan `-oProxyCommand=…` gibi bir "host adı" ssh tarafından SEÇENEK olarak
    /// okunurdu; ayırıcı bunu imkânsız kılar.
    @Test func aHostNameStartingWithADashCannotBecomeAnOption() {
        let arguments = SSHCommand.arguments(for: makeHost(hostName: "-oStrictHostKeyChecking=no"))
        #expect(arguments == ["/usr/bin/ssh", "--", "-oStrictHostKeyChecking=no"])
        #expect(optionElements(arguments).isEmpty)
    }

    // MARK: - Başlangıç dizini ve komutu

    @Test func aStartupDirectoryBecomesARemoteCommandWithATTY() {
        let arguments = SSHCommand.arguments(for: makeHost(startupDirectory: "/srv/app"))
        #expect(arguments == ["/usr/bin/ssh",
                              "-t",
                              "--",
                              "pinro.app",
                              "cd -- /srv/app; exec \"${SHELL:-/bin/sh}\" -l"])
    }

    @Test func aStartupCommandRunsAndThenHandsOverAnInteractiveShell() {
        let arguments = SSHCommand.arguments(for: makeHost(startupCommand: "docker compose ps"))
        #expect(arguments.last == "docker compose ps; exec \"${SHELL:-/bin/sh}\" -l")
        #expect(arguments.contains("-t"))
    }

    @Test func directoryAndCommandAreChainedInOneRemoteArgument() {
        let arguments = SSHCommand.arguments(for: makeHost(startupDirectory: "/srv/my app",
                                                           startupCommand: "npm run dev"))
        #expect(arguments.last == "cd -- '/srv/my app' && npm run dev; exec \"${SHELL:-/bin/sh}\" -l")
        #expect(arguments.filter { $0.contains("npm run dev") }.count == 1)
    }

    // MARK: - ~/.ssh/config hedefleri

    /// Config hedefinde ayrıştırdığımız değerler TEKRAR gönderilmez: bağlanırken
    /// `/usr/bin/ssh` config'i kendisi okur, bizim kopyamız ondan sapabilir.
    @Test func aConfigAliasIsPassedAloneSoSSHReadsItsOwnConfig() {
        let configHost = SSHConfigHost(alias: "pinro",
                                       hostName: "pinro.app",
                                       user: "deploy",
                                       port: 2222,
                                       identityFile: "~/.ssh/id_ed25519",
                                       proxyJump: "bastion")

        #expect(SSHCommand.arguments(for: SSHTarget.configHost(configHost))
                == ["/usr/bin/ssh", "--", "pinro"])
    }

    // MARK: - known_hosts doğrulaması

    /// briefs/2: "known_hosts doğrulamasını devre dışı bırakmamalı". Üretilen komut
    /// HİÇBİR `-o` seçeneği taşımaz, dolayısıyla doğrulamayı gevşetemez.
    @Test func generatedArgumentsNeverWeakenHostKeyChecking() {
        let hosts = [
            makeHost(),
            makeHost(port: 22, user: "root", authenticationMethod: .privateKey,
                     identityFile: "/keys/id", startupDirectory: "/srv", startupCommand: "ls",
                     proxyJump: "bastion"),
            makeHost(hostName: "10.0.0.1", user: "deploy"),
        ]
        let forbidden = ["StrictHostKeyChecking", "UserKnownHostsFile", "CheckHostIP",
                         "NoHostAuthenticationForLocalhost", "GlobalKnownHostsFile"]

        for host in hosts {
            let arguments = SSHCommand.arguments(for: host)
            #expect(!optionElements(arguments).contains("-o"))
            #expect(!optionElements(arguments).contains { $0.hasPrefix("-o") })
            for keyword in forbidden {
                #expect(!arguments.contains { $0.contains(keyword) },
                        "\(keyword) argümanlara sızdı: \(arguments)")
            }
        }
    }

    /// Kullanıcı alanına yazılmış bir seçenek metni bile seçeneğe DÖNÜŞEMEZ: değer,
    /// `-J`'nin argümanı olarak tek bir öğede kalır.
    @Test func anOptionLikeValueStaysAValueNotAnOption() {
        let arguments = SSHCommand.arguments(for: makeHost(proxyJump: "-oStrictHostKeyChecking=no"))

        #expect(arguments == ["/usr/bin/ssh", "-J", "-oStrictHostKeyChecking=no", "--", "pinro.app"])
        #expect(!optionElements(arguments).contains { $0.hasPrefix("-o") })
    }

    // MARK: - Kabuk alıntılama

    @Test func plainValuesAreLeftUnquoted() {
        #expect(SSHCommand.posixQuoted("deploy@pinro.app") == "deploy@pinro.app")
        #expect(SSHCommand.posixQuoted("/usr/bin/ssh") == "/usr/bin/ssh")
        #expect(SSHCommand.posixQuoted("-p") == "-p")
    }

    @Test func riskyValuesAreSingleQuoted() {
        #expect(SSHCommand.posixQuoted("") == "''")
        #expect(SSHCommand.posixQuoted("my key") == "'my key'")
        #expect(SSHCommand.posixQuoted("a;b") == "'a;b'")
        #expect(SSHCommand.posixQuoted("$(whoami)") == "'$(whoami)'")
        #expect(SSHCommand.posixQuoted("a'b") == "'a'\\''b'")
    }

    /// Alanlar kullanıcıdan gelir: komut satırı metin birleştirmesiyle değil, argüman
    /// dizisinin alıntılanmasıyla kurulur. Kabuğa giden metinde enjeksiyon kalmaz.
    @Test func theCommandLineQuotesEveryUserSuppliedField() {
        let host = makeHost(hostName: "pinro.app; rm -rf ~",
                            user: "deploy",
                            authenticationMethod: .privateKey,
                            identityFile: "/keys/my key")
        let arguments = SSHCommand.arguments(for: host)

        #expect(arguments.contains("deploy@pinro.app; rm -rf ~"))
        #expect(SSHCommand.commandLine(arguments)
                == "/usr/bin/ssh -i '/keys/my key' -- 'deploy@pinro.app; rm -rf ~'")
    }

    @Test func theCommandLineIsWhatALaunchedTabRuns() {
        let host = makeHost(port: 2222, user: "deploy")
        let target = SSHTarget.profile(host)

        #expect(target.commandLine == "/usr/bin/ssh -p 2222 -- deploy@pinro.app")
    }

    // MARK: - Sekmede başlatma

    @MainActor
    @Test func launchProfileCarriesTheSSHCommandAndTheDisplayName() {
        let host = makeHost(name: "Pinro Production", user: "deploy")
        let profile = SSHLaunch.profile(for: .profile(host))

        #expect(profile.name == "Pinro Production")
        #expect(profile.startupCommand == "/usr/bin/ssh -- deploy@pinro.app")
        // Kabuk kullanıcının varsayılanı kalır: ssh, kabuğun İÇİNDE çalışır; bağlantı
        // düştüğünde sekme kapanmaz ve kullanıcı yeniden bağlanabilir.
        #expect(profile.shellPath == nil)
    }

    @MainActor
    @Test func launchProfileNeverCopiesPrivateKeyContents() {
        // briefs/2: yalnız YOL saklanır. Profil de yalnız yolu taşır.
        let host = makeHost(authenticationMethod: .privateKey, identityFile: "/keys/id_ed25519")
        let profile = SSHLaunch.profile(for: .profile(host))

        #expect(profile.startupCommand?.contains("/keys/id_ed25519") == true)
        #expect(profile.environment.isEmpty)
    }
}
