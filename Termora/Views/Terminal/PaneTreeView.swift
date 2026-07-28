//
//  PaneTreeView.swift
//  Termora
//

import AppKit
import SwiftUI

/// Collects every leaf frame in the pane tree coordinate space.
struct PaneFramesPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] { [:] }

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Draws a `PaneNode` tree recursively. Recursion is broken with `AnyView`
/// inside `SplitContainerView`, otherwise the `Body` type would be infinite.
struct PaneTreeView: View {

    static let coordinateSpaceName = "termora.pane-tree"

    let node: PaneNode
    let tabID: UUID
    let activePaneID: UUID
    let viewModel: WorkspaceViewModel
    let sessionManager: SessionManager
    /// True for every pane that has at least one sibling. A window with a single pane needs
    /// no "which pane is active?" marker, so the accent border would only be noise there.
    var isInsideSplit: Bool = false

    @ViewBuilder
    var body: some View {
        switch node {
        case let .leaf(paneID, sessionID):
            PaneLeafView(paneID: paneID,
                         sessionID: sessionID,
                         isActive: paneID == activePaneID,
                         showsActiveIndicator: isInsideSplit,
                         viewModel: viewModel,
                         sessionManager: sessionManager)

        case let .split(id, axis, ratio, first, second):
            SplitContainerView(splitID: id,
                               axis: axis,
                               ratio: ratio,
                               first: first,
                               second: second,
                               tabID: tabID,
                               activePaneID: activePaneID,
                               viewModel: viewModel,
                               sessionManager: sessionManager)
        }
    }
}

// MARK: - Exit banner content

/// Brief 3 "Error State": the banner answers four questions — what failed (`title`),
/// why it probably failed plus the technical detail (`detail`), and what the user can do
/// next (`actions`). Pure data, so the wording is covered by tests.
struct PaneExitBanner: Equatable {

    enum Action: Equatable {
        case openSettings, useDefaultShell, retry, restart

        /// Brief 3: no vague `OK` / `Yes` — every button names its effect.
        var title: String {
            switch self {
            case .openSettings: return "Open Settings"
            case .useDefaultShell: return "Use Default Shell"
            case .retry: return "Try Again"
            case .restart: return "Restart Shell"
            }
        }
    }

    let title: String
    let detail: String
    let actions: [Action]
    /// Whether this is a failure the user is expected to act on (drives the icon/tint).
    let isFailure: Bool

    var accessibilityLabel: String { "\(title). \(detail)" }

    static func make(exitStatus: ExitStatus, launchFailure: String?) -> PaneExitBanner {
        if let path = launchFailure {
            return PaneExitBanner(
                title: "Shell failed to start",
                detail: "'\(path)' could not be launched — the file is missing or not executable. "
                    + "Check the shell path in Settings, or start the default shell instead.",
                actions: [.openSettings, .useDefaultShell, .retry],
                isFailure: true)
        }

        if let code = exitStatus.exitCode {
            if code == 0 {
                return PaneExitBanner(
                    title: "Shell exited",
                    detail: "The process finished normally (exit code 0). "
                        + "Start a new shell to keep using this pane.",
                    actions: [.restart],
                    isFailure: false)
            }
            return PaneExitBanner(
                title: "Shell exited with an error",
                detail: "The process ended with exit code \(code). "
                    + "The output above usually explains why.",
                actions: [.restart],
                isFailure: true)
        }

        if exitStatus.signal != nil {
            return PaneExitBanner(
                title: "Shell was terminated",
                detail: "The process was \(exitStatus.localizedSummary) — something outside this pane stopped it.",
                actions: [.restart],
                isFailure: true)
        }

        return PaneExitBanner(
            title: "Shell stopped",
            detail: "The process is no longer running. Raw wait status: \(exitStatus.rawStatus).",
            actions: [.restart],
            isFailure: true)
    }
}

// MARK: - Leaf

private struct PaneLeafView: View {
    let paneID: UUID
    let sessionID: UUID
    let isActive: Bool
    let showsActiveIndicator: Bool
    let viewModel: WorkspaceViewModel
    let sessionManager: SessionManager

    /// The banner takes key focus when it appears, so Enter restarts the session
    /// without the user having to click first.
    @FocusState private var isBannerFocused: Bool

    /// Brief 3 "Error State" offers `Open Settings` as a recovery action; the app declares a
    /// `Settings` scene, so this opens the real window instead of a dead end.
    @Environment(\.openSettings) private var openSettings

    /// Reading the @Observable session here makes the leaf redraw when the shell exits.
    private var session: TerminalSession? { sessionManager.session(id: sessionID) }

    private var exitStatus: ExitStatus? {
        guard case .exited(let status)? = session?.processState else { return nil }
        return status
    }

    /// Brief 3 "Ana Renkler": accent blue #169CFF → accent violet #7A3CFF. Kept local to this
    /// file on purpose — the pane border is the only place that needs it today.
    private static let accentGradient = LinearGradient(
        colors: [Color(red: 0.086, green: 0.612, blue: 1.0),
                 Color(red: 0.478, green: 0.235, blue: 1.0)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing)

    var body: some View {
        TerminalHostView(sessionID: sessionID,
                         sessionManager: sessionManager,
                         isActive: isActive,
                         onSplitRight: { split(axis: .vertical) },
                         onSplitDown: { split(axis: .horizontal) },
                         // Sağ tık menüsü BU panelde açıldı ama eylemler AKTİF panele
                         // bakıyor. Aktif olmayan bir panele sağ tıklandığında yanlış
                         // panelin seçimi işlenmesin diye önce panel aktifleştirilir.
                         onSearchSelection: { selection in
                             viewModel.activatePane(paneID: paneID)
                             viewModel.searchForSelection(selection)
                         },
                         // Menü AI'a dokunmaz, yalnız istek bırakır; pencere onu karşılar.
                         onExplainWithAI: {
                             viewModel.activatePane(paneID: paneID)
                             viewModel.requestExplainSelection()
                         })
            // Kimlik HEM oturumu HEM de yeniden başlatma kuşağını içerir:
            // - sessionID: iki sekmenin kök paneli aynı yapısal konumdadır; kimlik yalnız
            //   kuşak olursa (taze oturumlarda hep 0) SwiftUI makeNSView'i çağırmaz ve
            //   sekme değiştirince önceki sekmenin terminali ekranda kalır.
            // - restartGeneration: SessionManager.restartSession aynı sessionID icin YENI
            //   bir NSView kurar; bu olmadan SwiftUI olu gorunumu ekranda tutar.
            .id(PaneHostIdentity(sessionID: sessionID,
                                 restartGeneration: session?.restartGeneration ?? 0))
            .overlay(alignment: .top) {
                if let exitStatus {
                    banner(exitStatus: exitStatus, failedPath: session?.launchFailure)
                }
            }
            .overlay {
                // Brief 3 "Split Terminal Deneyimi": the inactive pane only gets a *slight*
                // background difference — the old 15% black scrim made its text hard to read.
                // The layer only exists while inactive, so an active pane never intercepts
                // clicks meant for the terminal (selection, links). It sits above the banner:
                // clicking an inactive pane focuses it first.
                if !isActive {
                    Color.black.opacity(0.04)
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.activatePane(paneID: paneID) }
                }
            }
            .overlay {
                // Brief 3: the active pane is marked with a thin accent border. Hit testing is
                // off so the border never eats a click at the edge of the terminal.
                //
                // The layer is always present and only its opacity changes, so the transition
                // stays on this overlay and never reaches the terminal surface below (brief 3
                // forbids decorative animation on terminal text, cursor and output).
                activeIndicator
                    .opacity(isActive && showsActiveIndicator ? 1 : 0)
                    .allowsHitTesting(false)
                    .motionAnimation(.selection, value: isActive)
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: PaneFramesPreferenceKey.self,
                        value: [paneID: proxy.frame(in: .named(PaneTreeView.coordinateSpaceName))]
                    )
                }
            )
    }

    /// Brief 3 "Erişilebilirlik → Sadece renkle durum anlatılmamalı": a colour-blind user must
    /// be able to tell the active pane apart, so the marker carries a shape signal as well as
    /// a hue. The 2 pt border has visible mass on its own, and the short bar centred on the
    /// top edge repeats the tab bar's "this one is active" language — a form that reads even
    /// if the blue-violet gradient is perceived as a flat grey.
    private var activeIndicator: some View {
        Rectangle()
            .strokeBorder(Self.accentGradient, lineWidth: 2)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Self.accentGradient)
                    .frame(width: 28, height: 3)
            }
    }

    /// Splits this pane from its own context menu. The pane is focused first because the view
    /// model splits whichever pane is active, and a right-click does not move focus by itself.
    private func split(axis: SplitAxis) {
        viewModel.activatePane(paneID: paneID)
        viewModel.splitActivePane(axis: axis)
    }

    /// Spec §8 + brief 3 "Error State": the pane stays open after the process exits and states
    /// what failed, why, and what to do next.
    @ViewBuilder
    private func banner(exitStatus: ExitStatus, failedPath: String?) -> some View {
        let content = PaneExitBanner.make(exitStatus: exitStatus, launchFailure: failedPath)

        HStack(alignment: .top, spacing: 8) {
            Image(systemName: content.isFailure ? "exclamationmark.triangle.fill" : "power")
                .foregroundStyle(content.isFailure ? Color.orange : Color.secondary)
                .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(content.title)
                    .font(.system(size: 11, weight: .semibold))
                Text(content.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                ForEach(content.actions, id: \.self) { action in
                    Button(action.title) { perform(action) }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.system(size: 11))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .focusable()
        // Brief 3 "Erişilebilirlik → Klavye focus görünür olmalı". This banner is focusable so
        // that Return restarts the shell; hiding the focus ring (as this used to do) left the
        // keyboard user with no way to see that Return was aimed here. The ring stays.
        .focused($isBannerFocused)
        .onKeyPress(.return) {
            viewModel.restartPaneSession(paneID: paneID)
            return .handled
        }
        .task { isBannerFocused = isActive }
        .onChange(of: isActive) { _, active in
            if active { isBannerFocused = true }
        }
        .accessibilityLabel(content.accessibilityLabel)
    }

    private func perform(_ action: PaneExitBanner.Action) {
        switch action {
        case .openSettings:
            openSettings()
        case .useDefaultShell:
            viewModel.restartPaneSession(paneID: paneID, forceDefaultShell: true)
        case .retry, .restart:
            viewModel.restartPaneSession(paneID: paneID)
        }
    }
}

// MARK: - Split

private struct SplitContainerView: View {
    let splitID: UUID
    let axis: SplitAxis
    let ratio: Double
    let first: PaneNode
    let second: PaneNode
    let tabID: UUID
    let activePaneID: UUID
    let viewModel: WorkspaceViewModel
    let sessionManager: SessionManager

    /// First pane length captured when a divider drag begins, so the ratio does
    /// not drift while the divider moves under the cursor.
    @State private var dragStartLength: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let total = axis == .vertical ? proxy.size.width : proxy.size.height
            let firstLength = SplitLayoutMath.firstLength(totalLength: total, ratio: ratio)
            let secondLength = SplitLayoutMath.secondLength(totalLength: total, ratio: ratio)

            if axis == .vertical {
                HStack(spacing: 0) {
                    childView(first).frame(width: firstLength)
                    divider(total: total, firstLength: firstLength)
                    childView(second).frame(width: secondLength)
                }
            } else {
                VStack(spacing: 0) {
                    childView(first).frame(height: firstLength)
                    divider(total: total, firstLength: firstLength)
                    childView(second).frame(height: secondLength)
                }
            }
        }
    }

    private func childView(_ node: PaneNode) -> AnyView {
        AnyView(PaneTreeView(node: node,
                             tabID: tabID,
                             activePaneID: activePaneID,
                             viewModel: viewModel,
                             sessionManager: sessionManager,
                             isInsideSplit: true))
    }

    private func divider(total: CGFloat, firstLength: CGFloat) -> some View {
        PaneDividerView(axis: axis)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStartLength ?? firstLength
                        dragStartLength = start
                        // SwiftUI's +y points down and VStack's first child is on top,
                        // so a downward drag grows the first pane in both axes.
                        let delta = axis == .vertical ? value.translation.width : value.translation.height
                        let newRatio = SplitLayoutMath.ratio(
                            atPosition: start + delta,
                            totalLength: SplitLayoutMath.usableLength(totalLength: total))
                        viewModel.updateSplitRatio(tabID: tabID, splitID: splitID, ratio: newRatio)
                    }
                    .onEnded { _ in dragStartLength = nil }
            )
    }
}

// MARK: - Divider

private struct PaneDividerView: View {
    let axis: SplitAxis

    /// Guards against unbalanced `NSCursor.pop()` calls.
    @State private var didPushCursor = false

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: axis == .vertical ? SplitLayoutMath.dividerThickness : nil,
                   height: axis == .horizontal ? SplitLayoutMath.dividerThickness : nil)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    guard !didPushCursor else { return }
                    didPushCursor = true
                    switch axis {
                    case .vertical: NSCursor.resizeLeftRight.push()
                    case .horizontal: NSCursor.resizeUpDown.push()
                    }
                } else if didPushCursor {
                    didPushCursor = false
                    NSCursor.pop()
                }
            }
            .onDisappear {
                if didPushCursor {
                    didPushCursor = false
                    NSCursor.pop()
                }
            }
            // Brief 3 "Erişilebilirlik": the divider is a real control, so VoiceOver must be
            // able to name it. It is drag-only today — see the pane resize note in the report.
            .accessibilityElement()
            .accessibilityLabel(axis == .vertical
                                ? "Vertical split divider"
                                : "Horizontal split divider")
            .accessibilityHint("Drag to resize the panes")
    }
}