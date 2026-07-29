import SwiftUI

// MARK: - İçerik (saf metin, test edilebilir)

/// Gizlilik sayfasının tek bir maddesi. Anahtar DEĞİL, cümledir: sayfanın işi bir şeyi
/// açıp kapamak değil, ne olduğunu dürüstçe söylemektir.
struct PrivacyStatement: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let symbolName: String
}

struct PrivacySection: Identifiable, Equatable {
    let id: String
    let title: String
    /// Bölümün altındaki açıklama; "neden burada anahtar yok" gibi soruları cevaplar.
    var footer: String?
    let statements: [PrivacyStatement]
}

/// briefs/2 "Gizlilik" bölümünün sayfa karşılığı.
///
/// Kural: **var olmayan bir özellik "kapalı" diye gösterilmez** — ve aynı kuralın diğer
/// yüzü: **var olan bir özellik "yok" diye gösterilmez.** AI asistanı geldi; sayfanın
/// "AI bağlı değil" demesi artık kullanıcıyı yanıltırdı. Telemetri ve bulut sağlayıcılar
/// hâlâ yok, onlar kendi bölümlerinde sebebiyle duruyor.
enum PrivacyContent {

    static let defaultsSection = PrivacySection(
        id: "defaults",
        title: "What Termora does today",
        footer: nil,
        statements: [
            PrivacyStatement(
                id: "no-account",
                title: "No account, no sign-in",
                detail: "Termora works without an account. Nothing you do here is tied to an identity "
                    + "and nothing is synced to a server.",
                symbolName: "person.crop.circle.badge.xmark"
            ),
            PrivacyStatement(
                id: "history-local",
                title: "Terminal output stays on this Mac",
                detail: "Termora never uploads terminal output or command history. What it remembers "
                    + "lives in its own preferences on this Mac.",
                symbolName: "internaldrive"
            ),
            PrivacyStatement(
                id: "secret-masking",
                title: "Secrets are hidden before any text leaves Termora",
                detail: "API keys, tokens, passwords, private key blocks and cookie values are replaced "
                    + "with \(SecretMasker.placeholder), and Termora tells you what it hid so you can "
                    + "check the text first.",
                symbolName: "eye.slash"
            ),
            PrivacyStatement(
                id: "startup-approval",
                title: "Startup commands wait for your approval",
                detail: "Workspace and profile startup commands never run on their own, and destructive "
                    + "ones are marked before you confirm them.",
                symbolName: "checkmark.shield"
            ),
            PrivacyStatement(
                id: "ai-on-request",
                title: "The assistant answers only when you ask",
                detail: "Termora talks to an Ollama server on this Mac, and only when you send a "
                    + "question. It shows the exact terminal context before it is sent, and your "
                    + "whole terminal history is never part of it.",
                symbolName: "sparkles"
            ),
            PrivacyStatement(
                id: "ai-no-auto-run",
                title: "A command the assistant writes never runs by itself",
                detail: "Suggested commands are shown with Copy, Insert, Explain and Run. Run asks "
                    + "first, and a destructive command is marked before you confirm it.",
                symbolName: "hand.raised"
            ),
        ]
    )

    static let storedDataSection = PrivacySection(
        id: "stored",
        title: "What Termora stores, and why",
        footer: "Deleting a workspace, profile or theme in Settings removes it from this Mac.",
        statements: [
            PrivacyStatement(
                id: "stored-settings",
                title: "Workspaces, profiles and themes",
                detail: "Saved so a project reopens with the same tabs, folders and colours. They stay "
                    + "in Termora's preferences on this Mac.",
                symbolName: "square.grid.2x2"
            ),
            PrivacyStatement(
                id: "stored-session",
                title: "Session restore",
                detail: "Window, tab and folder names from your last run, so Termora can reopen them. "
                    + "New shells are started — running commands do not continue and startup commands "
                    + "are not run again.",
                symbolName: "clock.arrow.circlepath"
            ),
            PrivacyStatement(
                id: "stored-ssh",
                title: "SSH connections",
                detail: "Termora reads your ~/.ssh/config to list hosts and saves the connection details "
                    + "you enter. Private key contents are never copied into Termora.",
                symbolName: "network"
            ),
            PrivacyStatement(
                id: "stored-ai",
                title: "AI address and model",
                detail: "Only the Ollama address and the model name you picked are saved, so the panel "
                    + "opens ready. The conversation itself is not written anywhere and is gone when "
                    + "the window closes.",
                symbolName: "sparkles"
            ),
        ]
    )

    static let notBuiltYetSection = PrivacySection(
        id: "not-built-yet",
        title: "Not built yet",
        footer: "Termora does not show a switch for something it cannot do. These entries become "
            + "settings when the features ship.",
        statements: [
            PrivacyStatement(
                id: "no-telemetry",
                title: "No telemetry and no crash reporting",
                detail: "This version contains no analytics, tracking or crash reporting code, so there "
                    + "is nothing here to turn off.",
                symbolName: "chart.bar.xaxis"
            ),
            PrivacyStatement(
                id: "no-cloud-ai",
                title: "No cloud AI provider",
                detail: "The assistant talks to Ollama on this Mac and nowhere else. Cloud providers "
                    + "are not built, so no question and no terminal context can leave this machine.",
                symbolName: "cloud.slash"
            ),
            PrivacyStatement(
                id: "keychain",
                title: "No API keys, so nothing to keep in the Keychain",
                detail: "Ollama runs locally and asks for no credentials, so Termora stores no API "
                    + "keys at all. A provider that needs one would keep it in the macOS Keychain, "
                    + "never in Termora's preferences.",
                symbolName: "key"
            ),
        ]
    )

    static let sections: [PrivacySection] = [defaultsSection, storedDataSection, notBuiltYetSection]
}

// MARK: - Görünüm

/// Ayarlar ▸ Privacy (briefs/2 "Gizlilik", briefs/3 Settings bölüm listesi).
struct PrivacySettingsView: View {

    let settings: SettingsStore

    var body: some View {
        Form {
            CrashReportingSection(settings: settings)

            ForEach(PrivacyContent.sections) { section in
                Section {
                    ForEach(section.statements) { statement in
                        row(statement)
                    }
                } header: {
                    Text(section.title)
                } footer: {
                    if let footer = section.footer {
                        Text(footer)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ statement: PrivacyStatement) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Simge dekoratiftir; başlık ve açıklama zaten her şeyi söyler, bu yüzden
            // ekran okuyucuya iki kez okutulmaz.
            Image(systemName: statement.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(statement.title)
                Text(statement.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(statement.title). \(statement.detail)")
    }
}

/// briefs/2 "Hata Raporlama" bölümü.
///
/// Anahtarın yanında raporun TAM İÇERİĞİ duruyor. Brief "gönderilecek içerik
/// incelenebilmeli" diyor ve bunu ayrı bir ekrana saklamak, kimsenin bakmadığı bir
/// vaade dönüştürürdü.
struct CrashReportingSection: View {
    let settings: SettingsStore

    @State private var showsSample = false

    /// Örnek rapor: gerçek bir çökme olmadan da kullanıcı NE gönderileceğini görebilmeli.
    private var sample: CrashReport {
        CrashReport.current(stackTrace: """
            0   Termora    0x0000000102a4c1f0 exampleFrame + 128
            1   AppKit     0x00007ff81a2b3c40 -[NSApplication run] + 586
            """)
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Send crash reports", isOn: Binding(
                    get: { settings.settings.sendsCrashReports },
                    set: { settings.settings.sendsCrashReports = $0 }
                ))
                Text("Off by default. Termora never sends anything about a crash unless "
                     + "this is on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DisclosureGroup("What a report contains", isExpanded: $showsSample) {
                Text(sample.previewText)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
        } header: {
            Text("Crash Reporting")
        } footer: {
            // Yasak listesi kullanıcıya AÇIKÇA söylenir: bir gizlilik vaadi ancak
            // söylendiğinde vaattir.
            Text("A report has four things: the Termora version, your macOS version, your "
                 + "Mac's architecture and the crash's stack trace. It never contains "
                 + "terminal output, the commands you typed, file contents, environment "
                 + "variables, API keys or SSH details.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
