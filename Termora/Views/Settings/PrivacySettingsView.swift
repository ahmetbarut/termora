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
/// Kural: **var olmayan bir özellik "kapalı" diye gösterilmez.** Telemetri ve AI bu
/// sürümde YOK; onları kapalı bir anahtarla göstermek, kullanıcının kapatabileceği bir
/// şey varmış izlenimi verirdi. Bunun yerine ayrı bir bölümde durumları yazıyla anlatılır.
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
                id: "no-ai",
                title: "The AI assistant is not connected",
                detail: "No AI provider ships in this version. When one does, it will run only when you "
                    + "ask for it, show you the exact text it is about to send, and support a local "
                    + "Ollama model.",
                symbolName: "sparkles"
            ),
            PrivacyStatement(
                id: "keychain",
                title: "Provider keys will live in the Keychain",
                detail: "Termora stores no API keys today. When AI settings arrive, the keys belong in "
                    + "the macOS Keychain and never in Termora's preferences.",
                symbolName: "key"
            ),
        ]
    )

    static let sections: [PrivacySection] = [defaultsSection, storedDataSection, notBuiltYetSection]
}

// MARK: - Görünüm

/// Ayarlar ▸ Privacy (briefs/2 "Gizlilik", briefs/3 Settings bölüm listesi).
struct PrivacySettingsView: View {

    var body: some View {
        Form {
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
