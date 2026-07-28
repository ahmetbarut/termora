import Foundation

/// Workspace kartında gösterilen depo özeti: deponun adı ve varsa mevcut dal.
struct GitRepositoryInfo: Equatable {
    /// `.git` girdisini barındıran klasörün adı (tam yol değil).
    var repositoryName: String
    /// Dal adı; HEAD okunamazsa nil.
    var branch: String?
}

/// Bir dizinin hangi depoya ait olduğunu dosya okuyarak çözer; git komutu çalıştırılmaz.
enum GitRepositoryReader {

    /// `dir` ve üstündeki ilk deponun bilgisi; depo değilse nil.
    static func info(forDirectory dir: String) -> GitRepositoryInfo? {
        guard let root = repositoryRoot(forDirectory: dir) else { return nil }
        let name = root.lastPathComponent
        guard !name.isEmpty, name != "/" else { return nil }
        return GitRepositoryInfo(
            repositoryName: name,
            branch: GitBranchReader.branchName(forDirectory: root.path)
        )
    }

    /// `.git` girdisini (dizin ya da worktree dosyası) barındıran ilk klasörü yukarı yürüyerek bulur.
    private static func repositoryRoot(forDirectory dir: String) -> URL? {
        guard !dir.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        var current = URL(fileURLWithPath: dir, isDirectory: true).standardizedFileURL
        while true {
            let gitPath = current.appendingPathComponent(".git").path
            if FileManager.default.fileExists(atPath: gitPath) { return current }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path { return nil }
            current = parent
        }
    }
}
