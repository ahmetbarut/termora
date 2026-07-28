import Foundation
import Testing
@testable import Termora

/// briefs/2 "Tehlikeli Komut Koruması".
///
/// Brief'in SINIRI bu testlerin yarısını oluşturur: "Koruma sistemi shell davranışını
/// bozmamalı ve her komuta müdahale etmemelidir. Yalnızca yüksek güvenle tespit edilen
/// işlemlerde uyarı verilmelidir." Bu yüzden "uyarı YOK" testleri en az "uyarı VAR"
/// testleri kadar önemlidir.
@Suite("Tehlikeli komut tespiti")
@MainActor
struct DangerousCommandTests {

    // MARK: - Her komuta müdahale edilmez

    @Test func everydayCommandsAreNeverFlagged() {
        let harmless = [
            "npm run dev",
            "php artisan serve",
            "php artisan queue:work",
            "php artisan migrate",
            "git status",
            "git pull --rebase",
            "docker compose up -d",
            "docker volume ls",
            "diskutil list",
            "ls -la",
            "tmux attach",
            "cd ~/Projects/pinro && npm test",
            "NODE_ENV=production npm run build",
            "dd if=source.img of=./backup.img",
            "mysql -e \"SELECT * FROM users\"",
        ]
        for command in harmless {
            #expect(DangerousCommand.inspect(command) == nil, "gereksiz uyarı: \(command)")
        }
    }

    /// Sınır tam olarak burada: proje içindeki bir klasörü silmek günlük iştir.
    @Test func aScopedRecursiveDeleteIsNotFlagged() {
        for command in ["rm -rf build",
                        "rm -rf node_modules",
                        "rm -rf ./dist",
                        "rm -rf /Users/dev/Projects/pinro/build"] {
            #expect(DangerousCommand.inspect(command) == nil, "gereksiz uyarı: \(command)")
        }
    }

    @Test func aCommandThatOnlyPrintsADangerousStringIsNotFlagged() {
        #expect(DangerousCommand.inspect("echo \"rm -rf /\"") == nil)
        #expect(DangerousCommand.inspect("grep \"DROP DATABASE\" schema.sql") == nil)
    }

    @Test func emptyInputIsNotACommand() {
        #expect(DangerousCommand.inspect("") == nil)
        #expect(DangerousCommand.inspect("   \n  ") == nil)
    }

    // MARK: - Geniş kapsamlı rm

    @Test func deletingTheRootOrHomeFolderIsHighRisk() throws {
        for command in ["rm -rf /",
                        "rm -rf /*",
                        "rm -r /",
                        "rm -rf ~",
                        "rm -rf $HOME",
                        "rm -rf ~/Library",
                        "rm -rf /Users",
                        "rm -rf /Users/dev",
                        "sudo rm -rf /System",
                        "rm -rf /var/www"] {
            let warning = try #require(DangerousCommand.inspect(command), "uyarı yok: \(command)")
            #expect(warning.risk == .high, "yanlış seviye: \(command)")
            #expect(warning.reason == .systemWideDelete, "yanlış gerekçe: \(command)")
        }
    }

    /// Görevin açık şartı: `rm -rf /` ile `rm -rf build` aynı şey değildir.
    @Test func theWorkingFolderIsDestructiveButNotTheSameAsTheRootFolder() throws {
        let workingFolder = try #require(DangerousCommand.inspect("rm -rf ."))
        #expect(workingFolder.risk == .caution)
        #expect(workingFolder.reason == .workingDirectoryDelete)

        let root = try #require(DangerousCommand.inspect("rm -rf /"))
        #expect(root.risk == .high)
        #expect(workingFolder.risk < root.risk)

        #expect(DangerousCommand.inspect("rm -rf build") == nil)
    }

    @Test func aDeleteWithoutRecursionIsNotBroadEnoughToWarn() {
        #expect(DangerousCommand.inspect("rm /tmp/termora.log") == nil)
        #expect(DangerousCommand.inspect("rm -f package-lock.json") == nil)
    }

    // MARK: - Disk ve aygıt

    @Test func writingStraightToADiskDeviceIsHighRisk() throws {
        let warning = try #require(DangerousCommand.inspect("dd if=/dev/zero of=/dev/disk2 bs=1m"))
        #expect(warning.risk == .high)
        #expect(warning.reason == .rawDeviceWrite)
    }

    @Test func formattingADiskIsHighRisk() throws {
        for command in ["diskutil eraseDisk JHFS+ Untitled /dev/disk2",
                        "diskutil partitionDisk /dev/disk2 1 GPT JHFS+ Data 100%",
                        "mkfs.ext4 /dev/sdb1",
                        "sudo newfs_hfs /dev/disk3s1"] {
            let warning = try #require(DangerousCommand.inspect(command), "uyarı yok: \(command)")
            #expect(warning.risk == .high)
            #expect(warning.reason == .diskFormat)
        }
    }

    // MARK: - Veritabanı

    @Test func droppingADatabaseIsHighRisk() throws {
        for command in ["dropdb production",
                        "psql -c \"DROP DATABASE termora\"",
                        "php artisan migrate:fresh",
                        "php artisan db:wipe",
                        "mongosh --eval \"db.dropDatabase()\""] {
            let warning = try #require(DangerousCommand.inspect(command), "uyarı yok: \(command)")
            #expect(warning.risk == .high)
            #expect(warning.reason == .databaseDrop)
        }
    }

    // MARK: - Docker

    @Test func removingADockerVolumeWarnsAndPruningWarnsHarder() throws {
        let single = try #require(DangerousCommand.inspect("docker volume rm termora_pgdata"))
        #expect(single.risk == .caution)
        #expect(single.reason == .dockerVolumeRemoval)

        let prune = try #require(DangerousCommand.inspect("docker volume prune -f"))
        #expect(prune.risk == .high)
        #expect(prune.reason == .dockerVolumeRemoval)
    }

    // MARK: - Git

    @Test func aForcedResetDiscardsWorkAndIsFlaggedAsDestructive() throws {
        let warning = try #require(DangerousCommand.inspect("git reset --hard HEAD~3"))
        #expect(warning.risk == .caution)
        #expect(warning.reason == .discardsLocalWork)

        #expect(DangerousCommand.inspect("git reset --soft HEAD~1") == nil)
        #expect(DangerousCommand.inspect("git reset") == nil)
    }

    @Test func cleaningUntrackedFilesIsAlsoDestructive() throws {
        let warning = try #require(DangerousCommand.inspect("git clean -fdx"))
        #expect(warning.reason == .discardsLocalWork)
        #expect(DangerousCommand.inspect("git clean --dry-run") == nil)
    }

    // MARK: - Korunan dizinlerin izinleri

    @Test func recursivePermissionChangesOnProtectedFoldersAreHighRisk() throws {
        for command in ["sudo chmod -R 777 /usr/local",
                        "chown -R root /System",
                        "sudo chmod -R 755 /"] {
            let warning = try #require(DangerousCommand.inspect(command), "uyarı yok: \(command)")
            #expect(warning.risk == .high)
            #expect(warning.reason == .protectedPermissionChange)
        }
    }

    @Test func permissionChangesInsideTheProjectAreLeftAlone() {
        #expect(DangerousCommand.inspect("chmod -R 755 ./public") == nil)
        #expect(DangerousCommand.inspect("chmod +x scripts/deploy.sh") == nil)
    }

    // MARK: - Uzak sunucu

    @Test func aRemoteRecursiveDeleteIsAlwaysHighRiskEvenWhenTheLocalRuleWouldStaySilent() throws {
        let warning = try #require(
            DangerousCommand.inspect("ssh deploy@pinro.app \"rm -rf /var/www/releases/*\"")
        )
        #expect(warning.risk == .high)
        #expect(warning.isRemote)
        #expect(warning.message.lowercased().contains("remote"))
    }

    @Test func aRemoteCommandInheritsTheReasonButNeverStaysMerelyCautious() throws {
        let warning = try #require(DangerousCommand.inspect("ssh deploy@pinro.app 'git reset --hard'"))
        #expect(warning.reason == .discardsLocalWork)
        #expect(warning.risk == .high)
        #expect(warning.isRemote)
    }

    /// Brief'in workspace örneğindeki `ssh deploy@pinro.app` satırı UYARISIZ açılmalı.
    @Test func openingAnSSHSessionWithoutARemoteCommandIsNotDangerous() {
        #expect(DangerousCommand.inspect("ssh deploy@pinro.app") == nil)
        #expect(DangerousCommand.inspect("ssh -p 2222 deploy@pinro.app") == nil)
    }

    // MARK: - Zincirlenmiş komutlar

    @Test func everyPartOfAChainedCommandIsInspected() throws {
        let warning = try #require(DangerousCommand.inspect("cd /tmp && rm -rf /"))
        #expect(warning.risk == .high)
        #expect(warning.command == "rm -rf /")
    }

    @Test func theMostSevereFindingWins() throws {
        let warning = try #require(DangerousCommand.inspect("git reset --hard; rm -rf /"))
        #expect(warning.risk == .high)
        #expect(warning.reason == .systemWideDelete)
    }

    @Test func aPipeIsAlsoABoundaryBetweenCommands() throws {
        let warning = try #require(DangerousCommand.inspect("cat list.txt | xargs rm -rf /"))
        #expect(warning.risk == .high)
    }

    // MARK: - Uyarının yüzü (renk TEK gösterge olamaz)

    @Test func eachRiskLevelHasItsOwnWordsAndItsOwnShape() {
        let labels = CommandRisk.allCases.map(\.label)
        let symbols = CommandRisk.allCases.map(\.symbolName)
        #expect(Set(labels).count == CommandRisk.allCases.count)
        #expect(Set(symbols).count == CommandRisk.allCases.count)
        // Renk ÜÇÜNCÜ sinyaldir, tek sinyal değil; yine de seviyeler ayrı renk taşır.
        #expect(Set(CommandRisk.allCases.map(\.colorToken.hex)).count == CommandRisk.allCases.count)
        for level in CommandRisk.allCases {
            #expect(!level.label.isEmpty)
            #expect(!level.symbolName.isEmpty)
            #expect(level.accessibilityLabel.count > level.label.count)
        }
    }

    @Test func riskLevelsAreOrderedFromLowToHigh() {
        #expect(CommandRisk.caution < CommandRisk.high)
        #expect(CommandRisk.allCases.first == .caution)
        #expect(CommandRisk.allCases.last == .high)
    }

    @Test func everyReasonSaysWhatTheCommandDoesInPlainEnglish() {
        for reason in DangerousCommandReason.allCases {
            #expect(reason.explanation.count > 20, "açıklama çok kısa: \(reason)")
            #expect(reason.explanation.hasSuffix("."), "cümle değil: \(reason)")
        }
        #expect(Set(DangerousCommandReason.allCases.map(\.explanation)).count
                == DangerousCommandReason.allCases.count)
    }

    /// Ekran okuyucu uyarıyı TEK başına anlamalı: seviye + ne olacağı bir arada.
    @Test func theSpokenWarningCarriesBothTheLevelAndTheConsequence() throws {
        let warning = try #require(DangerousCommand.inspect("rm -rf /"))
        #expect(warning.accessibilityLabel.contains(CommandRisk.high.accessibilityLabel))
        #expect(warning.accessibilityLabel.contains(warning.message))
    }

    @Test func theWarningNamesTheExactSubCommandItObjectsTo() throws {
        let warning = try #require(DangerousCommand.inspect("npm run build && docker volume prune"))
        #expect(warning.command == "docker volume prune")
    }
}
