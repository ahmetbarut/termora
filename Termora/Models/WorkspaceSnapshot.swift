import Foundation

/// Açık düzen ile kayıtlı workspace arasındaki SAF dönüşümler.
/// UI ya da servis bağımlılığı yoktur: oturum dizinleri closure dikişinden gelir.
enum WorkspaceSnapshot {

    /// Açık düzenden workspace tabloları üretir (PaneNode ağacı → WorkspaceLayout).
    /// Oturum kimlikleri düşer, panel kimlikleri korunur.
    static func layout(from node: PaneNode, directoryOfSession: (UUID) -> String?) -> WorkspaceLayout {
        switch node {
        case let .leaf(paneID, sessionID):
            return .pane(WorkspacePane(id: paneID,
                                       startupDirectory: nonBlank(directoryOfSession(sessionID)),
                                       startupCommand: nil))
        case let .split(_, axis, ratio, first, second):
            return .split(axis: axis,
                          ratio: ratio,
                          first: layout(from: first, directoryOfSession: directoryOfSession),
                          second: layout(from: second, directoryOfSession: directoryOfSession))
        }
    }

    /// Kaydedilmiş düzeni açılış planına çevirir: hangi panel, hangi dizin, hangi komut.
    static func plan(for workspace: Workspace) -> [WorkspaceOpenPlan.Tab] {
        workspace.tabs.map { tab in
            WorkspaceOpenPlan.Tab(
                title: tab.title,
                layout: tab.layout,
                panes: tab.layout.panes.map { pane in
                    WorkspaceOpenPlan.Pane(
                        paneID: pane.id,
                        directory: nonBlank(pane.startupDirectory) ?? workspace.directory,
                        startupCommand: nonBlank(pane.startupCommand))
                })
        }
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// Bir workspace açılırken kurulacak somut düzen.
enum WorkspaceOpenPlan {
    struct Pane: Equatable {
        var paneID: UUID
        /// Panelin açılacağı dizin; workspace dizinine düşürülmüş hâli.
        var directory: String
        /// Onay verilmedikçe çalıştırılmaz.
        var startupCommand: String?

        init(paneID: UUID, directory: String, startupCommand: String? = nil) {
            self.paneID = paneID
            self.directory = directory
            self.startupCommand = startupCommand
        }
    }

    struct Tab: Equatable {
        var title: String?
        var layout: WorkspaceLayout
        var panes: [Pane]

        init(title: String? = nil, layout: WorkspaceLayout, panes: [Pane]) {
            self.title = title
            self.layout = layout
            self.panes = panes
        }
    }

    /// Onay ekranında gösterilecek komutlar (boş → onay gerekmez).
    static func startupCommands(for workspace: Workspace) -> [String] {
        WorkspaceSnapshot.plan(for: workspace).flatMap { $0.panes.compactMap(\.startupCommand) }
    }
}
