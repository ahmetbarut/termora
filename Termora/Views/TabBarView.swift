import SwiftUI

/// Sekme çubuğunun saf yerleşim hesapları (test edilebilir).
enum TabBarLayout {
    static let height: CGFloat = 28
    static let newTabButtonWidth: CGFloat = 28
    static let maxTabWidth: CGFloat = 200
    static let minTabWidth: CGFloat = 72

    /// Sekmeler kalan genişliği eşit paylaşır; 200'ü aşmaz, 72'nin altına inmez.
    static func tabWidth(availableWidth: CGFloat, tabCount: Int) -> CGFloat {
        guard tabCount > 0 else { return 0 }
        let usable = max(0, availableWidth)
        let equalShare = usable / CGFloat(tabCount)
        return min(maxTabWidth, max(minTabWidth, equalShare))
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
            let width = TabBarLayout.tabWidth(
                availableWidth: proxy.size.width - TabBarLayout.newTabButtonWidth,
                tabCount: workspace.tabs.count
            )
            HStack(spacing: 0) {
                ForEach(workspace.tabs) { tab in
                    tabItem(tab, width: width)
                    Divider().frame(height: TabBarLayout.height * 0.6)
                }
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
                    .truncationMode(.middle)
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
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
                .accessibilityLabel("Sekmeyi kapat")
            }
        }
        .padding(.horizontal, 8)
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
        .help("Yeni sekme (⌘T)")
        .contextMenu {
            if workspace.profiles.profiles.isEmpty {
                Text("Profil yok")
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
