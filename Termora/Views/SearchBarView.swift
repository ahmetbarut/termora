import SwiftUI

/// Sekmenin üstünde ⌘F ile açılan arama çubuğu.
struct SearchBarView: View {
    @Bindable var tab: TerminalTab
    let workspace: WorkspaceViewModel

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find", text: $tab.searchQuery.term)
                .textFieldStyle(.plain)
                .focused($isFieldFocused)
                .onSubmit { workspace.findNextMatch() }
                .frame(minWidth: 140)

            Text(SearchSummaryFormatter.text(tab.searchSummary))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 48, alignment: .trailing)

            Button { workspace.findPreviousMatch() } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .help("Previous match (⇧⌘G)")
            .disabled(tab.searchQuery.term.isEmpty)

            Button { workspace.findNextMatch() } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .help("Next match (⌘G)")
            .disabled(tab.searchQuery.term.isEmpty)

            Divider().frame(height: 14)

            Toggle("Aa", isOn: $tab.searchQuery.caseSensitive)
                .toggleStyle(.button)
                .help("Match case")
            Toggle(".*", isOn: $tab.searchQuery.usesRegex)
                .toggleStyle(.button)
                .help("Regular expression")
            Toggle("W", isOn: $tab.searchQuery.wholeWord)
                .toggleStyle(.button)
                .help("Whole word only")

            Button { workspace.closeSearch() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Close (Esc)")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .onAppear {
            // @FocusState'i çubuğun eklendiği güncelleme turunda atamak güvenilir değil:
            // çubuk İKİNCİ kez açıldığında odak terminalde kalıyor, yazılan metin kabuğa
            // gidiyor ve Esc çubuğu kapatmıyordu (onExitCommand odağın çubukta olmasını
            // ister). Odağı bir sonraki run-loop turunda iste.
            DispatchQueue.main.async { isFieldFocused = true }
        }
        .onChange(of: tab.searchQuery) { _, _ in
            workspace.refreshSearchSummary()
        }
        .onExitCommand {
            workspace.closeSearch()
        }
    }
}
