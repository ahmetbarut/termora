import Foundation

// MARK: - Olay

/// PTY akışından çıkan tek bir anlamlı şey.
enum TerminalStreamEvent: Equatable {
    /// Görünür metin. Bir olay bir karakter taşır; sıra korunur.
    case text(String)
    case newline
    /// `\r` — ilerleme çubukları aynı satırı yeniden yazar.
    case carriageReturn
    case backspace
    /// Shell integration kancasının yaydığı komut sınırı.
    case marker(ShellIntegrationMarker)
}

// MARK: - Tarayıcı

/// PTY bayt akışını, SIRASI BOZULMADAN, görünür metne ve OSC 133 işaretlerine ayırır.
///
/// # Neden SwiftTerm'ün OSC kancası yetmiyor
///
/// `SessionManager.registerShellIntegrationHandler` OSC 133'ü zaten dinliyor ve oturumun
/// son çıkış kodunu oradan yazıyor. Komut BLOKLARI için o yol yeterli DEĞİL, çünkü bloklar
/// "şu bayt hangi komutun çıktısı?" sorusuna cevap vermek zorunda:
///
/// 1. Termora ham baytları `dataReceived(slice:)` ile TEK PARÇA alır ve SwiftTerm'e verir.
///    4 KB'lik tek bir okuma `C` işaretini, komutun tüm çıktısını ve `D` işaretini bir
///    arada taşıyabilir — parça içindeki sınırlar kaybolur.
/// 2. Oturum durumu MainActor'a ait olduğu için OSC kancası bir `Task` içinde ertelenir;
///    işaretler baytlardan SONRA gelir.
///
/// İkisi birlikte, çıktının bir önceki bloğa yazılması demektir — kullanıcının okuduğu her
/// blok yalan olurdu. Bu tarayıcı baytları kendisi yürüdüğü için sıra kuruluş gereği doğru.
///
/// # Ne atılır
///
/// CSI (`ESC [ … `), OSC 133 dışındaki OSC'ler, DCS/SOS/PM/APC ve tek karakterlik
/// kaçışlar. Bunlar rengi, imleci ve pencere başlığını yönetir; blok metninde karşılığı yok.
struct TerminalStreamScanner {

    /// Bitmeyen bir OSC yükünün (bozuk çıktı, `cat` edilmiş bir ikili dosya) belleği
    /// sınırsız büyütmesini engelleyen tavan. Base64'lenmiş uzun bir komut ve yol bunun
    /// çok altında kalır.
    nonisolated static let maxOSCPayloadBytes = 16_384

    private enum Mode {
        case text
        case escape
        case csi
        case osc
        case oscEscape
        /// DCS/SOS/PM/APC — hepsi ST ile biter, içeriği kullanılmaz.
        case string
        case stringEscape
        /// `ESC ( B` gibi karakter kümesi atamaları: tam olarak bir bayt daha yutulur.
        case charset
    }

    private var mode: Mode = .text
    private var oscPayload: [UInt8] = []
    /// Yük tavanı aşıldı: biriktirme durur ama dizi izlenmeye DEVAM eder. İzlemeyi de
    /// bıraksaydık dizinin bittiğini göremez ve akışın geri kalanını yutardık.
    private var didOverflowOSCPayload = false

    private var pendingUTF8: [UInt8] = []
    private var expectedUTF8Count = 0

    init() {}

    mutating func scan(_ bytes: some Sequence<UInt8>) -> [TerminalStreamEvent] {
        var events: [TerminalStreamEvent] = []
        for byte in bytes { scan(byte: byte, into: &events) }
        return events
    }

    private mutating func scan(byte: UInt8, into events: inout [TerminalStreamEvent]) {
        switch mode {
        case .escape:
            enterMode(after: byte)
            return
        case .csi:
            // Final bayt aralığı 0x40–0x7E; öncesi parametre ve ara baytlardır.
            if (0x40...0x7E).contains(byte) { mode = .text }
            return
        case .osc:
            if byte == 0x07 { finishOSC(into: &events) }
            else if byte == 0x1B { mode = .oscEscape }
            else { appendOSC(byte) }
            return
        case .oscEscape:
            if byte == 0x5C {                       // ESC \ = ST
                finishOSC(into: &events)
            } else {
                // Yalancı alarm: ESC yükün parçasıymış, ikisi de geri konur.
                appendOSC(0x1B)
                appendOSC(byte)
                mode = .osc
            }
            return
        case .string:
            if byte == 0x07 { mode = .text }
            else if byte == 0x1B { mode = .stringEscape }
            return
        case .stringEscape:
            mode = (byte == 0x5C) ? .text : .string
            return
        case .charset:
            mode = .text
            return
        case .text:
            break
        }

        if byte == 0x1B {
            flushPendingUTF8(into: &events)
            mode = .escape
            return
        }
        if byte >= 0x80 {
            scanUTF8(byte: byte, into: &events)
            return
        }
        flushPendingUTF8(into: &events)
        scanASCII(byte: byte, into: &events)
    }

    private mutating func enterMode(after byte: UInt8) {
        switch byte {
        case 0x5B: mode = .csi                       // [
        case 0x5D:                                   // ]
            mode = .osc
            oscPayload.removeAll(keepingCapacity: true)
            didOverflowOSCPayload = false
        case 0x50, 0x58, 0x5E, 0x5F: mode = .string  // P (DCS), X (SOS), ^ (PM), _ (APC)
        case 0x28, 0x29, 0x2A, 0x2B: mode = .charset // ( ) * +
        default: mode = .text                        // ESC 7, ESC =, … tek karakterlik
        }
    }

    // MARK: OSC

    private mutating func appendOSC(_ byte: UInt8) {
        guard oscPayload.count < Self.maxOSCPayloadBytes else {
            didOverflowOSCPayload = true
            return
        }
        oscPayload.append(byte)
    }

    /// Dizi bitti. Yalnız OSC 133 işaret üretir; başka her OSC sessizce düşer.
    /// Taşan bir yük ayrıştırılmaz: yarım bir komut metni, kullanıcının "yeniden çalıştır"
    /// diyebileceği YANLIŞ bir komut üretirdi.
    private mutating func finishOSC(into events: inout [TerminalStreamEvent]) {
        mode = .text
        defer { oscPayload.removeAll(keepingCapacity: true) }
        guard !didOverflowOSCPayload,
              let payload = String(bytes: oscPayload, encoding: .utf8),
              let marker = ShellIntegrationMarker(payload: payload)
        else { return }
        events.append(.marker(marker))
    }

    // MARK: UTF-8

    private mutating func scanUTF8(byte: UInt8, into events: inout [TerminalStreamEvent]) {
        if byte >= 0xC0 {
            // Yeni öncü bayt: yarım kalmış dizi bozuktur, olduğu gibi çözülür.
            flushPendingUTF8(into: &events)
            pendingUTF8 = [byte]
            expectedUTF8Count = byte >= 0xF0 ? 4 : (byte >= 0xE0 ? 3 : 2)
        } else if pendingUTF8.isEmpty {
            // Öncüsü olmayan devam baytı tek başına anlamsızdır; U+FFFD olarak görünür.
            events.append(.text("\u{FFFD}"))
            return
        } else {
            pendingUTF8.append(byte)
        }
        if pendingUTF8.count >= expectedUTF8Count { flushPendingUTF8(into: &events) }
    }

    /// Geçersiz dizi U+FFFD olur — sessizce yutmak, çıktının bir parçasının kaybolduğunu
    /// gizlerdi.
    private mutating func flushPendingUTF8(into events: inout [TerminalStreamEvent]) {
        guard !pendingUTF8.isEmpty else { return }
        let decoded = String(decoding: pendingUTF8, as: UTF8.self)
        pendingUTF8.removeAll(keepingCapacity: true)
        expectedUTF8Count = 0
        for character in decoded { events.append(.text(String(character))) }
    }

    // MARK: ASCII

    private mutating func scanASCII(byte: UInt8, into events: inout [TerminalStreamEvent]) {
        switch byte {
        case 0x0A: events.append(.newline)
        case 0x0D: events.append(.carriageReturn)
        case 0x08: events.append(.backspace)
        case 0x09: events.append(.text("\t"))
        default:
            // Diğer C0 kontrolleri (BEL, SO, SI…) ve DEL metinde görünmez.
            guard byte >= 0x20, byte != 0x7F else { return }
            events.append(.text(String(UnicodeScalar(byte))))
        }
    }
}
