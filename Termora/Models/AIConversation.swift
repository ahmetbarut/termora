import Foundation

/// Bir mesajın kimden geldiği. `rawValue`'lar Ollama'nın chat API'siyle aynıdır.
enum AIMessageRole: String, Codable, CaseIterable {
    case system
    case user
    case assistant
}

/// Panelde görünen tek mesaj.
///
/// Burada tutulan metin HAM'dır (kullanıcının yazdığı, modelin döndürdüğü). Maskeleme
/// yalnız DIŞARI çıkarken yapılır (`AIRequestBuilder`): kullanıcı kendi yazdığını
/// ekranda maskelenmiş görmemeli, ama gönderilen metin maskelenmiş olmalı.
struct AIMessage: Identifiable, Equatable {
    let id: UUID
    let role: AIMessageRole
    var text: String
    let date: Date

    init(id: UUID = UUID(), role: AIMessageRole, text: String, date: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
    }
}
