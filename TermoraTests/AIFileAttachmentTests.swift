import Foundation
import Testing
@testable import Termora

/// briefs/2 "Terminal Bağlamı" son maddesi: "Kullanıcının açıkça eklediği dosyalar".
///
/// Dosya eklemek, Termora'nın dışarı verdiği veri yüzeyini genişleten TEK özelliktir;
/// bu yüzden üç kural testle sabitlenir: içerik aynı maskeleme sınırından geçer, dosya
/// belleğe SINIRSIZ okunmaz, ve gönderilen şey kullanıcının önizlemede gördüğüdür.
@Suite("AI bağlamına dosya ekleme")
struct AIFileAttachmentTests {

    private func data(_ text: String) -> Data { Data(text.utf8) }

    // MARK: - Okuma sınırları

    /// Sınırsız okuma bir 2 GB'lık log dosyasında uygulamayı düşürürdü. Sınır AŞILDIĞINDA
    /// dosya sessizce kırpılmaz — eklenmez ve sebebi söylenir.
    @Test func aFileBiggerThanTheLimitIsRefusedWithAReason() {
        let big = data(String(repeating: "x", count: AIFileAttachmentLoader.byteLimit + 1))
        let result = AIFileAttachmentLoader.load(name: "huge.log", data: big)

        guard case let .failure(reason) = result else {
            Issue.record("büyük dosya kabul edildi")
            return
        }
        #expect(reason.message.contains("huge.log"))
        #expect(reason.message.lowercased().contains("too large"))
    }

    @Test func aFileAtExactlyTheLimitIsAccepted() {
        let exact = data(String(repeating: "x", count: AIFileAttachmentLoader.byteLimit))
        #expect(AIFileAttachmentLoader.load(name: "edge.txt", data: exact).isSuccess)
    }

    /// İkili dosya (görsel, binary) metin olarak gönderilemez: model için anlamsız,
    /// kullanıcı için ise ne gittiğini göremediği bir yığın olurdu.
    @Test func aBinaryFileIsRefusedRatherThanSentAsGarbage() {
        let binary = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        let result = AIFileAttachmentLoader.load(name: "photo.jpg", data: binary)

        guard case let .failure(reason) = result else {
            Issue.record("ikili dosya kabul edildi")
            return
        }
        #expect(reason.message.contains("photo.jpg"))
        #expect(reason.message.lowercased().contains("text"))
    }

    @Test func aTextFileKeepsItsNameAndContent() throws {
        let result = AIFileAttachmentLoader.load(name: "main.swift", data: data("print(\"hi\")"))
        let file = try #require(result.value)
        #expect(file.name == "main.swift")
        #expect(file.text == "print(\"hi\")")
    }

    /// Yalnız dosya ADI taşınır, tam yol DEĞİL: `/Users/ahmet/...` kullanıcı adını
    /// modele gönderirdi ve bunun cevaba hiçbir katkısı yok.
    @Test func onlyTheFileNameTravelsNotTheWholePath() throws {
        let url = URL(fileURLWithPath: "/Users/someone/secret-project/notes.md")
        let file = try #require(AIFileAttachmentLoader.load(contentsOf: url,
                                                            reading: { _ in self.data("hello") }).value)
        #expect(file.name == "notes.md")
        #expect(!file.text.contains("someone"))
    }

    @Test func anUnreadableFileIsReportedNotIgnored() {
        struct Boom: Error {}
        let url = URL(fileURLWithPath: "/nope/missing.txt")
        let result = AIFileAttachmentLoader.load(contentsOf: url, reading: { _ in throw Boom() })

        guard case let .failure(reason) = result else {
            Issue.record("okunamayan dosya sessizce yutuldu")
            return
        }
        #expect(reason.message.contains("missing.txt"))
    }

    // MARK: - Bağlam metnine dönüşme

    /// Her dosya ADIYLA başlar: model hangi içeriğin hangi dosyaya ait olduğunu bilmeli,
    /// yoksa iki dosya tek bir metne karışır.
    @Test func attachedFilesAreLabelledWithTheirNames() throws {
        let combined = try #require(AIFileAttachment.combinedText(of: [
            AIFileAttachment(name: "a.txt", text: "first"),
            AIFileAttachment(name: "b.txt", text: "second"),
        ]))
        #expect(combined.contains("a.txt"))
        #expect(combined.contains("first"))
        #expect(combined.contains("b.txt"))
        #expect(combined.contains("second"))
    }

    @Test func noAttachmentsProduceNoContextAtAll() {
        #expect(AIFileAttachment.combinedText(of: []) == nil)
    }

    // MARK: - Maskeleme sınırı (en kritik iddia)

    /// Dosya içeriği AYNI sınırdan geçer. Bir `.env` dosyası eklemek maskelemeyi
    /// atlatmanın yolu OLAMAZ.
    @Test func aSecretInsideAnAttachedFileIsMaskedLikeAnyOtherContext() throws {
        var snapshot = AIContextSnapshot()
        snapshot[.attachedFiles] = try #require(AIFileAttachment.combinedText(of: [
            AIFileAttachment(name: ".env", text: "API_TOKEN=sk-proj-1234567890abcdef"),
        ]))

        let prepared = AIContextBuilder.prepare(snapshot, preferences: AIContextPreferences())

        #expect(prepared.didFindSecrets)
        #expect(!prepared.previewText.contains("sk-proj-1234567890abcdef"))
    }

    /// Ayarlardan kapatılan dosya bağlamı isteğe HİÇ girmez — diğer türlerle aynı kural.
    @Test func turningTheKindOffKeepsAttachedFilesOutOfTheRequest() throws {
        var snapshot = AIContextSnapshot()
        snapshot[.attachedFiles] = try #require(AIFileAttachment.combinedText(of: [
            AIFileAttachment(name: "a.txt", text: "distinctive-content"),
        ]))
        var preferences = AIContextPreferences()
        preferences.setIncludes(.attachedFiles, false)

        let prepared = AIContextBuilder.prepare(snapshot, preferences: preferences)

        #expect(!prepared.previewText.contains("distinctive-content"))
    }

    // MARK: - Kesme yönü

    /// Seçili ÇIKTI sondan kesilir (hata mesajı sondadır) ama bir DOSYA baştan okunur:
    /// import'lar, tip tanımları ve yapı dosyanın başındadır. Aynı yönü kullanmak
    /// eklenen dosyanın en anlamlı kısmını atardı.
    @Test func anOverlongFileKeepsItsBeginningWhileOutputKeepsItsEnd() {
        let long = String(repeating: "a", count: 100) + String(repeating: "b", count: AIContextBuilder.entryCharacterLimit)

        var fileSnapshot = AIContextSnapshot()
        fileSnapshot[.attachedFiles] = long
        let file = AIContextBuilder.prepare(fileSnapshot, preferences: AIContextPreferences())
        #expect(file.previewText.contains("aaaa"))
        #expect(file.previewText.contains(AIContextBuilder.truncationMarker))

        var outputSnapshot = AIContextSnapshot()
        outputSnapshot[.selectedOutput] = long
        let output = AIContextBuilder.prepare(outputSnapshot, preferences: AIContextPreferences())
        #expect(!output.previewText.contains("aaaa"))
        #expect(output.previewText.contains(AIContextBuilder.truncationMarker))
    }
}

/// Panelin ekleme/kaldırma davranışı.
@MainActor
@Suite("AI paneli dosya ekleme")
struct AIPanelAttachmentTests {

    private func makeModel(files: [String: String]) throws -> AIPanelModel {
        let suiteName = "AIAttach.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = SettingsStore(defaults: defaults)
        let provider = FakeAIProvider()
        let model = AIPanelModel(provider: provider,
                                 settings: settings,
                                 catalog: AIModelCatalog(provider: provider, settings: settings))
        model.chooseFiles = { files.keys.sorted().map { URL(fileURLWithPath: "/tmp/\($0)") } }
        model.readFile = { url in
            guard let text = files[url.lastPathComponent] else { throw CocoaError(.fileNoSuchFile) }
            return Data(text.utf8)
        }
        return model
    }

    @Test func attachingPutsTheFileIntoTheContextTheUserCanReview() throws {
        let model = try makeModel(files: ["notes.md": "the build fails on linux"])

        model.attachFiles()

        #expect(model.attachments.map(\.name) == ["notes.md"])
        #expect(model.preparedContext.previewText.contains("the build fails on linux"))
        #expect(model.attachmentFailure == nil)
    }

    /// Aynı dosya iki kez eklenirse bağlam SESSİZCE ikiye katlanırdı.
    @Test func attachingTheSameFileTwiceKeepsOneCopy() throws {
        let model = try makeModel(files: ["a.txt": "same"])

        model.attachFiles()
        model.attachFiles()

        #expect(model.attachments.count == 1)
    }

    /// Tek bozuk dosya yüzünden seçimin tamamını atmak, kullanıcıyı hangisinin sorunlu
    /// olduğunu aramaya bırakırdı.
    @Test func oneUnreadableFileDoesNotThrowAwayTheGoodOnes() throws {
        let model = try makeModel(files: ["good.txt": "kept"])
        model.chooseFiles = {
            [URL(fileURLWithPath: "/tmp/good.txt"), URL(fileURLWithPath: "/tmp/missing.txt")]
        }

        model.attachFiles()

        #expect(model.attachments.map(\.name) == ["good.txt"])
        let failure = try #require(model.attachmentFailure)
        #expect(failure.contains("missing.txt"))
    }

    @Test func removingAFileTakesItOutOfTheContext() throws {
        let model = try makeModel(files: ["a.txt": "distinctive"])
        model.attachFiles()
        let file = try #require(model.attachments.first)

        model.removeAttachment(file)

        #expect(model.attachments.isEmpty)
        #expect(!model.preparedContext.previewText.contains("distinctive"))
    }

    @Test func theRequestCarriesTheAttachedFile() async throws {
        let suiteName = "AIAttachSend.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = SettingsStore(defaults: defaults)
        let provider = FakeAIProvider()
        let model = AIPanelModel(provider: provider,
                                 settings: settings,
                                 catalog: AIModelCatalog(provider: provider, settings: settings))
        model.chooseFiles = { [URL(fileURLWithPath: "/tmp/config.yml")] }
        model.readFile = { _ in Data("replicas: 3".utf8) }
        await model.refreshModels()
        model.attachFiles()

        model.prompt = "how many replicas"
        await model.send()

        let request = try #require(provider.requests.first)
        #expect(request.outgoingTexts.contains { $0.contains("replicas: 3") })
        #expect(request.outgoingTexts.contains { $0.contains("config.yml") })
    }
}

private extension Result where Success == AIFileAttachment {
    var isSuccess: Bool { if case .success = self { return true } else { return false } }
    var value: AIFileAttachment? { try? get() }
}
