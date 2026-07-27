import Foundation
import Testing
@testable import Termora

@Suite("GitBranchReader")
@MainActor
struct GitBranchReaderTests {

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("termora-git-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeGitDirectory(head: String, in repo: URL) throws {
        let gitDir = repo.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try head.write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
    }

    @Test func readsBranchNameFromSymbolicRef() throws {
        let repo = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: repo) }
        try writeGitDirectory(head: "ref: refs/heads/main\n", in: repo)

        #expect(GitBranchReader.branchName(forDirectory: repo.path) == "main")
    }

    @Test func readsSlashedBranchName() throws {
        let repo = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: repo) }
        try writeGitDirectory(head: "ref: refs/heads/feature/status-bar\n", in: repo)

        #expect(GitBranchReader.branchName(forDirectory: repo.path) == "feature/status-bar")
    }

    @Test func shortensDetachedHeadToSevenCharacters() throws {
        let repo = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: repo) }
        try writeGitDirectory(head: "3f1c9a2b7d4e5f60718293a4b5c6d7e8f9012345\n", in: repo)

        #expect(GitBranchReader.branchName(forDirectory: repo.path) == "3f1c9a2")
    }

    @Test func walksUpFromNestedDirectory() throws {
        let repo = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: repo) }
        try writeGitDirectory(head: "ref: refs/heads/develop\n", in: repo)
        let nested = repo.appendingPathComponent("src/app/deep", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        #expect(GitBranchReader.branchName(forDirectory: nested.path) == "develop")
    }

    @Test func returnsNilWhenNoRepositoryUpToRoot() throws {
        let plain = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: plain) }

        #expect(GitBranchReader.branchName(forDirectory: plain.path) == nil)
    }

    @Test func followsGitdirFileOfWorktree() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let realGitDir = root.appendingPathComponent("real-git", isDirectory: true)
        try FileManager.default.createDirectory(at: realGitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/worktree-branch\n"
            .write(to: realGitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)

        let worktree = root.appendingPathComponent("wt", isDirectory: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try "gitdir: \(realGitDir.path)\n"
            .write(to: worktree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        #expect(GitBranchReader.branchName(forDirectory: worktree.path) == "worktree-branch")
    }

    @Test func rejectsGarbageHeadContents() {
        #expect(GitBranchReader.branchName(fromHeadContents: "") == nil)
        #expect(GitBranchReader.branchName(fromHeadContents: "ref: refs/tags/v1\n") == nil)
        #expect(GitBranchReader.branchName(fromHeadContents: "not-a-sha\n") == nil)
        #expect(GitBranchReader.branchName(fromHeadContents: "ref: refs/heads/\n") == nil)
    }
}
