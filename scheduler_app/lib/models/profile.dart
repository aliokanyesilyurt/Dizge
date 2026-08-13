/// Bir kullanıcının **gösterilebilir** yüzü (Y4.4).
///
/// Tabloda e-posta yok ve bu sınıfta da olmayacak: grup arkadaşına gösterilmesi
/// gereken şey "bu işi kim yazdı" sorusunun cevabı, iletişim bilgisi değil.
class Profile {
  const Profile({required this.userId, this.displayName = '', this.avatarUrl});

  final String userId;

  /// Kayıtta Google adından, yoksa e-postanın `@` öncesinden dolar; hesap
  /// ekranından değiştirilebilir. Boş olabilir — sunucu `not null default ''`
  /// diyor ama boş bir ad arayüzde `?` rozetine düşer.
  final String displayName;

  /// Sağlayıcının (bugün Google) CDN adresi. Fotoğrafın kendisini
  /// kopyalamıyoruz; kullanıcı sağlayıcıdan silerse bizde de yaşamamalı.
  final String? avatarUrl;

  /// Rozette görünen 1–2 harf: `Ali Okan` → `AO`, `Ali` → `A`.
  ///
  /// Latin dışı adlar da çalışır (`Ömer` → `Ö`); harf sayılamayan bir şeyle
  /// başlayan ad (emoji, boşluk, noktalama) `?` verir — anlamsız bir simgeyi
  /// büyütüp göstermektense bilinmezliği söylemek dürüst.
  String get initials {
    final words = [
      for (final w in displayName.trim().split(RegExp(r'\s+')))
        if (w.isNotEmpty) w,
    ];
    if (words.isEmpty) return '?';

    final letters = [for (final w in words.take(2)) ?_firstLetter(w)];
    return letters.isEmpty ? '?' : letters.join();
  }

  /// Sözcüğün ilk **harfini** verir; harf yoksa null.
  static String? _firstLetter(String word) {
    for (final rune in word.runes) {
      final ch = String.fromCharCode(rune);
      if (RegExp(r'\p{L}', unicode: true).hasMatch(ch)) return ch.toUpperCase();
    }
    return null;
  }

  /// Ekranda tam ad gereken yerler (önizleme, düzenleyici, ekran okuyucu).
  String get label => displayName.trim().isEmpty ? 'Adsız' : displayName.trim();

  bool get hasPhoto => (avatarUrl ?? '').isNotEmpty;

  /// Sunucu satırından — sütun adları snake_case.
  factory Profile.fromRow(Map<String, dynamic> row) => Profile(
    userId: (row['user_id'] as String?) ?? '',
    displayName: (row['display_name'] as String?) ?? '',
    avatarUrl: _clean(row['avatar_url'] as String?),
  );

  /// Yerel önbellek için. Çevrimdışı açılışta grup işlerinin **kime ait
  /// olduğu** görünmeli: adların bir tur gecikmeyle gelmesi, her açılışta
  /// bloklarda bir kare boyunca `?` rozeti demekti.
  Map<String, dynamic> toJson() => {
    'userId': userId,
    'displayName': displayName,
    'avatarUrl': ?avatarUrl,
  };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    userId: (j['userId'] as String?) ?? '',
    displayName: (j['displayName'] as String?) ?? '',
    avatarUrl: _clean(j['avatarUrl'] as String?),
  );

  Profile copyWith({String? displayName, String? avatarUrl}) => Profile(
    userId: userId,
    displayName: displayName ?? this.displayName,
    avatarUrl: avatarUrl ?? this.avatarUrl,
  );

  /// Boş dize `null` sayılır: istemci "fotoğraf var" sanıp boş bir ağ isteği
  /// atmasın.
  static String? _clean(String? raw) =>
      (raw == null || raw.trim().isEmpty) ? null : raw.trim();

  @override
  bool operator ==(Object other) =>
      other is Profile &&
      other.userId == userId &&
      other.displayName == displayName &&
      other.avatarUrl == avatarUrl;

  @override
  int get hashCode => Object.hash(userId, displayName, avatarUrl);

  @override
  String toString() => 'Profile($userId, $displayName)';
}
