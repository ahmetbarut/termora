import Foundation
import Testing
@testable import Termora

/// briefs/3 "SSH Ekranı": kompakt satırda sunucu adı, host, kullanıcı, etiket ve son
/// bağlantı zamanı. Satırın TÜM metni burada üretilir; görünüm yalnız yerleşimdir.
@Suite("SSH ekranı satırı")
struct SSHScreenTests {

    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeHost(name: String = "Pinro Production",
                          hostName: String = "pinro.app",
                          port: Int? = 2222,
                          user: String? = "deploy",
                          tags: [String] = ["prod", "eu"],
                          colorHex: String? = "#169CFF",
                          lastConnectedAt: Date? = nil) -> SSHHost {
        SSHHost(name: name,
                hostName: hostName,
                port: port,
                user: user,
                tags: tags,
                colorHex: colorHex,
                lastConnectedAt: lastConnectedAt)
    }

    private func row(_ target: SSHTarget) -> SSHHostRowModel {
        SSHHostRowModel.make(target: target, now: Self.now)
    }

    // MARK: - Satırdaki bilgiler

    @Test func theRowCarriesNameDestinationUserTagsAndSource() {
        let model = row(.profile(makeHost()))

        #expect(model.name == "Pinro Production")
        #expect(model.destinationText == "deploy@pinro.app:2222")
        #expect(model.userText == "deploy")
        #expect(model.tags == ["prod", "eu"])
        #expect(model.sourceText == SSHHostRowModel.savedSourceText)
        #expect(model.isEditable)
    }

    @Test func aNamelessHostFallsBackToAReadableTitle() {
        #expect(row(.profile(makeHost(name: "   "))).name == "pinro.app")
        #expect(SSHHostRowModel.displayName("  ") == SSHHostRowModel.untitledName)
    }

    @Test func theDefaultPortIsNotSpelledOut() {
        #expect(row(.profile(makeHost(port: nil))).destinationText == "deploy@pinro.app")
        #expect(row(.profile(makeHost(port: nil, user: nil))).destinationText == "pinro.app")
    }

    /// Config satırları kullanıcının DOSYASINDAN gelir: düzenlenemez, silinemez.
    @Test func configHostsAreShownAsReadOnlyRows() {
        let model = row(.configHost(SSHConfigHost(alias: "bastion",
                                                  hostName: "bastion.example.com",
                                                  user: "jump")))

        #expect(model.name == "bastion")
        #expect(model.destinationText == "jump@bastion.example.com")
        #expect(model.sourceText == SSHHostRowModel.configSourceText)
        #expect(model.isEditable == false)
        #expect(model.lastConnectedText == SSHRelativeTime.neverText)
    }

    // MARK: - Son bağlantı zamanı

    @Test func neverConnectedIsSpelledOutInsteadOfLeftBlank() {
        #expect(row(.profile(makeHost())).lastConnectedText == SSHRelativeTime.neverText)
    }

    @Test func theRelativeTimeUsesEnglishFixedWording() {
        let cases: [(TimeInterval, String)] = [
            (10, "Connected just now"),
            (60 * 5, "Connected 5 minutes ago"),
            (60 * 60, "Connected 1 hour ago"),
            (60 * 60 * 26, "Connected 1 day ago"),
            (60 * 60 * 24 * 10, "Connected 1 week ago"),
            (60 * 60 * 24 * 40, "Connected 1 month ago"),
            (60 * 60 * 24 * 400, "Connected 1 year ago"),
        ]
        for (elapsed, expected) in cases {
            let stamp = Self.now.addingTimeInterval(-elapsed)
            #expect(SSHRelativeTime.text(lastConnectedAt: stamp, now: Self.now) == expected)
        }
    }

    /// Saat geri alınmışsa "-3 dakika önce" yazılmaz.
    @Test func aFutureStampDoesNotProduceNegativeText() {
        let future = Self.now.addingTimeInterval(600)
        #expect(SSHRelativeTime.text(lastConnectedAt: future, now: Self.now) == "Connected just now")
    }

    // MARK: - Erişilebilirlik

    @Test func theSpokenLabelRepeatsEverythingTheRowShows() {
        let model = row(.profile(makeHost(lastConnectedAt: Self.now.addingTimeInterval(-3_600))))

        #expect(model.accessibilityLabel.contains("Pinro Production"))
        #expect(model.accessibilityLabel.contains("deploy@pinro.app:2222"))
        #expect(model.accessibilityLabel.contains("prod, eu"))
        #expect(model.accessibilityLabel.contains("Connected 1 hour ago"))
    }

    /// Renk TEK sinyal olamaz: renk verilmiş satırın metni de her şeyi söyler.
    @Test func colourIsOnlyASecondarySignal() {
        let coloured = row(.profile(makeHost(colorHex: "#169CFF")))
        let plain = row(.profile(makeHost(colorHex: nil)))

        #expect(coloured.colorHex == "#169CFF")
        #expect(plain.colorHex == nil)
        #expect(coloured.accessibilityLabel == plain.accessibilityLabel)
    }

    @Test func everyRowActionHasASpokenLabel() {
        let model = row(.profile(makeHost()))

        #expect(model.connectAccessibilityLabel == "Connect to Pinro Production")
        #expect(model.copyAccessibilityLabel == "Copy ssh command for Pinro Production")
        #expect(model.editAccessibilityLabel == "Edit SSH host Pinro Production")
        #expect(model.deleteAccessibilityLabel == "Delete SSH host Pinro Production")
    }

    // MARK: - Form taslağı

    @Test func theDraftRoundTripsEveryFieldOfTheBrief() throws {
        let original = SSHHost(name: "Pinro",
                               hostName: "pinro.app",
                               port: 2222,
                               user: "deploy",
                               authenticationMethod: .privateKey,
                               identityFile: "~/.ssh/pinro_ed25519",
                               startupDirectory: "/srv/app",
                               startupCommand: "docker compose ps",
                               tags: ["prod"],
                               colorHex: "#169CFF",
                               proxyJump: "bastion",
                               lastConnectedAt: Self.now)

        let rebuilt = SSHHostDraft(editing: original).makeHost()

        #expect(rebuilt == original)
    }

    @Test func blankFormFieldsAreStoredAsMissingNotAsEmptyText() {
        var draft = SSHHostDraft.newHost()
        draft.hostName = "  pinro.app  "
        draft.user = "   "
        draft.identityFile = ""
        draft.startupCommand = "  "

        let host = draft.makeHost()

        #expect(host.hostName == "pinro.app")
        #expect(host.user == nil)
        #expect(host.identityFile == nil)
        #expect(host.startupCommand == nil)
        // Ad boşsa host adı görünen ad olur; liste hiçbir zaman boş satır göstermez.
        #expect(host.name == "pinro.app")
    }

    @Test func hostIsRequiredBeforeSaving() {
        var draft = SSHHostDraft.newHost()
        #expect(draft.isSaveEnabled == false)
        draft.hostName = "pinro.app"
        #expect(draft.isSaveEnabled)
    }

    @Test func anImpossiblePortIsWarnedAboutAndLeftUnset() {
        var draft = SSHHostDraft.newHost()
        draft.hostName = "pinro.app"
        draft.port = "not-a-port"

        #expect(draft.portWarning != nil)
        #expect(draft.makeHost().port == nil)

        draft.port = "2222"
        #expect(draft.portWarning == nil)
        #expect(draft.makeHost().port == 2222)
    }

    /// Form, kaydetmeden önce çalışacak komutu gösterir; host girilmeden gösterilecek
    /// bir komut YOKTUR.
    @Test func theFormPreviewsTheCommandItWillRun() {
        var draft = SSHHostDraft.newHost()
        #expect(draft.commandPreviewText == SSHHostDraft.commandPreviewPlaceholder)

        draft.hostName = "pinro.app"
        draft.user = "deploy"
        draft.port = "2222"

        #expect(draft.commandPreviewText == "/usr/bin/ssh -p 2222 -- deploy@pinro.app")
        // Önizleme kullanıcıya doğrulamanın gevşetilmediğini de gösterir.
        #expect(!draft.commandPreviewText.contains("-o"))
    }

    @Test func tagsAreSplitTrimmedAndDeduplicated() {
        #expect(SSHHostDraft.parseTags("prod, eu ,, PROD") == ["prod", "eu"])
        #expect(SSHHostDraft.parseTags("   ").isEmpty)
    }

    /// Config hostundan profil türetmek yalnız YOLU taşır; anahtar içeriği hiçbir yerde
    /// okunmaz (briefs/2).
    @Test func importingAConfigHostCarriesOnlyThePathOfTheKey() {
        let configHost = SSHConfigHost(alias: "pinro",
                                       hostName: "pinro.app",
                                       user: "deploy",
                                       port: 2222,
                                       identityFile: "~/.ssh/pinro_ed25519",
                                       proxyJump: "bastion")

        let host = SSHHostDraft(importing: configHost).makeHost()

        #expect(host.name == "pinro")
        #expect(host.hostName == "pinro.app")
        #expect(host.user == "deploy")
        #expect(host.port == 2222)
        #expect(host.authenticationMethod == .privateKey)
        #expect(host.identityFile == "~/.ssh/pinro_ed25519")
        #expect(host.proxyJump == "bastion")
        #expect(host.lastConnectedAt == nil)
    }

    @Test func editingAnExistingHostKeepsItsIdentityAndStamp() {
        let original = makeHost(lastConnectedAt: Self.now)
        var draft = SSHHostDraft(editing: original)
        draft.name = "Renamed"

        let edited = draft.makeHost()

        #expect(edited.id == original.id)
        #expect(edited.name == "Renamed")
        #expect(edited.lastConnectedAt == Self.now)
    }

    @Test func everyAuthenticationMethodExplainsItselfInEnglish() {
        for method in SSHAuthenticationMethod.allCases {
            #expect(!method.title.isEmpty)
            #expect(!method.explanation.isEmpty)
        }
        // Parola Termora'da SAKLANMAZ; ekran bunu açıkça söyler.
        #expect(SSHAuthenticationMethod.password.explanation.contains("never stores"))
    }
}
