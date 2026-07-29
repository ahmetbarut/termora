import Testing
@testable import Termora

/// briefs/3 "Sidebar".
///
/// Sidebar, komut paletinin Workspaces / Folders / SSH / Docker kategorileriyle aynı
/// kayıtları gösterir. Bu yüzden kendi listesini kurmaz, paletin öğelerini gruplar —
/// iki yüzeyin ayrışması (paletten açılan bir workspace'in sidebar'da görünmemesi)
/// böylece mümkün değil.
@MainActor
@Suite("Sidebar")
struct SidebarTests {

    private func item(_ id: String, _ category: CommandPaletteCategory) -> CommandPaletteItem {
        CommandPaletteItem(id: id, title: id, category: category, symbolName: "circle", action: {})
    }

    // MARK: - Genişlik (briefs/3: min 220, varsayılan 260, maks 380)

    @Test func widthIsClampedToTheBriefsRange() {
        #expect(SettingsLimits.clampSidebarWidth(10) == 220)
        #expect(SettingsLimits.clampSidebarWidth(1000) == 380)
        #expect(SettingsLimits.clampSidebarWidth(300) == 300)
        #expect(SettingsLimits.clampSidebarWidth(.nan) == 260)
    }

    @Test func theSidebarStartsClosedAtTheDefaultWidth() {
        let settings = AppSettings()
        // briefs/3: "Sidebar varsayılan olarak kapalı olabilir." Yeni kullanıcı yalnız
        // terminali görmeli (briefs/3 "Aşamalı Karmaşıklık").
        #expect(settings.isSidebarVisible == false)
        #expect(settings.sidebarWidth == 260)
    }

    // MARK: - Bölümler

    @Test func sectionsFollowTheOrderTheBriefLists() {
        #expect(SidebarSection.allCases.map(\.title)
                == ["Workspaces", "Recent Folders", "SSH Hosts", "Docker"])
    }

    @Test func eachSectionCollectsItsOwnPaletteCategory() {
        let items = [
            item("w1", .workspaces), item("f1", .folders), item("f2", .folders),
            item("s1", .ssh), item("d1", .docker),
            // Sidebar'a ait olmayan kategoriler: paletin kendi işleri.
            item("a1", .actions), item("t1", .themes), item("set1", .settings),
        ]
        let sections = SidebarCatalog.sections(from: items)

        #expect(sections.map(\.section) == SidebarSection.allCases)
        #expect(sections.first { $0.section == .folders }?.items.map(\.id) == ["f1", "f2"])
        #expect(sections.first { $0.section == .workspaces }?.items.map(\.id) == ["w1"])
        #expect(sections.flatMap(\.items).map(\.id).contains("a1") == false)
    }

    /// Kayıt yokken bölüm gizlenmez: kullanıcı SSH hostu olmadığını görebilmeli, yoksa
    /// sidebar'ın neden boş olduğunu anlayamaz (briefs/3 "Empty State").
    @Test func aSectionWithNoRecordsSurvivesSoItsEmptyStateCanBeShown() {
        let sections = SidebarCatalog.sections(from: [item("w1", .workspaces)])
        #expect(sections.count == SidebarSection.allCases.count)
        #expect(sections.first { $0.section == .ssh }?.items.isEmpty == true)
    }

    /// briefs/3 "Küçük Pencere Davranışı": *Terminal alanı korunmalı.* AI panelinde olduğu
    /// gibi, sidebar açılırken pencerenin alt sınırı sidebar kadar büyür — yoksa 720 pt'lik
    /// bir pencerede sidebar terminalin üçte birini yerdi.
    @Test func openingTheSidebarRaisesTheWindowsMinimumWidth() {
        // `Double(...)`: `minWidth` CGFloat, sidebar aralığı Double. Karışık aritmetik
        // derlenmez ve #expect içinde iki taraf AnyHashable'a kutulandığı için, örtük
        // dönüşüm olsaydı bile değerler eşitken karşılaştırma başarısız olurdu.
        let bare = Double(WindowLayout.minWidth(withAIPanel: false, withSidebar: false))
        let withSidebar = Double(WindowLayout.minWidth(withAIPanel: false, withSidebar: true))
        #expect(bare == Double(WindowLayout.minWidth))
        #expect(withSidebar == Double(WindowLayout.minWidth) + SettingsLimits.sidebarWidthRange.lowerBound)
    }

    @Test func theSidebarAndTheAIPanelBothWidenTheWindow() {
        let both = Double(WindowLayout.minWidth(withAIPanel: true, withSidebar: true))
        #expect(both == Double(WindowLayout.minWidth)
                + Double(AIPanelLayout.minWidth)
                + SettingsLimits.sidebarWidthRange.lowerBound)
    }

    @Test func everySectionCarriesATitleAndASymbol() {
        for section in SidebarSection.allCases {
            #expect(!section.title.isEmpty)
            #expect(!section.symbolName.isEmpty)
            #expect(!section.emptyMessage.isEmpty)
        }
    }
}
