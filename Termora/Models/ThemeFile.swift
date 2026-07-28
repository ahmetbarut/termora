import Foundation

/// brief 3 "Tema Sistemi → Kullanıcı özel tema dosyası içe ve dışa aktarabilmelidir".
///
/// Bir tema kimliği dosya adı olarak da kullanılır (`<id>.json`), bu yüzden kimlik dar bir
/// alfabeye çekilir: küçük ASCII harf/rakam ve tek tire. Kullanıcı dosyaya `id` yazmadıysa
/// ad bu kuralla kimliğe çevrilir; hiç harf/rakam yoksa boş kimlik yerine `fallbackID`
/// döner ve çakışma çözücü ona sayı ekler.
enum ThemeIdentifier {

    /// Ad hiç kullanılabilir karakter içermediğinde verilen kimlik.
    static let fallbackID = "custom-theme"

    static func slug(from name: String) -> String {
        let lowercased = name.lowercased()
        // "Gece Teması" → "gece temasi": aksan ve Latin dışı harfler ASCII'ye indirgenir,
        // yoksa kimlik dosya sisteminde ve Picker etiketlerinde sürprizler üretir.
        let ascii = lowercased.applyingTransform(StringTransform("Any-Latin; Latin-ASCII"),
                                                 reverse: false) ?? lowercased
        var slug = ""
        var separatorPending = false
        for scalar in ascii.unicodeScalars {
            let character = Character(scalar)
            if scalar.isASCII, character.isLetter || character.isNumber {
                if separatorPending && !slug.isEmpty {
                    slug.append("-")
                }
                separatorPending = false
                slug.append(character)
            } else {
                separatorPending = true
            }
        }
        return slug.isEmpty ? fallbackID : slug
    }
}

/// Tema dosyası okunamadığında/yazılamadığında kullanıcıya gösterilecek her şey.
///
/// brief 3 "Error State" dört soru sorar: ne başarısız oldu, muhtemel sebep, kullanıcı ne
/// yapabilir, teknik detay nasıl görüntülenir. Bu tip dördünü de taşır; çağıran taraf
/// hatayı sessizce yutamaz çünkü elinde yalnız bu metinler vardır.
struct ThemeFileError: Error, Equatable {

    enum Reason: Equatable {
        /// Dosya diskten okunamadı (taşınmış, silinmiş ya da izin yok).
        case unreadableFile(String)
        /// İçerik JSON değil.
        case invalidJSON(String)
        /// Zorunlu alan yok. İlişkili değer alanın DOSYADAKİ adıdır ("background", "cyan"…).
        case missingField(String)
        /// Alan var ama hex renk değil.
        case invalidColor(field: String, value: String)
        /// ANSI listesi 8 veya 16 dışında bir uzunlukta.
        case unusableColorCount(Int)
        case emptyName
        /// Tema çözüldü ama kullanıcı tema klasörüne yazılamadı.
        case couldNotAddToLibrary(String)
        /// Dışa aktarma sırasında hedefe yazılamadı.
        case couldNotSave(String)
    }

    let reason: Reason
    /// Kullanıcının seçtiği dosyanın adı; her metinde anılır ki hangi dosyadan söz
    /// edildiği belirsiz kalmasın.
    let fileName: String

    /// Ne başarısız oldu.
    var title: String {
        if case .couldNotSave = reason { return "Theme not exported" }
        return "Theme not imported"
    }

    /// Muhtemel sebep.
    var message: String {
        switch reason {
        case .unreadableFile:
            return "Termora could not open “\(fileName)”. The file may have been moved or renamed, "
                + "or Termora may not have permission to read it."
        case .invalidJSON:
            return "“\(fileName)” is not valid JSON. A missing comma, bracket or quote is the usual cause."
        case .missingField(let field):
            return "“\(fileName)” has no “\(field)” value, and a theme cannot be drawn without it."
        case .invalidColor(let field, let value):
            return "“\(fileName)” uses “\(value)” for “\(field)”, which is not a color Termora understands."
        case .unusableColorCount(let count):
            return "“\(fileName)” lists \(count) terminal colors. A theme needs either the 8 base "
                + "colors or all 16."
        case .emptyName:
            return "“\(fileName)” has no theme name, so it cannot be listed in Appearance settings."
        case .couldNotAddToLibrary:
            return "Termora read “\(fileName)” but could not copy it into your theme library."
        case .couldNotSave:
            return "Termora could not write “\(fileName)” to the folder you picked."
        }
    }

    /// Kullanıcı ne yapabilir.
    var recovery: String {
        switch reason {
        case .unreadableFile:
            return "Check that the file is still where you left it, then choose it again."
        case .invalidJSON:
            return "Open the file in a text editor, fix the JSON, then import it again."
        case .missingField(let field):
            return "Add a “\(field)” entry to the file, then import it again."
        case .invalidColor(let field, _):
            return "Write “\(field)” as a hex color such as “#1F5FBF”, then import the file again."
        case .unusableColorCount:
            return "Edit the “ansi” list so it holds 8 or 16 colors, then import the file again."
        case .emptyName:
            return "Add a “name” entry to the file, then import it again."
        case .couldNotAddToLibrary:
            return "Make sure Termora can write to your Application Support folder, then import it again."
        case .couldNotSave:
            return "Choose a folder you can write to, then export the theme again."
        }
    }

    /// Teknik detay: arayüz bunu ayrı ve ikincil gösterir, kullanıcı kopyalayıp
    /// bildirime ekleyebilsin.
    var technicalDetail: String {
        switch reason {
        case .unreadableFile(let detail), .invalidJSON(let detail),
             .couldNotAddToLibrary(let detail), .couldNotSave(let detail):
            return "\(fileName): \(detail)"
        case .missingField(let field):
            return "\(fileName): missing field “\(field)”"
        case .invalidColor(let field, let value):
            return "\(fileName): “\(field)” is “\(value)”, expected a hex color"
        case .unusableColorCount(let count):
            return "\(fileName): “ansi” holds \(count) colors, expected 8 or 16"
        case .emptyName:
            return "\(fileName): “name” is empty"
        }
    }
}

/// JSON dosyası ile `Theme` arasındaki TEK geçit. Paket temaları da, kullanıcının içe
/// aktardığı dosyalar da buradan geçer; böylece kabul edilen şekil tek yerde tanımlıdır.
///
/// Kabul edilen üç yazım:
/// 1. `ansi` dizisi 16 renkle (kanonik biçim, dışa aktarma bunu üretir),
/// 2. `ansi` dizisi 8 renkle — parlak yarı `ThemeColorDerivation` ile türetilir,
/// 3. brief 3'teki adlı renkler (`black`, `red` … `white`) — yine 8'den 16'ya türetilir.
enum ThemeFile {

    /// brief 3 "Tema Sistemi" örneğindeki renk adları, ANSI 0-7 sırasıyla.
    static let namedColorKeys = ["black", "red", "green", "yellow",
                                 "blue", "magenta", "cyan", "white"]

    static func theme(fromJSON data: Data, fileName: String) throws -> Theme {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ThemeFileError(reason: .invalidJSON(error.localizedDescription), fileName: fileName)
        }
        guard let fields = object as? [String: Any] else {
            throw ThemeFileError(reason: .invalidJSON("top level value is not an object"),
                                 fileName: fileName)
        }

        let name = try requiredString("name", in: fields, fileName: fileName)
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ThemeFileError(reason: .emptyName, fileName: fileName)
        }

        let background = try color("background", in: fields, fileName: fileName)
        let foreground = try color("foreground", in: fields, fileName: fileName)
        let cursor = try color("cursor", in: fields, fileName: fileName)
        let selection = try color("selection", in: fields, fileName: fileName)
        let ansi = try ansiColors(in: fields, fileName: fileName)

        // Verilen kimlik de aynı kuraldan geçer: dosya adı ondan üretiliyor.
        let requestedID = (fields["id"] as? String) ?? ""
        let id = requestedID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ThemeIdentifier.slug(from: name)
            : ThemeIdentifier.slug(from: requestedID)

        return Theme(id: id,
                     name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                     background: background,
                     foreground: foreground,
                     cursor: cursor,
                     selection: selection,
                     ansi: ansi)
    }

    /// Dışa aktarılan dosya elle düzenlenebilir olmalı: biçimli, sıralı ve satır sonuyla biter.
    static func encoded(_ theme: Theme) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(theme)
        data.append(0x0A)
        return data
    }

    static func suggestedFileName(for theme: Theme) -> String {
        "\(theme.id).json"
    }

    // MARK: - Alan çözme

    private static func requiredString(_ key: String,
                                       in fields: [String: Any],
                                       fileName: String) throws -> String {
        guard let value = fields[key] as? String else {
            throw ThemeFileError(reason: .missingField(key), fileName: fileName)
        }
        return value
    }

    private static func color(_ key: String,
                              in fields: [String: Any],
                              fileName: String) throws -> String {
        try normalizedHex(try requiredString(key, in: fields, fileName: fileName),
                          field: key,
                          fileName: fileName)
    }

    /// "0a0b0c" → "#0A0B0C". Alfa kanalı korunur, yalnız büyük harfe çekilir; böylece
    /// dışa aktarılan dosya her zaman aynı görünür ve karşılaştırılabilir.
    private static func normalizedHex(_ value: String,
                                      field: String,
                                      fileName: String) throws -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") {
            text.removeFirst()
        }
        guard text.count == 6 || text.count == 8, text.allSatisfy(\.isHexDigit) else {
            throw ThemeFileError(reason: .invalidColor(field: field, value: value), fileName: fileName)
        }
        return "#" + text.uppercased()
    }

    private static func ansiColors(in fields: [String: Any], fileName: String) throws -> [String] {
        if let listed = fields["ansi"] {
            return try ansiColors(fromList: listed, fileName: fileName)
        }
        // Adlı renklerden en az biri varsa kullanıcı brief'in biçimini yazıyor demektir;
        // eksik olanı "ansi" diye bildirmek onu yanlış satıra bakmaya gönderirdi.
        if namedColorKeys.contains(where: { fields[$0] != nil }) {
            let base = try namedColorKeys.map {
                try color($0, in: fields, fileName: fileName)
            }
            return withDerivedBrightHalf(base)
        }
        throw ThemeFileError(reason: .missingField("ansi"), fileName: fileName)
    }

    private static func ansiColors(fromList listed: Any, fileName: String) throws -> [String] {
        guard let entries = listed as? [Any] else {
            throw ThemeFileError(reason: .unusableColorCount(0), fileName: fileName)
        }
        guard entries.count == 8 || entries.count == 16 else {
            throw ThemeFileError(reason: .unusableColorCount(entries.count), fileName: fileName)
        }
        let colors = try entries.enumerated().map { index, entry -> String in
            let field = "ansi[\(index)]"
            guard let text = entry as? String else {
                throw ThemeFileError(reason: .invalidColor(field: field, value: "\(entry)"),
                                     fileName: fileName)
            }
            return try normalizedHex(text, field: field, fileName: fileName)
        }
        return colors.count == 8 ? withDerivedBrightHalf(colors) : colors
    }

    /// 8 temel renkten 16'ya: parlak yarı projedeki tek türetme kuralıyla üretilir.
    private static func withDerivedBrightHalf(_ base: [String]) -> [String] {
        base + base.map { ThemeColorDerivation.brightened($0) ?? $0 }
    }
}
