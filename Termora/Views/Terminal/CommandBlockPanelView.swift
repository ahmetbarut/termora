import AppKit
import Combine
import SwiftUI

/// briefs/2 "Komut Blokları" paneli.
///
/// Terminalin YERİNE geçmez, yanında durur. Blok görünümü terminali değiştirseydi `vim`,
/// `top`, `tmux` gibi tam ekran uygulamalar bozulurdu (briefs/2 kabul kriteri:
/// *Interactive uygulamaların görünümü bozulmuyor*). Panel kapalıyken görünüm tam olarak
/// klasik terminaldir.
struct CommandBlockPanelView: View {

    let blocks: [CommandBlock]
    /// Shell integration bu oturumda gerçekten çalışıyor mu. Çalışmıyorsa boş liste bir
    /// hata değil, bir eksik kurulumdur ve empty state bunu söylemeli.
    let hasShellIntegration: Bool

    let onRunAgain: (String) -> Void
    let onInsert: (String) -> Void
    let onExplain: (CommandBlock) -> Void
    /// briefs/3 "Sidebar" ▸ Saved Commands: bloktan kaydetmek en doğal yol — blok
    /// komutu zaten biliyor, kullanıcının yeniden yazmasına gerek yok.
    let onSave: (String) -> Void
    let onDismiss: () -> Void

    /// Süre çalışan bloklarda akar; saniyede bir tazelenir.
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if blocks.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .onReceive(ticker) { now = $0 }
    }

    private var header: some View {
        HStack {
            Label("Command Blocks", systemImage: "square.stack.3d.up")
                .font(.callout.weight(.semibold))
            Spacer()
            if !blocks.isEmpty {
                Button("Export All") {
                    copy(CommandBlockMarkdown.text(for: blocks))
                }
                .help("Copy every block as Markdown")
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Hide Command Blocks")
            .accessibilityLabel("Hide Command Blocks")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// briefs/3 "Empty State": tek cümle, birincil eylem, illüstrasyon yok.
    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text(hasShellIntegration
                 ? "No commands yet in this session."
                 : "Command blocks need shell integration.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !hasShellIntegration {
                Text("Termora marks command boundaries with the shell hooks it installs from "
                     + "Settings. Without them it will not guess where one command ends.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                // En yenisi ÜSTTE: kullanıcı son çalıştırdığı komuta bakar, ilkine değil.
                ForEach(blocks.reversed()) { block in
                    CommandBlockRow(block: block,
                                    now: now,
                                    onRunAgain: onRunAgain,
                                    onInsert: onInsert,
                                    onExplain: onExplain,
                                    onSave: onSave)
                }
            }
            .padding(12)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Satır

private struct CommandBlockRow: View {
    let block: CommandBlock
    let now: Date
    let onRunAgain: (String) -> Void
    let onInsert: (String) -> Void
    let onExplain: (CommandBlock) -> Void
    let onSave: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusLine
            if let command = block.command, !command.isEmpty {
                Text(command)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
            if !block.output.isEmpty {
                if block.didTruncateOutput {
                    // Kullanıcı eksik bir çıktıya tam sanarak bakmamalı.
                    Text("Beginning of the output was truncated.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(block.output)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            actions
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
    }

    /// Durum, süre ve saat. Renk TEK gösterge değildir: her durumun kendi sözcüğü ve
    /// kendi sembolü var (briefs/3 "Erişilebilirlik").
    private var statusLine: some View {
        HStack(spacing: 6) {
            Image(systemName: block.state.symbolName)
                .foregroundStyle(block.state.colorToken.color)
            Text(block.state.label)
                .font(.caption.weight(.semibold))
            Text(CommandBlockDuration.text(block.duration(now: now)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Text(CommandBlockClock.text(block.startedAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [block.state.accessibilityLabel]
        if let command = block.command, !command.isEmpty { parts.append("Command: \(command)") }
        parts.append("Ran for \(CommandBlockDuration.text(block.duration(now: now)))")
        return parts.joined(separator: ". ")
    }

    /// briefs/2 blok işlemleri. "Run again" ve "Edit and run" AYRI: birincisi komutu
    /// çalıştırır, ikincisi yalnız satıra yazar — kullanıcı düzenleyip kendisi Enter'lar.
    /// Hiçbir komut onay olmadan çalışmaz kuralı burada da geçerli (briefs/1 "Güvenlik").
    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 8) {
            if let command = block.command, !command.isEmpty {
                Button("Copy Command") { copy(command) }
                Button("Run Again") { onRunAgain(command) }
                Button("Edit and Run") { onInsert(command) }
                Button("Save") { onSave(command) }
                    .help("Keep this command in Saved Commands")
            }
            if !block.output.isEmpty {
                Button("Copy Output") { copy(block.output) }
            }
            Button("Markdown") { copy(CommandBlockMarkdown.text(for: block)) }
                .help("Copy this block as Markdown")
            Button("Explain") { onExplain(block) }
                .help("Ask the AI assistant about this command")
            Spacer()
        }
        .font(.caption)
        .buttonStyle(.link)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
