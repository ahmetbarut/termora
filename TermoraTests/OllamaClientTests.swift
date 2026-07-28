import Foundation
import Testing
@testable import Termora

// MARK: - Sahte taşıma

/// Ağ katmanının test dikişi. HİÇBİR test gerçek bir istek yapmaz; bu sınıf
/// `URLRequest`'i kaydeder ve hazır bir cevap (ya da hata) döndürür.
@MainActor
final class FakeAIHTTPTransport: AIHTTPTransport {
    var responses: [Result<(Data, Int), any Error>] = []
    private(set) var sent: [URLRequest] = []

    init(_ responses: [Result<(Data, Int), any Error>] = []) {
        self.responses = responses
    }

    convenience init(json: String, status: Int = 200) {
        self.init([.success((Data(json.utf8), status))])
    }

    convenience init(failure: any Error) {
        self.init([.failure(failure)])
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        sent.append(request)
        guard !responses.isEmpty else {
            throw AIProviderError.malformedResponse("test: cevap kuyruğu boş")
        }
        switch responses.removeFirst() {
        case let .success((data, status)):
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url,
                                                 statusCode: status,
                                                 httpVersion: nil,
                                                 headerFields: nil) else {
                throw AIProviderError.malformedResponse("test: cevap kurulamadı")
            }
            return (data, response)
        case let .failure(error):
            throw error
        }
    }

    var lastBodyText: String? {
        sent.last?.httpBody.flatMap { String(data: $0, encoding: .utf8) }
    }
}

// MARK: - Testler

/// briefs/2 "AI Asistanı" — bu turda YALNIZ Ollama (yerel, anahtarsız).
///
/// Ağ katmanı protokolün arkasındadır; testler sahte taşımayla koşar ve hiçbir gerçek
/// istek yapmaz. Bu makinede Ollama kurulu ama HİÇ MODEL YOK: "model yok" istisna değil,
/// ilk karşılaşılan durumdur ve burada birinci sınıf bir hata olarak ele alınır.
@Suite("Ollama istemcisi")
@MainActor
struct OllamaClientTests {

    private func makeClient(_ transport: FakeAIHTTPTransport,
                            endpoint: String = OllamaEndpoint.defaultAddress) -> OllamaClient {
        OllamaClient(endpoint: { endpoint }, transport: transport)
    }

    // MARK: - Uç nokta çözümleme

    @Test func theDefaultEndpointIsTheLocalOllamaAddress() {
        #expect(OllamaEndpoint.defaultAddress == "http://localhost:11434")
        #expect(OllamaEndpoint.url(from: OllamaEndpoint.defaultAddress) != nil)
    }

    @Test func aHostWithoutASchemeIsTreatedAsPlainHTTP() {
        #expect(OllamaEndpoint.url(from: "localhost:11434")?.absoluteString == "http://localhost:11434")
        #expect(OllamaEndpoint.url(from: "  127.0.0.1:11434/  ")?.absoluteString == "http://127.0.0.1:11434")
    }

    @Test func nonHTTPEndpointsAreRejectedInsteadOfBeingGuessed() {
        #expect(OllamaEndpoint.url(from: "") == nil)
        #expect(OllamaEndpoint.url(from: "   ") == nil)
        #expect(OllamaEndpoint.url(from: "file:///etc/passwd") == nil)
        #expect(OllamaEndpoint.url(from: "ftp://example.com") == nil)
    }

    @Test func anUnusableEndpointFailsBeforeAnyRequestIsSent() async {
        let transport = FakeAIHTTPTransport(json: "{}")
        let client = makeClient(transport, endpoint: "not a url at all")
        await #expect(throws: AIProviderError.invalidEndpoint("not a url at all")) {
            _ = try await client.availableModels()
        }
        #expect(transport.sent.isEmpty, "geçersiz uç noktaya istek gitti")
    }

    // MARK: - Model listesi

    @Test func installedModelsAreListedNewestSizeAndNameIntact() async throws {
        let transport = FakeAIHTTPTransport(json: """
            {"models":[{"name":"llama3.2:latest","size":2019393189},{"name":"qwen2.5-coder:7b","size":4683087519}]}
            """)
        let models = try await makeClient(transport).availableModels()
        #expect(models.map(\.name) == ["llama3.2:latest", "qwen2.5-coder:7b"])
        #expect(models.first?.sizeBytes == 2_019_393_189)
        #expect(transport.sent.first?.url?.absoluteString == "http://localhost:11434/api/tags")
        #expect(transport.sent.first?.httpMethod == "GET")
    }

    /// Bu makinenin GERÇEK durumu: Ollama çalışıyor, `/api/tags` boş liste dönüyor.
    /// Boş dizi sessizce "hiç model yok" diye geçilmez; kendi hatası vardır, çünkü
    /// kullanıcının yapması gereken somut bir şey var.
    @Test func anEmptyModelListIsItsOwnErrorNotAnEmptyDropdown() async {
        let transport = FakeAIHTTPTransport(json: #"{"models":[]}"#)
        let client = makeClient(transport)
        await #expect(throws: AIProviderError.noModelsInstalled(endpoint: "http://localhost:11434")) {
            _ = try await client.availableModels()
        }
    }

    @Test func aMissingModelsKeyIsReportedAsAMalformedAnswerNotAsEmptiness() async {
        let transport = FakeAIHTTPTransport(json: #"{"hello":"world"}"#)
        let client = makeClient(transport)
        await #expect(throws: (any Error).self) {
            _ = try await client.availableModels()
        }
    }

    // MARK: - Sohbet

    @Test func aChatRequestPostsTheModelAndTheMessagesWithoutStreaming() async throws {
        let transport = FakeAIHTTPTransport(json: #"{"message":{"role":"assistant","content":"use ls"}}"#)
        let request = AIRequestBuilder.build(model: "llama3.2",
                                             prompt: "list files",
                                             context: PreparedAIContext.empty,
                                             history: [])
        let reply = try await makeClient(transport).complete(request)

        #expect(reply.text == "use ls")
        let sent = try #require(transport.sent.last)
        #expect(sent.url?.absoluteString == "http://localhost:11434/api/chat")
        #expect(sent.httpMethod == "POST")
        #expect(sent.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(transport.lastBodyText)
        #expect(body.contains("\"model\":\"llama3.2\""))
        // Akış KAPALI: panel tek parça cevap bekliyor, yarım JSON ayrıştırmıyor.
        #expect(body.contains("\"stream\":false"))
        #expect(body.contains("list files"))
    }

    /// Sözleşmenin ağ ucundaki hâli: TELDEN GEÇEN baytlarda ham sır bulunamaz.
    @Test func theBytesOnTheWireCarryNoUnmaskedSecret() async throws {
        let secret = "ghp_abcdefghijklmnopqrstuvwxyz0123456789"
        let snapshot = AIContextSnapshot([
            .selectedOutput: "remote: rejected token \(secret)",
            .workingDirectory: "/Users/dev/pinro",
        ])
        let prepared = AIContextBuilder.prepare(snapshot, preferences: AIContextPreferences())
        let request = AIRequestBuilder.build(model: "llama3.2",
                                             prompt: "why was my push rejected?",
                                             context: prepared,
                                             history: [])

        let transport = FakeAIHTTPTransport(json: #"{"message":{"content":"rotate the token"}}"#)
        _ = try await makeClient(transport).complete(request)

        let body = try #require(transport.lastBodyText)
        #expect(!body.contains(secret), "sır tele düştü")
        #expect(body.contains(SecretMasker.placeholder))
    }

    @Test func anEmptyAnswerIsReportedInsteadOfShowingABlankBubble() async {
        let transport = FakeAIHTTPTransport(json: #"{"message":{"content":"   "}}"#)
        let request = AIRequestBuilder.build(model: "llama3.2",
                                             prompt: "hi",
                                             context: PreparedAIContext.empty,
                                             history: [])
        await #expect(throws: (any Error).self) {
            _ = try await makeClient(transport).complete(request)
        }
    }

    // MARK: - Hatalar

    @Test func aRefusedConnectionBecomesAnUnreachableEndpointNotARawURLError() async {
        let transport = FakeAIHTTPTransport(failure: URLError(.cannotConnectToHost))
        let client = makeClient(transport)
        await #expect(throws: AIProviderError.endpointUnreachable(endpoint: "http://localhost:11434")) {
            _ = try await client.availableModels()
        }
    }

    @Test func aTimeoutIsAlsoAnUnreachableEndpoint() async {
        let transport = FakeAIHTTPTransport(failure: URLError(.timedOut))
        let client = makeClient(transport)
        await #expect(throws: AIProviderError.endpointUnreachable(endpoint: "http://localhost:11434")) {
            _ = try await client.complete(AIRequestBuilder.build(model: "m",
                                                                 prompt: "hi",
                                                                 context: .empty,
                                                                 history: []))
        }
    }

    /// Ollama silinmiş bir model istendiğinde 404 döner. Kullanıcıya "sunucu hata verdi"
    /// demek işe yaramaz; hangi modelin eksik olduğu söylenmeli.
    @Test func askingForAModelThatIsNotPulledNamesTheModel() async {
        let transport = FakeAIHTTPTransport(
            [.success((Data(#"{"error":"model 'llama3.2' not found, try pulling it first"}"#.utf8), 404))]
        )
        let client = makeClient(transport)
        await #expect(throws: AIProviderError.modelNotFound("llama3.2")) {
            _ = try await client.complete(AIRequestBuilder.build(model: "llama3.2",
                                                                 prompt: "hi",
                                                                 context: .empty,
                                                                 history: []))
        }
    }

    @Test func anyOtherServerErrorKeepsTheStatusAndTheBodyForTheDetailView() async throws {
        let transport = FakeAIHTTPTransport([.success((Data(#"{"error":"boom"}"#.utf8), 500))])
        let client = makeClient(transport)
        do {
            _ = try await client.availableModels()
            Issue.record("hata bekleniyordu")
        } catch let error as AIProviderError {
            #expect(error == .requestFailed(status: 500, detail: "boom"))
            #expect(error.technicalDetail.contains("500"))
        }
    }

    // MARK: - Hata metinleri (briefs/3 "Error State")

    /// Brief dört soruyu cevaplamayı şart koşar: ne başarısız oldu, muhtemel sebep,
    /// kullanıcı ne yapabilir, teknik detay nerede.
    @Test func everyErrorAnswersTheFourQuestionsTheBriefAsksFor() {
        let errors: [AIProviderError] = [
            .invalidEndpoint("nope"),
            .endpointUnreachable(endpoint: "http://localhost:11434"),
            .noModelsInstalled(endpoint: "http://localhost:11434"),
            .modelNotFound("llama3.2"),
            .requestFailed(status: 500, detail: "boom"),
            .malformedResponse("bad json"),
        ]
        for error in errors {
            #expect(!error.title.isEmpty)
            #expect(error.reason.hasSuffix("."), "sebep cümle değil: \(error.title)")
            #expect(error.recovery.hasSuffix("."), "çözüm cümle değil: \(error.title)")
            #expect(!error.technicalDetail.isEmpty, "teknik detay yok: \(error.title)")
            // Belirsiz "Something went wrong" yasak.
            #expect(!error.title.lowercased().contains("something went wrong"))
        }
    }

    /// Model yokken kullanıcıya ne YAPACAĞI söylenmeli — bu makinenin ilk açılış durumu.
    @Test func theNoModelsErrorTellsTheUserTheExactCommandToRun() {
        let error = AIProviderError.noModelsInstalled(endpoint: "http://localhost:11434")
        #expect(error.recovery.contains("ollama pull"))
        #expect(error.reason.lowercased().contains("no models"))
    }

    @Test func theUnreachableErrorNamesTheAddressItTried() {
        let error = AIProviderError.endpointUnreachable(endpoint: "http://localhost:11434")
        #expect(error.reason.contains("http://localhost:11434")
                || error.technicalDetail.contains("http://localhost:11434"))
        #expect(error.recovery.lowercased().contains("ollama serve")
                || error.recovery.lowercased().contains("settings"))
    }
}
