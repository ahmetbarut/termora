import AppKit
import SwiftUI

/// Workspace oluşturma/düzenleme formu (briefs/3 "Workspace Ekranı").
///
/// Adımlar brief'teki sırayı izler: klasör → düzen → başlangıç komutları → kaydet.
/// "Gelişmiş ayarlar ilk ekranda gösterilmemelidir" gereği güven anahtarı katlanmış
/// bir bölümde durur; formun tamamı `WorkspaceDraft` tarafından yönetilir.
struct WorkspaceEditorView: View {

    @Binding var draft: WorkspaceDraft

    /// Açık pencerenin düzenini benimsemek için ("Use Current Layout").
    /// Sıfırdan görsel düzen editörü yerine bu: kullanıcı düzeni terminalde kurar, buradan alır.
    let captureCurrentLayout: () -> [WorkspaceTab]

    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var isAdvancedExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                folderSection
                layoutSection
                startupCommandsSection
                advancedSection
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(draft.isEditingExistingWorkspace ? "Save Changes" : "Create Workspace",
                       action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.isSaveEnabled)
            }
            .padding(12)
        }
    }

    // MARK: - 1. Klasör

    private var folderSection: some View {
        Section("Project Folder") {
            HStack(spacing: 8) {
                Text(draft.directory.isEmpty ? WorkspaceCardModel.noFolderText : draft.directory)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(draft.directory.isEmpty ? .secondary : .primary)
                    .help(draft.directory)

                Spacer()

                Button("Choose…") { chooseDirectory() }
                    .accessibilityLabel("Choose Project Folder")
            }

            TextField("Name", text: $draft.name, prompt: Text("Workspace name"))
                .accessibilityLabel("Workspace Name")
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        draft.chooseDirectory(url.path)
    }

    // MARK: - 2. Düzen

    private var layoutSection: some View {
        Section("Terminal Layout") {
            LabeledContent("Layout") {
                Text(draft.layoutSummary)
                    .foregroundStyle(.secondary)
            }

            Button("Use Current Layout") {
                draft.useLayout(from: captureCurrentLayout())
            }
            .help("Copy the tabs and splits from the open window.")

            Text("Open the tabs and splits you want, then copy them here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 3. Başlangıç komutları

    private var startupCommandsSection: some View {
        Section("Startup Commands") {
            ForEach(draft.paneEditors) { pane in
                TextField(pane.label,
                          text: binding(for: pane),
                          prompt: Text("npm run dev"))
                    .accessibilityLabel(pane.accessibilityLabel)
            }

            Text("Commands need your approval each time the workspace opens.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func binding(for pane: WorkspaceDraft.PaneEditor) -> Binding<String> {
        Binding(
            get: { pane.command },
            set: { draft.setStartupCommand($0, paneID: pane.paneID) }
        )
    }

    // MARK: - 4. Gelişmiş (ilk ekranda görünmez)

    private var advancedSection: some View {
        Section {
            DisclosureGroup("Advanced", isExpanded: $isAdvancedExpanded) {
                Toggle(WorkspaceLaunchPrompt.trustToggleTitle,
                       isOn: $draft.trustsStartupCommands)
                    .help(WorkspaceLaunchPrompt.trustToggleHelp)
            }
        }
    }
}
