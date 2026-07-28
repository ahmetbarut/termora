import AppKit
import Foundation
import SwiftTerm

/// `AITerminalBridging`'in gerçek terminale bağlanan hâli.
///
/// Panel modeli bu sınıfı DEĞİL protokolü tanır; testler canlı bir PTY olmadan koşar.
///
/// # Ne okunur, ne okunmaz
///
/// Okunan her şey briefs/2'nin "Terminal Bağlamı" listesinden gelir. Scrollback tamponu
/// **hiç okunmaz** — böyle bir yol yoktur. Kullanıcının SEÇTİĞİ metin okunur, o da
/// `AIContextBuilder` içinde bir üst sınırdan geçer.
@MainActor
final class WorkspaceTerminalBridge: AITerminalBridging {

    private let workspace: WorkspaceViewModel
    private let sessionManager: SessionManager

    init(workspace: WorkspaceViewModel, sessionManager: SessionManager) {
        self.workspace = workspace
        self.sessionManager = sessionManager
    }

    // MARK: - Bağlam

    func captureContext() -> AIContextSnapshot {
        var snapshot = AIContextSnapshot()
        snapshot[.operatingSystem] = Self.operatingSystemDescription

        // Bağlam gönderilmeden önce dizin TAZELENİR: kullanıcı panel açıkken `cd` yapmış
        // olabilir ve modele yanlış dizini söylemek cevabı sessizce bozar. Durum çubuğu da
        // aynı ikiliyi çağırır, bu yüzden panelin gördüğü ile çubukta yazan ayrışmaz.
        workspace.refreshActiveWorkingDirectory()
        if let status = workspace.statusSnapshot() {
            snapshot[.shell] = status.shellName
            // Yol KISALTILMIŞ gider (`~/Projects/pinro`): cevabın doğruluğu için yeterli
            // ve kullanıcı adını dışarı taşımaz.
            snapshot[.workingDirectory] = status.workingDirectory
            snapshot[.gitBranch] = status.branchName
        }

        if let selection = activeSelection() {
            // Komut blokları henüz yok, bu yüzden "komut" ile "çıktı" ayrımı seçimin
            // ŞEKLİNDEN çıkarılır: tek satır seçen kullanıcı bir komutu işaret ediyordur,
            // blok seçen çıktıyı. Yanlış tahminin bedeli yalnız etikettir; metin aynıdır.
            if selection.contains("\n") {
                snapshot[.selectedOutput] = selection
            } else {
                snapshot[.selectedCommand] = selection
            }
        }
        return snapshot
    }

    /// "macOS 14.5 (arm64)" — modelin Linux'a özgü bayrak önermemesi için.
    private static var operatingSystemDescription: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let architecture: String
        #if arch(arm64)
        architecture = "arm64"
        #elseif arch(x86_64)
        architecture = "x86_64"
        #else
        architecture = "unknown"
        #endif
        return "macOS \(version.majorVersion).\(version.minorVersion) (\(architecture))"
    }

    private func activeSelection() -> String? {
        guard let view = activeTerminalView(), view.selectionActive else { return nil }
        let selection = view.getSelection()?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let selection, !selection.isEmpty else { return nil }
        return selection
    }

    // MARK: - Yazma

    /// Metni terminal girişine yazar; return'e BASMAZ. Kullanıcı düzenleyip kendisi
    /// çalıştırır (briefs/2 "Düzenleyebilir").
    ///
    /// Metin OLDUĞU GİBİ yazılır. Çok satırlı bir öneriyi tek satıra indirmek burada
    /// DEĞİL `AICommandSuggestion.terminalText` içinde yapılır: kullanıcının onay
    /// penceresinde okuduğu metinle terminale düşen metin aynı olmalı.
    func insert(_ text: String) {
        activeTerminalView()?.send(txt: text)
    }

    /// Onaylanmış komutu yazar ve çalıştırır. Yalnız `AIPanelModel.confirmRun` çağırır.
    func run(_ command: String) {
        activeTerminalView()?.send(txt: command + "\n")
    }

    private func activeTerminalView() -> TermoraTerminalView? {
        guard let tab = workspace.activeTab,
              let sessionID = tab.root.sessionID(ofPane: tab.activePaneID) else { return nil }
        return sessionManager.terminalView(for: sessionID)
    }
}
