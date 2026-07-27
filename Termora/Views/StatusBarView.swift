import Combine
import SwiftUI

/// Aktif sekmenin aktif panelinin durumu: shell adı, çalışma dizini (~ kısaltmalı),
/// git dalı, terminal boyutu (cols×rows) ve işlem göstergesi.
///
/// Veri `WorkspaceViewModel.statusSnapshot()` ile çekilir. Spec §10 gereği en fazla 1 Hz
/// ve yalnız görünür sekme için okunur: `statusSnapshot()` `libproc` ile cwd sorgular ve
/// `.git/HEAD` okur — her yeniden çizimde çalıştırılamaz, bu yüzden değer `@State`'te tutulur.
struct StatusBarView: View {

    let workspace: WorkspaceViewModel

    @State private var snapshot: WorkspaceViewModel.StatusSnapshot?

    /// `@State` bilerek: `Timer.publish(...)` her `body` değerlendirmesinde YENİ bir publisher
    /// üretir; `let` özellik olarak tutulsaydı `onReceive` her yeniden çizimde yeniden abone
    /// olur ve 1 sn'lik sayaç sürekli baştan başlardı (sık çizimde hiç tetiklenmeyebilirdi).
    /// `.common` mode: menü açıkken ya da ayraç sürüklenirken de tetiklenir.
    /// Abonelik görünüm ağaçtan çıkınca iptal olur — çubuk kapalıyken zamanlayıcı çalışmaz.
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            content
                .padding(.horizontal, 10)
                .frame(height: 22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .onAppear { snapshot = workspace.statusSnapshot() }
        .onReceive(ticker) { _ in snapshot = workspace.statusSnapshot() }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot {
            HStack(spacing: 8) {
                item("terminal", snapshot.shellName)

                separator

                Text(snapshot.workingDirectory)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(snapshot.workingDirectory)

                if let branch = snapshot.branchName {
                    separator
                    item("arrow.triangle.branch", branch)
                }

                Spacer(minLength: 8)

                Text("\(snapshot.columns)×\(snapshot.rows)")
                    .monospacedDigit()
                    .help("Terminal size (columns × rows)")

                separator

                busyIndicator(isBusy: snapshot.isBusy)
            }
        } else {
            Color.clear
        }
    }

    private func item(_ systemImage: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(text).lineLimit(1)
        }
    }

    private var separator: some View {
        Divider().frame(height: 11)
    }

    private func busyIndicator(isBusy: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                // brief 3 marka paleti: çalışan işlem "Success" yeşili.
                .fill(isBusy ? DesignTokens.success.color : Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)
            Text(isBusy ? "running" : "idle")
        }
        .help(isBusy ? "A process is running in this pane" : "No process is running in this pane")
    }
}
