import SwiftUI
import Testing
@testable import Termora

/// briefs/1 ve briefs/2 "Erişilebilirlik": *Sistem font büyüklüğü tercihleri dikkate
/// alınmalı.*
///
/// Terminal fontu bunun DIŞINDA: onun boyutu kullanıcının kendi ayarı ve sistem yazı
/// boyutuyla büyürse terminalin sütun sayısı kullanıcının haberi olmadan değişir.
@Suite("Dynamic Type")
struct DynamicTypeTests {

    @Test func interfaceTextScalesWithTheSystemPreference() {
        let base = 13.0
        #expect(DynamicTypeScale.scaled(base, for: .large) == base)
        #expect(DynamicTypeScale.scaled(base, for: .xxxLarge) > base)
        #expect(DynamicTypeScale.scaled(base, for: .xSmall) < base)
    }

    /// Ölçek sınırlı: sistem "accessibility" boyutlarında arayüz büyür ama düzen
    /// bozulacak kadar değil. Sınırsız ölçek, dar pencerede her satırı sarardı.
    @Test func theScaleIsBoundedSoTheLayoutSurvives() {
        let base = 13.0
        let largest = DynamicTypeScale.scaled(base, for: .accessibility5)
        #expect(largest <= base * DynamicTypeScale.maximumFactor)
        #expect(largest > base)
    }

    /// Terminal fontu sistem tercihini İZLEMEZ: boyutu kullanıcının kendi ayarıdır ve
    /// sistemle büyürse terminalin sütun sayısı haber verilmeden değişir.
    @Test func theTerminalFontIgnoresTheSystemPreference() {
        #expect(DynamicTypeScale.appliesToTerminalFont == false)
    }
}
