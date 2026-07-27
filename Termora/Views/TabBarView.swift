import SwiftUI

/// Sekme çubuğunun saf yerleşim hesapları (test edilebilir).
enum TabBarLayout {
    static let height: CGFloat = 28
    static let newTabButtonWidth: CGFloat = 28
    static let maxTabWidth: CGFloat = 200
    static let minTabWidth: CGFloat = 72
    static let dividerWidth: CGFloat = 1

    /// Bu genişliğin altında sekme yalnız kısaltılmış bir başlığa yer bırakır.
    static let compactTabWidth: CGFloat = 110

    /// Sekmeler kalan genişliği eşit paylaşır; 200'ü aşmaz, 72'nin altına inmez.
    static func tabWidth(availableWidth: CGFloat, tabCount: Int) -> CGFloat {
        guard tabCount > 0 else { return 0 }
        let usable = max(0, availableWidth)
        let equalShare = usable / CGFloat(tabCount)
        return min(maxTabWidth, max(minTabWidth, equalShare))
    }

    /// Dar sekmede başlık kısalır ve yatay iç boşluk azalır (brief 3, "Küçük Pencere Davranışı").
    static func isCompact(tabWidth: CGFloat) -> Bool {
        tabWidth < compactTabWidth
    }

    /// Kaç sekme en küçük genişlikte tam görünür — bunun ötesi kaydırılarak gezilir.
    /// Terminal alanı hiç daralmaz: çubuk sabit yüksekliktedir ve taşan sekmeler kaydırılır.
    static func fittingTabCount(availableWidth: CGFloat) -> Int {
        let usable = max(0, availableWidth - newTabButtonWidth)
        return max(1, Int(usable / minTabWidth))
    }

    /// Sekme şeridinin toplam genişliği (ayırıcılar dahil).
    static func stripWidth(tabWidth: CGFloat, tabCount: Int) -> CGFloat {
        guard tabCount > 0 else { return 0 }
        return CGFloat(tabCount) * (tabWidth + dividerWidth)
    }
}

/// Elle çizilen sekme çubuğu (macOS 14'te NSWindow tab bar'ı kullanılmaz).
struct TabBarView: View {
    let workspace: WorkspaceViewModel

    @State private var hoveredTabID: UUID?
    @State private var editingTabID: UUID?
    @State private var editingText: String = ""
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let available = proxy.size.width - TabBarLayout.newTabButtonWidth
            let width = TabBarLayout.tabWidth(availableWidth: available, tabCount: workspace.tabs.count)
            let stripWidth = min(TabBarLayout.stripWidth(tabWidth: width, tabCount: workspace.tabs.count),
                                 max(0, available))
            HStack(spacing: 0) {
                // Sekmeler taşarsa kaydırılır; "+" düğmesi her zaman erişilebilir kalır ve
                // terminal alanı bundan etkilenmez.
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(workspace.tabs) { tab in
                            tabItem(tab, width: width)
                            Divider().frame(height: TabBarLayout.height * 0.6)
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(width: stripWidth)

                newTabButton
                Spacer(minLength: 0)
            }
        }
        .frame(height: TabBarLayout.height)
        .background(.bar)
    }

    // MARK: - Parçalar

    private func tabItem(_ tab: TerminalTab, width: CGFloat) -> some View {
        let isActive = tab.id == workspace.activeTabID
        let isHovered = hoveredTabID == tab.id
        let isCompact = TabBarLayout.isCompact(tabWidth: width)

        return HStack(spacing: 4) {
            if editingTabID == tab.id {
                TextField("", text: $editingText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename(tab) }
                    .onChange(of: renameFieldFocused) { _, focused in
                        if !focused { commitRename(tab) }
                    }
            } else {
                Text(tab.displayTitle)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    // Dar pencerede baş taraf okunabilir kalsın diye sondan kısaltılır.
                    .truncationMode(isCompact ? .tail : .middle)
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    .help(tab.displayTitle)
            }

            Spacer(minLength: 0)

            if isHovered || isActive {
                Button {
                    workspace.requestCloseTab(id: tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Tab")
            }
        }
        .padding(.horizontal, isCompact ? 4 : 8)
        .frame(width: width, height: TabBarLayout.height)
        .background(isActive ? Color.accentColor.opacity(0.22) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isActive ? Color.accentColor : Color.clear)
                .frame(height: 2)
        }
        .contentShape(Rectangle())
        // XCUITest smoke testi (Task 13) sekmeleri bu önekle sayar.
        .accessibilityIdentifier("tab-\(tab.id)")
        .onHover { hovering in
            if hovering {
                hoveredTabID = tab.id
            } else if hoveredTabID == tab.id {
                hoveredTabID = nil
            }
        }
        .onTapGesture(count: 2) { beginRename(tab) }
        .onTapGesture { workspace.activeTabID = tab.id }
        // Sürükleyerek sıralama: taşınan sekmenin kimliği metin olarak taşınır, bırakılan
        // sekmenin yuvasına yerleşir. Sıra değişimini view model yapar (test edilebilir).
        .draggable(tab.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let identifier = items.first, let draggedID = UUID(uuidString: identifier) else { return false }
            workspace.moveTab(id: draggedID, toSlotOf: tab.id)
            return true
        }
    }

    private var newTabButton: some View {
        Button {
            workspace.newTab()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .frame(width: TabBarLayout.newTabButtonWidth, height: TabBarLayout.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("new-tab-button")
        .accessibilityLabel("New Tab")
        .help("New Tab (⌘T)")
        .contextMenu {
            if workspace.profiles.profiles.isEmpty {
                Text("No Profiles")
            } else {
                ForEach(workspace.profiles.profiles) { profile in
                    Button(profile.name) { workspace.newTab(profile: profile) }
                }
            }
        }
    }

    // MARK: - Yeniden adlandırma

    private func beginRename(_ tab: TerminalTab) {
        editingText = tab.customTitle ?? tab.displayTitle
        editingTabID = tab.id
        renameFieldFocused = true
    }

    private func commitRename(_ tab: TerminalTab) {
        guard editingTabID == tab.id else { return }
        editingTabID = nil
        workspace.renameTab(id: tab.id, to: editingText)
    }
}
