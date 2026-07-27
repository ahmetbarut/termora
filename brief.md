# Termora — Ürün ve Geliştirme Brief’i

## Proje Tanımı

Termora, yalnızca macOS için geliştirilen, native, hızlı ve modern bir terminal uygulamasıdır. Uygulama; klasik terminal kullanımını sekmeler, bölünmüş ekranlar, çalışma alanları ve geliştirici odaklı araçlarla daha düzenli hâle getirmeyi amaçlar.

İlk sürümün hedefi Warp kadar karmaşık bir sistem kurmak değil; günlük kullanıma uygun, hızlı açılan ve güvenilir bir terminal deneyimi oluşturmaktır.

## Teknoloji

- Dil: Swift
- Platform: macOS
- Minimum sürüm: macOS 14 Sonoma
- Arayüz: SwiftUI
- Terminal görünümü: AppKit üzerinden `NSViewRepresentable`
- Terminal motoru: SwiftTerm
- Veri saklama: SwiftData
- Hassas bilgiler: macOS Keychain
- Mimari: MVVM
- Paket yönetimi: Swift Package Manager

## Temel Hedefler

- Native macOS deneyimi sunmak
- Uygulamanın hızlı açılmasını sağlamak
- Terminal giriş ve çıktısını gecikmesiz göstermek
- Klavye odaklı bir kullanım tasarlamak
- Sekme ve terminal oturumlarını düzenli yönetmek
- Modern fakat sade bir arayüz oluşturmak
- Sonraki sürümlerde SSH, workspace ve AI özelliklerine uygun mimari kurmak

## MVP Özellikleri

### Terminal Oturumu

- Kullanıcının varsayılan shell’ini çalıştır
- `zsh`, `bash` ve `fish` desteği sağla
- Yeni terminal açıldığında kullanıcının home dizininden başlat
- İstenirse belirli bir klasörde terminal açılabilsin
- Terminal boyutu değiştiğinde satır ve sütun değerleri PTY’ye aktarılsın
- ANSI renkleri, Unicode, emoji ve Nerd Font karakterleri desteklensin
- `vim`, `nano`, `top`, `htop` ve benzeri interaktif uygulamalar çalışabilsin
- Kopyalama ve yapıştırma desteklensin
- Scrollback geçmişi bulunsun

### Sekmeler

- Aynı pencere içinde birden fazla terminal sekmesi açılabilsin
- Sekmeler yeniden adlandırılabilsin
- Sekmeler kapatılabilsin
- Aktif sekme belirgin şekilde gösterilsin
- Çalışan işlem bulunan sekme kapatılırken kullanıcı uyarılsın

Klavye kısayolları:

- `⌘T`: Yeni sekme
- `⌘W`: Aktif sekmeyi kapat
- `⌘1–9`: Sekmeler arasında geçiş
- `⌘Shift+]`: Sonraki sekme
- `⌘Shift+[`: Önceki sekme

### Bölünmüş Terminal

- Terminal yatay veya dikey bölünebilsin
- Her panel bağımsız bir terminal oturumu çalıştırsın
- Aktif panel görsel olarak belli olsun
- Panel boyutları sürüklenerek değiştirilebilsin

Klavye kısayolları:

- `⌘D`: Dikey böl
- `⌘Shift+D`: Yatay böl
- `⌘Option+Yön Tuşları`: Paneller arasında geçiş

### Arama

- Terminal çıktısında arama yapılabilsin
- Eşleşmeler terminal üzerinde işaretlensin
- Önceki ve sonraki eşleşmeye geçilebilsin
- Arama paneli `⌘F` ile açılabilsin

### Görünüm Ayarları

Kullanıcı aşağıdaki ayarları değiştirebilsin:

- Terminal fontu
- Font boyutu
- Satır yüksekliği
- İmleç şekli
- İmleç yanıp sönmesi
- Arka plan rengi
- Metin rengi
- ANSI renk paleti
- Pencere saydamlığı
- Scrollback satır sınırı
- Varsayılan shell
- Başlangıç klasörü

Başlangıçta en az şu temalar sunulsun:

- Termora Dark
- Termora Light
- Dracula
- Nord
- Tokyo Night

## Arayüz Tasarımı

Uygulama koyu tema öncelikli, sade ve profesyonel görünmelidir. Arayüz terminal içeriğinin önüne geçmemelidir.

### Ana Pencere

Ana pencere şu alanlardan oluşmalıdır:

1. macOS title bar
2. Sekme çubuğu
3. Terminal çalışma alanı
4. İsteğe bağlı durum çubuğu

Sekme çubuğunda:

- Açık sekmeler
- Yeni sekme butonu
- Aktif klasör veya çalışan işlem adı
- Sekme kapatma butonu bulunmalıdır

Durum çubuğunda:

- Aktif shell
- Çalışma dizini
- Git branch
- Terminal boyutu
- İşlem durumu gösterilebilir

### Görsel Dil

- macOS sistem tasarımına uyumlu olmalı
- Gereksiz büyük butonlar kullanılmamalı
- Yuvarlak köşeler ölçülü kullanılmalı
- Terminal alanı mümkün olduğunca geniş tutulmalı
- SF Symbols tercih edilmeli
- Hover ve seçim animasyonları kısa tutulmalı
- Animasyonlar terminal performansını etkilememeli

## Uygulama Mimarisi

Önerilen klasör yapısı:

```text
Termora/
├── App/
│   ├── TermoraApp.swift
│   └── AppCommands.swift
├── Models/
│   ├── TerminalSession.swift
│   ├── TerminalTab.swift
│   ├── TerminalPane.swift
│   ├── TerminalProfile.swift
│   └── AppSettings.swift
├── Views/
│   ├── MainWindow/
│   ├── Terminal/
│   ├── Tabs/
│   ├── SplitView/
│   └── Settings/
├── ViewModels/
│   ├── WorkspaceViewModel.swift
│   ├── TerminalViewModel.swift
│   └── SettingsViewModel.swift
├── Services/
│   ├── ShellService.swift
│   ├── SessionManager.swift
│   ├── SettingsService.swift
│   └── KeychainService.swift
├── Extensions/
└── Resources/
    ├── Themes/
    └── Assets.xcassets
```

## Veri Modelleri

### TerminalSession

Her terminal işlemini temsil eder.

- Benzersiz kimlik
- Shell yolu
- Çalışma dizini
- Ortam değişkenleri
- Başlangıç tarihi
- İşlem kimliği
- Oturum durumu

### TerminalTab

Bir sekmeyi temsil eder.

- Benzersiz kimlik
- Başlık
- Panel düzeni
- Aktif panel
- Oluşturulma tarihi

### TerminalProfile

Kullanıcı tarafından kaydedilen terminal profilini temsil eder.

- Profil adı
- Shell
- Başlangıç klasörü
- Başlangıç komutu
- Font
- Tema
- Ortam değişkenleri

## Güvenlik

- API anahtarları ve parolalar UserDefaults içinde tutulmamalı
- Hassas bilgiler Keychain’de saklanmalı
- Terminal çıktısı varsayılan olarak harici servislere gönderilmemeli
- Uygulama ilk sürümde sandbox dışında çalıştırılabilir
- Shell işlemleri kullanıcı yetkileriyle çalıştırılmalı
- Komutlar kullanıcı onayı olmadan otomatik çalıştırılmamalı
- Terminal kapatıldığında alt işlemler güvenli şekilde sonlandırılmalı

## Performans Gereksinimleri

- Uygulama mümkünse bir saniyeden kısa sürede açılmalı
- Yazı girişinde fark edilebilir gecikme olmamalı
- Yoğun terminal çıktısında ana arayüz donmamalı
- PTY okuma işlemleri ana thread üzerinde yapılmamalı
- UI güncellemeleri gruplandırılmalı
- Büyük scrollback geçmişi bellek kullanımını kontrolsüz artırmamalı
- Aynı anda en az 10 aktif terminal oturumu kullanılabilmeli

## İlk Sürümde Olmayacaklar

MVP kapsamını korumak için aşağıdaki özellikler ilk sürüme eklenmeyecektir:

- Kullanıcı hesabı
- Bulut senkronizasyonu
- Takım özellikleri
- Yerleşik dosya editörü
- Web tarayıcı
- Eklenti sistemi
- Kubernetes arayüzü
- Docker yönetim paneli
- AI asistanı
- SSH bağlantı yöneticisi
- Komutları Warp benzeri bloklara ayırma

Bunlar sonraki sürümler için değerlendirilecektir.

## İkinci Aşama Özellikleri

- SSH bağlantı profilleri
- SSH anahtarlarını Keychain üzerinden yönetme
- Proje bazlı workspace sistemi
- Hazır terminal yerleşimleri
- Oturumları yeniden açma
- Docker container içine terminal açma
- Git repository algılama
- Komut paleti
- Hızlı klasör açma
- Shell integration
- Çalışan komuta göre sekme başlığını otomatik güncelleme

## AI Özellikleri

AI özellikleri terminal motorundan bağımsız bir modül olarak tasarlanmalıdır.

Planlanan özellikler:

- Doğal dilden shell komutu üretme
- Hatalı komut çıktısını açıklama
- Seçili terminal çıktısını analiz etme
- Komutu çalıştırmadan önce açıklama
- OpenAI, Claude ve Ollama desteği
- API anahtarlarını Keychain’de saklama
- Terminal çıktısındaki secret değerleri otomatik maskeleme
- AI tarafından üretilen komutu kullanıcı onayı olmadan çalıştırmama

## Başarı Kriterleri

MVP tamamlandığında kullanıcı:

- Uygulamayı açabilmeli
- Varsayılan shell ile terminal kullanabilmeli
- Birden fazla sekme açabilmeli
- Terminal ekranını yatay ve dikey bölebilmeli
- Terminal çıktısında arama yapabilmeli
- Tema ve font ayarlarını değiştirebilmeli
- Uygulamayı tamamen klavye üzerinden yönetebilmeli
- `vim`, `git`, `ssh`, `docker`, `npm` ve benzeri CLI araçlarını sorunsuz çalıştırabilmelidir

## Ürün Konumlandırması

Termora, Warp’ın kopyası olarak değil; macOS için geliştirilmiş hızlı, sade ve geliştirici dostu bir terminal olarak konumlandırılmalıdır.

Temel ürün vaadi:

> Termora, modern geliştiriciler için hazırlanmış hızlı ve native macOS terminalidir.

Kısa slogan:

> Your terminal. Native, fast, focused.
