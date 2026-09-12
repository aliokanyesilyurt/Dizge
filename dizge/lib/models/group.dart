/// Paylaşılan bir takvim bağlamı (Y3 şeması, Y4 arayüzü).
///
/// İstemci için grup bir ad, bir kimlik ve (R1) bir renk ile kısa bir
/// açıklama: hangi işlerin birlikte gösterileceğini söyleyen bir etiket. Kimin
/// neyi görebildiğine dair bütün karar sunucuda, RLS'te — bu sınıfta bir yetki
/// alanı yok ve olmamalı.
class Group {
  const Group({
    required this.id,
    required this.name,
    this.ownerId,
    this.description,
    this.colorIndex,
  });

  /// Açıklamanın üst sınırı — sunucudaki `groups_description_length` ile aynı.
  static const int maxDescription = 200;

  final String id;
  final String name;

  /// Grubu kuran kişi. Davet etme ve düzenleme hakkı yalnız onda (Y3f);
  /// arayüz o düğmeleri buna bakarak gösteriyor.
  final String? ownerId;

  /// "Ev işleri ve alışveriş" gibi tek satırlık açıklama; yoksa null.
  final String? description;

  /// Grubun rengi: `kAvatarColors` içindeki **sıra**, hex değil (göç 06 §1).
  /// Null ise renk kimlikten türüyor (`groupColorOf`).
  final int? colorIndex;

  bool isOwnedBy(String? userId) => userId != null && ownerId == userId;

  /// Sunucu satırından — sütun adları snake_case.
  factory Group.fromRow(Map<String, dynamic> row) => Group(
    id: (row['id'] as String?) ?? '',
    name: (row['name'] as String?) ?? '',
    ownerId: row['owner_id'] as String?,
    description: _clean(row['description'] as String?),
    colorIndex: (row['color'] as num?)?.toInt(),
  );

  /// Yerel önbellek için. Çevrimdışı açılışta grup **adlarının** görünmesi
  /// gerekiyor: bağlam seçicide "Kişisel" ile yan yana boş bir satır durması,
  /// kullanıcının grubunun kaybolduğunu sanması demekti.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ownerId': ?ownerId,
    'description': ?description,
    'colorIndex': ?colorIndex,
  };

  factory Group.fromJson(Map<String, dynamic> j) => Group(
    id: (j['id'] as String?) ?? '',
    name: (j['name'] as String?) ?? '',
    ownerId: j['ownerId'] as String?,
    description: _clean(j['description'] as String?),
    colorIndex: (j['colorIndex'] as num?)?.toInt(),
  );

  /// Düzenleme sonrası kopya. Açıklama boş dizeyle **silinebiliyor** (null
  /// "değiştirme" demek, `''` "kaldır").
  Group copyWith({String? name, String? description, int? colorIndex}) => Group(
    id: id,
    name: name ?? this.name,
    ownerId: ownerId,
    description: description == null ? this.description : _clean(description),
    colorIndex: colorIndex ?? this.colorIndex,
  );

  static String? _clean(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  @override
  bool operator ==(Object other) =>
      other is Group &&
      other.id == id &&
      other.name == name &&
      other.ownerId == ownerId &&
      other.description == description &&
      other.colorIndex == colorIndex;

  @override
  int get hashCode => Object.hash(id, name, ownerId, description, colorIndex);

  @override
  String toString() => 'Group($id, $name)';
}

/// Grubun bir üyesi (R3: grup sayfası). Ad ve rozet profil dizininden gelir;
/// burada yalnız kimlik ve rol.
class GroupMember {
  const GroupMember({required this.userId, required this.isOwner});

  final String userId;
  final bool isOwner;

  factory GroupMember.fromRow(Map<String, dynamic> row) => GroupMember(
    userId: (row['user_id'] as String?) ?? '',
    isOwner: row['role'] == 'owner',
  );

  @override
  bool operator ==(Object other) =>
      other is GroupMember &&
      other.userId == userId &&
      other.isOwner == isOwner;

  @override
  int get hashCode => Object.hash(userId, isOwner);
}
