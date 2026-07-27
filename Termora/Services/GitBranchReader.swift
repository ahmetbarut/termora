import Foundation

/// Çalışma dizininden yukarı yürüyerek `.git/HEAD` okur ve dal adını çözer.
/// Git komutu çalıştırılmaz; yalnız dosya okunur (durum çubuğu 1 Hz'de çağırır).
enum GitBranchReader {

    /// `dir` ve üstündeki dizinlerde ilk bulunan deponun dal adı; yoksa nil.
    static func branchName(forDirectory dir: String) -> String? {
        var current = URL(fileURLWithPath: dir, isDirectory: true).standardizedFileURL
        while true {
            let gitPath = current.appendingPathComponent(".git")
            if let headURL = headURL(forGitPath: gitPath),
               let data = try? Data(contentsOf: headURL),
               let text = String(data: data, encoding: .utf8),
               let name = branchName(fromHeadContents: text) {
                return name
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path { return nil }
            current = parent
        }
    }

    /// `.git/HEAD` içeriğini ayrıştırır: "ref: refs/heads/X" → X, 40 karakterlik SHA → ilk 7.
    static func branchName(fromHeadContents contents: String) -> String? {
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("ref: ") {
            let ref = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            let headsPrefix = "refs/heads/"
            guard ref.hasPrefix(headsPrefix) else { return nil }
            let name = String(ref.dropFirst(headsPrefix.count))
            return name.isEmpty ? nil : name
        }

        guard trimmed.count == 40, trimmed.allSatisfy({ $0.isHexDigit }) else { return nil }
        return String(trimmed.prefix(7))
    }

    /// `.git` bir dizin ise HEAD doğrudan içindedir; bir dosya ise ("gitdir: ...") worktree'dir.
    private static func headURL(forGitPath gitPath: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitPath.path, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue {
            return gitPath.appendingPathComponent("HEAD")
        }
        guard let data = try? Data(contentsOf: gitPath),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "gitdir: "
        guard trimmed.hasPrefix(prefix) else { return nil }
        let raw = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        let base = raw.hasPrefix("/")
            ? URL(fileURLWithPath: raw, isDirectory: true)
            : gitPath.deletingLastPathComponent().appendingPathComponent(raw, isDirectory: true)
        return base.standardizedFileURL.appendingPathComponent("HEAD")
    }
}
