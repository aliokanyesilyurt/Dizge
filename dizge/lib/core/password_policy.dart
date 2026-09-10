/// Parola kuralı ve güç tahmini — tek yer (P1).
///
/// Kural **sunucuyla aynı** olmalı: Supabase panosunda en az 8 karakter ve
/// "harf ve rakam" gereksinimi açık. İstemci daha gevşek olsaydı kullanıcı
/// ekranda yeşil tik görüp sunucudan ret yerdi; daha sıkı olsaydı sunucunun
/// kabul ettiği parolayı biz reddederdik.
///
/// Kural ile güç ayrı şeyler: kural bir **engel** (uymayan parola
/// gönderilmez), güç yalnız bir **ipucu** (uzunluk ve çeşitlilik). Güç
/// göstergesi "zayıf" dese de kurala uyan parola kaydedilebilir.
library;

const int kPasswordMinLength = 8;

class PasswordRule {
  const PasswordRule(this.label, this.test);

  final String label;
  final bool Function(String password) test;
}

/// Ekranda liste olarak gösterilen kurallar, sırasıyla.
final List<PasswordRule> kPasswordRules = [
  PasswordRule(
    'En az $kPasswordMinLength karakter',
    (p) => p.length >= kPasswordMinLength,
  ),
  PasswordRule(
    'Harf içeriyor',
    (p) => RegExp(r'\p{L}', unicode: true).hasMatch(p),
  ),
  PasswordRule('Rakam içeriyor', (p) => RegExp(r'\d').hasMatch(p)),
];

/// Parola kurala uyuyor mu — gönderilebilir mi?
bool passwordAcceptable(String password) =>
    kPasswordRules.every((r) => r.test(password));

enum PasswordStrength {
  empty(''),
  weak('Zayıf'),
  fair('Orta'),
  good('İyi'),
  strong('Güçlü');

  const PasswordStrength(this.label);
  final String label;
}

/// Uzunluk ve karakter çeşitliliğinden kaba bir güç tahmini.
///
/// Bilerek basit: gerçek bir tahminci (zxcvbn gibi) sözlük ve kalıp bilir,
/// ama burada amaç kullanıcıya "biraz daha uzat" demek. Kuralı geçmeyen
/// parola en fazla "Zayıf" olabilir.
PasswordStrength strengthOf(String password) {
  if (password.isEmpty) return PasswordStrength.empty;
  if (!passwordAcceptable(password)) return PasswordStrength.weak;

  var score = 0;
  if (password.length >= 12) score++;
  if (password.length >= 16) score++;
  if (RegExp(r'[a-zçğıöşü]').hasMatch(password) &&
      RegExp(r'[A-ZÇĞİÖŞÜ]').hasMatch(password)) {
    score++;
  }
  if (RegExp(r'[^\p{L}\d]', unicode: true).hasMatch(password)) score++;

  return switch (score) {
    0 => PasswordStrength.fair,
    1 || 2 => PasswordStrength.good,
    _ => PasswordStrength.strong,
  };
}
