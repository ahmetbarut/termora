import Foundation
import Testing
@testable import Termora

@Suite("GitRepositoryReader")
@MainActor
struct GitRepositoryReaderTests {

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("termora-repo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeRepository(named name: String, head: String, in parent: URL) throws -> URL {
        let repo = parent.appendingPathComponent(name, isDirectory: true)
        let gitDir = repo.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try head.write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        return repo
    }

    @Test func readsRepositoryNameAndBranch() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try makeRepository(named: "termora", head: "ref: refs/heads/main\n", in: root)

        let info = try #require(GitRepositoryReader.info(forDirectory: repo.path))
        #expect(info.repositoryName == "termora")
        #expect(info.branch == "main")
    }

    @Test func usesRepositoryFolderNameWhenStartingFromNestedDirectory() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try makeRepository(named: "my-project", head: "ref: refs/heads/develop\n", in: root)
        let nested = repo.appendingPathComponent("Sources/App", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let info = try #require(GitRepositoryReader.info(forDirectory: nested.path))
        #expect(info.repositoryName == "my-project")
        #expect(info.branch == "develop")
    }

    @Test func returnsNilWhenDirectoryIsNotInRepository() throws {
        let plain = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: plain) }

        #expect(GitRepositoryReader.info(forDirectory: plain.path) == nil)
    }

    @Test func returnsNilForEmptyPath() {
        #expect(GitRepositoryReader.info(forDirectory: "") == nil)
    }

    @Test func reportsDetachedHeadAsShortSha() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try makeRepository(
            named: "detached",
            head: "3f1c9a2b7d4e5f60718293a4b5c6d7e8f9012345\n",
            in: root
        )

        let info = try #require(GitRepositoryReader.info(forDirectory: repo.path))
        #expect(info.repositoryName == "detached")
        #expect(info.branch == "3f1c9a2")
    }

    @Test func keepsRepositoryNameWhenBranchIsUnreadable() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try makeRepository(named: "broken-head", head: "not-a-ref\n", in: root)

        let info = try #require(GitRepositoryReader.info(forDirectory: repo.path))
        #expect(info.repositoryName == "broken-head")
        #expect(info.branch == nil)
    }

    @Test func namesWorktreeFolderThatHoldsGitdirFile() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let realGitDir = root.appendingPathComponent("real-git", isDirectory: true)
        try FileManager.default.createDirectory(at: realGitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/feature/workspaces\n"
            .write(to: realGitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)

        let worktree = root.appendingPathComponent("termora-wt", isDirectory: true)
        let nested = worktree.appendingPathComponent("Termora/Services", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "gitdir: \(realGitDir.path)\n"
            .write(to: worktree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        let info = try #require(GitRepositoryReader.info(forDirectory: nested.path))
        #expect(info.repositoryName == "termora-wt")
        #expect(info.branch == "feature/workspaces")
    }

    @Test func equatableComparesNameAndBranch() {
        let a = GitRepositoryInfo(repositoryName: "termora", branch: "main")
        let b = GitRepositoryInfo(repositoryName: "termora", branch: "main")
        let c = GitRepositoryInfo(repositoryName: "termora", branch: nil)

        #expect(a == b)
        #expect(a != c)
    }
}
