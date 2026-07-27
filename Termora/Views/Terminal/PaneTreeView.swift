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

    @ViewBuilder
    var body: some View {
        switch node {
        case let .leaf(paneID, sessionID):
            PaneLeafView(paneID: paneID,
                         sessionID: sessionID,
                         isActive: paneID == activePaneID,
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

// MARK: - Leaf

private struct PaneLeafView: View {
    let paneID: UUID
    let sessionID: UUID
    let isActive: Bool
    let viewModel: WorkspaceViewModel
    let sessionManager: SessionManager

    /// The banner takes key focus when it appears, so Enter restarts the session
    /// without the user having to click first.
    @FocusState private var isBannerFocused: Bool

    /// Reading the @Observable session here makes the leaf redraw when the shell exits.
    private var session: TerminalSession? { sessionManager.session(id: sessionID) }

    private var exitStatus: ExitStatus? {
        guard case .exited(let status)? = session?.processState else { return nil }
        return status
    }

    var body: some View {
        TerminalHostView(sessionID: sessionID,
                         sessionManager: sessionManager,
                         isActive: isActive)
            // SessionManager.restartSession aynı sessionID icin YENI bir NSView kurar;
            // bu anahtar olmadan SwiftUI olu gorunumu ekranda tutar (Task 8/10 notlari).
            .id(session?.restartGeneration ?? 0)
            .overlay(alignment: .top) {
                if let exitStatus {
                    banner(exitStatus: exitStatus, failedPath: session?.launchFailure)
                }
            }
            .overlay {
                // The dimming layer only exists while inactive, so an active pane
                // never intercepts clicks meant for the terminal (selection, links).
                // It sits above the banner: clicking an inactive pane focuses it first.
                if !isActive {
                    Color.black.opacity(0.15)
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.activatePane(paneID: paneID) }
                }
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

    /// Spec §8: the pane stays open after the process exits and offers a way back.
    @ViewBuilder
    private func banner(exitStatus: ExitStatus, failedPath: String?) -> some View {
        HStack(spacing: 8) {
            if let failedPath {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("'\(failedPath)' çalıştırılamadı")
                Spacer(minLength: 8)
                Button("Yeniden dene") {
                    viewModel.restartPaneSession(paneID: paneID)
                }
                Button("Varsayılan shell ile dene") {
                    viewModel.restartPaneSession(paneID: paneID, forceDefaultShell: true)
                }
            } else {
                Text("İşlem sonlandı (\(exitStatus.localizedSummary))")
                Spacer(minLength: 8)
                Button("Yeniden başlat") {
                    viewModel.restartPaneSession(paneID: paneID)
                }
            }
        }
        .font(.system(size: 11))
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .focusable()
        .focusEffectDisabled()
        .focused($isBannerFocused)
        .onKeyPress(.return) {
            viewModel.restartPaneSession(paneID: paneID)
            return .handled
        }
        .task { isBannerFocused = isActive }
        .onChange(of: isActive) { _, active in
            if active { isBannerFocused = true }
        }
        .accessibilityLabel(failedPath == nil
                            ? "İşlem sonlandı: \(exitStatus.localizedSummary)"
                            : "Shell çalıştırılamadı: \(failedPath ?? "")")
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
                             sessionManager: sessionManager))
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
    }
}