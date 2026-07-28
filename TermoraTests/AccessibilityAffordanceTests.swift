import Testing
@testable import Termora

/// brief 3 "Erişilebilirlik → Sadece renkle durum anlatılmamalı" + "Tüm butonlarda
/// VoiceOver etiketi bulunmalı".
///
/// Görünümün kendisi test edilemez, ama görünümün OKUDUĞU karar saf tutulursa test edilebilir:
/// her durum göstergesi renk DIŞINDA en az bir ayırt edici sinyal (metin + simge) taşımalı ve
/// ikon-yalnız düğmelerin etiketi hangi nesneye ait olduğunu söylemeli.
@MainActor
@Suite("Renk dışı durum göstergeleri ve VoiceOver etiketleri")
struct AccessibilityAffordanceTests {

    // MARK: - Status bar: çalışıyor / boşta

    @Test func busyStateIsDerivedFromTheSnapshotFlag() {
        #expect(ProcessActivity(isBusy: true) == .running)
        #expect(ProcessActivity(isBusy: false) == .idle)
    }

    /// Kritik: yeşil/gri nokta TEK sinyal olamaz. İki durum hem görünen metinde hem de
    /// SF Symbol adında farklı olmalı — renk körü kullanıcı şekilden ayırt eder.
    @Test func theTwoStatesDifferInTextAndInShapeNotOnlyInColour() {
        #expect(ProcessActivity.running.text != ProcessActivity.idle.text)
        #expect(ProcessActivity.running.symbolName != ProcessActivity.idle.symbolName)
    }

    @Test func everyStateHasVisibleTextBesideTheDot() {
        for state in ProcessActivity.allCases {
            #expect(!state.text.isEmpty, "Metinsiz durum: \(state)")
        }
    }

    /// VoiceOver etiketi durumu tam cümleyle söyler; "running" tek başına bağlamsızdır.
    @Test func everyStateHasADistinctSpokenLabel() {
        let labels = ProcessActivity.allCases.map(\.accessibilityLabel)
        #expect(Set(labels).count == ProcessActivity.allCases.count)
        for label in labels {
            #expect(label.count > "running".count, "Konuşulan etiket çok kısa: \(label)")
        }
    }

    // MARK: - Sekme çubuğu etiketleri

    /// Ekranda beş "Close Tab" düğmesi varsa VoiceOver kullanıcısı hangisinin hangi sekmeye
    /// ait olduğunu bilemez; etiket sekmenin başlığını taşımalı.
    @Test func theCloseButtonLabelNamesItsOwnTab() {
        let label = TabAccessibility.closeLabel(title: "zsh — ~/Projects")
        #expect(label.contains("zsh — ~/Projects"))
        #expect(label != TabAccessibility.closeLabel(title: "vim"))
    }

    @Test func theTabLabelNamesTheTabAndItsPosition() {
        let label = TabAccessibility.tabLabel(title: "zsh", index: 0, total: 3)
        #expect(label.contains("zsh"))
        #expect(label.contains("1"))
        #expect(label.contains("3"))
    }

    /// Boş başlıklı sekme sessiz kalmamalı.
    @Test func anEmptyTitleStillProducesASpokenLabel() {
        #expect(!TabAccessibility.tabLabel(title: "", index: 0, total: 1).isEmpty)
        #expect(!TabAccessibility.closeLabel(title: "").isEmpty)
    }
}
