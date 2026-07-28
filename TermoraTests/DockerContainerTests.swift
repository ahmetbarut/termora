import Foundation
import Testing
@testable import Termora

/// briefs/2 "Docker Entegrasyonu": Termora daemon soketine konuşmaz, `docker` CLI'ını
/// çalıştırır. Bu süit CLI çıktısının AYRIŞTIRILMASINI ve üretilen ARGÜMAN DİZİLERİNİ
/// doğrular — hiçbir test gerçek docker çağırmaz.
@Suite("Docker CLI çıktısını ayrıştırma")
struct DockerContainerParsingTests {

    /// `docker ps --format json` satır satır JSON (NDJSON) yayar; dizi DEĞİLDİR.
    private static let twoLines = """
        {"ID":"2fefa732134c","Image":"graylog/graylog:6.1","Names":"delivery-graylog-1","State":"running","Status":"Up 41 minutes (healthy)"}
        {"ID":"15a91cae2b85","Image":"sail-8.5/app","Names":"delivery-app-1","State":"running","Status":"Up 41 minutes"}
        """

    @Test func parsesNewlineDelimitedObjects() {
        let containers = DockerContainerParser.containers(from: Self.twoLines)

        #expect(containers.map(\.id) == ["2fefa732134c", "15a91cae2b85"])
        #expect(containers.first?.name == "delivery-graylog-1")
        #expect(containers.first?.image == "graylog/graylog:6.1")
        #expect(containers.first?.state == "running")
        #expect(containers.first?.status == "Up 41 minutes (healthy)")
    }

    /// Bazı docker/compose sürümleri aynı bilgiyi TEK bir JSON dizisi olarak yazar.
    /// İki biçim de aynı sonucu vermelidir, yoksa özellik sürüme göre sessizce boşalır.
    @Test func parsesJSONArrayForm() {
        let array = """
            [{"ID":"aaa111","Names":"one","State":"running"},{"ID":"bbb222","Names":"two","State":"running"}]
            """

        #expect(DockerContainerParser.containers(from: array).map(\.id) == ["aaa111", "bbb222"])
    }

    @Test func emptyOutputYieldsNoContainers() {
        #expect(DockerContainerParser.containers(from: "").isEmpty)
        #expect(DockerContainerParser.containers(from: "   \n\n ").isEmpty)
    }

    /// Bozuk bir satır TÜM listeyi düşürmemeli: docker uyarı metnini de stdout'a yazabilir.
    @Test func skipsUnparsableLinesAndKeepsTheRest() {
        let mixed = """
            WARNING: daemon is slow
            {"ID":"aaa111","Names":"one","State":"running"}
            not json at all
            """

        #expect(DockerContainerParser.containers(from: mixed).map(\.id) == ["aaa111"])
    }

    /// Kimliksiz kayıt kullanılamaz (her komut kimlikle kurulur) — atlanır.
    @Test func skipsObjectsWithoutAnIdentifier() {
        #expect(DockerContainerParser.containers(from: #"{"Names":"orphan","State":"running"}"#).isEmpty)
    }

    /// İleri uyumluluk: bilinmeyen alanlar kaydı düşürmez, eksik alanlar boşa düşer.
    @Test func toleratesUnknownAndMissingFields() {
        let line = #"{"ID":"aaa111","Names":"one","SomethingNewInDocker42":{"nested":true}}"#
        let container = DockerContainerParser.containers(from: line).first

        #expect(container?.id == "aaa111")
        #expect(container?.image == "")
        #expect(container?.state == "")
    }

    /// Bir container'ın birden çok adı olabilir; başlıkta ilki kullanılır.
    @Test func usesTheFirstOfSeveralNames() {
        let line = #"{"ID":"aaa111","Names":"primary,secondary","State":"running"}"#

        #expect(DockerContainerParser.containers(from: line).first?.name == "primary")
    }

    /// Adı olmayan container kimliğiyle anılır — başlıkta boş satır görünmemeli.
    @Test func fallsBackToTheIdentifierWhenThereIsNoName() {
        let line = #"{"ID":"aaa111","State":"running"}"#

        #expect(DockerContainerParser.containers(from: line).first?.displayName == "aaa111")
    }
}

@Suite("Docker etiketlerini ayrıştırma")
struct DockerLabelParsingTests {

    /// Gerçek bir `docker ps` çıktısından alınmış etiket dizesi. Kritik nokta: DEĞERLER
    /// virgül içerir (`maintainer=Graylog, Inc. …`, `depends_on=a:…,b:…`), yani etiketleri
    /// düz virgülden bölmek yanlış çiftler üretir.
    private static let realLabels = """
        com.docker.compose.config-hash=a313dc28,com.docker.compose.container-number=1,\
        com.docker.compose.depends_on=opensearch:service_started:false,mongodb:service_started:false,\
        com.docker.compose.oneoff=False,com.docker.compose.project=delivery-backend,\
        com.docker.compose.project.config_files=/Users/dev/delivery-backend/compose.yaml,\
        com.docker.compose.project.working_dir=/Users/dev/delivery-backend,\
        com.docker.compose.service=graylog,com.docker.compose.version=5.1.2,\
        maintainer=Graylog, Inc. <hello@graylog.com>,org.label-schema.version=6.1.16
        """

    @Test func readsComposeProjectAndService() {
        #expect(DockerLabels.value("com.docker.compose.project", in: Self.realLabels) == "delivery-backend")
        #expect(DockerLabels.value("com.docker.compose.service", in: Self.realLabels) == "graylog")
    }

    /// Virgüllü bir değer bir SONRAKİ anahtarı yutmamalı.
    @Test func aValueContainingCommasStaysWhole() {
        #expect(DockerLabels.value("com.docker.compose.depends_on", in: Self.realLabels)
                == "opensearch:service_started:false,mongodb:service_started:false")
        #expect(DockerLabels.value("maintainer", in: Self.realLabels) == "Graylog, Inc. <hello@graylog.com>")
    }

    @Test func missingKeyIsNil() {
        #expect(DockerLabels.value("com.docker.compose.project", in: "") == nil)
        #expect(DockerLabels.value("nope", in: Self.realLabels) == nil)
    }

    /// Anahtar adı başka bir anahtarın SONEKİ olmamalı: "compose.project" araması
    /// "compose.project.config_files" değerini döndürmemeli.
    @Test func doesNotMatchALongerKeyThatStartsTheSameWay() {
        let labels = "com.docker.compose.project.config_files=/tmp/a.yaml,com.docker.compose.project=demo"

        #expect(DockerLabels.value("com.docker.compose.project", in: labels) == "demo")
    }

    @Test func containerCarriesItsComposeIdentityAndConfigFiles() {
        let line = """
            {"ID":"aaa111","Names":"one","State":"running","Labels":"\(Self.realLabels.replacingOccurrences(of: "\"", with: ""))"}
            """
        let container = DockerContainerParser.containers(from: line).first

        #expect(container?.composeProject == "delivery-backend")
        #expect(container?.composeService == "graylog")
        #expect(container?.composeConfigFiles == ["/Users/dev/delivery-backend/compose.yaml"])
    }
}

@Suite("Docker Compose servis listesi")
struct DockerComposeServiceTests {

    private func container(_ id: String,
                           project: String?,
                           service: String?,
                           configFiles: [String] = ["/tmp/compose.yaml"]) -> DockerContainer {
        DockerContainer(id: id,
                        name: id,
                        image: "img",
                        state: "running",
                        status: "Up",
                        composeProject: project,
                        composeService: service,
                        composeConfigFiles: project == nil ? [] : configFiles)
    }

    /// Servis listesi ÇALIŞAN container'lardan türetilir: ek bir `docker compose ps`
    /// süreci başlatmadan (bkz. DockerStore ölçüm notu) aynı bilgi elde edilir.
    @Test func derivesServicesFromRunningContainers() {
        let services = DockerComposeService.services(in: [
            container("a", project: "shop", service: "web"),
            container("b", project: "shop", service: "db"),
            container("c", project: nil, service: nil),
        ])

        #expect(services.map(\.id) == ["shop/db", "shop/web"])
        #expect(services.first?.displayName == "shop / db")
    }

    /// Aynı servisin birden çok kopyası (`--scale`) tek satırda toplanır.
    @Test func collapsesReplicasOfTheSameService() {
        let services = DockerComposeService.services(in: [
            container("a", project: "shop", service: "web"),
            container("b", project: "shop", service: "web"),
        ])

        #expect(services.count == 1)
        #expect(services.first?.containerIDs == ["a", "b"])
    }

    /// Compose'a ait olmayan container servis listesine girmez.
    @Test func plainContainersAreNotComposeServices() {
        #expect(DockerComposeService.services(in: [container("a", project: nil, service: nil)]).isEmpty)
    }

    /// Servis adı olmayan (yalnız proje etiketli) kayıt da listelenemez.
    @Test func aProjectWithoutAServiceNameIsSkipped() {
        #expect(DockerComposeService.services(in: [container("a", project: "shop", service: nil)]).isEmpty)
    }
}

/// `DockerCommand` alıntılamayı `SSHCommand`'dan ödünç aldığı için `MainActor`'dadır.
@MainActor
@Suite("Docker komut satırı üretimi")
struct DockerCommandTests {

    @Test func listCommandAsksForMachineReadableOutput() {
        #expect(DockerCommand.listContainers() == ["ps", "--format", "json"])
    }

    /// Container içine shell açmak: interaktif TTY + kimlik + kabuk. Kimlik AYRI bir
    /// argümandır; string birleştirme yoktur (kabuk enjeksiyonu).
    @Test func openShellRunsExecWithATTY() {
        #expect(DockerCommand.openShell(containerID: "2fefa732134c")
                == ["exec", "-it", "2fefa732134c", "/bin/sh"])
    }

    /// Kabuk seçilebilir ama varsayılan HER imajda bulunan `/bin/sh`'tir.
    @Test func openShellHonoursAnExplicitShell() {
        #expect(DockerCommand.openShell(containerID: "abc", shell: "/bin/bash")
                == ["exec", "-it", "abc", "/bin/bash"])
        #expect(DockerCommand.defaultContainerShell == "/bin/sh")
    }

    @Test func logsFollowsWithABoundedBacklog() {
        #expect(DockerCommand.logs(containerID: "abc")
                == ["logs", "--tail", "200", "--follow", "abc"])
    }

    @Test func restartTargetsASingleContainer() {
        #expect(DockerCommand.restart(containerID: "abc") == ["restart", "abc"])
    }

    /// `docker compose exec` her compose dosyasını ayrı `-f` ile alır ve proje adını
    /// açıkça belirtir; böylece komut HERHANGİ bir çalışma dizininden doğru çalışır.
    @Test func composeExecPassesEveryConfigFileAndTheProjectName() {
        #expect(DockerCommand.composeOpenShell(configFiles: ["/a/compose.yaml", "/a/override.yaml"],
                                               project: "shop",
                                               service: "web")
                == ["compose", "-f", "/a/compose.yaml", "-f", "/a/override.yaml",
                    "-p", "shop", "exec", "web", "/bin/sh"])
    }

    /// Compose dosyası bilinmiyorsa proje adı tek başına yeter: compose çalışan
    /// container'ı etiketlerden bulur.
    @Test func composeExecWorksWithTheProjectNameAlone() {
        #expect(DockerCommand.composeOpenShell(configFiles: [], project: "shop", service: "web")
                == ["compose", "-p", "shop", "exec", "web", "/bin/sh"])
    }

    // MARK: - Kabuğa verilen metin

    @Test func commandLineQuotesEveryArgumentSeparately() {
        #expect(DockerCommand.commandLine(executablePath: "/usr/local/bin/docker",
                                          arguments: ["exec", "-it", "abc", "/bin/sh"])
                == "/usr/local/bin/docker exec -it abc /bin/sh")
    }

    /// Düşmanca bir imaj/servis adı komutu BÖLEMEZ — tek bir alıntılanmış argüman kalır.
    @Test func aHostileArgumentStaysInsideOneQuotedWord() {
        #expect(DockerCommand.commandLine(executablePath: "/usr/local/bin/docker",
                                          arguments: ["exec", "-it", "abc; rm -rf ~", "/bin/sh"])
                == "/usr/local/bin/docker exec -it 'abc; rm -rf ~' /bin/sh")
    }

    /// Docker yolunun kendisi de boşluk içerebilir (kullanıcı kurulumu).
    @Test func theExecutablePathIsQuotedToo() {
        #expect(DockerCommand.commandLine(executablePath: "/Applications/Docker Beta/docker",
                                          arguments: ["ps"])
                == "'/Applications/Docker Beta/docker' ps")
    }
}
