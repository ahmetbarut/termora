import Foundation

struct TerminalProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var shellPath: String? = nil
    var startupDirectory: String? = nil
    var startupCommand: String? = nil
    var fontName: String? = nil
    var fontSize: Double? = nil
    var themeID: String? = nil
    var environment: [String: String] = [:]
}
