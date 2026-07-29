import Foundation
import Testing
@testable import Termora

/// briefs/2 "Komut Blokları" ▸ *Bloğu Markdown olarak dışa aktarabilmelidir.*
///
/// Dışa aktarma saf bir dönüşüm: blok girer, metin çıkar. Panoya kopyalama ya da dosyaya
/// yazma bunun dışında kalır — biçimin doğruluğu bir görünüme bağlı olmamalı.
@Suite("Komut bloğu Markdown")
struct CommandBlockMarkdownTests {

    private var epoch: Date { Date(timeIntervalSince1970: 1_000) }

    private func block(command: String? = "npm test",
                       output: String = "2 passing",
                       exitCode: Int? = 0,
                       directory: String? = "/work",
                       truncated: Bool = false) -> CommandBlock {
        CommandBlock(command: command,
                     output: output,
                     startedAt: epoch,
                     finishedAt: epoch.addingTimeInterval(2),
                     exitCode: exitCode,
                     workingDirectory: directory,
                     didTruncateOutput: truncated)
    }

    @Test func aFinishedBlockCarriesItsCommandOutputAndResult() {
        let markdown = CommandBlockMarkdown.text(for: block())

        #expect(markdown.contains("```sh\nnpm test\n```"))
        #expect(markdown.contains("```\n2 passing\n```"))
        #expect(markdown.contains("Exit code: 0"))
        #expect(markdown.contains("/work"))
        #expect(markdown.contains("2s"))
    }

    /// Çıkış kodu bilinmiyorsa 0 YAZILMAZ — dışa aktarılan metin de blok kadar dürüst
    /// olmalı, yoksa kopyalanıp paylaşılan bir çıktı yanlış bilgi taşır.
    @Test func anUnknownExitCodeIsSaidToBeUnknown() {
        let markdown = CommandBlockMarkdown.text(for: block(exitCode: nil))

        #expect(markdown.contains("Exit code: 0") == false)
        #expect(markdown.lowercased().contains("not reported"))
    }

    /// Komut metni yoksa uydurulmaz; blok yine de çıktısıyla dışa aktarılabilir.
    @Test func aBlockWithoutACommandStillExports() {
        let markdown = CommandBlockMarkdown.text(for: block(command: nil))

        #expect(markdown.contains("```sh") == false)
        #expect(markdown.contains("2 passing"))
    }

    /// Kırpılmış çıktı BUNU SÖYLER. Eksik bir çıktıyı tam gibi paylaşmak, okuyanı
    /// hatanın ilk satırını aramaya gönderirdi.
    @Test func aTruncatedBlockSaysSoInTheExport() {
        let markdown = CommandBlockMarkdown.text(for: block(truncated: true))
        #expect(markdown.lowercased().contains("truncated"))
    }

    /// Çıktının içindeki ``` dizisi çitleri kırar; çit uzatılarak korunur.
    @Test func outputContainingAFenceDoesNotBreakTheCodeBlock() {
        let markdown = CommandBlockMarkdown.text(for: block(output: "```\nnested\n```"))

        #expect(markdown.contains("````"))
        #expect(markdown.contains("nested"))
    }

    @Test func aRunningBlockExportsWithoutAResultLine() {
        let running = CommandBlock(command: "sleep 5", output: "", startedAt: epoch)
        let markdown = CommandBlockMarkdown.text(for: running)

        #expect(markdown.contains("Running"))
        #expect(markdown.contains("Exit code") == false)
    }

    /// Birden çok blok tek belgede dışa aktarılabilir; aralarında ayırıcı olur.
    @Test func severalBlocksExportAsOneDocument() {
        let markdown = CommandBlockMarkdown.text(for: [
            block(command: "first", output: "one"),
            block(command: "second", output: "two"),
        ])

        #expect(markdown.contains("first"))
        #expect(markdown.contains("second"))
        #expect(markdown.contains("---"))
    }
}
