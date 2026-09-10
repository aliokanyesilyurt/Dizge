/// Paylaşılan bir takvim bağlamı (Y3 şeması, Y4 arayüzü).
///
/// İstemci için grup **yalnız bir ad ve bir kimlik**: hangi işlerin birlikte
/// gösterileceğini söyleyen bir etiket. Kimin neyi görebildiğine dair bütün
/// karar sunucuda, RLS'te — bu sınıfta bir yetki alanı yok ve olmamalı.
class Group {
  const Group({
    required this.id,
    required this.name,
    this.ownerId,
    this.description,
    this.color,
  });

  final String id;
  final String name;

  /// Grubu kuran kişi. Davet etme hakkı yalnız onda (Y3f); arayüz "davet et"
  /// düğmesini buna bakarak gösteriyor.
  final String? ownerId;

  /// Grup açıklaması veya özelleştirme seçeneği.
  final String? description;

  /// Grup rengi (ör. 0xFF22D3EE).
  final int? color;

  bool isOwnedBy(String? userId) => userId != null && ownerId == userId;

  /// Sunucu satırından — sütun adları snake_case.
  factory Group.fromRow(Map<String, dynamic> row) => Group(
    id: (row['id'] as String?) ?? '',
    name: (row['name'] as String?) ?? '',
    ownerId: row['owner_id'] as String?,
    description: row['description'] as String?,
    color: row['color'] as int?,
  );

  /// Yerel önbellek için. Çevrimdışı açılışta grup **adlarının** görünmesi
  /// gerekiyor: bağlam seçicide "Kişisel" ile yan yana boş bir satır durması,
  /// kullanıcının grubunun kaybolduğunu sanması demekti.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ownerId': ownerId,
    'description': description,
    'color': color,
  };

  factory Group.fromJson(Map<String, dynamic> j) => Group(
    id: (j['id'] as String?) ?? '',
    name: (j['name'] as String?) ?? '',
    ownerId: j['ownerId'] as String?,
    description: j['description'] as String?,
    color: j['color'] as int?,
  );

  Group copyWith({String? name, String? description, int? color}) => Group(
    id: id,
    name: name ?? this.name,
    ownerId: ownerId,
    description: description ?? this.description,
    color: color ?? this.color,
  );

  @override
  bool operator ==(Object other) =>
      other is Group &&
      other.id == id &&
      other.name == name &&
      other.ownerId == ownerId &&
      other.description == description &&
      other.color == color;

  @override
  int get hashCode => Object.hash(id, name, ownerId, description, color);

  @override
  String toString() => 'Group($id, $name, $description, $color)';
}
