import AppKit
import Foundation
import SwiftTerm

/// Arama işlemlerinin uygulama tarafındaki sınırı. Gerçek uygulayıcı `SessionManager`,
/// testlerde çift kullanılır; böylece WorkspaceViewModel SwiftTerm'ü hiç görmez.
@MainActor
protocol TerminalSearchRunner: AnyObject {
    func findNext(sessionID: UUID, query: TerminalSearchQuery) -> Bool
    func findPrevious(sessionID: UUID, query: TerminalSearchQuery) -> Bool
    func matchSummary(sessionID: UUID, query: TerminalSearchQuery) -> SearchSummary
    func clearSearch(sessionID: UUID)
    func focusTerminal(sessionID: UUID)
}

extension TerminalSearchQuery {
    /// SwiftTerm'ün arama seçeneklerine çevirir (SwiftTerm `regex` diyor, biz `usesRegex`).
    var swiftTermOptions: SearchOptions {
        SearchOptions(caseSensitive: caseSensitive, regex: usesRegex, wholeWord: wholeWord)
    }
}

extension SessionManager: TerminalSearchRunner {
    func findNext(sessionID: UUID, query: TerminalSearchQuery) -> Bool {
        guard !query.term.isEmpty, let view = terminalView(for: sessionID) else { return false }
        return view.findNext(query.term, options: query.swiftTermOptions)
    }

    func findPrevious(sessionID: UUID, query: TerminalSearchQuery) -> Bool {
        guard !query.term.isEmpty, let view = terminalView(for: sessionID) else { return false }
        return view.findPrevious(query.term, options: query.swiftTermOptions)
    }

    func matchSummary(sessionID: UUID, query: TerminalSearchQuery) -> SearchSummary {
        guard !query.term.isEmpty, let view = terminalView(for: sessionID) else { return .empty }
        let result = view.searchMatchSummary(query.term, options: query.swiftTermOptions, limit: 1000)
        return SearchSummary(index: result.index, total: result.total)
    }

    func clearSearch(sessionID: UUID) {
        terminalView(for: sessionID)?.clearSearch()
    }

    /// Klavye odağını terminale geri verir. Çubuk kapanırken çağrıldığı için bir sonraki
    /// run-loop turuna ertelenir: SwiftUI aynı turda arama alanını söküyor ve senkron
    /// yapılan makeFirstResponder çağrısını geri alıyor.
    func focusTerminal(sessionID: UUID) {
        guard let view = terminalView(for: sessionID) else { return }
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
    }
}
