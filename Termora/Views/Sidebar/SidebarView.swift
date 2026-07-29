import SwiftUI

/// briefs/3 "Sidebar": Workspaces, Recent Folders, SSH Hosts, Docker.
///
/// Sidebar kendi kayıtlarını toplamaz — komut paletinin ürettiği öğeleri gösterir ve
/// tıklanınca onların eylemini çalıştırır. Paletten workspace açmakla sidebar'dan açmak
/// bu yüzden aynı yoldur.
struct SidebarView: View {
    let sections: [SidebarSectionContent]
    let onDismiss: () -> Void

    var body: some View {
        List {
            ForEach(sections) { content in
                Section {
                    if content.items.isEmpty {
                        EmptyStateView(content: EmptyStateContent(
                            message: content.section.emptyMessage
                        ))
                    } else {
                        ForEach(content.items) { item in
                            SidebarRow(item: item)
                        }
                    }
                } header: {
                    Label(content.section.title, systemImage: content.section.symbolName)
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Sidebar")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: onDismiss) {
                    Image(systemName: "sidebar.left")
                }
                .help("Hide Sidebar")
                .accessibilityLabel("Hide Sidebar")
            }
        }
    }
}

/// Tek bir sidebar satırı. Eylem paletin öğesinden gelir; satır onu yalnızca çizer.
private struct SidebarRow: View {
    let item: CommandPaletteItem

    var body: some View {
        Button(action: item.action) {
            HStack(spacing: 6) {
                Image(systemName: item.symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                // Yollar dar sidebar'a sığmaz; baş ve son parça okunabilir kalsın diye
                // ortadan kırpılır ("~/Proj…/pinro" yerine "~/Projects/…/pinro").
                Text(item.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // İkon sesli okunmaz; satırın türü (favori mi son kullanılan mı) yalnız burada
        // duyulur — palet satırlarıyla aynı etiket.
        .accessibilityLabel(item.accessibilityLabel)
    }
}

/// Sidebar ile terminal arasındaki, sürüklenerek genişlik değiştiren ayırıcı.
///
/// briefs/3 sidebar genişliğini 220–380 pt arasında tutmayı ister. Sürükleme sırasında
/// değer sınırlara kırpılır, yani kullanıcı fareyi ne kadar sürüklerse sürüklesin
/// terminal alanı korunur.
struct SidebarResizeHandle: View {
    @Binding var width: Double

    /// Sürükleme başladığındaki genişlik. Her adımda `width`'e eklemek yerine buradan
    /// hesaplamak şart: kırpılmış bir değere translation eklemek, sınıra dayandıktan
    /// sonra fareyle görünüm arasında kalıcı bir kayma bırakırdı.
    @State private var widthAtDragStart: Double?

    var body: some View {
        Divider()
            .frame(width: 1)
            .overlay(
                // Görünen çizgi 1 pt; tutma alanı daha geniş olmalı (briefs/3: "Split
                // divider alanları kolay tutulabilir olmalı" — aynı gerekçe).
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 10)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let start = widthAtDragStart ?? width
                                widthAtDragStart = start
                                width = SettingsLimits.clampSidebarWidth(start + value.translation.width)
                            }
                            .onEnded { _ in widthAtDragStart = nil }
                    )
            )
            .accessibilityHidden(true)
    }
}
