import '../../models/node.dart';

/// Bir kaydın hangi koleksiyona ait olduğu. Uzak şemada tablo/koleksiyon adına
/// karşılık gelir (Supabase: `tasks`, `notes`, `habits`).
enum EntityKind { task, note, habit, category }

/// Yapılan işlem.
enum MutationOp { upsert, delete }

/// **Offline-first'ün taşıyıcısı.** Kullanıcı bir şey değiştirdiğinde önce
/// yerel model güncellenir (anında UI), sonra bu kayıt outbox'a yazılır.
/// Bağlantı geldiğinde outbox sırayla uzak sunucuya boşaltılır.
///
/// Çakışma stratejisi — **son yazan kazanır (LWW)**: her mutasyon [at] damgası
/// taşır; sunucudaki kayıt daha yeniyse gönderim atlanır. Tek kullanıcılı bir
/// planlayıcı için doğru denge; çok cihazlı düzenlemede alan bazlı birleştirme
/// gerekirse [payload] zaten tam kaydı taşıdığı için burası genişletilebilir.
class Mutation {
  Mutation({
    String? id,
    required this.kind,
    required this.entityId,
    required this.op,
    required this.payload,
    DateTime? at,
    this.attempts = 0,
  })  : id = id ?? newNodeId(),
        at = at ?? DateTime.now();

  /// Mutasyonun kendi kimliği. Sunucu tarafında **idempotency key** olarak
  /// kullanılır: aynı mutasyon iki kez gönderilirse (ağ zaman aşımı sonrası
  /// tekrar) ikinci kez uygulanmaz.
  final String id;

  final EntityKind kind;

  /// Değişen kaydın kimliği (Task.id, Note.id, Habit.id).
  final String entityId;

  final MutationOp op;

  /// `upsert` için kaydın tam JSON'ı; `delete` için boş harita.
  final Map<String, dynamic> payload;

  final DateTime at;

  /// Kaç kez gönderilmeye çalışıldı — geri çekilme (backoff) ve zehirli kayıt
  /// tespiti için.
  final int attempts;

  Mutation withAttempt() => Mutation(
        id: id,
        kind: kind,
        entityId: entityId,
        op: op,
        payload: payload,
        at: at,
        attempts: attempts + 1,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'entityId': entityId,
        'op': op.name,
        'payload': payload,
        'at': at.toIso8601String(),
        'attempts': attempts,
      };

  factory Mutation.fromJson(Map<String, dynamic> j) => Mutation(
        id: j['id'] as String?,
        kind: EntityKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => EntityKind.task,
        ),
        entityId: (j['entityId'] as String?) ?? '',
        op: MutationOp.values.firstWhere(
          (o) => o.name == j['op'],
          orElse: () => MutationOp.upsert,
        ),
        payload:
            (j['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        at: DateTime.tryParse((j['at'] as String?) ?? ''),
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
      );

  @override
  String toString() => 'Mutation(${op.name} ${kind.name}/$entityId)';
}
