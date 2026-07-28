import Foundation
import Testing
@testable import Termora

/// briefs/2 "Docker Entegrasyonu": "Silme, durdurma veya yeniden başlatma gibi ETKİLİ
/// işlemlerde kullanıcıdan onay alınmalıdır."
///
/// Kural burada tek bir davranışa iniyor: onay verilene kadar HİÇBİR docker komutu
/// çalışmaz. Testler bunu "eylem çalıştı mı" sayacıyla doğruluyor.
@MainActor
@Suite("Docker etkili işlem onayı")
struct DockerConfirmationTests {

    private struct Subject {
        let workspace: WorkspaceViewModel
        let sessions: MockSessionManager
    }

    private func makeSubject() throws -> Subject {
        let suiteName = "DockerConfirm.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let sessions = MockSessionManager()
        let workspace = WorkspaceViewModel(sessionManager: sessions,
                                           settings: SettingsStore(defaults: defaults),
                                           profiles: ProfileStore(defaults: defaults))
        workspace.newTab()
        return Subject(workspace: workspace, sessions: sessions)
    }

    // MARK: - Onaysız hiçbir şey çalışmaz

    @Test func requestingARestartDoesNotRunItYet() throws {
        let subject = try makeSubject()
        var runs = 0

        subject.workspace.requestDockerRestart(containerName: "shop-web-1") { runs += 1 }

        #expect(runs == 0)
        #expect(subject.workspace.pendingDockerAction != nil)
    }

    @Test func confirmingRunsTheActionExactlyOnce() throws {
        let subject = try makeSubject()
        var runs = 0
        subject.workspace.requestDockerRestart(containerName: "shop-web-1") { runs += 1 }

        subject.workspace.confirmPendingDockerAction()

        #expect(runs == 1)
        #expect(subject.workspace.pendingDockerAction == nil)
    }

    /// İkinci bir onay eylemi TEKRAR çalıştırmamalı: onay tüketilir.
    @Test func confirmingTwiceRunsTheActionOnlyOnce() throws {
        let subject = try makeSubject()
        var runs = 0
        subject.workspace.requestDockerRestart(containerName: "shop-web-1") { runs += 1 }

        subject.workspace.confirmPendingDockerAction()
        subject.workspace.confirmPendingDockerAction()

        #expect(runs == 1)
    }

    @Test func cancellingNeverRunsTheAction() throws {
        let subject = try makeSubject()
        var runs = 0
        subject.workspace.requestDockerRestart(containerName: "shop-web-1") { runs += 1 }

        subject.workspace.cancelPendingDockerAction()

        #expect(runs == 0)
        #expect(subject.workspace.pendingDockerAction == nil)
    }

    /// İptalden sonra gelen bir onay çağrısı da bir şey çalıştırmamalı — kapanış silinmiştir.
    @Test func confirmingAfterCancellingRunsNothing() throws {
        let subject = try makeSubject()
        var runs = 0
        subject.workspace.requestDockerRestart(containerName: "shop-web-1") { runs += 1 }

        subject.workspace.cancelPendingDockerAction()
        subject.workspace.confirmPendingDockerAction()

        #expect(runs == 0)
    }

    // MARK: - Diğer onaylarla çakışmaz

    /// Ekranda kapatma onayı varken araya girilmez: iki diyalog aynı anda açılamaz ve
    /// bekleyen kapatma isteğini ezmek onu sessizce düşürürdü.
    @Test func aPendingCloseBlocksTheDockerPrompt() throws {
        let subject = try makeSubject()
        let tabID = try #require(subject.workspace.activeTabID)
        let sessionID = try #require(subject.workspace.activeTab?.root.leaves.first?.sessionID)
        subject.sessions.busySessionIDs.insert(sessionID)
        subject.workspace.requestCloseTab(id: tabID)
        var runs = 0

        subject.workspace.requestDockerRestart(containerName: "shop-web-1") { runs += 1 }

        #expect(subject.workspace.pendingDockerAction == nil)
        #expect(subject.workspace.pendingClose != nil)
        #expect(runs == 0)
    }

    /// Bekleyen bir docker onayı ikinci bir istekle DEĞİŞTİRİLMEZ: kullanıcı ekranda
    /// gördüğü cümleyi onaylar, arkadan sessizce değişen bir eylemi değil.
    @Test func aSecondRequestDoesNotReplaceTheFirstPrompt() throws {
        let subject = try makeSubject()
        var firstRuns = 0
        var secondRuns = 0
        subject.workspace.requestDockerRestart(containerName: "first") { firstRuns += 1 }

        subject.workspace.requestDockerRestart(containerName: "second") { secondRuns += 1 }

        // Ekrandaki cümle hâlâ İLK isteğe ait…
        #expect(subject.workspace.pendingDockerActionTitle.contains("first"))
        subject.workspace.confirmPendingDockerAction()
        // …ve onay o isteği çalıştırır.
        #expect(firstRuns == 1)
        #expect(secondRuns == 0)
    }

    // MARK: - Metinler

    /// brief 3 "Uygulama Metin Dili": belirsiz OK/Yes yasak, buton eylemi adlandırır.
    @Test func thePromptNamesTheContainerAndTheAction() throws {
        let subject = try makeSubject()
        subject.workspace.requestDockerRestart(containerName: "shop-web-1") {}

        #expect(subject.workspace.pendingDockerActionTitle.contains("shop-web-1"))
        #expect(subject.workspace.pendingDockerActionConfirmLabel == "Restart Container")
        #expect(subject.workspace.pendingDockerActionMessage.isEmpty == false)
    }

    @Test func thereIsNoPromptTextWhileNothingIsPending() throws {
        let subject = try makeSubject()

        #expect(subject.workspace.pendingDockerActionTitle == "")
        #expect(subject.workspace.pendingDockerActionMessage == "")
        #expect(subject.workspace.pendingDockerActionConfirmLabel == "")
    }

    @Test func promptTextIsBuiltFromTheContainerName() {
        #expect(DockerActionPrompt.restartTitle(containerName: "shop-web-1")
                == "Restart the container “shop-web-1”?")
        #expect(DockerActionPrompt.restartConfirmLabel == "Restart Container")
        #expect(DockerActionPrompt.cancelLabel == "Cancel")
    }
}
