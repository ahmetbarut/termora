//
//  TermoraTerminalView.swift
//  Termora
//

import AppKit
import Foundation
import SwiftTerm

// MARK: - Context menu model

/// One entry of the terminal right-click menu. Pure data so the ordering and the
/// enabled/disabled rules can be tested without an NSMenu or a live PTY.
struct TerminalContextMenuItem: Equatable {
    enum Command: Equatable {
        case copy, paste, selectAll, searchSelection, openLink, copyLink, explainWithAI,
             clearScreen, splitRight, splitDown
    }

    let command: Command
    let title: String
    let isEnabled: Bool
}

/// Brief 3 "Sağ Tık Menüleri". Unavailable entries stay visible but disabled, so the
/// menu never changes shape under the cursor.
enum TerminalContextMenu {

    /// Ctrl-L. It goes to the PTY, not to the emulator: the shell's line editor clears the
    /// screen *and redraws its prompt*. Feeding `ESC[2J ESC[H` to the emulator instead would
    /// wipe the prompt off the screen and leave the user staring at an empty pane.
    static let clearScreenInput = "\u{0C}"

    /// Menu entries grouped into sections; the caller draws a separator between sections.
    /// - Parameter hasLink: imlecin ALTINDA bir bağlantı var mı. Seçime değil tıklanan
    ///   hücreye bağlıdır: seçim olmadan da bir URL'in üstüne sağ tıklanabilir.
    static func sections(hasSelection: Bool,
                         canPaste: Bool,
                         canSplit: Bool,
                         hasLink: Bool) -> [[TerminalContextMenuItem]] {
        [
            [
                TerminalContextMenuItem(command: .copy, title: "Copy", isEnabled: hasSelection),
                TerminalContextMenuItem(command: .paste, title: "Paste", isEnabled: canPaste),
                TerminalContextMenuItem(command: .selectAll, title: "Select All", isEnabled: true),
                // Arama TEK SATIRDA çalışır; seçim yoksa aranacak bir şey de yok.
                TerminalContextMenuItem(command: .searchSelection,
                                        title: "Search Selection",
                                        isEnabled: hasSelection),
                TerminalContextMenuItem(command: .openLink, title: "Open Link", isEnabled: hasLink),
                TerminalContextMenuItem(command: .copyLink, title: "Copy Link", isEnabled: hasLink),
                // Seçilen metin AI panelinin bağlamına girer, bu yüzden seçim olmadan
                // anlamsızdır. Brief gereği gizlenmez: menü imlecin altında şekil değiştirmez.
                TerminalContextMenuItem(command: .explainWithAI,
                                        title: "Explain with AI",
                                        isEnabled: hasSelection),
            ],
            [
                TerminalContextMenuItem(command: .clearScreen, title: "Clear Screen", isEnabled: true),
            ],
            [
                TerminalContextMenuItem(command: .splitRight, title: "Split Right", isEnabled: canSplit),
                TerminalContextMenuItem(command: .splitDown, title: "Split Down", isEnabled: canSplit),
            ],
        ]
    }
}

// MARK: - View

/// `LocalProcessTerminalView` subclass with the four things Termora needs on top of SwiftTerm:
///
/// 1. It knows which session it renders, so `SessionManager` can route delegate callbacks
///    back to a `TerminalSession` from the `source` argument alone.
/// 2. It ignores zero and negative layout passes. SwiftUI hands an `NSViewRepresentable`
///    a 0x0 frame during transient layout; SwiftTerm would recompute a 0-column terminal
///    and push that size onto the PTY with `TIOCSWINSZ`, wrecking the running program.
/// 3. Spec §7 key handling: AppKit offers a ⌘ key equivalent to the key window's view
///    hierarchy *before* the main menu, so a terminal that handles ⌘ itself would swallow
///    ⌘T / ⌘W / ⌘D / ⌘F. Declining every ⌘ combination here hands them to the menu;
///    ⌘C / ⌘V keep working through the standard Edit menu and SwiftTerm's `copy(_:)`/`paste(_:)`.
/// 4. The right-click menu (brief 3). The pane-level entries are closures the SwiftUI host
///    installs, because an AppKit view has no way back into the view model on its own.
final class TermoraTerminalView: LocalProcessTerminalView {
    let sessionID: UUID

    /// Installed by `TerminalHostView`. Nil means the pane cannot split (the menu entries
    /// are then shown disabled rather than hidden).
    var onSplitRight: (() -> Void)?
    var onSplitDown: (() -> Void)?
    /// "Search Selection". Seçim metni BU görünümden okunur ve argüman olarak verilir:
    /// menü tıklanan panelde açılır, aktif panel başkası olabilir.
    var onSearchSelection: ((String) -> Void)?
    /// "Explain with AI". Nil ise öğe menüde kalır ama hiçbir şey yapmaz — AI paneli
    /// olmayan bir bağlamda (önizleme) çizilen terminal için doğru davranış budur.
    var onExplainWithAI: (() -> Void)?

    init(sessionID: UUID, frame: CGRect) {
        self.sessionID = sessionID
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("TermoraTerminalView is created in code only")
    }

    /// Ham PTY baytlarının musluğu (briefs/2 "Komut Blokları").
    ///
    /// Komut blokları "şu bayt hangi komutun çıktısı?" sorusuna cevap vermek zorunda ve
    /// SwiftTerm'ün OSC kancası buna yetmez: kanca ayrıştırma sırasında ateşlenir ama
    /// oturum durumu MainActor'a ait olduğu için bir `Task`'e ertelenir — işaretler
    /// baytlardan SONRA gelir. Burası akışın SIRASI BOZULMAMIŞ tek noktası.
    ///
    /// Nil iken hiçbir ek iş yapılmaz: blok paneli kapalıyken terminal tam eskisi gibi
    /// çalışır.
    var onDataReceived: ((ArraySlice<UInt8>) -> Void)?

    /// Musluk ÖNCE terminale verir: blok kaydı bir gün hata verse bile terminalin kendisi
    /// baytları almış olur. Terminal her şeyden önce terminaldir.
    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        onDataReceived?(slice)
    }

    override func setFrameSize(_ newSize: NSSize) {
        guard newSize.width > 0, newSize.height > 0 else { return }
        super.setFrameSize(newSize)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) { return false }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: Right-click menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let canPaste = NSPasteboard.general.string(forType: .string)?.isEmpty == false
        // Menü AÇILIRKEN bir kez çözülür. Eylem anında yeniden çözmek, terminal bu arada
        // kaydırıldıysa BAŞKA bir bağlantıyı açardı: kullanıcı gördüğü satırı onaylıyor.
        linkUnderCursor = resolveLink(at: event)
        let sections = TerminalContextMenu.sections(hasSelection: selectionActive,
                                                    canPaste: canPaste,
                                                    canSplit: onSplitRight != nil && onSplitDown != nil,
                                                    hasLink: linkUnderCursor != nil)

        let menu = NSMenu()
        // Items are enabled from the model above; letting AppKit auto-validate would send
        // these selectors up the responder chain and re-enable Copy without a selection.
        menu.autoenablesItems = false

        for (index, section) in sections.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for item in section {
                let menuItem = NSMenuItem(title: item.title,
                                          action: Self.selector(for: item.command),
                                          keyEquivalent: "")
                menuItem.target = self
                menuItem.isEnabled = item.isEnabled
                menu.addItem(menuItem)
            }
        }
        return menu
    }

    private static func selector(for command: TerminalContextMenuItem.Command) -> Selector {
        switch command {
        case .copy: return #selector(copy(_:))
        case .paste: return #selector(paste(_:))
        case .selectAll: return #selector(selectAll(_:))
        case .searchSelection: return #selector(searchSelection(_:))
        case .openLink: return #selector(openLinkUnderCursor(_:))
        case .copyLink: return #selector(copyLinkUnderCursor(_:))
        case .explainWithAI: return #selector(explainWithAI(_:))
        case .clearScreen: return #selector(clearScreen(_:))
        case .splitRight: return #selector(splitRight(_:))
        case .splitDown: return #selector(splitDown(_:))
        }
    }

    @objc private func clearScreen(_ sender: Any?) {
        send(txt: TerminalContextMenu.clearScreenInput)
    }

    @objc private func searchSelection(_ sender: Any?) {
        guard let selection = getSelection(), !selection.isEmpty else { return }
        onSearchSelection?(selection)
    }

    @objc private func explainWithAI(_ sender: Any?) {
        onExplainWithAI?()
    }

    // MARK: Bağlantılar (briefs/3 "Sağ Tık Menüleri")

    /// Menü açılırken çözülen bağlantı. Eylem anında değil AÇILIŞ anında saptanır.
    private var linkUnderCursor: String?

    @objc private func openLinkUnderCursor(_ sender: Any?) {
        guard let link = linkUnderCursor, let url = URL(string: link) else { return }
        // Şema BEYAZ LİSTEDEN geçer: terminal çıktısı düşmanca olabilir ve `file://` ya da
        // özel bir şema, tek tıkla keyfi bir uygulamayı açmaya dönüşürdü.
        guard let scheme = url.scheme?.lowercased(),
              Self.openableLinkSchemes.contains(scheme) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func copyLinkUnderCursor(_ sender: Any?) {
        guard let link = linkUnderCursor else { return }
        // Kopyalamada şema kısıtı YOK: panoya yazmak hiçbir şeyi çalıştırmaz.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
    }

    /// Tek tıkla açılmasına izin verilen şemalar.
    private static let openableLinkSchemes: Set<String> = ["http", "https", "mailto"]

    /// İmlecin altındaki bağlantı, yoksa nil.
    ///
    /// Hücre ölçüsü fonttan hesaplanır (SwiftTerm'ün formülü `internal`) ve SwiftTerm'ün
    /// KENDİ bildirdiği piksel boyutuna karşı DOĞRULANIR. Uyuşmazlık, çoğaltılan formülün
    /// ayrıştığı anlamına gelir; o durumda bağlantı çözülmez ve öğeler disabled kalır —
    /// yanlış bir URL açmaktansa hiç açmamak doğrudur.
    private func resolveLink(at event: NSEvent) -> String? {
        let terminal = getTerminal()
        let glyph = font.glyph(withName: "W")
        guard let cellSize = TerminalCellGeometry.cellSize(
                ascent: CTFontGetAscent(font),
                descent: CTFontGetDescent(font),
                leading: CTFontGetLeading(font),
                advanceWidth: font.advancement(forGlyph: glyph).width,
                lineSpacing: lineSpacing),
              let reported = cellSizeInPixels(source: terminal),
              TerminalCellGeometry.agrees(cellSize: cellSize,
                                          withPixelSize: reported,
                                          scale: window?.backingScaleFactor ?? 1),
              let hit = TerminalCellGeometry.cell(at: convert(event.locationInWindow, from: nil),
                                                  viewHeight: bounds.height,
                                                  cellSize: cellSize,
                                                  cols: terminal.cols,
                                                  rows: terminal.rows)
        else { return nil }

        // `.screen`: satır GÖRÜNÜR alana göredir, kaydırma ofsetini SwiftTerm ekler.
        return terminal.link(at: .screen(Position(col: hit.col, row: hit.row)),
                             mode: .explicitAndImplicit)
    }

    @objc private func splitRight(_ sender: Any?) {
        onSplitRight?()
    }

    @objc private func splitDown(_ sender: Any?) {
        onSplitDown?()
    }
}
