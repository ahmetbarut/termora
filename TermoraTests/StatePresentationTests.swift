import Testing
@testable import Termora

/// briefs/3 "Durum Tasarımları": empty, loading ve error için TEK kural.
///
/// Kurallar metin olarak sınanıyor çünkü brief'in koyduğu şey bir görünüm değil bir
/// söz: hata dört soruyu yanıtlamalı, boş ekran tek cümle olmalı, yükleme kısa
/// sürerse hiç görünmemeli.
@Suite("Durum sunumları")
struct StatePresentationTests {

    /// briefs/3: hata mesajı ne başarısız oldu, muhtemel sebep, kullanıcı ne yapabilir
    /// ve teknik detay sorularını yanıtlamalı.
    @Test func anErrorStateAnswersTheBriefsFourQuestions() {
        let state = ErrorStateContent(
            title: "Shell başlatılamadı",
            reason: "/usr/local/bin/fish dosyası bulunamadı.",
            recovery: "Varsayılan shell ayarını kontrol edin.",
            technicalDetail: "ENOENT /usr/local/bin/fish"
        )

        #expect(!state.title.isEmpty)
        #expect(!state.reason.isEmpty)
        #expect(!state.recovery.isEmpty)
        #expect(state.technicalDetail?.isEmpty == false)
    }

    /// Teknik detay isteğe bağlı: her hatanın gösterilecek bir iç detayı yoktur ve
    /// boş bir "Details" bölümü açan hata, kullanıcıyı boşuna tıklatır.
    @Test func technicalDetailIsOptional() {
        let state = ErrorStateContent(title: "T", reason: "R", recovery: "F")
        #expect(state.technicalDetail == nil)
    }

    /// briefs/3 "Empty State": tek cümle, birincil eylem, illüstrasyon yok.
    @Test func anEmptyStateIsOneSentenceAndAtMostOneAction() {
        let withAction = EmptyStateContent(message: "No workspaces yet",
                                           actionTitle: "Create Workspace")
        #expect(withAction.actionTitle == "Create Workspace")

        let plain = EmptyStateContent(message: "No containers running")
        #expect(plain.actionTitle == nil)
    }

    /// briefs/3 "Loading State": *Shell birkaç yüz milisaniye içinde başlamıyorsa küçük
    /// bir durum göstergesi yeterlidir.* Yani gösterge hemen değil, GECİKMELİ çıkar —
    /// hızlı işlemde hiç görünmez ve ekran titremez.
    @Test func aLoadingIndicatorWaitsBeforeItAppears() {
        #expect(LoadingStateContent.delay >= .milliseconds(200))
        #expect(LoadingStateContent.delay <= .milliseconds(600))
    }

    /// briefs/3 "Uygulama Metin Dili": belirsiz OK/Yes butonu kullanılmaz — buton
    /// eylemi adlandırır.
    @Test func actionTitlesNameTheirAction() {
        let vague = ["OK", "Yes", "No", "Continue"]
        for title in vague {
            #expect(StateActionTitle.isVague(title), "\(title) belirsiz sayılmalı")
        }
        for title in ["Close Terminal", "Open Shell Settings", "Try Again"] {
            #expect(StateActionTitle.isVague(title) == false)
        }
    }
}
