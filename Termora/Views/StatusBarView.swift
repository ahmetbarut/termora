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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var snapshot: WorkspaceViewModel.StatusSnapshot?

    /// briefs/3 "Küçük Pencere Davranışı" ▸ ilk adım: status bar bilgileri azaltılır.
    /// Hangi bilginin önce düşeceğine `CompactionLevel` karar verir; burası yalnız
    /// genişliği ölçüp uygular.
    @State private var level = CompactionLevel.full

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
                // Genişlik GÖRÜNÜMDEN okunur, pencereden değil: çubuk sidebar ve AI
                // paneli açıkken pencereden dar olur ve kararı asıl o genişlik verir.
                .background(GeometryReader { proxy in
                    Color.clear.onChange(of: proxy.size.width, initial: true) { _, width in
                        level = CompactionLevel(availableWidth: width)
                    }
                })
        }
        // briefs/2 "Erişilebilirlik": sistem yazı boyutu tercihi izlenir. Sabit 11 pt,
        // sistemi büyüten kullanıcı için okunmaz kalırdı.
        .font(.system(size: DynamicTypeScale.scaled(11, for: dynamicTypeSize)))
        .foregroundStyle(.secondary)
        .onAppear {
            workspace.refreshActiveWorkingDirectory()
            snapshot = workspace.statusSnapshot()
            Task { await workspace.refreshGitStatus() }
        }
        .onReceive(ticker) { _ in
            // Tazeleme ÖNCE, okuma sonra: ikisi ayrı çağrı olduğu için `statusSnapshot()`
            // saf kalır ve bir gün `body` içinden çağrılırsa güncelleme döngüsü doğmaz.
            workspace.refreshActiveWorkingDirectory()
            snapshot = workspace.statusSnapshot()
            // Git yoklaması bu saatin İÇİNDE çalışmaz: çağrı arka plana gider ve
            // `GitStatusMonitor` onu kendi (çok daha seyrek) aralığına göre kısar.
            Task { await workspace.refreshGitStatus() }
        }
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

                if let git = snapshot.gitStatus, level.showsGitDetail {
                    separator
                    gitDetail(git, repositoryName: snapshot.repositoryName)
                } else if let branch = snapshot.branchName, level.showsGitDetail {
                    // Detay henüz gelmedi (ya da depo git'e göre okunamadı): dosyadan
                    // okunan dal yine de gösterilir, çubuk boş kalmaz.
                    separator
                    item("arrow.triangle.branch",
                         branchText(branch: branch, repositoryName: snapshot.repositoryName),
                         label: "Git branch: \(branch)")
                }

                // briefs/3 "Status Bar": SSH bağlantısı. SSH ile ilgisi olmayan panelde
                // hiç çizilmez.
                if let ssh = snapshot.sshConnection {
                    separator
                    sshIndicator(ssh)
                        // Ses durumun DEĞİŞTİĞİ anda çalar; her çizimde çalsaydı bağlantı
                        // koptuğu sürece saniyede bir ses çıkardı.
                        .onChange(of: ssh) { previous, current in
                            guard previous != current, current.canReconnect else { return }
                            SoundPlayer.play(.sshDisconnected, settings: workspace.settings.settings)
                        }
                }

                Spacer(minLength: 8)

                if level.showsTerminalSize {
                    Text("\(snapshot.columns)×\(snapshot.rows)")
                        .monospacedDigit()
                        .help("Terminal size (columns × rows)")
                        .accessibilityLabel(
                            "Terminal size: \(snapshot.columns) columns by \(snapshot.rows) rows")

                    separator
                }

                activityIndicator(ProcessActivity(isBusy: snapshot.isBusy))
            }
        } else {
            Color.clear
        }
    }

    /// SSH bağlantı göstergesi. Bağlantı KOPTUĞUNDA satır bir düğmeye dönüşür
    /// (briefs/2 "SSH Yöneticisi": *Bağlantı kesildiğinde tekrar bağlanma seçeneği
    /// sunmalıdır*); diğer durumlarda tıklanacak bir şey yok, sadece bilgi.
    @ViewBuilder
    private func sshIndicator(_ state: SSHConnectionState) -> some View {
        if state.canReconnect {
            Button {
                workspace.restartActivePaneSession()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: state.symbolName)
                    Text("Reconnect")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .help("The SSH connection failed. Click to run the same connection again.")
            .accessibilityLabel("SSH \(state.title). Reconnect")
        } else {
            item(state.symbolName, "SSH \(state.title)", label: "SSH \(state.title)")
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

    /// briefs/2 "Git Entegrasyonu": repository adı, aktif branch, değişiklik durumu ve
    /// ahead/behind. Son commit özeti tooltip'te ve VoiceOver etiketinde durur — tek
    /// satırlık bir çubuk brief'in istediği gibi SADE kalmalı.
    ///
    /// Erişilebilirlik (brief 3): oklar ve rozet SESLİ OKUNMAZ, bu yüzden satır TEK bir
    /// öğeye indirilir ve etiket her şeyi kelimelerle söyler.
    private func gitDetail(_ git: GitStatusDetail, repositoryName: String?) -> some View {
        let label = git.accessibilityLabel(repositoryName: repositoryName)
        return HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                Text(branchText(branch: git.branch, repositoryName: repositoryName))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            // Kirlilik ÜÇ kanaldan anlatılır: ikon (kalem), METİN ("2 changes") ve renk.
            // Renk kaldırılsa bile diğer ikisi ayakta kalır.
            if let changes = git.changesText {
                HStack(spacing: 3) {
                    Image(systemName: "pencil").imageScale(.small)
                    Text(changes)
                }
                .foregroundStyle(DesignTokens.warning.color)
            }

            if let sync = git.aheadBehindText {
                Text(sync).monospacedDigit()
            }
        }
        .help(label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    /// "Termora/main" — depo adı biliniyorsa dalın önüne konur; aynı adlı iki dal farklı
    /// pencerelerde ayırt edilebilsin diye. Ayrık HEAD'de dal adı yoktur.
    private func branchText(branch: String?, repositoryName: String?) -> String {
        let head = branch ?? "detached HEAD"
        guard let repositoryName, !repositoryName.isEmpty else { return head }
        return "\(repositoryName)/\(head)"
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
