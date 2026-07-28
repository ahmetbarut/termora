import SwiftUI

/// Sekmenin üstünde ⌘F ile açılan arama çubuğu.
struct SearchBarView: View {
    @Bindable var tab: TerminalTab
    let workspace: WorkspaceViewModel

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Dekoratif: anlamı yandaki alanın etiketi taşır.
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Find", text: $tab.searchQuery.term)
                .textFieldStyle(.plain)
                .focused($isFieldFocused)
                .onSubmit { workspace.findNextMatch() }
                .frame(minWidth: 140)
                .accessibilityLabel("Search Term")

            // "3/12" gibi bir metin VoiceOver'da "üç bölü on iki" diye okunur; sayaç
            // ne anlama geldiğini kendi söylemeli.
            Text(SearchSummaryFormatter.text(tab.searchSummary))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 48, alignment: .trailing)
                .accessibilityLabel("Match count")
                .accessibilityValue(SearchSummaryFormatter.text(tab.searchSummary))

            Button { workspace.findPreviousMatch() } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .help("Previous match (⇧⌘G)")
            .accessibilityLabel("Previous Match")
            .disabled(tab.searchQuery.term.isEmpty)

            Button { workspace.findNextMatch() } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .help("Next match (⌘G)")
            .accessibilityLabel("Next Match")
            .disabled(tab.searchQuery.term.isEmpty)

            Divider().frame(height: 14)

            // Etiketler ("Aa", ".*", "W") gözle taranmak için kısaltılmıştır; VoiceOver
            // onları harf harf okur, bu yüzden her birine tam ad verilir.
            Toggle("Aa", isOn: $tab.searchQuery.caseSensitive)
                .toggleStyle(.button)
                .help("Match case")
                .accessibilityLabel("Match Case")

            Toggle(".*", isOn: $tab.searchQuery.usesRegex)
                .toggleStyle(.button)
                .help("Regular expression")
                .accessibilityLabel("Regular Expression")

            Toggle("W", isOn: $tab.searchQuery.wholeWord)
                .toggleStyle(.button)
                .help("Whole word only")
                .accessibilityLabel("Whole Word Only")

            Button { workspace.closeSearch() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Close (Esc)")
            .accessibilityLabel("Close Search")
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
