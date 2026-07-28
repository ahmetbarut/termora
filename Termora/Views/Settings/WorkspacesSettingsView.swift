import SwiftUI

/// Settings ▸ Workspaces (briefs/3 "Workspace Ekranı").
///
/// Kompakt liste: brief sunucu/workspace kartlarının "aşırı büyük" olmamasını,
/// yoğun bilgiyi az yerde göstermesini istiyor. Kart metinlerinin tamamı
/// `WorkspaceCardModel` tarafından üretilir; bu görünüm yalnız yerleşimdir.
struct WorkspacesSettingsView: View {

    let workspaces: WorkspaceStore
    let requestOpen: (Workspace) -> Void
    /// Açık pencerenin düzeni; pencere yoksa boş döner ve taslak dokunulmadan kalır.
    let captureCurrentLayout: () -> [WorkspaceTab]

    @State private var draft: WorkspaceDraft?

    var body: some View {
        VStack(spacing: 0) {
            if workspaces.workspaces.isEmpty {
                emptyState
            } else {
                list
            }
        }
        // `.sheet(item:)`in VERDİĞİ taslak kullanılır. `{ _ in ... }` deyip dışarıdaki
        // `$draft`'ı yeniden okumak, sayfanın kapanışı durum yazılmadan önceki görünüm
        // değerini yakaladığında BOŞ bir sayfa çizer (canlı uygulamada görüldü).
        .sheet(item: $draft) { presented in editorSheet(presented) }
    }

    // MARK: - Liste

    private var list: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(cards) { card in
                        WorkspaceCard(
                            card: card,
                            onOpen: { open(id: card.id) },
                            onEdit: { edit(id: card.id) },
                            onDelete: { workspaces.remove(id: card.id) }
                        )
                    }
                }
                .padding(12)
            }

            Divider()

            HStack {
                Button {
                    draft = .newWorkspace()
                } label: {
                    Label(WorkspacesEmptyState.primaryActionTitle, systemImage: "plus")
                }
                .accessibilityLabel(WorkspacesEmptyState.primaryActionTitle)
                Spacer()
            }
            .padding(12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(WorkspacesEmptyState.title)
                .font(.headline)
            Text(WorkspacesEmptyState.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(WorkspacesEmptyState.primaryActionTitle) {
                draft = .newWorkspace()
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var cards: [WorkspaceCardModel] {
        let now = Date()
        let home = NSHomeDirectory()
        return workspaces.workspaces.map { item in
            WorkspaceCardModel.make(
                workspace: item,
                repository: GitRepositoryReader.info(forDirectory: item.directory),
                now: now,
                home: home
            )
        }
    }

    // MARK: - Eylemler

    private func open(id: UUID) {
        guard let item = workspaces.workspaces.first(where: { $0.id == id }) else { return }
        requestOpen(item)
    }

    private func edit(id: UUID) {
        guard let item = workspaces.workspaces.first(where: { $0.id == id }) else { return }
        draft = WorkspaceDraft(editing: item)
    }

    private func editorSheet(_ presented: WorkspaceDraft) -> some View {
        // Sayfa kendi taslağını sunar; düzenlemeler `draft`'a yazılır, okurken de oraya
        // bakılır — `draft` bir an için boşalırsa sunulan değere düşülür.
        let binding = Binding<WorkspaceDraft>(
            get: { draft ?? presented },
            set: { draft = $0 }
        )
        return WorkspaceEditorView(
            draft: binding,
            captureCurrentLayout: captureCurrentLayout,
            onSave: {
                workspaces.upsert(binding.wrappedValue.makeWorkspace())
                draft = nil
            },
            onCancel: { draft = nil }
        )
        .frame(width: 520, height: 460)
    }
}

/// Tek satırlık kompakt kart.
private struct WorkspaceCard: View {
    let card: WorkspaceCardModel
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(card.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    if let trustText = card.trustText {
                        // Rozet metinle birlikte: durum yalnız renkle anlatılmaz.
                        Label(trustText, systemImage: WorkspaceCardModel.trustedSymbolName)
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(card.pathText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)

                HStack(spacing: 6) {
                    Text(card.tabsText)
                    if let panesText = card.panesText { dot; Text(panesText) }
                    if let commands = card.startupCommandsText { dot; Text(commands) }
                    if let repository = card.repositoryText {
                        dot
                        Label(repository, systemImage: WorkspaceCardModel.repositorySymbolName)
                            .labelStyle(.titleAndIcon)
                    }
                    dot
                    Text(card.lastOpenedText)
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isHovered {
                Button(action: onEdit) { Image(systemName: "pencil") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(card.editAccessibilityLabel)
                Button(action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(card.deleteAccessibilityLabel)
            }

            Button("Open", action: onOpen)
                .accessibilityLabel(card.launchAccessibilityLabel)
        }
        .padding(10)
        .background(Color.primary.opacity(isHovered ? 0.06 : 0.03), in: RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(card.accessibilityLabel)
    }

    private var dot: some View {
        Text("·").foregroundStyle(.tertiary)
    }
}

extension WorkspaceDraft: Identifiable {
    /// Sheet kimliği: taslak açıkken kimliğin sabit kalması yeterli.
    public var id: String { isEditingExistingWorkspace ? "edit" : "new" }
}
