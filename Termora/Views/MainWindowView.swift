import AppKit
import Combine
import SwiftUI

/// Pencere kabuğunun ölçüleri (brief 3, "Küçük Pencere Davranışı").
enum WindowLayout {
    /// Brief'teki alt sınır: bu boyutta sekme çubuğu ve terminal birlikte kullanılabilir kalır.
    static let minWidth: CGFloat = 720
    static let minHeight: CGFloat = 480
}

struct MainWindowView: View {
    private let services: AppServices
    @State private var workspace: WorkspaceViewModel

    /// Pencere kapatma delegesi. `@State` tutulur çünkü `NSWindow.delegate` zayıftır;
    /// başka bir sahibi olmazsa ilk yerleşimden hemen sonra yok olur.
    @State private var closeCoordinator = WindowCloseCoordinator()

    /// Komut paleti pencere başına bir tanedir; ⌘K menüden, ⌘⇧P dinleyiciden gelir.
    @State private var palette = CommandPaletteModel()
    @State private var paletteHotkey = CommandPaletteHotkeyMonitor()

    /// Sekme başlığı artık çalışan komutu da gösteriyor; komutun başlaması/bitmesi ne OSC
    /// başlığını ne de cwd'yi değiştirdiği için `sessionTitleDigest` değişmez. Başlığın
    /// gerçeği yansıtması için saniyede bir tazelenir (durum çubuğuyla aynı bütçe).
    /// `@State`: `Timer.publish(...)` her `body` değerlendirmesinde yeni bir publisher üretir.
    @State private var titleTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
        .frame(minWidth: WindowLayout.minWidth, minHeight: WindowLayout.minHeight)
        // Palet terminalin ÜZERİNDE bir katmandır: oturumlar okumaya/çalışmaya devam eder
        // (brief 3: "Komut paleti açıldığında terminal oturumu durmamalıdır").
        .overlay(alignment: .top) {
            if palette.isPresented {
                CommandPaletteView(model: palette,
                                   workspace: workspace,
                                   settings: services.settings,
                                   themes: services.themes)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: palette.isPresented)
        .focusedSceneValue(\.commandPalette, palette)
        .onChange(of: palette.isPresented) { _, isPresented in
            // Palet kapanınca klavye terminale geri döner; yoksa tuşlar hiçbir yere gitmez.
            if !isPresented { focusActiveTerminal() }
        }
        .onDisappear { paletteHotkey.detach() }
        .onAppear {
            // Sistemin otomatik pencere sekmelerini kapat: kendi sekme çubuğumuzu çiziyoruz,
            // aksi hâlde macOS "Show Tab Bar" öğesini ekler ve ⌘T ile çakışır.
            NSWindow.allowsAutomaticWindowTabbing = false
            if workspace.tabs.isEmpty { workspace.newTab() }
        }
        .onChange(of: workspace.sessionTitleDigest, initial: true) { _, _ in
            workspace.syncAutomaticTitles()
        }
        .onReceive(titleTicker) { _ in
            workspace.syncAutomaticTitles()
        }
        .focusedSceneValue(\.workspace, workspace)
        .background(
            WindowAccessor { window in
                closeCoordinator.attach(window: window, workspace: workspace)
                paletteHotkey.attach(window: window) { palette.toggle() }
            }
        )
        .confirmationDialog(
            workspace.pendingCloseTitle,
            isPresented: pendingCloseBinding,
            titleVisibility: .visible
        ) {
            // Belirsiz "OK"/"Yes" yerine eylemin adı (brief 3, "Uygulama Metin Dili").
            Button(workspace.pendingCloseConfirmLabel, role: .destructive) {
                workspace.confirmPendingClose()
            }
            Button("Cancel", role: .cancel) { workspace.cancelPendingClose() }
        } message: {
            Text(workspace.pendingCloseMessage)
        }
    }

    /// Klavye odağını aktif panelin terminaline geri verir.
    private func focusActiveTerminal() {
        guard let tab = workspace.activeTab,
              let sessionID = tab.root.sessionID(ofPane: tab.activePaneID) else { return }
        services.sessionManager.focusTerminal(sessionID: sessionID)
    }

    private var pendingCloseBinding: Binding<Bool> {
        Binding(
            get: { workspace.pendingClose != nil },
            set: { isPresented in
                if !isPresented { workspace.cancelPendingClose() }
            }
        )
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
