import 'package:flutter/material.dart';

import '../../theme.dart';
import 'editor_controls.dart';

/// Türkçe duyarlı katlama: "İstanbul", "istanbul" ve "ıstanbul" aynı yerdir.
///
/// `'İ'.toLowerCase()` Dart'ta noktayı ayrı bir birleşen olarak bırakıyor
/// (`i` + U+0307), yani düz küçültme "İ" ile "i"yi eşitlemiyor. Aksanı da
/// düşürüyoruz: "sisli" yazan "Şişli"yi bulabilsin — öneri listesi, doğru
/// harfi hatırlamayı sınamak için değil.
String foldPlace(String s) {
  const tr = <String, String>{
    'İ': 'i',
    'I': 'i',
    'ı': 'i',
    'Ş': 's',
    'ş': 's',
    'Ğ': 'g',
    'ğ': 'g',
    'Ü': 'u',
    'ü': 'u',
    'Ö': 'o',
    'ö': 'o',
    'Ç': 'c',
    'ç': 'c',
  };
  final out = StringBuffer();
  for (final ch in s.trim().split('')) {
    out.write(tr[ch] ?? ch.toLowerCase());
  }
  return out.toString();
}

/// Yer alanı için öneri listesi: kullanıcının **daha önce yazdığı** yerler.
///
/// Çevrimiçi bir yer arama servisi kullanılmıyor (bkz. plan K7′): her tuş
/// vuruşunda dışarı istek atmak uygulamanın "veri dışarı gitmez" sözünü
/// bozardı, üstelik pratikte de gereksiz — kimse her gün yeni bir yere
/// gitmiyor.
///
/// [history] var olan işlerin `place` alanları, **tekrarlarıyla birlikte**:
/// sıralamayı tekrar sayısı belirliyor. [query] boşsa en sık kullanılanlar
/// döner, yani öneri yazmaya başlamadan önce de vardır.
List<String> placeSuggestions(
  Iterable<String> history,
  String query, {
  int limit = 6,
}) {
  final counts = <String, int>{}; // katlanmış anahtar -> kaç işte geçiyor
  final spelling = <String, String>{}; // anahtar -> ilk görülen yazım
  for (final raw in history) {
    final value = raw.trim();
    if (value.isEmpty) continue;
    final key = foldPlace(value);
    counts[key] = (counts[key] ?? 0) + 1;
    spelling.putIfAbsent(key, () => value);
  }

  final q = foldPlace(query);
  final typed = query.trim();
  final hits = <String>[];
  for (final key in counts.keys) {
    if (q.isEmpty) {
      hits.add(key);
    } else if (spelling[key] != typed && key.contains(q)) {
      // Elenen yalnız **birebir** aynı yazım: kullanıcı onu zaten yazdı.
      // Katlanmış eşitlik yetmez — "sisli" yazana "Şişli"yi önermek, doğru
      // harfi onun yerine hatırlamak demek.
      hits.add(key);
    }
  }

  hits.sort((a, b) {
    if (q.isNotEmpty) {
      // Baştan eşleşen önce: "of" yazınca "Ofis", "Yeni ofis"ten önce gelsin.
      final byPrefix = (b.startsWith(q) ? 1 : 0) - (a.startsWith(q) ? 1 : 0);
      if (byPrefix != 0) return byPrefix;
    }
    final byCount = counts[b]!.compareTo(counts[a]!);
    // Alfabetik son basamak: eşit sıklıkta liste her açılışta aynı çıksın.
    return byCount != 0 ? byCount : a.compareTo(b);
  });

  return [for (final key in hits.take(limit)) spelling[key]!];
}

/// Yer alanı: metin kutusu + altında geçmişten gelen öneri çipleri.
///
/// Çip listesi yazdıkça daralıyor; dokunuş alanı doldurup imleci sona
/// alıyor — seçtikten sonra üstüne yazmak isteyen olabilir ("Ofis" → "Ofis,
/// 3. kat").
class PlaceField extends StatefulWidget {
  /// Düzenlenen metin. Sahibi editör; burada yalnız okunup yazılıyor.
  final TextEditingController controller;

  /// Var olan işlerin yer alanları, tekrarlarıyla birlikte.
  final List<String> history;

  /// Üstteki satırın özet metnini tazelemesi için.
  final ValueChanged<String>? onChanged;

  const PlaceField({
    super.key,
    required this.controller,
    required this.history,
    this.onChanged,
  });

  @override
  State<PlaceField> createState() => _PlaceFieldState();
}

class _PlaceFieldState extends State<PlaceField> {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final query = widget.controller.text;
    final picks = placeSuggestions(widget.history, query);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(color: c.ink, fontSize: T.strong),
          onChanged: (v) {
            setState(() {});
            widget.onChanged?.call(v);
          },
          decoration: const InputDecoration(hintText: 'Ev, ofis, spor salonu…'),
        ),
        if (picks.isNotEmpty) ...[
          const SizedBox(height: S.md),
          if (query.trim().isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: S.sm),
              // Nereden geldiği yazmazsa çipler "önerilen yerler" gibi
              // okunuyor; oysa hepsini kullanıcı kendi yazmış.
              child: Text(
                'Daha önce yazdıkların',
                style: TextStyle(color: c.inkDim, fontSize: T.caption),
              ),
            ),
          Wrap(
            spacing: S.sm,
            runSpacing: S.sm,
            children: [
              for (final place in picks)
                ChoiceChipTile(
                  text: place,
                  selected: false,
                  onTap: () => _pick(place),
                ),
            ],
          ),
        ],
      ],
    );
  }

  void _pick(String place) {
    widget.controller.value = TextEditingValue(
      text: place,
      selection: TextSelection.collapsed(offset: place.length),
    );
    setState(() {});
    widget.onChanged?.call(place);
  }
}
