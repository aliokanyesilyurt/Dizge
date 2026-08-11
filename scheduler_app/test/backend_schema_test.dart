import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Şemanın kendisi Dart değil, ama **güvenliği** Dart'tan doğrulanabilir.
///
/// Bu dosyanın var olma sebebi tek bir satır risk: RLS politikası yazılmamış
/// bir tablo, anon anahtarı olan herkese bütün kullanıcıların takvimini açar.
/// Şemayı elle gözden geçirmek buna yeterli bir bekçi değil — dördüncü tablo
/// eklendiği gün gözden kaçar. Bu yüzden kural test:
///
///   *`public` altında oluşturulan **her** tabloda RLS açık ve en az bir
///    politika olmalı.*
void main() {
  late final String sql;
  late final List<String> tables;

  setUpAll(() {
    final dir = Directory('supabase/migrations');
    expect(
      dir.existsSync(),
      isTrue,
      reason: 'supabase/migrations bulunamadı — şema repoda durmalı',
    );

    // Tek bir dosya değil, **bütün** migration'lar. Bekçinin değeri geleceğe
    // bakmasında: gruplar ikinci bir migration'la yeni tablolar getirecek ve
    // o tabloların RLS'i de burada denetlenmeli. Tek dosyaya bağlı kalsaydı
    // test yeşil kalır, açık büyürdü.
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.sql'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    expect(files, isNotEmpty, reason: 'en az bir migration dosyası bulunmalı');

    // Karşılaştırmalar küçük harf ve tek boşluk üzerinden: SQL büyük/küçük
    // harfe duyarsız ve sütun hizalaması bir okunurluk tercihi. Güvenlik
    // testinin ikisine de bağlanmaması gerekir — `alter table public.nodes`
    // ile `alter table  public.nodes` aynı şeydir.
    sql = files
        .map((f) => f.readAsStringSync())
        .join('\n')
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');

    tables = RegExp(
      r'create\s+table\s+(?:if\s+not\s+exists\s+)?public\.(\w+)',
    ).allMatches(sql).map((m) => m.group(1)!).toList();
  });

  group('şema güvenliği', () {
    test('şema en az üç tablo tanımlar', () {
      // Plan B1: nodes, habits, categories. Test sayıyı çakmıyor, yalnız
      // şemanın gerçekten dolu olduğunu doğruluyor.
      expect(tables, containsAll(['nodes', 'habits', 'categories']));
    });

    test('her tabloda RLS açık', () {
      for (final t in tables) {
        expect(
          sql,
          contains('alter table public.$t enable row level security'),
          reason: '$t tablosunda RLS açılmamış — tablo herkese açık',
        );
      }
    });

    test('her tablonun en az bir politikası var', () {
      for (final t in tables) {
        // RLS açık ama politika yoksa tablo kimseye açık olmaz; sessizce
        // "hiçbir şey senkronlanmıyor" hatası verir. O da bir bozukluk.
        expect(
          RegExp('create\\s+policy[^;]+?on\\s+public\\.$t\\b').hasMatch(sql),
          isTrue,
          reason: '$t tablosunun politikası yok',
        );
      }
    });

    test('her politika sahipliği auth.uid() ile kısıtlar', () {
      final policies = RegExp(
        r'create\s+policy(.*?);',
        dotAll: true,
      ).allMatches(sql).map((m) => m.group(1)!);

      expect(policies, isNotEmpty);
      for (final p in policies) {
        expect(
          p,
          contains('auth.uid()'),
          reason: 'auth.uid() geçmeyen politika sahipliği kısıtlamıyor: $p',
        );
      }
    });

    test('yazan politikalar with check taşır', () {
      // `using` yalnız okumayı süzer. `with check` olmadan kullanıcı, başka
      // birinin user_id'siyle satır **yazabilir**.
      final policies = RegExp(r'create\s+policy(.*?);', dotAll: true)
          .allMatches(sql)
          .map((m) => m.group(1)!)
          .where((p) => p.contains('for all') || p.contains('for insert'));

      expect(policies, isNotEmpty);
      for (final p in policies) {
        expect(
          p,
          contains('with check'),
          reason: 'yazmaya izin veren politikada with check yok: $p',
        );
      }
    });
  });

  group('fonksiyonlar', () {
    test('apply_mutations security invoker', () {
      // Plan B5: `definer` seçilseydi fonksiyon RLS'i baypas ederdi ve doğru
      // user_id yazmak tek başına fonksiyonun dikkatine kalırdı.
      final fn = RegExp(
        r'create\s+(?:or\s+replace\s+)?function\s+public\.apply_mutations(.*?)\$\$',
        dotAll: true,
      ).firstMatch(sql);

      expect(fn, isNotNull, reason: 'apply_mutations tanımlı değil');
      expect(fn!.group(1), contains('security invoker'));
    });

    test('kullanıcı verisine dokunan her fonksiyon search_path sabitler', () {
      // search_path sabitlenmezse, çağıran kendi şemasını öne alıp
      // `public.nodes` yerine kendi tablosunu okutabilir.
      final fns = RegExp(
        r'create\s+(?:or\s+replace\s+)?function\s+public\.(\w+)(.*?)\$\$',
        dotAll: true,
      ).allMatches(sql);

      expect(fns, isNotEmpty);
      for (final f in fns) {
        expect(
          f.group(2),
          contains('search_path'),
          reason: '${f.group(1)} search_path sabitlemiyor',
        );
      }
    });

    test('definer yetkili bakım fonksiyonu herkese açık değil', () {
      // Mezar taşı temizliği bütün kullanıcıların satırlarına dokunur; definer
      // olmak zorunda. O hâlde onu çağırma hakkı geri alınmalı.
      if (!sql.contains('purge_tombstones')) return;
      expect(
        sql,
        contains('revoke execute on function public.purge_tombstones'),
        reason: 'purge_tombstones çağrı hakkı geri alınmamış',
      );
    });
  });
}
