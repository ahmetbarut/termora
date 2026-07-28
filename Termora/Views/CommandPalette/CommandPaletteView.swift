import SwiftUI

/// Komut paleti (brief 3, "Komut Paleti Tasarımı").
///
/// Pencerenin üst orta bölümünde, en fazla 640 pt genişliğinde, arka planı bulanık bir
/// katman. Terminal ALTTA çalışmaya devam eder: palet hiçbir oturumu duraklatmaz, yalnız
/// klavye odağını geçici olarak alır.
struct CommandPaletteView: View {

    /// Paletin üst kenarının pencere üstünden uzaklığı.
    static let topInset: CGFloat = 64
    /// brief: "Maksimum genişlik: 640 pt".
    static let maxWidth: CGFloat = 640
    /// Liste bundan uzunsa kaydırılır; kısaysa panel içeriğe göre kısalır.
    static let maxListHeight: CGFloat = 360
    private static let cornerRadius: CGFloat = 12

    @Bindable var model: CommandPaletteModel
    let workspace: WorkspaceViewModel
    let settings: SettingsStore
    let themes: ThemeStore
    /// SSH kategorisi; nil ise palet SSH göstermez (testlerdeki varsayılan).
    var ssh: SSHHostStore?
    /// Folders kategorisi (briefs/2 "Hızlı Açma"); nil ise palet klasör göstermez.
    var folders: RecentFoldersStore?
    /// Aktif panelin çalışma dizini; favoriye alma komutu buna dayanır.
    var currentDirectory: @MainActor () -> String? = { nil }

    @Environment(\.openSettings) private var openSettings
    @FocusState private var isSearchFocused: Bool
    @State private var listContentHeight: CGFloat = 0

    private var items: [CommandPaletteItem] {
        CommandPaletteCatalog.items(workspace: workspace,
                                    settings: settings,
                                    themes: themes,
                                    ssh: ssh,
                                    folders: folders,
                                    currentDirectory: currentDirectory,
                                    openSettings: { openSettings() })
    }

    private var results: [CommandPaletteResult] {
        CommandPaletteFilter.results(items: items,
                                     query: model.query,
                                     recentIDs: model.recentIDs)
    }

    var body: some View {
        let results = self.results

        ZStack(alignment: .top) {
            // Paletin dışına tıklamak kapatır.
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture { model.dismiss() }

            panel(results: results)
                .frame(maxWidth: Self.maxWidth)
                .padding(.horizontal, 24)
                .padding(.top, Self.topInset)
        }
        .onAppear {
            // Diske BURADA bakılır, `items` içinde değil: `items` her çizimde çağrılıyor ve
            // çizim sırasında durum yazmak SwiftUI güncelleme döngüsü doğurur.
            // Silinmiş klasörler böylece palet AÇILIRKEN elenir (bkz. RecentFoldersStore).
            folders?.refreshAvailability()
            // @FocusState'i eklendiği güncelleme turunda atamak güvenilir değil: palet İKİNCİ
            // kez açıldığında odak terminalde kalıyor ve yazılan metin kabuğa gidiyordu
            // (aynı tuzak arama çubuğunda da yaşandı). Odağı bir sonraki tura ertele.
            DispatchQueue.main.async { isSearchFocused = true }
        }
        .onChange(of: model.query) { _, _ in
            model.clampSelection(resultCount: self.results.count)
        }
        .onExitCommand { model.dismiss() }
    }

    // MARK: - Panel

    private func panel(results: [CommandPaletteResult]) -> some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            if results.isEmpty {
                emptyState
            } else {
                resultList(results: results)
            }
        }
        // Bulanık zemin (brief: "Arka plan blur") + sistem penceresi tonu. Ton olmadan
        // panel, ALTINDAKİ terminal temasına göre açılıp koyulaşıyor ve açık temalarda
        // metin okunmaz hâle geliyordu; `windowBackgroundColor` sistem görünümünü izler.
        .background {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: Self.cornerRadius)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.62))
                }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(DesignTokens.border.color.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.32), radius: 24, y: 10)
        // ↑/↓ metin alanına takılmasın diye tuş işleyicisi panelin tamamındadır.
        .onKeyPress(.upArrow) { moveSelection(by: -1, resultCount: results.count) }
        .onKeyPress(.downArrow) { moveSelection(by: 1, resultCount: results.count) }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            TextField("Search commands", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isSearchFocused)
                .onSubmit { runSelected() }

            if !model.query.isEmpty {
                Button {
                    model.query = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
    }

    private var emptyState: some View {
        Text("No matching commands")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
    }

    private func resultList(results: [CommandPaletteResult]) -> some View {
        // Klavye seçimi DÜZ listenin indeksiyle çalışır; bölümler yalnız görsel gruplamadır.
        let indexByID = Dictionary(uniqueKeysWithValues: results.enumerated().map { ($1.id, $0) })
        let selectedIndex = model.selectedIndex

        // Satır sayısı azdır (bugün ~20); tembel yığın yerine düz VStack kullanılır ki her
        // satırın seçili hâli üst görünümün güncellemesiyle AYNI turda yeniden çizilsin.
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(CommandPaletteFilter.sections(for: results, query: model.query)) { section in
                        sectionHeader(section.title)
                        ForEach(section.results) { result in
                            CommandPaletteRow(result: result,
                                              isSelected: indexByID[result.id] == selectedIndex,
                                              showsCategory: isSearching,
                                              run: { model.run(result) })
                                .id(result.id)
                        }
                    }
                }
                .padding(.vertical, 6)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: PaletteContentHeightKey.self,
                                               value: proxy.size.height)
                    }
                )
            }
            .frame(height: min(max(listContentHeight, 1), Self.maxListHeight))
            .onPreferenceChange(PaletteContentHeightKey.self) { height in
                Task { @MainActor in listContentHeight = height }
            }
            .onChange(of: model.selectedIndex) { _, index in
                guard results.indices.contains(index) else { return }
                proxy.scrollTo(results[index].id, anchor: .center)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 3)
    }

    // MARK: - Klavye

    private var isSearching: Bool {
        !model.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func moveSelection(by delta: Int, resultCount: Int) -> KeyPress.Result {
        guard resultCount > 0 else { return .ignored }
        model.moveSelection(by: delta, resultCount: resultCount)
        return .handled
    }

    private func runSelected() {
        let results = self.results
        guard results.indices.contains(model.selectedIndex) else { return }
        model.run(results[model.selectedIndex])
    }
}

/// Listenin gerçek yüksekliği; panel içerik kadar uzar, `maxListHeight`'ta durur.
private struct PaletteContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Palet listesinin tek satırı.
///
/// Seçili olma bilgisi DIŞARIDAN değer olarak gelir: satırın kendi içinde
/// `model.selectedIndex` okunsaydı, satır yeniden çizilmeden seçim değişebilir ve
/// vurgulama listeyle tutarsız kalırdı (bu hata bir kez yaşandı).
private struct CommandPaletteRow: View {
    let result: CommandPaletteResult
    let isSelected: Bool
    /// Arama sırasında satırın hangi kategoriden geldiği yazılır; sorgu boşken zaten
    /// bölüm başlığı söylüyor.
    let showsCategory: Bool
    let run: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: result.item.symbolName)
                .font(.system(size: 13))
                .frame(width: 18)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)

            title
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer(minLength: 12)

            if showsCategory {
                Text(result.item.category.title)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary)
            }

            if let shortcut = result.item.shortcut {
                Text(shortcut)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isSelected ? Color.white.opacity(0.18)
                                             : DesignTokens.border.color.opacity(0.35))
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(background)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: run)
        // Fare geri bildirimi klavye seçiminden AYRIDIR: imlecin listenin üzerinde durması
        // Enter'ın ne çalıştıracağını değiştirmemelidir (brief: "Klavye ile tam kontrol").
        .onHover { isHovered = $0 }
        // Satır tek bir erişilebilirlik öğesidir; etiketi komutun kendisi söyler. İkon ve
        // vurgulama renkleri okunmadığı için (örn. favori ⭑ / son kullanılan ⏱ ayrımı)
        // etiket bu farkı KELİMEYLE taşır.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(result.item.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    /// Seçili satır markanın mavi→mor geçişiyle vurgulanır
    /// (brief 3: gradyan "aktif durum vurgusu" alanlarında kullanılabilir).
    @ViewBuilder
    private var background: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 7)
                .fill(LinearGradient(
                    colors: [DesignTokens.accentBlue.color, DesignTokens.accentViolet.color],
                    startPoint: .leading,
                    endPoint: .trailing))
        } else if isHovered {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(0.07))
        } else {
            Color.clear
        }
    }

    /// Eşleşen karakterler kalın ve vurgulu çizilir (fuzzy aramanın neden eşleştiğini gösterir).
    private var title: Text {
        let characters = Array(result.item.title)
        let matched = Set(result.matchedIndices)
        guard !matched.isEmpty else { return Text(result.item.title) }

        var text = Text("")
        var buffer = ""
        var bufferIsMatch = matched.contains(0)

        func flush() {
            guard !buffer.isEmpty else { return }
            var piece = Text(buffer)
            if bufferIsMatch {
                piece = piece.bold()
                    .foregroundColor(isSelected ? .white : DesignTokens.accentBlue.color)
            }
            text = text + piece
            buffer = ""
        }

        for index in characters.indices {
            let isMatch = matched.contains(index)
            if isMatch != bufferIsMatch {
                flush()
                bufferIsMatch = isMatch
            }
            buffer.append(characters[index])
        }
        flush()
        return text
    }
}
