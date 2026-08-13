<#
.SYNOPSIS
    Dağıtılabilir sürüm üretir: Windows klasörü (+ zip) ve/veya Android APK.

.DESCRIPTION
    Elle `flutter build` çalıştırmakla arasındaki fark tek bir şey değil:

      * `--dart-define-from-file=env.json` **unutulmuyor**. Unutulursa
        derleme başarılı olur ama uygulama sunucusuz açılır (`AppConfig`
        boş) — yani hatasız çalışan, hesaba bağlanamayan bir sürüm. Bu,
        fark edilmesi en zor kusur.
      * Windows çıktısı yanına `dizge://` şemasını kaydeden bir betikle
        birlikte paketleniyor; onsuz Google ile giriş tarayıcıda takılı
        kalır.
      * Sürüm numarası çıktının adına yazılıyor: "hangi zip'i göndermiştim"
        sorusu bir daha sorulmuyor.

.PARAMETER Target
    `windows`, `android` ya da `both` (varsayılan).

.PARAMETER SkipTests
    Testleri atlar. Varsayılan olarak koşuyorlar: dağıtılan bir sürüm,
    kırmızı bir takımla çıkmamalı.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\surum_cikar.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\surum_cikar.ps1 -Target android
#>
[CmdletBinding()]
param(
    [ValidateSet('windows', 'android', 'both')]
    [string] $Target = 'both',
    [switch] $SkipTests
)

$ErrorActionPreference = 'Stop'

$project = Split-Path -Parent $PSScriptRoot
$env_file = Join-Path $project 'env.json'
$out = Join-Path $project 'build\surum'

if (-not (Test-Path $env_file)) {
    Write-Error @'
env.json yok. Sunucu adresi ve anahtarlar oradan geliyor; onsuz üretilen
sürüm açılır ama hiçbir hesaba bağlanamaz.

    copy env.example.json env.json

sonra içini doldur.
'@
    exit 1
}

# Sürüm numarası pubspec'ten: iki yerde tutulan bir numara er geç ayrışır.
$pubspec = Get-Content (Join-Path $project 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)') {
    Write-Error 'pubspec.yaml içinde sürüm satırı okunamadı.'
    exit 1
}
$version = $Matches[1]
$build = $Matches[2]

Write-Host ""
Write-Host "Dizge $version+$build  ·  hedef: $Target" -ForegroundColor Cyan
Write-Host ""

Push-Location $project
try {
    if (-not $SkipTests) {
        Write-Host "› Testler koşuyor…" -ForegroundColor DarkGray
        flutter test
        if ($LASTEXITCODE -ne 0) {
            Write-Error 'Testler kırmızı. Sürüm çıkarılmadı.'
            exit 1
        }
    }

    New-Item -ItemType Directory -Force -Path $out | Out-Null

    if ($Target -in @('windows', 'both')) {
        Write-Host "› Windows derleniyor…" -ForegroundColor DarkGray
        flutter build windows --release "--dart-define-from-file=$env_file"
        if ($LASTEXITCODE -ne 0) { exit 1 }

        $release = Join-Path $project 'build\windows\x64\runner\Release'
        $stage = Join-Path $out "Dizge-$version-windows"

        if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
        Copy-Item $release $stage -Recurse

        # Şema kaydı kullanıcının makinesinde, kurulum yerine göre yapılmalı:
        # derleme makinesindeki yolu zip'in içine gömmek, her kurulumda
        # yanlış kopyaya bağlanan bir kayıt üretirdi.
        Copy-Item (Join-Path $PSScriptRoot 'dizge_scheme.ps1') $stage
        Set-Content -Path (Join-Path $stage 'OKU-BENI.txt') -Encoding utf8 -Value @"
Dizge $version

Kurulum:
  1. Bu klasörü kalıcı bir yere çıkar (ör. C:\Program Files\Dizge).
     Klasörün tamamı gerekli — yalnız .exe'yi taşımak çalışmaz.
  2. Dizge.exe ile aç.

Google ile giriş kullanacaksan bir adım daha gerekiyor. Tarayıcı, girişi
bitirince adresi uygulamaya geri vermek zorunda; Windows'un bu bağlantıyı
tanıması için tek seferlik bir kayıt şart:

     powershell -ExecutionPolicy Bypass -File dizge_scheme.ps1

Kaydı silmek için aynı komuta -Unregister ekle.

Uygulama imzalanmamış: Windows ilk açılışta "bilinmeyen yayımcı" uyarısı
gösterebilir. "Daha fazla bilgi" › "Yine de çalıştır" ile geçilir.
"@

        $zip = Join-Path $out "Dizge-$version-windows.zip"
        if (Test-Path $zip) { Remove-Item $zip -Force }
        Compress-Archive -Path "$stage\*" -DestinationPath $zip

        Write-Host "  ✓ $zip" -ForegroundColor Green
    }

    if ($Target -in @('android', 'both')) {
        Write-Host "› Android APK derleniyor…" -ForegroundColor DarkGray

        if (-not (Test-Path (Join-Path $project 'android\key.properties'))) {
            Write-Host ""
            Write-Host "  UYARI · key.properties yok: APK hata ayıklama anahtarıyla" -ForegroundColor Yellow
            Write-Host "  imzalanacak. Kurulur ve çalışır, ama gerçek anahtarla" -ForegroundColor Yellow
            Write-Host "  imzalanmış bir sürüme sonradan güncellenemez." -ForegroundColor Yellow
            Write-Host "  Bkz. android/key.properties.example" -ForegroundColor Yellow
            Write-Host ""
        }

        # `--split-per-abi` değil tek APK: yandan yükleme için tek dosya
        # göndermek, karşı tarafa "telefonun hangi işlemciyi kullanıyor"
        # diye sormaktan iyi. Mağazaya çıkılırsa orada app bundle var.
        flutter build apk --release "--dart-define-from-file=$env_file"
        if ($LASTEXITCODE -ne 0) { exit 1 }

        $apk = Join-Path $project 'build\app\outputs\flutter-apk\app-release.apk'
        $dest = Join-Path $out "Dizge-$version-$build.apk"
        Copy-Item $apk $dest -Force

        Write-Host "  ✓ $dest" -ForegroundColor Green
    }
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "Bitti: $out" -ForegroundColor Cyan
