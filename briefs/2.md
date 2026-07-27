# Termora — Ürün ve Geliştirme Brief’i: Bölüm 2

## Komut Blokları

İkinci aşamada terminal çıktıları geleneksel tek akış görünümüne ek olarak komut blokları şeklinde gösterilebilmelidir.

Her blok şu bilgileri içermelidir:

- Girilen komut
- Komutun çıktısı
- Başlangıç ve bitiş zamanı
- Çalışma süresi
- Çıkış kodu
- Çalışma dizini
- Başarılı, başarısız veya devam ediyor durumu

Kullanıcı bir blok üzerinde:

- Komutu kopyalayabilmeli
- Çıktıyı kopyalayabilmeli
- Komutu yeniden çalıştırabilmeli
- Aynı komutu düzenleyerek çalıştırabilmeli
- Çıktıyı temizleyebilmeli
- Hata çıktısını AI ile açıklayabilmeli
- Bloğu Markdown olarak dışa aktarabilmelidir

Komut blokları zorunlu olmamalı; ayarlardan klasik terminal görünümüne geçilebilmelidir.

## Workspace Sistemi

Workspace, belirli bir proje için terminal düzenini ve başlangıç komutlarını saklayan çalışma alanıdır.

Her workspace şu bilgileri içermelidir:

- Ad
- Proje klasörü
- Terminal sekmeleri
- Split düzeni
- Her panelin başlangıç dizini
- Başlangıç komutları
- Ortam değişkenleri
- İlişkili SSH bağlantıları
- Tema veya profil
- Son kullanım tarihi

Örnek:

```yaml
name: Pinro
directory: ~/Projects/pinro

terminals:
  - title: Backend
    command: php artisan serve

  - title: Queue
    command: php artisan queue:work

  - title: Frontend
    command: npm run dev

  - title: Server
    command: ssh deploy@pinro.app
```

Kullanıcı workspace açtığında kayıtlı sekme ve panel düzeni yeniden oluşturulmalıdır.

Başlangıç komutları otomatik çalıştırılmadan önce kullanıcıdan onay alınmalıdır. Kullanıcı isterse güvenilir workspace’ler için bu onayı kapatabilmelidir.

## Komut Paleti

Uygulamanın tüm önemli işlemleri klavye üzerinden erişilebilir olmalıdır.

Komut paleti `⌘K` veya `⌘Shift+P` ile açılabilmelidir.

Komut paletinden yapılabilecek işlemler:

- Yeni terminal açma
- Yeni sekme oluşturma
- Terminali yatay veya dikey bölme
- Workspace açma
- Son kullanılan klasörü açma
- SSH bağlantısı başlatma
- Tema değiştirme
- Font boyutunu değiştirme
- Ayarları açma
- Terminal geçmişinde arama
- AI komut alanını açma
- Uygulama komutlarını arama

Arama fuzzy matching desteklemeli ve son kullanılan işlemleri üst sıralarda göstermelidir.

## Hızlı Açma

Kullanıcı aşağıdaki kaynaklardan hızlıca terminal açabilmelidir:

- Finder’da seçili klasör
- Son kullanılan klasörler
- Favori klasörler
- Git repository’leri
- Kaydedilmiş workspace’ler
- Kayıtlı SSH sunucuları

Finder için “Open in Termora” özelliği sağlanmalıdır.

Uygulama özel URL şeması destekleyebilir:

```text
termora://open?path=/Users/ahmet/Projects/pinro
```

## SSH Yöneticisi

Termora, kayıtlı SSH bağlantıları için sade bir yönetim ekranı sunmalıdır.

Her SSH profili şu alanları içermelidir:

- Görünen ad
- Host
- Port
- Kullanıcı adı
- Kimlik doğrulama yöntemi
- Private key yolu
- Başlangıç dizini
- Başlangıç komutu
- Etiketler
- Renk
- ProxyJump ayarı

İlk aşamada yeni bir SSH protokolü uygulanmamalıdır. Sistem üzerindeki `/usr/bin/ssh` ve kullanıcının `~/.ssh/config` dosyası kullanılmalıdır.

Termora:

- Mevcut SSH config hostlarını listeleyebilmeli
- `known_hosts` doğrulamasını devre dışı bırakmamalı
- Private key içeriğini uygulama veritabanına kopyalamamalı
- Parola gerekiyorsa güvenli macOS giriş yöntemlerini kullanmalı
- Bağlantı kesildiğinde tekrar bağlanma seçeneği sunmalıdır

## Git Entegrasyonu

Terminal aktif bir Git repository’sindeyse aşağıdaki bilgiler gösterilebilmelidir:

- Repository adı
- Aktif branch
- Değişiklik durumu
- Ahead ve behind sayısı
- Son commit özeti

Git bilgileri terminal girişini veya çıktı render işlemini engellememelidir. Kontroller arka planda ve kontrollü aralıklarla yapılmalıdır.

İlk sürümlerde Termora bir Git istemcisine dönüştürülmemelidir. Git entegrasyonu yalnızca bağlamsal bilgi ve hızlı komutlar sunmalıdır.

## Docker Entegrasyonu

Docker entegrasyonu geliştirici ve DevOps kullanımını kolaylaştırmalıdır.

Planlanan işlemler:

- Çalışan container’ları listeleme
- Container içine shell açma
- Container loglarını terminalde gösterme
- Docker Compose servislerini listeleme
- Bir servis için `docker compose exec` çalıştırma
- Container yeniden başlatma

Termora Docker daemon ile doğrudan karmaşık bir API entegrasyonu kurmak yerine başlangıçta Docker CLI komutlarını kullanmalıdır.

Silme, durdurma veya yeniden başlatma gibi etkili işlemlerde kullanıcıdan onay alınmalıdır.

## AI Asistanı

AI asistanı terminalin yanında açılabilen bağımsız bir panel olmalıdır.

Desteklenecek sağlayıcılar:

- OpenAI
- Anthropic
- Ollama
- OpenAI uyumlu özel API adresleri

Temel AI işlemleri:

### Komut Üretme

Kullanıcı doğal dilde isteğini yazar:

```text
Bu klasörde 30 günden eski log dosyalarını listele.
```

AI uygun shell komutunu üretir ancak otomatik çalıştırmaz.

Kullanıcı:

- Komutu kopyalayabilir
- Terminal girişine ekleyebilir
- Düzenleyebilir
- Onaylayarak çalıştırabilir

### Hata Açıklama

Başarısız bir komut bloğu seçildiğinde AI:

- Hatanın olası nedenini
- İlgili hata satırlarını
- Güvenli çözüm adımlarını
- Önerilen komutları göstermelidir

### Terminal Bağlamı

AI’a gönderilecek bağlam kullanıcı tarafından görülebilmelidir.

Olası bağlamlar:

- Seçili komut
- Seçili çıktı
- Aktif çalışma dizini
- İşletim sistemi
- Shell türü
- Git branch
- Kullanıcının açıkça eklediği dosyalar

Tüm terminal geçmişi varsayılan olarak AI’a gönderilmemelidir.

## Secret Maskeleme

AI’a veri gönderilmeden önce hassas değerler tespit edilip maskelenmelidir.

Maskelenecek örnekler:

- API anahtarları
- Bearer token’lar
- AWS anahtarları
- GitHub token’ları
- Parolalar
- Private key blokları
- `.env` değerleri
- Authorization header içerikleri
- Cookie ve session değerleri

Örnek:

```text
Authorization: Bearer sk-proj-123456
```

şu şekilde gönderilmelidir:

```text
Authorization: Bearer [REDACTED]
```

Kullanıcı gönderilecek son içeriği AI isteğinden önce inceleyebilmelidir.

## Tehlikeli Komut Koruması

Termora, geri dönüşü zor sonuçlar oluşturabilecek komutlarda ek uyarı gösterebilir.

Örnek riskli işlemler:

- Geniş kapsamlı `rm` komutları
- Disk biçimlendirme
- Dosya sistemi üzerine doğrudan yazma
- Veritabanı silme
- Docker volume silme
- Zorla Git resetleme
- Korunan dizinlerin izinlerini değiştirme
- Uzak sunucuda toplu silme

Koruma sistemi shell davranışını bozmamalı ve her komuta müdahale etmemelidir. Yalnızca yüksek güvenle tespit edilen işlemlerde uyarı verilmelidir.

AI tarafından üretilen riskli komutlar hiçbir koşulda otomatik çalıştırılmamalıdır.

## Onboarding

İlk açılış deneyimi en fazla üç adımdan oluşmalıdır.

### Adım 1 — Shell Algılama

- Varsayılan shell gösterilir
- Kullanıcı farklı bir shell seçebilir

### Adım 2 — Görünüm

- Tema seçimi
- Font seçimi
- Font boyutu önizlemesi

### Adım 3 — İsteğe Bağlı Özellikler

- Shell integration kurulumu
- Finder entegrasyonu
- AI sağlayıcısı bağlantısı

Kullanıcı onboarding’i atlayabilmelidir. Uygulama hesap oluşturmadan kullanılabilmelidir.

## Ayarlar Ekranı

Ayarlar şu bölümlere ayrılmalıdır:

- General
- Appearance
- Terminal
- Profiles
- Workspaces
- SSH
- AI
- Keybindings
- Privacy
- Updates
- About

Ayar değişiklikleri mümkün olduğunca anında uygulanmalıdır.

Klavye kısayolları çakıştığında kullanıcı uyarılmalıdır.

## Menü Çubuğu

Termora standart macOS menülerini desteklemelidir:

- Termora
- File
- Edit
- View
- Shell
- Window
- Help

Temel işlemler yalnızca özel butonlara bağlı olmamalı; macOS menü sisteminden de erişilebilir olmalıdır.

## Pencere Yönetimi

- Birden fazla uygulama penceresi açılabilmeli
- Her pencerenin kendi sekmeleri bulunmalı
- Tam ekran desteklenmeli
- Pencere boyutu ve konumu hatırlanmalı
- Uygulama yeniden açıldığında önceki oturum isteğe bağlı geri yüklenmeli
- macOS trafik ışığı kontrolleri doğal biçimde korunmalı

## Bildirimler

Uzun süren bir işlem tamamlandığında isteğe bağlı macOS bildirimi gösterilebilir.

Örnek kullanım:

```text
npm run build completed successfully in 4m 18s
```

Bildirimler:

- Profil bazında kapatılabilmeli
- Belirli bir süreden kısa işlemler için gösterilmemeli
- Başarılı ve başarısız işlemler için ayrı ayarlanabilmelidir

## Oturum Geri Yükleme

Uygulama kapanırken aşağıdaki bilgiler kaydedilebilir:

- Açık pencereler
- Sekmeler
- Split düzenleri
- Çalışma dizinleri
- Workspace bağlantıları

Güvenlik nedeniyle çalışan shell işlemlerinin birebir devam edeceği vaat edilmemelidir. Uygulama yeniden açıldığında yeni shell işlemleri oluşturulmalı ve kayıtlı dizinlere geçilmelidir.

Başlangıç komutları kullanıcı onayı olmadan yeniden çalıştırılmamalıdır.

## Güncelleme Sistemi

Uygulama App Store dışında dağıtılacaksa otomatik güncelleme sistemi bulunmalıdır.

Güncelleme ekranında:

- Yeni sürüm numarası
- Değişiklik notları
- İndirme boyutu
- Güncelleme butonu
- Daha sonra hatırlat seçeneği bulunmalıdır

Güncelleme paketleri imzalanmalı ve doğrulanmalıdır.

## Gizlilik

Termora gizlilik odaklı tasarlanmalıdır.

Varsayılan davranışlar:

- Hesap zorunlu değildir
- Terminal geçmişi buluta gönderilmez
- Telemetri varsayılan olarak kapalıdır
- AI yalnızca kullanıcı isteğiyle çağrılır
- Gönderilecek AI bağlamı kullanıcıya gösterilir
- API anahtarları Keychain’de tutulur
- Yerel Ollama kullanımı desteklenir

Gizlilik sayfasında hangi verinin neden işlendiği açık şekilde anlatılmalıdır.

## Hata Raporlama

Uygulama çökmeleri için isteğe bağlı hata raporlama sistemi eklenebilir.

Hata raporlarında şu bilgiler bulunmamalıdır:

- Terminal çıktısı
- Yazılan komutlar
- Dosya içerikleri
- Ortam değişkenleri
- API anahtarları
- SSH bilgileri

Teknik hata raporu yalnızca uygulama sürümü, macOS sürümü, cihaz mimarisi ve stack trace gibi gerekli bilgileri içermelidir.

## Lisanslama ve Planlar

### Free

- Sınırsız yerel terminal
- Sekmeler
- Split terminal
- Temalar
- Arama
- Temel profiller

### Pro

- Sınırsız workspace
- SSH yöneticisi
- AI entegrasyonu
- Docker araçları
- Gelişmiş komut blokları
- Oturum geri yükleme
- Özel tema ve profiller

İlk sürümde abonelik yerine tek seferlik lisans veya yıllık güncelleme modeli değerlendirilebilir.

Temel terminal özellikleri ücret duvarının arkasına konulmamalıdır. Kullanıcı uygulamayı ücretsiz olarak gerçek anlamda kullanabilmelidir.

## Dağıtım

Termora aşağıdaki biçimlerde dağıtılabilir:

- Notarized DMG
- Homebrew Cask
- İlerleyen dönemde Mac App Store

DMG dağıtımı için:

- Developer ID Application ile imzalama
- Apple notarization
- Stapling
- Sparkle güncelleme imzası
- Gatekeeper doğrulaması uygulanmalıdır

## Test Stratejisi

### Unit Test

- Workspace oluşturma ve geri yükleme
- Profil yönetimi
- Tema ayrıştırma
- Ayarların saklanması
- Secret maskeleme
- Riskli komut tespiti
- SSH config ayrıştırma

### Integration Test

- Shell başlatma
- Shell sonlandırma
- Çalışma dizini değiştirme
- Terminal resize
- Çoklu sekme
- Split terminal
- Oturum geri yükleme
- Uzun süreli komutlar
- Büyük terminal çıktısı

### Uyumluluk Testi

Aşağıdaki araçlar manuel ve otomatik olarak test edilmelidir:

- `zsh`
- `bash`
- `fish`
- `vim`
- `nano`
- `tmux`
- `ssh`
- `git`
- `docker`
- `npm`
- `composer`
- `php artisan`
- `htop`
- Claude Code
- Codex CLI
- Ollama

## Erişilebilirlik

- VoiceOver etiketleri sağlanmalı
- Klavye ile tam kullanım mümkün olmalı
- Kontrast oranları korunmalı
- Renk tek durum göstergesi olarak kullanılmamalı
- Sistem font büyüklüğü tercihleri dikkate alınmalı
- “Reduce Motion” ayarı desteklenmelidir

## Geliştirme Aşamaları

### Faz 1 — Terminal Çekirdeği

- SwiftTerm entegrasyonu
- Yerel shell başlatma
- Terminal giriş ve çıkışı
- Resize
- Kopyalama ve yapıştırma
- Temel pencere

### Faz 2 — Günlük Kullanım

- Sekmeler
- Split terminal
- Arama
- Temalar
- Font ayarları
- Klavye kısayolları
- Profil sistemi

### Faz 3 — Workspace

- Workspace modeli
- Düzen kaydetme
- Başlangıç komutları
- Komut paleti
- Son kullanılan klasörler
- Oturum geri yükleme

### Faz 4 — DevOps Özellikleri

- SSH profilleri
- SSH config import
- Git bilgileri
- Docker container terminali
- Uzun işlem bildirimleri

### Faz 5 — AI

- Sağlayıcı sistemi
- Keychain entegrasyonu
- Komut üretme
- Hata açıklama
- Secret maskeleme
- Riskli komut uyarıları

### Faz 6 — Yayın

- Lisans sistemi
- Otomatik güncelleme
- Notarization
- DMG
- Homebrew Cask
- Web sitesi ve dokümantasyon

## MVP Tamamlanma Kriterleri

MVP aşağıdaki koşullar sağlandığında tamamlanmış kabul edilir:

- Uygulama crash olmadan shell başlatabiliyor
- Klavye girişleri doğru iletiliyor
- ANSI renkleri doğru gösteriliyor
- Unicode ve emoji hizalaması bozulmuyor
- Terminal resize işlemi düzgün çalışıyor
- En az 10 sekme açılabiliyor
- Yatay ve dikey split kullanılabiliyor
- `vim`, `tmux` ve `ssh` çalışıyor
- Ayarlar uygulama yeniden açıldığında korunuyor
- Aktif işlem bulunan sekme yanlışlıkla kapatılmıyor
- Yoğun çıktıda arayüz kullanılabilir kalıyor
- Uygulama imzalı ve notarized DMG olarak kurulabiliyor

## Geliştirme Kuralları

- Önce çalışan terminal çekirdeği hazırlanmalı
- UI katmanı terminal motorundan ayrılmalı
- View içinde iş mantığı tutulmamalı
- Her terminal oturumu bağımsız yönetilmeli
- Ana thread üzerinde PTY okuma yapılmamalı
- Gereksiz üçüncü taraf bağımlılık eklenmemeli
- Force unwrap kullanılmamalı
- Hatalar sessizce yutulmamalı
- Hassas veriler loglanmamalı
- Yeni özellikler mevcut shell davranışını bozmamalı
- Her faz tamamlanmadan sonraki faza geçilmemelidir

## İlk Geliştirme Görevi

İlk görev yalnızca çalışan terminal prototipini hazırlamaktır.

Beklenen çıktı:

1. SwiftTerm bağımlılığını projeye ekle
2. SwiftUI içinde terminali göstermek için AppKit köprüsü oluştur
3. Kullanıcının varsayılan shell’ini algıla
4. Shell’i login shell olarak başlat
5. Home dizininde yeni terminal oturumu aç
6. Pencere resize edildiğinde terminal ölçülerini güncelle
7. Kopyalama ve yapıştırmayı çalıştır
8. Shell sonlandığında terminal durumunu göster
9. Projenin build aldığını doğrula

Bu görev sırasında sekme, split, workspace, SSH veya AI özellikleri eklenmemelidir. Öncelik terminal çekirdeğinin doğru ve kararlı çalışmasıdır.
