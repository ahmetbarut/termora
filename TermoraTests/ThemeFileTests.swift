import Foundation
import Testing
@testable import Termora

/// brief 3 "Tema Sistemi → Kullanıcı özel tema dosyası içe ve dışa aktarabilmelidir".
///
/// Bu suite yalnız SAF katmanı kilitler: bir JSON dosyasından temaya geçiş, kabul edilen
/// şekiller ve reddedilen dosyaların kullanıcıya NE anlattığı. Disk, panel ve depo yok.
@MainActor
@Suite("Tema dosyası çözme")
struct ThemeFileTests {

    /// Brief'in "Tema Sistemi" bölümündeki örnek dosyanın AYNISI: `id` yok, ANSI renkleri
    /// `ansi` dizisi yerine adlarıyla verilmiş. İçe aktarma bu şekli kabul etmelidir,
    /// yoksa brief'in kendi örneği Termora'ya yüklenemez.
    static let briefFormatJSON = """
    {
      "name": "Termora Dark",
      "background": "#080B18",
      "foreground": "#F4F6FF",
      "cursor": "#169CFF",
      "selection": "#263B70",
      "black": "#141827",
      "red": "#FF5D67",
      "green": "#32D583",
      "yellow": "#F5B942",
      "blue": "#169CFF",
      "magenta": "#A66BFF",
      "cyan": "#42D9E8",
      "white": "#E8ECF8"
    }
    """

    static let canonicalJSON = """
    {
      "id": "midnight",
      "name": "Midnight",
      "background": "#101015",
      "foreground": "#F0F0F0",
      "cursor": "#FF5500",
      "selection": "#33467C",
      "ansi": ["#000000", "#FF0000", "#00FF00", "#FFFF00",
               "#0000FF", "#FF00FF", "#00FFFF", "#FFFFFF",
               "#808080", "#FF8080", "#80FF80", "#FFFF80",
               "#8080FF", "#FF80FF", "#80FFFF", "#C0C0C0"]
    }
    """

    private func theme(_ json: String, fileName: String = "theme.json") throws -> Theme {
        try ThemeFile.theme(fromJSON: Data(json.utf8), fileName: fileName)
    }

    private func failure(_ json: String, fileName: String = "theme.json") throws -> ThemeFileError {
        do {
            let theme = try ThemeFile.theme(fromJSON: Data(json.utf8), fileName: fileName)
            Issue.record("Beklenen hata yerine tema çözüldü: \(theme.id)")
            throw ThemeFileError(reason: .emptyName, fileName: fileName)
        } catch let error as ThemeFileError {
            return error
        }
    }

    // MARK: - Kabul edilen şekiller

    @Test func readsTheCanonicalSixteenColourFile() throws {
        let theme = try theme(Self.canonicalJSON)
        #expect(theme.id == "midnight")
        #expect(theme.name == "Midnight")
        #expect(theme.background == "#101015")
        #expect(theme.selection == "#33467C")
        #expect(theme.ansi.count == 16)
        #expect(theme.ansi.first == "#000000")
        #expect(theme.ansi.last == "#C0C0C0")
    }

    @Test func readsTheBriefsNamedColourFileAndDerivesTheBrightHalf() throws {
        let theme = try theme(Self.briefFormatJSON)
        #expect(theme.name == "Termora Dark")
        #expect(theme.ansi.count == 16)
        #expect(Array(theme.ansi.prefix(8)) == ["#141827", "#FF5D67", "#32D583", "#F5B942",
                                                "#169CFF", "#A66BFF", "#42D9E8", "#E8ECF8"])
        for index in 0..<8 where theme.ansi.indices.contains(index + 8) {
            #expect(ThemeColorDerivation.brightened(theme.ansi[index]) == theme.ansi[index + 8],
                    "ansi[\(index + 8)] türetme kuralına uymuyor")
        }
    }

    @Test func eightEntryAnsiArrayAlsoDerivesTheBrightHalf() throws {
        let json = """
        {"name": "Eight", "background": "#000000", "foreground": "#FFFFFF",
         "cursor": "#FFFFFF", "selection": "#1F5FBF",
         "ansi": ["#141827", "#FF5D67", "#32D583", "#F5B942",
                  "#169CFF", "#A66BFF", "#42D9E8", "#E8ECF8"]}
        """
        let theme = try theme(json)
        #expect(theme.ansi.count == 16)
        #expect(theme.ansi.last == ThemeColorDerivation.brightened("#E8ECF8"))
    }

    /// `id` yoksa addan türetilir: dosyayı elle yazan kullanıcı kimlik uydurmak zorunda kalmasın.
    @Test func derivesAnIdentifierFromTheNameWhenTheFileHasNone() throws {
        #expect(try theme(Self.briefFormatJSON).id == "termora-dark")
    }

    @Test func identifierSlugIsLowercasedAsciiWithSingleHyphens() {
        #expect(ThemeIdentifier.slug(from: "Termora Dark") == "termora-dark")
        #expect(ThemeIdentifier.slug(from: "  Tokyo   Night!!  ") == "tokyo-night")
        #expect(ThemeIdentifier.slug(from: "Gece Teması") == "gece-temasi")
        #expect(ThemeIdentifier.slug(from: "Solarized (light)") == "solarized-light")
        // Hiç harf/rakam yoksa boş kimlik üretilmez; çakışma çözücü buna sayı ekler.
        #expect(ThemeIdentifier.slug(from: "***") == ThemeIdentifier.fallbackID)
        #expect(ThemeIdentifier.slug(from: "") == ThemeIdentifier.fallbackID)
    }

    /// Hex'ler tek biçime çekilir: dışa aktarılan dosya her zaman aynı görünür.
    @Test func normalisesHexColoursToUppercaseWithHash() throws {
        let json = """
        {"id": "lower", "name": "Lower", "background": "0a0b0c", "foreground": "#ffffff",
         "cursor": "#ff5500ff", "selection": "#33467c",
         "ansi": ["#000000", "#ff0000", "#00ff00", "#ffff00",
                  "#0000ff", "#ff00ff", "#00ffff", "#ffffff"]}
        """
        let theme = try theme(json)
        #expect(theme.background == "#0A0B0C")
        #expect(theme.foreground == "#FFFFFF")
        // Alfa kanalı korunur, yalnız büyük harfe çekilir.
        #expect(theme.cursor == "#FF5500FF")
        #expect(theme.ansi.first == "#000000")
        #expect(theme.ansi.dropFirst().first == "#FF0000")
    }

    // MARK: - Reddedilen dosyalar (brief 3 "Error State")

    @Test func rejectsDataThatIsNotJSON() throws {
        let error = try failure("this is not json", fileName: "notes.txt")
        guard case .invalidJSON = error.reason else {
            Issue.record("Beklenen .invalidJSON, gelen \(error.reason)")
            return
        }
        #expect(error.fileName == "notes.txt")
    }

    @Test func rejectsAFileWithNoBackgroundColour() throws {
        let json = """
        {"name": "No Background", "foreground": "#FFFFFF", "cursor": "#FFFFFF",
         "selection": "#1F5FBF", "ansi": ["#000000", "#FF0000", "#00FF00", "#FFFF00",
                                          "#0000FF", "#FF00FF", "#00FFFF", "#FFFFFF"]}
        """
        #expect(try failure(json).reason == .missingField("background"))
    }

    @Test func rejectsAFileWithNoColoursAtAll() throws {
        let json = """
        {"name": "Colourless", "background": "#000000", "foreground": "#FFFFFF",
         "cursor": "#FFFFFF", "selection": "#1F5FBF"}
        """
        #expect(try failure(json).reason == .missingField("ansi"))
    }

    /// Adlı renklerden biri eksikse EKSİK OLAN ad söylenir; "ansi" demek kullanıcıyı
    /// yanlış dosya alanına bakmaya gönderirdi.
    @Test func namesTheMissingAnsiColourWhenTheFileUsesNamedColours() throws {
        let json = """
        {"name": "Half", "background": "#000000", "foreground": "#FFFFFF",
         "cursor": "#FFFFFF", "selection": "#1F5FBF",
         "black": "#141827", "red": "#FF5D67", "green": "#32D583", "yellow": "#F5B942",
         "blue": "#169CFF", "magenta": "#A66BFF"}
        """
        #expect(try failure(json).reason == .missingField("cyan"))
    }

    @Test func rejectsAnUnusableNumberOfAnsiColours() throws {
        let json = """
        {"name": "Twelve", "background": "#000000", "foreground": "#FFFFFF",
         "cursor": "#FFFFFF", "selection": "#1F5FBF",
         "ansi": ["#000000", "#FF0000", "#00FF00", "#FFFF00", "#0000FF", "#FF00FF",
                  "#00FFFF", "#FFFFFF", "#808080", "#FF8080", "#80FF80", "#FFFF80"]}
        """
        #expect(try failure(json).reason == .unusableColorCount(12))
    }

    @Test func rejectsAColourThatIsNotHex() throws {
        let json = """
        {"name": "Bad Colour", "background": "midnight-blue", "foreground": "#FFFFFF",
         "cursor": "#FFFFFF", "selection": "#1F5FBF",
         "ansi": ["#000000", "#FF0000", "#00FF00", "#FFFF00",
                  "#0000FF", "#FF00FF", "#00FFFF", "#FFFFFF"]}
        """
        #expect(try failure(json).reason == .invalidColor(field: "background", value: "midnight-blue"))
    }

    @Test func rejectsABadColourInsideTheAnsiArray() throws {
        let json = """
        {"name": "Bad Ansi", "background": "#000000", "foreground": "#FFFFFF",
         "cursor": "#FFFFFF", "selection": "#1F5FBF",
         "ansi": ["#000000", "#FF0000", "#00FF00", "#FFFF00",
                  "#0000FF", "#FF00FF", "#00FFFF", "#12345"]}
        """
        #expect(try failure(json).reason == .invalidColor(field: "ansi[7]", value: "#12345"))
    }

    @Test func rejectsAnEmptyName() throws {
        let json = """
        {"id": "nameless", "name": "   ", "background": "#000000", "foreground": "#FFFFFF",
         "cursor": "#FFFFFF", "selection": "#1F5FBF",
         "ansi": ["#000000", "#FF0000", "#00FF00", "#FFFF00",
                  "#0000FF", "#FF00FF", "#00FFFF", "#FFFFFF"]}
        """
        #expect(try failure(json).reason == .emptyName)
    }

    // MARK: - Hata metni (brief 3 "Error State": ne oldu / neden / ne yapabilirim / teknik detay)

    @Test func everyFailureExplainsItselfInFourParts() {
        let reasons: [ThemeFileError.Reason] = [
            .unreadableFile("no such file"),
            .invalidJSON("unexpected character"),
            .missingField("cursor"),
            .invalidColor(field: "ansi[3]", value: "rgb(1,2,3)"),
            .unusableColorCount(3),
            .emptyName,
            .couldNotAddToLibrary("permission denied"),
            .couldNotSave("disk full"),
        ]
        for reason in reasons {
            let error = ThemeFileError(reason: reason, fileName: "aurora.json")
            #expect(!error.title.isEmpty, "\(reason) başlıksız")
            #expect(!error.message.isEmpty, "\(reason) açıklamasız")
            #expect(!error.recovery.isEmpty, "\(reason) çözüm önerisiz")
            #expect(error.technicalDetail.contains("aurora.json"), "\(reason) teknik detayı dosyayı anmıyor")
        }
    }

    /// Mesaj kullanıcıyı doğru alana gönderir: eksik alanın adı ve kötü değer metinde geçer.
    @Test func failureMessagesNameTheThingThatWentWrong() {
        let missing = ThemeFileError(reason: .missingField("cursor"), fileName: "aurora.json")
        #expect(missing.message.contains("cursor"))
        #expect(missing.message.contains("aurora.json"))
        #expect(missing.recovery.contains("cursor"))

        let badColor = ThemeFileError(reason: .invalidColor(field: "background", value: "midnight"),
                                      fileName: "aurora.json")
        #expect(badColor.message.contains("midnight"))
        #expect(badColor.message.contains("background"))

        let count = ThemeFileError(reason: .unusableColorCount(12), fileName: "aurora.json")
        #expect(count.message.contains("12"))

        let underlying = ThemeFileError(reason: .invalidJSON("Expected ',' at line 4"), fileName: "aurora.json")
        #expect(underlying.technicalDetail.contains("Expected ',' at line 4"))
    }

    /// Hata metni İngilizce ve teknik detay dışında kod terimi içermez (brief 3 "Uygulama Metin Dili").
    @Test func failureTextIsUserFacingEnglish() {
        let error = ThemeFileError(reason: .invalidJSON("boom"), fileName: "aurora.json")
        #expect(error.title == "Theme not imported")
        #expect(error.message.contains("aurora.json"))
        #expect(!error.message.contains("Optional("))
    }

    // MARK: - Dışa aktarma biçimi

    @Test func exportedDataRoundTripsBackIntoTheSameTheme() throws {
        let original = try theme(Self.canonicalJSON)
        let data = try ThemeFile.encoded(original)
        #expect(try ThemeFile.theme(fromJSON: data, fileName: "midnight.json") == original)
    }

    @Test func exportedDataIsReadableJSONWithEveryValue() throws {
        let data = try ThemeFile.encoded(try theme(Self.canonicalJSON))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"id\""))
        #expect(text.contains("\"name\""))
        #expect(text.contains("\"selection\""))
        #expect(text.contains("\"ansi\""))
        // Elle düzenlenebilir olsun: tek satırlık blob değil, satır sonuyla biten metin.
        #expect(text.contains("\n"))
        #expect(text.hasSuffix("\n"))
    }

    @Test func suggestedFileNameUsesTheIdentifier() throws {
        #expect(ThemeFile.suggestedFileName(for: try theme(Self.canonicalJSON)) == "midnight.json")
    }
}
