<#
.SYNOPSIS
    `dizge://` özel şemasını bu makineye kaydeder (Google ile giriş, G8b).

.DESCRIPTION
    Tarayıcıda Google girişi bitince Supabase, jetonu
    `dizge://login-callback` adresine yollar. Windows'un bu adresi
    uygulamaya bağlaması için registry'de bir kayıt gerekir; bu betik onu
    yazar.

    Kayıt **HKCU** altına gidiyor: yönetici hakkı istemez ve yalnız bu
    kullanıcıyı etkiler. Kurulum paketi geldiğinde aynı kaydı HKLM altına
    kendisi yapacak; bu betik geliştirme içindir.

    Neden düz bir `.reg` dosyası değil: kayıt, çalıştırılabilir dosyanın
    **tam yolunu** taşımak zorunda. Repoya sabit bir yol yazmak, o yol her
    makinede ve her derleme kipinde (Debug/Release) farklı olduğu için
    sessizce yanlış kopyaya bağlanan bir kayıt üretirdi.

.PARAMETER ExePath
    Bağlanacak uygulama. Verilmezse önce Release, sonra Debug derlemesi
    aranır.

.PARAMETER Unregister
    Kaydı siler.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\dizge_scheme.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\dizge_scheme.ps1 -Unregister
#>
[CmdletBinding()]
param(
    [string] $ExePath,
    [switch] $Unregister
)

$ErrorActionPreference = 'Stop'

$scheme  = 'dizge'
$root    = "HKCU:\Software\Classes\$scheme"
$project = Split-Path -Parent $PSScriptRoot

if ($Unregister) {
    if (Test-Path $root) {
        Remove-Item -Path $root -Recurse -Force
        Write-Host "Kayıt silindi: $root"
    } else {
        Write-Host "Kayıt zaten yok: $root"
    }
    exit 0
}

if (-not $ExePath) {
    $candidates = @(
        (Join-Path $project 'build\windows\x64\runner\Release\scheduler_app.exe'),
        (Join-Path $project 'build\windows\x64\runner\Debug\scheduler_app.exe')
    )
    $ExePath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $ExePath -or -not (Test-Path $ExePath)) {
    Write-Error @'
Uygulama bulunamadı. Önce derle:

    flutter build windows

ya da yolu kendin ver:

    tools\dizge_scheme.ps1 -ExePath C:\yol\scheduler_app.exe
'@
    exit 1
}

$ExePath = (Resolve-Path $ExePath).Path

# "URL Protocol" değeri boş olacak; Windows bir anahtarı şema olarak ancak bu
# değer varsa tanır. Adı önemli, içeriği değil.
New-Item -Path $root -Force | Out-Null
Set-ItemProperty -Path $root -Name '(Default)'   -Value "URL:$scheme Protocol"
Set-ItemProperty -Path $root -Name 'URL Protocol' -Value ''

New-Item -Path "$root\DefaultIcon" -Force | Out-Null
Set-ItemProperty -Path "$root\DefaultIcon" -Name '(Default)' -Value "`"$ExePath`",0"

# `%1` gelen adresin tamamı. Tırnak şart: adres jetonu taşıyor ve içinde
# tırnaksız bırakılırsa ayrı argümanlara bölünecek karakterler var.
New-Item -Path "$root\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path "$root\shell\open\command" -Name '(Default)' -Value "`"$ExePath`" `"%1`""

Write-Host "Kayıt yazıldı."
Write-Host "  şema : ${scheme}://"
Write-Host "  hedef: $ExePath"
Write-Host ""
Write-Host "Sınamak için (uygulama açıkken, pencere öne gelmeli):"
Write-Host "  start dizge://login-callback"
