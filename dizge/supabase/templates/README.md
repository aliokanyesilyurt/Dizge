# E-posta şablonları (P5)

Uygulama e-postada **bağlantı değil kod** kullanıyor: bağlantılar Windows'ta
derin bağlantı istiyor ve tarayıcıda açılıp kalıyordu. Supabase'in varsayılan
şablonları İngilizce ve bağlantılı. Bu klasördekiler Türkçe ve kodu
(`{{ .Token }}`) büyük gösteriyor.

## Nereye yapıştırılır

Supabase → **Authentication → Email Templates** (yeni arayüzde
**Authentication → Emails**):

| Dosya | Şablon kutusu | Konu satırı |
|---|---|---|
| `confirmation.html` | Confirm signup | Dizge — e-posta doğrulama kodun |
| `recovery.html` | Reset Password | Dizge — parola sıfırlama kodun |
| `reauthentication.html` | Reauthentication | Dizge — doğrulama kodun |
| `email_change.html` | Change Email Address | Dizge — e-posta değişikliği kodun |
| `password_changed.html` | Security notifications → Password changed (önce aç) | Dizge — parolan değiştirildi |

Dosyanın başındaki `<!-- … -->` yorumunu yapıştırmana gerek yok, zararı da yok.

## Uygulamanın beklediği ayarlar

**Authentication → Providers → Email**

- **Confirm email**: açık. Kayıttan sonra uygulama kod ekranına geçiyor.
- **Secure password change**: açık.
- **Minimum password length**: `8`.
- **Password requirements**: *Letters and digits*. Uygulamadaki kural
  listesi (`lib/core/password_policy.dart`) birebir bunu gösteriyor.
  Burayı sıkılaştırırsan oradaki kuralı da güncelle.
- **Email OTP length**: `6` (varsayılan). Uygulamadaki kod alanı 6 hane
  bekliyor.

## Özel SMTP (önemli)

Supabase'in yerleşik e-posta servisi saatte yalnız birkaç e-posta gönderiyor
ve ekip üyesi olmayan adreslere gönderimi kısıtlıyor. Bu durumda kayıt ve
kurtarma kodları gerçek kullanıcılara **ulaşmaz**.

**Project Settings → Authentication → SMTP Settings**. Resend ya da Brevo gibi
bir servisin ücretsiz katmanı yeterli. Gönderici adı olarak `Dizge` yaz.
