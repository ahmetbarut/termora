import AppKit
import SwiftUI

struct MainWindowView: View {
    private let services: AppServices
    @State private var workspace: WorkspaceViewModel

    @MainActor
    init(services: AppServices) {
        self.services = services
        _workspace = State(initialValue: WorkspaceViewModel(
            sessionManager: services.sessionManager,
            settings: services.settings,
            profiles: services.profiles
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(workspace: workspace)
            Divider()
            if let tab = workspace.activeTab, tab.isSearchVisible {
                SearchBarView(tab: tab, workspace: workspace)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            terminalContent
            if workspace.isStatusBarVisible {
                StatusBarView(workspace: workspace)
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .onAppear {
            // Sistemin otomatik pencere sekmelerini kapat: kendi sekme çubuğumuzu çiziyoruz,
            // aksi hâlde macOS "Show Tab Bar" öğesini ekler ve ⌘T ile çakışır.
            NSWindow.allowsAutomaticWindowTabbing = false
            if workspace.tabs.isEmpty { workspace.newTab() }
        }
        .onChange(of: workspace.sessionTitleDigest, initial: true) { _, _ in
            workspace.syncAutomaticTitles()
        }
        .focusedSceneValue(\.workspace, workspace)
        .confirmationDialog(
            pendingCloseMessage,
            isPresented: pendingCloseBinding
        ) {
            Button("Kapat", role: .destructive) { workspace.confirmPendingClose() }
            Button("Vazgeç", role: .cancel) { workspace.cancelPendingClose() }
        }
    }

    private var pendingCloseBinding: Binding<Bool> {
        Binding(
            get: { workspace.pendingClose != nil },
            set: { isPresented in
                if !isPresented { workspace.cancelPendingClose() }
            }
        )
    }

    /// Onay metni hedefe göre değişir; M3'te panel (Task 17), M5'te pencere (Task 22) dalı da kullanılır.
    private var pendingCloseMessage: String {
        switch workspace.pendingClose?.target {
        case .pane:
            return "Bu panelde çalışan bir işlem var. Panel kapatılsın mı?"
        case .window:
            return "Çalışan işlemler var. Pencere kapatılsın mı?"
        case .tab, .none:
            return "Bu sekmede çalışan bir işlem var. Sekme kapatılsın mı?"
        }
    }

    @ViewBuilder
    private var terminalContent: some View {
        if let tab = workspace.activeTab {
            GeometryReader { root in
                PaneTreeView(node: tab.root,
                             tabID: tab.id,
                             activePaneID: tab.activePaneID,
                             viewModel: workspace,
                             sessionManager: services.sessionManager)
                    .coordinateSpace(.named(PaneTreeView.coordinateSpaceName))
                    .onPreferenceChange(PaneFramesPreferenceKey.self) { frames in
                        let converted = PaneFrameConverter.appKitFrames(
                            frames, containerHeight: root.size.height)
                        Task { @MainActor in
                            workspace.paneFrames = converted
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
        }
    }
}
