import 'dart:io';

import 'package:dizge/core/pool_labels.dart';
import 'package:flutter_test/flutter_test.dart';

/// H1 — havuzun adı "Havuz"; "Kenarda Bekleyenler" hiçbir yüzeyde kalmadı.
void main() {
  test('şeridin ipucu sayıyı parantezde taşır', () {
    expect(poolCountLabel(0), 'Havuz');
    expect(poolCountLabel(3), 'Havuz (3)');
  });

  test('eski ad hiçbir ekran metninde geçmiyor', () {
    // Yorumlar serbest (tarihçe anlatıyorlar); yalnız tırnak içindeki
    // metinler taranıyor — kullanıcının gördüğü şey onlar.
    final literal = RegExp(r"'[^'\n]*(Kenarda|[Kk]enara al)[^'\n]*'");
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        if (literal.hasMatch(line)) offenders.add('${entity.path}:${i + 1}');
      }
    }

    expect(offenders, isEmpty, reason: 'eski havuz adı');
  });
}
