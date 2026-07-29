import Foundation

/// briefs/2 "Komut Blokları" ▸ *Bloğu Markdown olarak dışa aktarabilmelidir.*
///
/// Saf bir dönüşüm: blok girer, metin çıkar. Panoya kopyalama ya da dosyaya yazma bunun
/// dışında kalır — biçimin doğruluğu bir görünüme bağlı olmamalı.
enum CommandBlockMarkdown {

    static func text(for block: CommandBlock) -> String {
        var lines: [String] = []

        if let command = block.command, !command.isEmpty {
            lines.append(fenced(command, language: "sh"))
            lines.append("")
        }

        if !block.output.isEmpty {
            lines.append(fenced(block.output))
            lines.append("")
        }

        lines.append(metadata(for: block))
        return lines.joined(separator: "\n")
    }

    /// Birden çok blok tek belge olur; aralarında yatay çizgi durur.
    static func text(for blocks: [CommandBlock]) -> String {
        blocks.map { text(for: $0) }.joined(separator: "\n\n---\n\n")
    }

    /// Durum, süre, dizin ve —biliniyorsa— çıkış kodu.
    ///
    /// Bilinmeyen çıkış kodu 0 YAZILMAZ: dışa aktarılan metin de blok kadar dürüst olmalı,
    /// yoksa kopyalanıp paylaşılan bir çıktı yanlış bilgi taşır.
    private static func metadata(for block: CommandBlock) -> String {
        var parts: [String] = []
        parts.append("Status: \(block.state.label)")

        if !block.isRunning {
            switch block.exitCode {
            case let code?: parts.append("Exit code: \(code)")
            case nil: parts.append("Exit code: not reported by the shell")
            }
            parts.append("Duration: \(CommandBlockDuration.text(block.duration(now: block.startedAt)))")
        }

        if let directory = block.workingDirectory, !directory.isEmpty {
            parts.append("Directory: \(directory)")
        }
        parts.append("Started: \(CommandBlockClock.text(block.startedAt))")

        if block.didTruncateOutput {
            // Eksik bir çıktıyı tam gibi paylaşmak, okuyanı hatanın ilk satırını aramaya
            // gönderirdi.
            parts.append("Note: the beginning of this output was truncated.")
        }
        return parts.map { "- \($0)" }.joined(separator: "\n")
    }

    /// Çit, metnin içindeki en uzun ``` dizisinden bir uzun olur; aksi hâlde iç içe bir
    /// kod bloğu dışa aktarmayı bozardı.
    private static func fenced(_ text: String, language: String = "") -> String {
        var longest = 0
        var run = 0
        for character in text {
            run = character == "`" ? run + 1 : 0
            longest = max(longest, run)
        }
        let fence = String(repeating: "`", count: max(3, longest + 1))
        return "\(fence)\(language)\n\(text)\n\(fence)"
    }
}
