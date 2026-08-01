import '../models/node.dart';

/// Obsidian tarzı [[Başlık]] bağlantılarının tek merkezden çözümlendiği indeks.
///
/// Mimari karar — İlişkisel yapı: bağlantının **tek kaynağı** node'un gövde
/// metnidir ([Node.body]). Backlink'leri ayrıca saklamayız (denormalizasyon =
/// tutarsızlık riski); bunun yerine tüm gövdeleri tarayıp hem ileri hem geri
/// haritayı burada türetiriz. Node eklenince/silinince/değişince yeniden kurulur.
class LinkIndex {
  /// title (küçük harfe indirgenmiş) -> node id. Aynı başlıkta ilk gelen kazanır.
  final Map<String, String> _idByTitle;

  /// nodeId -> bu node'un gövdesinde geçen ve çözülebilen hedef node id'leri.
  final Map<String, Set<String>> forward;

  /// nodeId -> bu node'a link veren node id'leri (çift yönlü bağlantı = backlink).
  final Map<String, Set<String>> backlinks;

  /// Henüz karşılığı olmayan [[başlık]]'lar (kırık/oluşturulmamış bağlantılar).
  /// Editörde "tıkla ve oluştur" akışını besler.
  final Map<String, Set<String>> unresolvedByNode;

  const LinkIndex._(
    this._idByTitle,
    this.forward,
    this.backlinks,
    this.unresolvedByNode,
  );

  /// Gövdedeki `[[...]]` kalıplarını yakalar. Boşluk/case'e toleranslı; `|` ile
  /// verilen görünen ad (alias) desteklenir: `[[Hedef|görünen]]`.
  static final RegExp _linkPattern = RegExp(r'\[\[([^\[\]|]+)(?:\|[^\[\]]*)?\]\]');

  /// Bir metindeki tüm bağlantı hedeflerini (normalize edilmemiş, ham başlık)
  /// döndürür. Editör/parser burayı tek noktadan kullanmalı.
  static List<String> extractLinkTitles(String body) => _linkPattern
      .allMatches(body)
      .map((m) => m.group(1)!.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  static String _norm(String title) => title.trim().toLowerCase();

  /// Verilen node kümesinden indeksi baştan kurar. O(toplam metin uzunluğu).
  factory LinkIndex.build(Iterable<Node> nodes) {
    final idByTitle = <String, String>{};
    for (final n in nodes) {
      final key = _norm(n.title);
      if (key.isNotEmpty) idByTitle.putIfAbsent(key, () => n.id);
    }

    final forward = <String, Set<String>>{};
    final backlinks = <String, Set<String>>{};
    final unresolved = <String, Set<String>>{};

    for (final n in nodes) {
      final targets = <String>{};
      final missing = <String>{};
      for (final raw in extractLinkTitles(n.body)) {
        final targetId = idByTitle[_norm(raw)];
        if (targetId == null || targetId == n.id) {
          if (targetId == null) missing.add(raw);
          continue; // kendine link veya çözülemeyen -> ileri bağlantı sayılmaz
        }
        targets.add(targetId);
        backlinks.putIfAbsent(targetId, () => <String>{}).add(n.id);
      }
      if (targets.isNotEmpty) forward[n.id] = targets;
      if (missing.isNotEmpty) unresolved[n.id] = missing;
    }

    return LinkIndex._(idByTitle, forward, backlinks, unresolved);
  }

  /// [title]'ın karşılık geldiği node id'si (yoksa null). [[ ]] tıklamasını çözer.
  String? resolveTitle(String title) => _idByTitle[_norm(title)];

  /// [id]'nin verdiği bağlantılar.
  Set<String> linksFrom(String id) => forward[id] ?? const {};

  /// [id]'ye gelen bağlantılar (backlink paneli için).
  Set<String> linksTo(String id) => backlinks[id] ?? const {};
}
