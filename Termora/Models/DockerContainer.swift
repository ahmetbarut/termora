import Foundation

/// Çalışan tek bir Docker container'ı (briefs/2 "Docker Entegrasyonu").
///
/// Kaynak `docker ps --format json` çıktısıdır; Termora daemon soketine KONUŞMAZ ve
/// bir Docker kütüphanesi eklemez — brief ilk aşamada açıkça CLI'ı işaret ediyor.
///
/// `nonisolated`: proje varsayılanı `MainActor` ama burada paylaşılan durum yok; ayrıştırma
/// arka planda çalışacak (bkz. `DockerStore`).
nonisolated struct DockerContainer: Identifiable, Equatable, Sendable {
    /// Kısa kimlik ("2fefa732134c"). HER komut bu kimlikle kurulur — adlar değişebilir,
    /// kimlik değişmez; ayrıca kimlik onaltılıktır, yani seçenek gibi ayrıştırılamaz.
    var id: String
    /// Görünen ad; docker birden çok ad verirse ilki.
    var name: String
    var image: String
    /// "running", "exited", …
    var state: String
    /// İnsan okunur durum ("Up 41 minutes (healthy)").
    var status: String
    /// Compose etiketlerinden gelen proje adı; compose ile başlatılmadıysa nil.
    var composeProject: String?
    var composeService: String?
    /// Projenin compose dosyaları; `docker compose exec` bunları `-f` ile alır.
    var composeConfigFiles: [String]

    init(id: String,
         name: String = "",
         image: String = "",
         state: String = "",
         status: String = "",
         composeProject: String? = nil,
         composeService: String? = nil,
         composeConfigFiles: [String] = []) {
        self.id = id
        self.name = name
        self.image = image
        self.state = state
        self.status = status
        self.composeProject = composeProject
        self.composeService = composeService
        self.composeConfigFiles = composeConfigFiles
    }

    /// Listelerde ve komut başlıklarında kullanılan ad. Adsız container kimliğiyle anılır;
    /// boş bir satır göstermek kullanıcıya hiçbir şey anlatmaz.
    var displayName: String {
        name.isEmpty ? id : name
    }

    var isRunning: Bool {
        state.caseInsensitiveCompare("running") == .orderedSame
    }
}

/// Bir compose projesinin tek bir servisi (briefs/2 "Docker Compose servislerini listeleme").
///
/// Liste ÇALIŞAN container'lardan TÜRETİLİR; ayrı bir `docker compose ps` süreci
/// başlatılmaz. Sebep ölçülebilir: `docker ps` çağrısı bu makinede ~20 ms sürüyor ve
/// compose bilgisi zaten aynı çıktının etiketlerinde duruyor — ikinci bir süreç aynı
/// veriyi iki kat maliyetle getirirdi.
nonisolated struct DockerComposeService: Identifiable, Equatable, Sendable {
    var project: String
    var service: String
    /// Servisin çalışan kopyaları (`--scale` ile birden fazla olabilir).
    var containerIDs: [String]
    var configFiles: [String]

    var id: String { "\(project)/\(service)" }
    var displayName: String { "\(project) / \(service)" }

    /// Container listesinden servis listesi. Compose etiketi taşımayan container'lar
    /// dışarıda kalır; servis adı olmayan kayıt da listelenemez (komut kurulamaz).
    static func services(in containers: [DockerContainer]) -> [DockerComposeService] {
        var byID: [String: DockerComposeService] = [:]
        for container in containers {
            guard let project = container.composeProject, !project.isEmpty,
                  let service = container.composeService, !service.isEmpty else { continue }
            let key = "\(project)/\(service)"
            if var existing = byID[key] {
                existing.containerIDs.append(container.id)
                // Compose dosyası ilk gören kopyadan alınır; kopyalar aynı projeye ait
                // olduğu için değerleri de aynıdır.
                if existing.configFiles.isEmpty { existing.configFiles = container.composeConfigFiles }
                byID[key] = existing
            } else {
                byID[key] = DockerComposeService(project: project,
                                                 service: service,
                                                 containerIDs: [container.id],
                                                 configFiles: container.composeConfigFiles)
            }
        }
        // Sıra kararlı olmalı: palet satırlarının her açılışta yer değiştirmesi
        // kas hafızasını bozar (sözlük sırası tanımsızdır).
        return byID.values.sorted { $0.id < $1.id }
    }
}

// MARK: - Etiket ayrıştırma

/// `docker ps --format json` etiketleri TEK bir dize olarak verir: `k=v,k=v,…`.
///
/// TUZAK: değerlerin İÇİNDE de virgül olabilir — gerçek çıktıda
/// `maintainer=Graylog, Inc. <hello@graylog.com>` ve
/// `com.docker.compose.depends_on=a:started:false,b:started:false` gibi. Düz virgülden
/// bölmek bu değerleri sahte anahtarlara böler. Bu yüzden bir parça YALNIZCA `=`
/// içeriyorsa VE `=` öncesi boşluksuz/boş olmayan bir anahtara benziyorsa yeni bir çift
/// başlatır; aksi hâlde önceki değerin devamıdır.
nonisolated enum DockerLabels {

    static func pairs(in labels: String) -> [(key: String, value: String)] {
        var pairs: [(key: String, value: String)] = []
        for fragment in labels.split(separator: ",", omittingEmptySubsequences: false) {
            let piece = String(fragment)
            if let key = plausibleKey(in: piece) {
                pairs.append((key, String(piece.dropFirst(key.count + 1))))
            } else if !pairs.isEmpty {
                // Devam parçası: bölünen virgül geri konur.
                pairs[pairs.count - 1].value += "," + piece
            }
        }
        return pairs
    }

    static func value(_ key: String, in labels: String) -> String? {
        pairs(in: labels).first { $0.key == key }?.value
    }

    /// Parça yeni bir çift mi başlatıyor? `=` öncesi boş olmamalı ve boşluk içermemeli.
    private static func plausibleKey(in fragment: String) -> String? {
        guard let separator = fragment.firstIndex(of: "=") else { return nil }
        let key = String(fragment[fragment.startIndex..<separator])
        guard !key.isEmpty,
              !key.contains(where: { $0.isWhitespace }) else { return nil }
        return key
    }
}

// MARK: - JSON ayrıştırma

/// `docker ps --format json` çıktısını `DockerContainer` listesine çevirir.
///
/// İki biçim de kabul edilir: satır başına bir JSON nesnesi (docker'ın bugünkü davranışı)
/// ve tek bir JSON dizisi (`docker compose ls` bu biçimi kullanıyor, docker sürümleri
/// arasında da değişiyor). Bozuk satır TÜM listeyi düşürmez: docker uyarı metnini de
/// stdout'a yazabiliyor.
nonisolated enum DockerContainerParser {

    static func containers(from output: String) -> [DockerContainer] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if trimmed.hasPrefix("[") {
            // Öğe öğe çözülür (`LenientArray` ile aynı gerekçe): tek bozuk kayıt bütün
            // listeyi düşürmemeli. Burada elle yapılıyor çünkü ayrıştırma `nonisolated`
            // kalmalı — liste arka planda çözülüyor.
            guard let objects = (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [Any]
            else { return [] }
            return objects.compactMap { object in
                guard let data = try? JSONSerialization.data(withJSONObject: object),
                      let decoded = try? JSONDecoder().decode(Line.self, from: data) else { return nil }
                return decoded.container
            }
        }

        return trimmed
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> DockerContainer? in
                let text = line.trimmingCharacters(in: .whitespaces)
                guard text.hasPrefix("{"),
                      let decoded = try? JSONDecoder().decode(Line.self, from: Data(text.utf8))
                else { return nil }
                return decoded.container
            }
    }

    /// CLI çıktısının tek satırı. `docker ps` ve `docker compose ps` alan adları
    /// örtüşmediği için ikisi de okunur (`Names` / `Name`, etiketler / `Project`+`Service`).
    private struct Line: Decodable {
        let container: DockerContainer

        private enum CodingKeys: String, CodingKey {
            case id = "ID"
            case names = "Names"
            case name = "Name"
            case image = "Image"
            case state = "State"
            case status = "Status"
            case labels = "Labels"
            case project = "Project"
            case service = "Service"
        }

        /// Yalnız `ID` zorunludur: kimliksiz kayıtla hiçbir komut kurulamaz, o satır atlanır.
        /// Diğer alanlar `decodeIfPresent` ile okunur — docker sürümleri alan ekleyip
        /// çıkarıyor ve eksik bir alan yüzünden container'ı düşürmek özelliği susturur.
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let id = try values.decode(String.self, forKey: .id)
            let names = try values.decodeIfPresent(String.self, forKey: .names)
                ?? values.decodeIfPresent(String.self, forKey: .name)
                ?? ""
            let labels = try values.decodeIfPresent(String.self, forKey: .labels) ?? ""

            container = DockerContainer(
                id: id,
                name: names.split(separator: ",").first.map(String.init) ?? "",
                image: try values.decodeIfPresent(String.self, forKey: .image) ?? "",
                state: try values.decodeIfPresent(String.self, forKey: .state) ?? "",
                status: try values.decodeIfPresent(String.self, forKey: .status) ?? "",
                // `docker compose ps` proje/servisi açık alanlarda verir; `docker ps`
                // yalnız etiketlerde. Açık alan varsa o tercih edilir.
                composeProject: Self.nonBlank(try values.decodeIfPresent(String.self, forKey: .project))
                    ?? Self.nonBlank(DockerLabels.value("com.docker.compose.project", in: labels)),
                composeService: Self.nonBlank(try values.decodeIfPresent(String.self, forKey: .service))
                    ?? Self.nonBlank(DockerLabels.value("com.docker.compose.service", in: labels)),
                composeConfigFiles: Self.configFiles(in: labels))
        }

        private static func configFiles(in labels: String) -> [String] {
            guard let raw = DockerLabels.value("com.docker.compose.project.config_files", in: labels)
            else { return [] }
            return raw.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        private static func nonBlank(_ value: String?) -> String? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else { return nil }
            return trimmed
        }
    }
}

// MARK: - Komut üretimi

/// `docker` çağrılarını ARGÜMAN DİZİSİ olarak kuran saf çekirdek.
///
/// `SSHCommand` ile aynı kural geçerlidir: komut satırı string birleştirmesiyle KURULMAZ.
/// Önce argüman dizisi üretilir, kabuğa verilecek metin ise her öğe ayrı ayrı
/// alıntılanarak elde edilir. Ayrıca hedef her zaman container KİMLİĞİDİR (onaltılık),
/// yani kullanıcı adı ne olursa olsun seçenek gibi okunamaz.
///
/// Ayrıştırmanın aksine bu tip `nonisolated` DEĞİLDİR (proje varsayılanı `MainActor`):
/// alıntılamayı `SSHCommand`'dan ödünç alıyor ve komutlar zaten paletten, yani ana
/// aktörden kuruluyor. Arka planda çalışacak olan yalnız `DockerCommandRunning.run`'dır.
enum DockerCommand {

    /// Her imajda bulunması garanti olan tek kabuk. `bash` çoğu alpine tabanlı imajda
    /// yoktur ve "shell açılmadı" hatası kullanıcıya hiçbir şey anlatmaz.
    static let defaultContainerShell = "/bin/sh"

    /// Geriye kalan komutlarda kullanılacak günlük kuyruğu; sınırsız `logs` devasa
    /// çıktıyı terminale boşaltır ve pencereyi kilitler.
    static let defaultLogTail = 200

    static func listContainers() -> [String] {
        ["ps", "--format", "json"]
    }

    static func openShell(containerID: String, shell: String = defaultContainerShell) -> [String] {
        ["exec", "-it", containerID, shell]
    }

    static func logs(containerID: String, tail: Int = defaultLogTail) -> [String] {
        ["logs", "--tail", String(tail), "--follow", containerID]
    }

    static func restart(containerID: String) -> [String] {
        ["restart", containerID]
    }

    /// `docker compose exec`. Compose dosyaları biliniyorsa her biri ayrı `-f` ile
    /// gönderilir; böylece komut HERHANGİ bir çalışma dizininden çalışır. Dosya
    /// bilinmiyorsa proje adı tek başına yeter — compose container'ı etiketlerden bulur.
    static func composeOpenShell(configFiles: [String],
                                 project: String,
                                 service: String,
                                 shell: String = defaultContainerShell) -> [String] {
        var arguments = ["compose"]
        for file in configFiles {
            arguments += ["-f", file]
        }
        arguments += ["-p", project, "exec", service, shell]
        return arguments
    }

    /// Argüman dizisinden kabuğa verilebilir tek satır.
    ///
    /// Alıntılama TEK yerde durur: `SSHCommand.posixQuoted`. İkinci bir kopya yazmak,
    /// birinde düzeltilen bir kaçış hatasının diğerinde yaşamaya devam etmesi demektir.
    static func commandLine(executablePath: String, arguments: [String]) -> String {
        SSHCommand.commandLine([executablePath] + arguments)
    }
}
