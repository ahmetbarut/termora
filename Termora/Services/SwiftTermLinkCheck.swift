import SwiftTerm

/// Build-time smoke check: SwiftTerm paketinin çözülüp linklendiğini garanti eder.
/// Task 8 gerçek SwiftTerm kullanımını (TermoraTerminalView) getirdiğinde silinir.
enum SwiftTermLinkCheck {
    static let terminalViewType: AnyClass = LocalProcessTerminalView.self
}
