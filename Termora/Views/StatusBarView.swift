import Combine
import SwiftUI

/// Panelde işlem çalışıp çalışmadığı — brief 3 "Erişilebilirlik → Sadece renkle durum
/// anlatılmamalı".
///
/// Durum ÜÇ kanaldan aynı anda anlatılır: renk (yeşil / soluk), ŞEKİL (dolu daire / boş
/// halka) ve METİN ("running" / "idle"). Renk körü bir kullanıcı için ilk kanal kaybolsa
/// bile diğer ikisi ayakta kalır. Karar saf tutulur ki test edilebilsin.
enum ProcessActivity: Equatable, CaseIterable {
    case running
    case idle

    init(isBusy: Bool) {
        self = isBusy ? .running : .idle
    }

    /// Noktanın yanında görünen kısa etiket.
    var text: String {
        switch self {
        case .running: return "running"
        case .idle: return "idle"
        }
    }

    /// Dolu daire ve boş halka: renk kaldırılsa bile iki durum ayırt edilir.
    var symbolName: String {
        switch self {
        case .running: return "circle.fill"
        case .idle: return "circle"
        }
    }

    /// VoiceOver ve tooltip için tam cümle.
    var accessibilityLabel: String {
        switch self {
        case .running: return "A process is running in this pane"
        case .idle: return "No process is running in this pane"
        }
    }
}

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
                item("terminal", snapshot.shellName, label: "Shell: \(snapshot.shellName)")

                separator

                Text(snapshot.workingDirectory)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(snapshot.workingDirectory)
                    .accessibilityLabel("Working directory: \(snapshot.workingDirectory)")

                if let branch = snapshot.branchName {
                    separator
                    item("arrow.triangle.branch", branch, label: "Git branch: \(branch)")
                }

                Spacer(minLength: 8)

                Text("\(snapshot.columns)×\(snapshot.rows)")
                    .monospacedDigit()
                    .help("Terminal size (columns × rows)")
                    .accessibilityLabel(
                        "Terminal size: \(snapshot.columns) columns by \(snapshot.rows) rows")

                separator

                activityIndicator(ProcessActivity(isBusy: snapshot.isBusy))
            }
        } else {
            Color.clear
        }
    }

    /// İkon dekoratiftir; anlam yanındaki metinde. VoiceOver ikonu ayrı bir öğe olarak
    /// okumasın diye satır tek bir erişilebilirlik öğesine indirilir.
    private func item(_ systemImage: String, _ text: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(text).lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var separator: some View {
        Divider().frame(height: 11)
    }

    /// brief 3 "Sadece renkle durum anlatılmamalı": renk + şekil + metin birlikte.
    private func activityIndicator(_ activity: ProcessActivity) -> some View {
        HStack(spacing: 4) {
            Image(systemName: activity.symbolName)
                // brief 3 marka paleti: çalışan işlem "Success" yeşili; boşta soluk halka.
                .foregroundStyle(activity == .running
                                 ? DesignTokens.success.color
                                 : Color.secondary.opacity(0.55))
                .font(.system(size: 7))
                .imageScale(.small)
            Text(activity.text)
        }
        .help(activity.accessibilityLabel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(activity.accessibilityLabel)
    }
}
