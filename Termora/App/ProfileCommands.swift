import SwiftUI

/// File menüsüne "New Tab with Profile" alt menüsünü ekler.
/// Hedef pencere, `@FocusedValue(\.workspace)` ile key window'un view model'idir.
struct ProfileCommands: Commands {
    let profiles: ProfileStore

    @FocusedValue(\.workspace) private var workspace

    private static let title = "New Tab with Profile"

    var body: some Commands {
        CommandGroup(after: .newItem) {
            // `Menu { … }.disabled(…)` macOS'ta üst menü öğesini SOLUKLAŞTIRMIYOR (elle
            // doğrulandı: öğe etkin görünüyor ve boş bir alt menü açıyor). Bu yüzden
            // seçilecek profil yokken alt menü yerine devre dışı tek bir öğe çizilir —
            // `Button`'daki `.disabled` menü çubuğunda doğru çalışıyor (bkz. AppCommands).
            if profiles.profiles.isEmpty || workspace == nil {
                Button(Self.title) {}
                    .disabled(true)
            } else {
                Menu(Self.title) {
                    ForEach(profiles.profiles) { profile in
                        Button(profile.name.isEmpty ? "Untitled Profile" : profile.name) {
                            workspace?.newTab(profile: profile)
                        }
                    }
                }
            }
        }
    }
}
