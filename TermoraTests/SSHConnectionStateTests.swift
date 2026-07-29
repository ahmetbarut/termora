import Testing
@testable import Termora

/// briefs/2 "SSH Yöneticisi": *Bağlantı kesildiğinde tekrar bağlanma seçeneği sunmalıdır.*
/// briefs/3 "SSH Ekranı": Disconnected / Connecting / Connected / Failed.
///
/// Termora kendi SSH protokolünü konuşmuyor; `ssh` bir terminal panelinde çalışan sıradan
/// bir süreç (briefs/2: *sistem üzerindeki `/usr/bin/ssh` kullanılmalıdır*). Bu yüzden
/// bağlantı durumu ayrı bir yerde tutulamaz — o panelde ne çalıştığından TÜRETİLİR.
/// Yan etkisi hoş: kullanıcı `ssh` komutunu kendi eliyle yazsa da durum görünür.
@Suite("SSH bağlantı durumu")
struct SSHConnectionStateTests {

    @Test func aRunningSshProcessMeansConnected() {
        let state = SSHConnectionTracker.state(
            foregroundCommand: "ssh", didLaunchSSH: true, lastExitCode: nil
        )
        #expect(state == .connected)
    }

    /// Oturum SSH için açıldı ama `ssh` henüz foreground'a gelmedi: shell hâlâ komutu
    /// çalıştırıyor. Bu "bağlantı yok" değil, "bağlanıyor".
    @Test func anSshSessionWithNoForegroundProcessYetIsConnecting() {
        let state = SSHConnectionTracker.state(
            foregroundCommand: nil, didLaunchSSH: true, lastExitCode: nil
        )
        #expect(state == .connecting)
    }

    /// `ssh` bitti ve temiz çıktı: kullanıcı `exit` yazdı. Hata değil.
    @Test func aCleanExitLeavesTheSessionDisconnected() {
        let state = SSHConnectionTracker.state(
            foregroundCommand: "zsh", didLaunchSSH: true, lastExitCode: 0
        )
        #expect(state == .disconnected)
    }

    /// `ssh` sıfırdan farklı çıktı: bağlantı koptu ya da hiç kurulamadı. Yeniden bağlanma
    /// seçeneği YALNIZ bu durumda anlamlı.
    @Test func aFailedExitIsReportedWithItsCode() {
        let state = SSHConnectionTracker.state(
            foregroundCommand: "zsh", didLaunchSSH: true, lastExitCode: 255
        )
        #expect(state == .failed(exitCode: 255))
        #expect(state?.canReconnect == true)
    }

    @Test func onlyTheFailedStateOffersReconnect() {
        #expect(SSHConnectionState.connected.canReconnect == false)
        #expect(SSHConnectionState.connecting.canReconnect == false)
        // Temiz çıkışta kullanıcı kapanmayı KENDİ istedi; ona "yeniden bağlan" diye
        // buton göstermek, istemediği bir şeyi teklif etmek olurdu.
        #expect(SSHConnectionState.disconnected.canReconnect == false)
        #expect(SSHConnectionState.failed(exitCode: 255).canReconnect)
    }

    /// SSH ile başlatılmamış sıradan bir panelde durum HİÇ gösterilmez; `vim` çalışıyor
    /// diye kullanıcıya "Disconnected" demek yanlış bilgi olurdu.
    @Test func aPlainShellSessionHasNoSshState() {
        #expect(SSHConnectionTracker.state(
            foregroundCommand: "vim", didLaunchSSH: false, lastExitCode: nil
        ) == nil)
        #expect(SSHConnectionTracker.state(
            foregroundCommand: nil, didLaunchSSH: false, lastExitCode: 0
        ) == nil)
    }

    /// Kullanıcı `ssh` komutunu elle yazdıysa oturum SSH ile başlatılmamıştır ama bağlantı
    /// gerçektir; durum yine görünmeli.
    @Test func aHandTypedSshIsTrackedToo() {
        #expect(SSHConnectionTracker.state(
            foregroundCommand: "ssh", didLaunchSSH: false, lastExitCode: nil
        ) == .connected)
    }

    /// `SSHCommand` komutu tam yolla üretir; çıplak ada bakan bir kontrol Termora'nın
    /// kendi başlattığı HER bağlantıyı kaçırırdı.
    @Test func theLaunchCommandIsRecognisedByItsLastPathComponent() {
        #expect(SSHConnectionTracker.isSSHCommandLine("/usr/bin/ssh -- deploy"))
        #expect(SSHConnectionTracker.isSSHCommandLine("ssh user@host"))
        #expect(SSHConnectionTracker.isSSHCommandLine(SSHCommand.commandLine(
            SSHCommand.arguments(forConfigAlias: "deploy")
        )))
        #expect(SSHConnectionTracker.isSSHCommandLine("npm run dev") == false)
        #expect(SSHConnectionTracker.isSSHCommandLine(nil) == false)
        #expect(SSHConnectionTracker.isSSHCommandLine("") == false)
        // "sshuttle" ssh DEĞİLDİR; önek eşleşmesi yanlış pozitif üretirdi.
        #expect(SSHConnectionTracker.isSSHCommandLine("sshuttle -r host") == false)
    }

    @Test func everyStateHasALabelAndASymbol() {
        let states: [SSHConnectionState] = [.connecting, .connected, .disconnected, .failed(exitCode: 255)]
        for state in states {
            #expect(!state.title.isEmpty)
            #expect(!state.symbolName.isEmpty)
        }
        // briefs/3 "Erişilebilirlik": durum yalnız renkle anlatılmamalı — her durumun
        // kendi metni ve kendi sembolü var.
        #expect(Set(states.map(\.title)).count == states.count)
        #expect(Set(states.map(\.symbolName)).count == states.count)
    }
}
