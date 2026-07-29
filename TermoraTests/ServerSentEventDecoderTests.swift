import Foundation
import Testing
@testable import Termora

/// OpenAI ve Anthropic akışlarının ortak taşıyıcısı Server-Sent Events'tir. Çözücü saf
/// tutuluyor çünkü akışın en kırılgan yeri ağ paketlerinin olay sınırında GELMEMESİ ve
/// bunu gerçek bir sunucuyla sınamak imkânsıza yakın.
@Suite("Server-sent event çözücü")
struct ServerSentEventDecoderTests {

    private func chunk(_ text: String) -> Data { Data(text.utf8) }

    @Test func aCompleteEventIsDecodedInOnePiece() {
        var decoder = ServerSentEventDecoder()
        let events = decoder.consume(chunk("event: message\ndata: {\"a\":1}\n\n"))
        #expect(events == [ServerSentEvent(name: "message", data: "{\"a\":1}")])
    }

    /// Asıl mesele bu: sunucu tek bir olayı istediği yerden bölebilir ve tamponlama
    /// olmadan cevabın ortası sessizce kaybolur.
    @Test func anEventSplitAcrossChunksIsReassembled() {
        var decoder = ServerSentEventDecoder()
        #expect(decoder.consume(chunk("data: {\"te")).isEmpty)
        #expect(decoder.consume(chunk("xt\":\"hi\"}")).isEmpty)
        let events = decoder.consume(chunk("\n\n"))
        #expect(events == [ServerSentEvent(name: nil, data: "{\"text\":\"hi\"}")])
    }

    @Test func severalEventsInOneChunkArriveInOrder() {
        var decoder = ServerSentEventDecoder()
        let events = decoder.consume(chunk("data: one\n\ndata: two\n\ndata: three\n\n"))
        #expect(events.map(\.data) == ["one", "two", "three"])
    }

    /// SSE birden çok `data:` satırını satırbaşıyla birleştirir — kod bloğu içeren bir
    /// cevapta bu gerçekten olur.
    @Test func multipleDataLinesJoinWithNewlines() {
        var decoder = ServerSentEventDecoder()
        let events = decoder.consume(chunk("data: first\ndata: second\n\n"))
        #expect(events == [ServerSentEvent(name: nil, data: "first\nsecond")])
    }

    /// `:` ile başlayan satır yorumdur (sunucular bağlantıyı canlı tutmak için gönderir)
    /// ve olay üretmemeli.
    @Test func commentLinesAreIgnored() {
        var decoder = ServerSentEventDecoder()
        let events = decoder.consume(chunk(": keep-alive\n\ndata: real\n\n"))
        #expect(events.map(\.data) == ["real"])
    }

    @Test func carriageReturnsAreToleratedForServersThatSendCRLF() {
        var decoder = ServerSentEventDecoder()
        let events = decoder.consume(chunk("event: ping\r\ndata: {}\r\n\r\n"))
        #expect(events == [ServerSentEvent(name: "ping", data: "{}")])
    }

    /// Veri taşımayan olay (yalnız `event:` satırı) yutulur: çağıranın çözecek bir şeyi
    /// yok ve boş bir parça cevaba eklenirse akış bozulmuş görünür.
    @Test func anEventWithoutDataIsDropped() {
        var decoder = ServerSentEventDecoder()
        #expect(decoder.consume(chunk("event: ping\n\n")).isEmpty)
    }

    @Test func aTrailingEventWithoutABlankLineIsNotEmittedYet() {
        var decoder = ServerSentEventDecoder()
        #expect(decoder.consume(chunk("data: unfinished\n")).isEmpty)
    }
}
