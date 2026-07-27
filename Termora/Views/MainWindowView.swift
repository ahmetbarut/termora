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
            terminalContent
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
    }

    @ViewBuilder
    private var terminalContent: some View {
        if let tab = workspace.activeTab,
           let sessionID = tab.root.sessionID(ofPane: tab.activePaneID) {
            TerminalHostView(sessionID: sessionID,
                             sessionManager: services.sessionManager,
                             isActive: true)
                .id(sessionID)
        } else {
            Color.clear
        }
    }
}
