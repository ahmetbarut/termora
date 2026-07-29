import Foundation
import Testing
@testable import Termora

/// Ollama `stream: true` ile NDJSON döndürür: her satır bir JSON nesnesi, sonuncusunda
/// `done: true`.
///
/// Akış brief'te İSTENMİYOR; yerel bir modelin ilk kelimesi ile son kelimesi arasında
/// onlarca saniye olabildiği için eklendi. Bu yüzden tek bir kural pazarlığa kapalı:
/// **komut önerileri asla yarım metinden çıkarılmaz** — yarım bir kod bloğu, çalıştırılabilir
/// görünen ama eksik bir komut üretirdi.
@Suite("Ollama akış çözücüsü")
struct OllamaStreamDecoderTests {

    private func decode(_ lines: [String]) -> (text: String, isDone: Bool) {
        var decoder = OllamaStreamDecoder()
        var text = ""
        var done = false
        for line in lines {
            for event in decoder.consume(Data((line + "\n").utf8)) {
                switch event {
                case let .delta(chunk): text += chunk
                case .done: done = true
                }
            }
        }
        return (text, done)
    }

    @Test func deltasAreJoinedInOrder() {
        let result = decode([
            #"{"message":{"role":"assistant","content":"Run "},"done":false}"#,
            #"{"message":{"role":"assistant","content":"`ls`"},"done":false}"#,
            #"{"message":{"role":"assistant","content":""},"done":true}"#,
        ])
        #expect(result.text == "Run `ls`")
        #expect(result.isDone)
    }

    /// Ağ paketleri satır sınırında gelmez. Yarım bir satır tamponlanmazsa JSON çözümü
    /// düşer ve cevabın ortası SESSİZCE kaybolurdu.
    @Test func aChunkSplitInTheMiddleOfALineIsBuffered() {
        var decoder = OllamaStreamDecoder()
        var text = ""
        let whole = #"{"message":{"role":"assistant","content":"hello"},"done":false}"# + "\n"
        let bytes = Array(whole.utf8)
        for half in [bytes[..<20], bytes[20...]] {
            for case let .delta(chunk) in decoder.consume(Data(half)) { text += chunk }
        }
        #expect(text == "hello")
    }

    /// Ollama arada boş satır ya da ilgisiz alanlar yayabilir; bunlar akışı DÜŞÜRMEZ.
    @Test func blankAndUnknownLinesDoNotBreakTheStream() {
        let result = decode([
            "",
            #"{"model":"llama3.2","created_at":"now","done":false}"#,
            #"{"message":{"role":"assistant","content":"ok"},"done":false}"#,
            #"{"done":true}"#,
        ])
        #expect(result.text == "ok")
        #expect(result.isDone)
    }

    /// Bozuk bir satır o satırı atlar ama gelmiş metni ATMAZ: yarısı gelmiş bir cevabı
    /// silmek kullanıcıya hiçbir şey kazandırmaz.
    @Test func oneMalformedLineDoesNotDiscardWhatAlreadyArrived() {
        let result = decode([
            #"{"message":{"role":"assistant","content":"kept"},"done":false}"#,
            "{ this is not json",
            #"{"done":true}"#,
        ])
        #expect(result.text == "kept")
        #expect(result.isDone)
    }

    /// Ollama hata alanını akışın içinde yayabilir.
    @Test func anErrorLineIsSurfacedRatherThanIgnored() {
        var decoder = OllamaStreamDecoder()
        let events = decoder.consume(Data((#"{"error":"model not found"}"# + "\n").utf8))
        #expect(events.contains { if case .done = $0 { return true } else { return false } } == false)
        #expect(decoder.failure?.contains("model not found") == true)
    }
}

/// Panelin akış davranışı. Kırmızı çizgi burada sınanıyor.
@MainActor
@Suite("AI paneli akışı")
struct AIPanelStreamingTests {

    private func makeModel(chunks: [String], failure: (any Error)? = nil) throws -> (AIPanelModel, FakeAIProvider) {
        let suiteName = "AIStream.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = SettingsStore(defaults: defaults)
        let provider = FakeAIProvider()
        provider.streamChunks = chunks
        provider.streamFailure = failure
        let model = AIPanelModel(provider: provider,
                                 settings: settings,
                                 catalog: AIModelCatalog(provider: provider, settings: settings))
        return (model, provider)
    }

    @Test func theAnswerArrivesInPiecesAndEndsAsOneMessage() async throws {
        let (model, _) = try makeModel(chunks: ["Run ", "`ls`", " to list files."])
        await model.refreshModels()

        model.prompt = "list files"
        await model.send()

        #expect(model.conversation.messages.last?.text == "Run `ls` to list files.")
        #expect(model.streamingText == nil, "akış bitti ama canlı metin ekranda kaldı")
        #expect(model.sendState == .idle)
    }

    /// KIRMIZI ÇİZGİ: yarım gelen metinden komut önerisi ÇIKARILMAZ. Yarım bir kod bloğu
    /// çalıştırılabilir görünen ama eksik bir komut üretirdi — ve Run düğmesi eksik bir
    /// komutu onaylatırdı.
    @Test func noCommandIsOfferedUntilTheAnswerIsComplete() async throws {
        let (model, _) = try makeModel(chunks: ["```sh\nrm -rf ", "/tmp/cache\n```"])
        await model.refreshModels()
        var suggestionCountsDuringStream: [Int] = []
        model.onStreamDelta = { suggestionCountsDuringStream.append(model.conversation.messages.count) }

        model.prompt = "clean the cache"
        await model.send()

        // Akış sürerken konuşmaya HİÇBİR asistan mesajı eklenmedi (öneriler oradan çıkar).
        #expect(suggestionCountsDuringStream.allSatisfy { $0 <= 1 })
        // Bitince tam komut tek parça olarak geldi.
        let text = try #require(model.conversation.messages.last?.text)
        #expect(AIReplyParser.suggestions(in: text).map(\.command) == ["rm -rf /tmp/cache"])
    }

    /// Akış ortasında kopan bağlantı, gelmiş metni EKRANDA BIRAKMAZ ve hata gösterir:
    /// yarım bir cevabı tam sanmak en kötü sonuç olurdu.
    @Test func aBrokenStreamReportsTheErrorInsteadOfKeepingHalfAnAnswer() async throws {
        let (model, _) = try makeModel(chunks: ["half "],
                                       failure: AIProviderError.endpointUnreachable(endpoint: "http://localhost:11434"))
        await model.refreshModels()

        model.prompt = "why"
        await model.send()

        #expect(model.conversation.messages.isEmpty)
        #expect(model.streamingText == nil)
        #expect(model.status?.recovery.isEmpty == false)
        #expect(model.prompt == "why", "hata hâlinde kullanıcının yazdığı kayboldu")
    }
}
