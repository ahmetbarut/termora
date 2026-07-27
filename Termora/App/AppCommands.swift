import SwiftUI

/// Menü komutları key window'un WorkspaceViewModel'ine @FocusedValue ile ulaşır.
struct WorkspaceFocusedKey: FocusedValueKey {
    typealias Value = WorkspaceViewModel
}

extension FocusedValues {
    var workspace: WorkspaceViewModel? {
        get { self[WorkspaceFocusedKey.self] }
        set { self[WorkspaceFocusedKey.self] = newValue }
    }
}

struct AppCommands: Commands {
    @FocusedValue(\.workspace) private var workspace

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Yeni Sekme") {
                workspace?.newTab()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(workspace == nil)
        }

        // ⌘W standart "Close Window" öğesinin yerine geçer: önce sekme kapanır.
        CommandGroup(replacing: .saveItem) {
            Button("Sekmeyi Kapat") {
                if let workspace, let activeTabID = workspace.activeTabID {
                    workspace.requestCloseTab(id: activeTabID)
                }
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(workspace?.activeTabID == nil)
        }

        // DİKKAT: `Commands` protokolünde `disabled` YOKTUR (yalnız `View` üzerinde vardır);
        // `CommandMenu { … }.disabled(…)` derlenmez. Etkinlik her Button'a tek tek verilir.
        CommandMenu("Sekme") {
            Button("Sonraki Sekme") { workspace?.nextTab() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(workspace == nil)
            Button("Önceki Sekme") { workspace?.previousTab() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(workspace == nil)

            Divider()

            ForEach(1...9, id: \.self) { number in
                Button("Sekme \(number)") {
                    workspace?.selectTab(at: number - 1)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                .disabled(workspace == nil)
            }
        }
    }
}
