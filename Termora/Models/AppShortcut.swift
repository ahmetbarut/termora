import SwiftUI

/// Menüde bir komuta bağlı tek bir klavye kısayolu.
///
/// `id` kalıcıdır: Keybindings ekranı kullanıcının değiştirdiği kısayolu bu kimlikle
/// saklayacak, yani başlık çevrildiğinde ya da değiştiğinde kayıt bozulmaz.
struct AppShortcut: Identifiable, Equatable {
    let id: String
    let title: String
    let key: KeyEquivalent
    let modifiers: EventModifiers

    /// Çakışma karşılaştırmasının anahtarı: aynı tuş + aynı değiştirici = aynı vuruş.
    /// `KeyEquivalent` `Equatable` olmadığı için karakter üzerinden yazılır.
    var stroke: String { "\(key.character)-\(modifiers.rawValue)" }

    static func == (lhs: AppShortcut, rhs: AppShortcut) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.stroke == rhs.stroke
    }
}

extension View {
    /// Menü öğesine kataloğdaki kısayolu bağlar. Menüler tuşları doğrudan yazmak yerine
    /// bunu kullanır; aksi hâlde çakışma testi kataloğu ölçer, menüyü değil.
    func shortcut(_ shortcut: AppShortcut) -> some View {
        keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
    }
}

/// Uygulamanın bütün menü kısayolları. Menüler (`AppCommands`) bu kataloğu okur; katalog
/// tek doğruluk kaynağı olduğu için çakışma denetimi gerçek menüyü ölçer.
///
/// briefs/2 "Ayarlar Ekranı": *Klavye kısayolları çakıştığında kullanıcı uyarılmalıdır.*
enum AppShortcuts {

    // MARK: - File

    static let newTab = AppShortcut(
        id: "newTab", title: "New Tab", key: "t", modifiers: .command
    )
    /// Aktif sekme varken sekmeyi, yoksa pencereyi kapatır — tek öğe, tek kısayol.
    static let closeTabOrWindow = AppShortcut(
        id: "closeTabOrWindow", title: "Close Tab / Close Window", key: "w", modifiers: .command
    )

    // MARK: - Edit

    static let find = AppShortcut(
        id: "find", title: "Find…", key: "f", modifiers: .command
    )
    static let findNext = AppShortcut(
        id: "findNext", title: "Find Next", key: "g", modifiers: .command
    )
    static let findPrevious = AppShortcut(
        id: "findPrevious", title: "Find Previous", key: "g", modifiers: [.command, .shift]
    )

    // MARK: - View

    static let toggleSidebar = AppShortcut(
        id: "toggleSidebar", title: "Show / Hide Sidebar", key: "s", modifiers: [.command, .shift]
    )
    static let toggleAIPanel = AppShortcut(
        id: "toggleAIPanel", title: "Show / Hide AI Assistant", key: "a", modifiers: [.command, .shift]
    )
    static let explainSelection = AppShortcut(
        id: "explainSelection", title: "Explain Selection with AI", key: "e", modifiers: [.command, .shift]
    )
    /// Paletin ikinci kısayolu (⌘⇧P) menüde değil, pencere düzeyinde
    /// `CommandPaletteHotkeyMonitor`'da karşılanır: bir menü öğesi tek kısayol taşır.
    static let commandPalette = AppShortcut(
        id: "commandPalette", title: "Command Palette…", key: "k", modifiers: .command
    )

    // MARK: - Shell

    static let clearScreen = AppShortcut(
        id: "clearScreen", title: "Clear Screen", key: "k", modifiers: [.command, .shift]
    )
    static let restartSession = AppShortcut(
        id: "restartSession", title: "Restart Session", key: "r", modifiers: .command
    )
    static let restartWithDefaultShell = AppShortcut(
        id: "restartWithDefaultShell", title: "Restart with Default Shell", key: "r", modifiers: [.command, .shift]
    )

    // MARK: - Pane

    static let splitVertically = AppShortcut(
        id: "splitVertically", title: "Split Vertically", key: "d", modifiers: .command
    )
    static let splitHorizontally = AppShortcut(
        id: "splitHorizontally", title: "Split Horizontally", key: "d", modifiers: [.command, .shift]
    )
    static let closePane = AppShortcut(
        id: "closePane", title: "Close Pane", key: "w", modifiers: [.command, .shift]
    )
    static let focusPaneLeft = AppShortcut(
        id: "focusPaneLeft", title: "Focus Pane Left", key: .leftArrow, modifiers: [.command, .option]
    )
    static let focusPaneRight = AppShortcut(
        id: "focusPaneRight", title: "Focus Pane Right", key: .rightArrow, modifiers: [.command, .option]
    )
    static let focusPaneUp = AppShortcut(
        id: "focusPaneUp", title: "Focus Pane Up", key: .upArrow, modifiers: [.command, .option]
    )
    static let focusPaneDown = AppShortcut(
        id: "focusPaneDown", title: "Focus Pane Down", key: .downArrow, modifiers: [.command, .option]
    )

    // MARK: - Tab

    static let nextTab = AppShortcut(
        id: "nextTab", title: "Next Tab", key: "]", modifiers: [.command, .shift]
    )
    static let previousTab = AppShortcut(
        id: "previousTab", title: "Previous Tab", key: "[", modifiers: [.command, .shift]
    )

    /// briefs/1 "Sekmeler": `⌘1–9` sekmeler arasında geçiş.
    static let tabSelection: [AppShortcut] = (1...9).map { number in
        AppShortcut(
            id: "selectTab\(number)",
            title: "Tab \(number)",
            key: KeyEquivalent(Character("\(number)")),
            modifiers: .command
        )
    }

    static let all: [AppShortcut] = [
        newTab, closeTabOrWindow,
        find, findNext, findPrevious,
        toggleSidebar, toggleAIPanel, explainSelection, commandPalette,
        clearScreen, restartSession, restartWithDefaultShell,
        splitVertically, splitHorizontally, closePane,
        focusPaneLeft, focusPaneRight, focusPaneUp, focusPaneDown,
        nextTab, previousTab,
    ] + tabSelection

    /// Aynı vuruşu paylaşan komut grupları. Boş dizi = çakışma yok.
    static func conflicts(in shortcuts: [AppShortcut] = all) -> [[AppShortcut]] {
        Dictionary(grouping: shortcuts, by: \.stroke)
            .values
            .filter { $0.count > 1 }
            .sorted { ($0.first?.id ?? "") < ($1.first?.id ?? "") }
    }
}
