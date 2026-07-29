import SwiftUI
import Testing
@testable import Termora

/// briefs/2 "Ayarlar Ekranı": *Klavye kısayolları çakıştığında kullanıcı uyarılmalıdır.*
///
/// Uyarabilmenin ön koşulu, kısayolların tek bir yerde sayılabilir olmasıdır. Menüler
/// `AppShortcuts` üzerinden kurulduğu için buradaki testler gerçek menüyü ölçer: menüye
/// elle eklenmiş ikinci bir ⌘T bu paketten kaçamaz.
@Suite("Klavye kısayolu kataloğu")
struct AppShortcutTests {

    @Test func noTwoCommandsClaimTheSameKeyStroke() {
        let conflicts = AppShortcuts.conflicts()
        // Çakışma varsa hangi komutlar olduğu mesajda görünsün; yoksa "bir yerde çakışma
        // var" deyip test edeni kataloğu elle taramaya bırakırdık.
        let described = conflicts
            .map { group in group.map(\.title).joined(separator: " ↔ ") }
            .joined(separator: ", ")
        #expect(conflicts.isEmpty, "Çakışan kısayollar: \(described)")
    }

    @Test func everyShortcutIsNamedAndIdentifiable() {
        for shortcut in AppShortcuts.all {
            #expect(!shortcut.title.isEmpty)
            #expect(!shortcut.id.isEmpty)
        }
        #expect(Set(AppShortcuts.all.map(\.id)).count == AppShortcuts.all.count)
    }

    /// briefs/1 "Sekmeler": `⌘1–9` sekmeler arasında geçiş.
    @Test func tabSelectionCoversOneThroughNine() {
        let strokes = AppShortcuts.tabSelection.map(\.stroke)
        #expect(AppShortcuts.tabSelection.count == 9)
        #expect(strokes == (1...9).map { "\($0)-\(EventModifiers.command.rawValue)" })
    }

    /// briefs/1'in adıyla saydığı kısayollar kataloğa girmiş olmalı; biri düşerse menüden
    /// de düşmüş demektir.
    @Test func theShortcutsTheBriefNamesAreAllPresent() {
        let strokes = Set(AppShortcuts.all.map(\.stroke))
        let command = EventModifiers.command.rawValue
        let commandShift = EventModifiers([.command, .shift]).rawValue
        #expect(strokes.contains("t-\(command)"))          // ⌘T yeni sekme
        #expect(strokes.contains("w-\(command)"))          // ⌘W sekmeyi kapat
        #expect(strokes.contains("]-\(commandShift)"))     // ⌘⇧] sonraki sekme
        #expect(strokes.contains("[-\(commandShift)"))     // ⌘⇧[ önceki sekme
        #expect(strokes.contains("d-\(command)"))          // ⌘D dikey böl
        #expect(strokes.contains("d-\(commandShift)"))     // ⌘⇧D yatay böl
        #expect(strokes.contains("f-\(command)"))          // ⌘F arama
    }
}
