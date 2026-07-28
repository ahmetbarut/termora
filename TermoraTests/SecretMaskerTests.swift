import Foundation
import Testing
@testable import Termora

/// briefs/2 "Secret Maskeleme": AI'a veri gönderilmeden önce hassas değerler maskelenir.
///
/// Buradaki bütün sırlar SAHTE'dir — gerçek görünümlü, ama hiçbiri geçerli bir anahtar
/// değildir. Kural: yanlış negatif (sızan sır) yanlış pozitiften (gereksiz maskeleme)
/// daha tehlikelidir; kararsız kalınan yerde maskelenir.
@Suite("Secret maskeleme")
@MainActor
struct SecretMaskerTests {

    private let placeholder = SecretMasker.placeholder

    // MARK: - Brief'in kendi örneği

    @Test func theBriefExampleIsMaskedExactlyAsWritten() {
        let result = SecretMasker.mask("Authorization: Bearer sk-proj-123456")
        #expect(result.maskedText == "Authorization: Bearer [REDACTED]")
        #expect(result.findings.map(\.kind) == [.authorizationHeader])
    }

    // MARK: - Maskeleme sırrın uzunluğunu sızdırmaz

    @Test func thePlaceholderIsConstantSoTheSecretLengthNeverLeaks() {
        let short = SecretMasker.mask("API_TOKEN=ab12cd").maskedText
        let long = SecretMasker.mask("API_TOKEN=ab12cd" + String(repeating: "x", count: 200)).maskedText
        #expect(short == long)
        #expect(short == "API_TOKEN=\(placeholder)")
    }

    @Test func theMaskedTextNeverContainsAnyPartOfTheSecret() {
        let secret = "hunter2-swordfish-9000"
        let result = SecretMasker.mask("DB_PASSWORD=\(secret)")
        #expect(!result.maskedText.contains("hunter2"))
        #expect(!result.maskedText.contains(secret))
    }

    // MARK: - Zararsız satırlar korunur (aşırı maskeleme çıktıyı işe yaramaz hâle getirir)

    @Test func harmlessEnvironmentLinesAreLeftAlone() {
        let harmless = """
        PATH=/usr/bin:/bin
        NODE_ENV=production
        LANG=en_US.UTF-8
        EDITOR=vim
        HOME=/Users/dev
        """
        let result = SecretMasker.mask(harmless)
        #expect(result.maskedText == harmless)
        #expect(result.findings.isEmpty)
        #expect(result.didFindSecrets == false)
    }

    /// Yol/dosya adları sır değildir: `*_PATH`, `*_FILE`, `*_DIR` maskelenmez.
    @Test func pathsToKeyFilesAreNotSecretsThemselves() {
        let lines = """
        SSH_KEY_PATH=/Users/dev/.ssh/id_ed25519
        SECRET_FILE=/etc/termora/secrets.env
        TOKEN_DIR=/var/tmp/tokens
        """
        #expect(SecretMasker.mask(lines).maskedText == lines)
    }

    @Test func plainTerminalOutputIsUntouched() {
        let output = """
        $ npm run build
        > vite build
        ✓ built in 4.18s
        """
        let result = SecretMasker.mask(output)
        #expect(result.maskedText == output)
        #expect(result.summary == SecretMasker.noSecretsSummary)
    }

    // MARK: - Adı sır söyleyen atamalar (.env değerleri, parolalar)

    @Test func valuesWhoseNameNamesASecretAreMasked() {
        let cases = [
            "DB_PASSWORD=hunter2",
            "export API_KEY=abcdef123456",
            "STRIPE_SECRET=whatever-value",
            "SESSION_TOKEN=aaaabbbbcccc",
            "client_secret=0123456789abcdef",
        ]
        for line in cases {
            let result = SecretMasker.mask(line)
            #expect(result.didFindSecrets, "maskelenmedi: \(line)")
            #expect(result.maskedText.hasSuffix(placeholder), "maskelenmedi: \(line)")
        }
    }

    @Test func aShellVariableReferenceIsNotMaskedBecauseItLeaksNothing() {
        #expect(SecretMasker.mask("DB_PASSWORD=$DB_PASSWORD").maskedText == "DB_PASSWORD=$DB_PASSWORD")
        #expect(SecretMasker.mask("API_KEY=\"${API_KEY}\"").maskedText == "API_KEY=\"${API_KEY}\"")
    }

    @Test func aWordThatMerelyStartsLikeASecretNameIsNotMasked() {
        // "AUTHOR" sadece "auth" ile başlar; ad parçalara ayrılıp tam sözcük aranır.
        #expect(SecretMasker.mask("AUTHOR=Ahmet Barut").maskedText == "AUTHOR=Ahmet Barut")
        #expect(SecretMasker.mask("KEYBOARD_LAYOUT=us").maskedText == "KEYBOARD_LAYOUT=us")
    }

    @Test func jsonAndYamlValuesAreMaskedToo() {
        #expect(SecretMasker.mask("  \"api_key\": \"abc123def456\",").maskedText
                == "  \"api_key\": \"\(placeholder)\",")
        #expect(SecretMasker.mask("password: hunter2").maskedText == "password: \(placeholder)")
    }

    // MARK: - Bilinen anahtar biçimleri (adı olmasa da tanınır)

    @Test func awsAccessKeyIDsAreMaskedWhereverTheyAppear() {
        let result = SecretMasker.mask("aws sts get-caller-identity for AKIAJ7EXAMPLE4TERMOR now")
        #expect(!result.maskedText.contains("AKIAJ7EXAMPLE4TERMOR"))
        #expect(result.maskedText.contains(placeholder))
        #expect(result.findings.map(\.kind) == [.awsAccessKey])
    }

    @Test func gitHubTokensAreMasked() {
        let classic = "remote: token ghp_0000abcdEFGH1234ijklMNOP5678qrstUVWX used"
        #expect(!SecretMasker.mask(classic).maskedText.contains("ghp_0000abcdEFGH1234ijklMNOP5678qrstUVWX"))

        let fineGrained = "github_pat_11AAAAAA0abcdefghijklmn_0123456789ABCDEFGHIJ"
        let result = SecretMasker.mask(fineGrained)
        #expect(result.maskedText == placeholder)
        #expect(result.findings.map(\.kind) == [.githubToken])
    }

    @Test func vendorApiKeyPrefixesAreMasked() {
        for key in ["sk-ant-api03-0000fake1111", "xoxb-000000-111111-fakeSlackToken", "glpat-FAKEfake1234567890"] {
            let result = SecretMasker.mask("token is \(key) ok")
            #expect(!result.maskedText.contains(key), "maskelenmedi: \(key)")
        }
    }

    @Test func jsonWebTokensAreMasked() {
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.fakeSignature0123"
        let result = SecretMasker.mask("cookie was set with \(jwt)")
        #expect(!result.maskedText.contains(jwt))
        #expect(result.findings.map(\.kind) == [.jsonWebToken])
    }

    // MARK: - HTTP başlıkları, çerezler, URL parolaları

    @Test func aBearerTokenIsMaskedButTheSchemeSurvives() {
        let result = SecretMasker.mask("curl -H \"Authorization: Bearer ghp_fakeTOKEN0123456789abcdefXYZ\" https://api.example.com/v1/users")
        #expect(result.maskedText
                == "curl -H \"Authorization: Bearer \(placeholder)\" https://api.example.com/v1/users")
        // URL, yöntem ve başlık adı korunur — çıktı hâlâ okunabilir olmalı.
        #expect(result.maskedText.contains("https://api.example.com/v1/users"))
    }

    @Test func basicCredentialsAreMaskedEvenThoughTheyAreNotBearer() {
        let result = SecretMasker.mask("Authorization: Basic ZGV2OnN1cGVyc2VjcmV0")
        #expect(result.maskedText == "Authorization: Basic \(placeholder)")
    }

    @Test func apiKeyHeadersAreMasked() {
        #expect(SecretMasker.mask("X-Api-Key: 8f14e45fceea167a5a36dedd4bea2543").maskedText
                == "X-Api-Key: \(placeholder)")
    }

    @Test func cookieAndSessionValuesAreMasked() {
        let result = SecretMasker.mask("Cookie: session=abc123; remember_me=yes")
        #expect(result.maskedText == "Cookie: \(placeholder)")
        #expect(result.findings.map(\.kind) == [.cookie])

        #expect(SecretMasker.mask("Set-Cookie: laravel_session=eyJpdiI6ImZha2UifQ%3D%3D; Path=/").maskedText
                == "Set-Cookie: \(placeholder)")
    }

    @Test func passwordsInsideConnectionURLsAreMaskedWithoutLosingTheHost() {
        let result = SecretMasker.mask("DATABASE_URL=postgres://app:s3cr3t-pw@db.internal:5432/app")
        #expect(result.maskedText == "DATABASE_URL=postgres://app:\(placeholder)@db.internal:5432/app")
        #expect(result.findings.map(\.kind) == [.urlPassword])
    }

    @Test func longCommandLineSecretFlagsAreMasked() {
        #expect(SecretMasker.mask("mysqldump --password=hunter2 termora").maskedText
                == "mysqldump --password=\(placeholder) termora")
        #expect(SecretMasker.mask("gh auth login --token ghp_fakeTOKEN0123456789abcdefXYZ").maskedText
                == "gh auth login --token \(placeholder)")
    }

    // MARK: - Private key BLOKLARI (satır satır değil, blok olarak)

    @Test func aPrivateKeyBlockIsMaskedAsOneUnit() {
        let text = """
        keeping this line
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gt
        ZmFrZWZha2VmYWtlZmFrZWZha2VmYWtlZmFrZWZha2VmYWtlZmFrZWZha2VmYWtlZg==
        -----END OPENSSH PRIVATE KEY-----
        and this one
        """
        let result = SecretMasker.mask(text)
        #expect(result.maskedText == """
        keeping this line
        \(placeholder)
        and this one
        """)
        #expect(result.findings.map(\.kind) == [.privateKeyBlock])
        #expect(!result.maskedText.contains("BEGIN"))
        #expect(!result.maskedText.contains("b3BlbnNzaC1rZXktdjEA"))
    }

    @Test func anUnterminatedPrivateKeyBlockIsMaskedToTheEndOfTheText() {
        let text = """
        -----BEGIN RSA PRIVATE KEY-----
        MIIEowIBAAKCAQEAfakefakefakefakefakefakefakefakefakefakefakefake
        """
        let result = SecretMasker.mask(text)
        #expect(result.maskedText == placeholder)
        #expect(!result.maskedText.contains("MIIEow"))
    }

    @Test func aPgpPrivateKeyBlockIsAlsoRecognised() {
        let text = """
        -----BEGIN PGP PRIVATE KEY BLOCK-----
        lQOYBGFakeKeyMaterial
        -----END PGP PRIVATE KEY BLOCK-----
        """
        #expect(SecretMasker.mask(text).maskedText == placeholder)
    }

    /// Public key sır değildir — blok kuralı yalnızca PRIVATE anahtarları yakalar.
    @Test func aPublicKeyBlockIsNotMasked() {
        let text = """
        -----BEGIN PUBLIC KEY-----
        MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEfake
        -----END PUBLIC KEY-----
        """
        #expect(SecretMasker.mask(text).maskedText == text)
    }

    // MARK: - Çok satırlı metin ve aynı satırda birden çok sır

    @Test func onlyTheSecretLinesChangeInAMultilineTranscript() {
        let text = """
        $ cat .env
        APP_NAME=Termora
        DB_PASSWORD=hunter2
        PATH=/usr/bin
        AWS_SECRET_ACCESS_KEY=wJalrFAKEkeyMaterial1234567890abcdEFGH
        $ echo done
        """
        let result = SecretMasker.mask(text)
        #expect(result.maskedText == """
        $ cat .env
        APP_NAME=Termora
        DB_PASSWORD=\(placeholder)
        PATH=/usr/bin
        AWS_SECRET_ACCESS_KEY=\(placeholder)
        $ echo done
        """)
        #expect(result.findings.count == 2)
    }

    @Test func twoSecretsOnTheSameLineAreBothMasked() {
        let line = "curl -H \"X-Api-Key: abcd1234efgh5678\" -H \"Authorization: Bearer sk-proj-123456\" https://example.com"
        let result = SecretMasker.mask(line)
        #expect(!result.maskedText.contains("abcd1234efgh5678"))
        #expect(!result.maskedText.contains("sk-proj-123456"))
        #expect(result.findings.count == 2)
        #expect(result.maskedText.contains("https://example.com"))
    }

    @Test func findingsCarryOneBasedLineNumbersSoTheUserCanReviewThem() {
        let text = """
        harmless line
        DB_PASSWORD=hunter2
        another harmless line
        API_KEY=abcdef123456
        """
        let lines = SecretMasker.mask(text).findings.map(\.line)
        #expect(lines == [2, 4])
    }

    @Test func lineNumbersSurviveAPrivateKeyBlockAbove() {
        let text = """
        -----BEGIN RSA PRIVATE KEY-----
        MIIEowIBAAKCAQEAfake
        -----END RSA PRIVATE KEY-----
        DB_PASSWORD=hunter2
        """
        let findings = SecretMasker.mask(text).findings
        #expect(findings.first?.line == 1)
        #expect(findings.last?.line == 4)
    }

    @Test func windowsLineEndingsAndTrailingNewlinesSurvive() {
        let text = "APP=Termora\r\nDB_PASSWORD=hunter2\r\n"
        let result = SecretMasker.mask(text)
        #expect(result.maskedText == "APP=Termora\r\nDB_PASSWORD=\(placeholder)\r\n")
    }

    // MARK: - Kullanıcı NE maskelendiğini görebilmeli (brief şartı)

    @Test func theSummaryNamesWhatWasHiddenAndHowMuch() {
        let result = SecretMasker.mask("""
        Authorization: Bearer sk-proj-123456
        DB_PASSWORD=hunter2
        API_KEY=abcdef123456
        """)
        #expect(result.summary.contains("3 secrets"))
        #expect(result.summary.contains("Authorization header"))
        #expect(result.summary.contains("2 environment values"))
    }

    @Test func aSingleFindingIsReportedInTheSingular() {
        let summary = SecretMasker.mask("DB_PASSWORD=hunter2").summary
        #expect(summary.contains("1 secret "))
        #expect(!summary.contains("1 secrets"))
    }

    @Test func cleanTextSaysSoInsteadOfStayingSilent() {
        let result = SecretMasker.mask("ls -la")
        #expect(result.summary == SecretMasker.noSecretsSummary)
        #expect(SecretMasker.noSecretsSummary.lowercased().contains("no secret"))
    }

    @Test func everyKindHasAReadableEnglishName() {
        for kind in SecretKind.allCases {
            #expect(!kind.displayName.isEmpty, "adsız tür: \(kind)")
            #expect(kind.displayName.first?.isWhitespace == false)
        }
        #expect(Set(SecretKind.allCases.map(\.displayName)).count == SecretKind.allCases.count)
    }

    // MARK: - Kararlılık

    @Test func maskingIsIdempotent() {
        let text = """
        Authorization: Bearer sk-proj-123456
        DB_PASSWORD=hunter2
        DATABASE_URL=postgres://app:s3cr3t@db:5432/app
        """
        let once = SecretMasker.mask(text)
        let twice = SecretMasker.mask(once.maskedText)
        #expect(twice.maskedText == once.maskedText)
        #expect(twice.findings.isEmpty)
    }

    /// Bozuk bir düzenli ifade `try?` yüzünden sessizce kaybolabilirdi; kural sayısı
    /// tutmazsa bir kural derlenmemiş demektir (briefs/2: hatalar sessizce yutulmamalı).
    @Test func everyDeclaredRuleActuallyCompiles() {
        #expect(SecretMasker.compiledRuleCount == SecretMasker.declaredRuleCount)
        #expect(SecretMasker.compiledRuleCount > 0)
    }

    @Test func emptyTextIsHandledWithoutCrashing() {
        let result = SecretMasker.mask("")
        #expect(result.maskedText.isEmpty)
        #expect(result.findings.isEmpty)
    }
}
