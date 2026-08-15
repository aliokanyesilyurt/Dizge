import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/core/usage_mode_controller.dart';
import 'package:scheduler_app/data/local_store.dart';
import 'package:scheduler_app/data/persistence_providers.dart';

/// A2 — kullanım modu tercihi.
///
/// Tema kipiyle bilinçli olarak aynı kalıpta yazıldı; iki tercihin de aynı
/// yerde, aynı biçimde yaşadığı buradan da okunsun.
void main() {
  group('kullanım modu', () {
    ProviderContainer containerWith(LocalStore store) {
      final container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('kayıt yoksa karma ile başlar', () {
      // Varsayılanın karma olması bir karar: mevcut kullanıcının klavyesi
      // elinden alınmıyor, yeni yol da gizlenmiyor.
      final container = containerWith(InMemoryStore());
      expect(container.read(usageModeProvider), UsageMode.karma);
    });

    test('seçim depoya yazılır ve sonraki açılışta geri okunur', () async {
      final store = InMemoryStore();

      final first = containerWith(store);
      await first.read(usageModeProvider.notifier).set(UsageMode.ajanda);
      expect(store.readString(kUsageModeKey), 'ajanda');

      final second = containerWith(store);
      expect(second.read(usageModeProvider), UsageMode.ajanda);
    });

    test('bozuk kayıt karmaya düşer, patlamaz', () async {
      // İleride bir mod kaldırılırsa eski kaydı olan kullanıcı kilitli
      // kalmamalı.
      final store = InMemoryStore();
      await store.writeString(kUsageModeKey, 'defter');

      final container = containerWith(store);
      expect(container.read(usageModeProvider), UsageMode.karma);
    });

    test('modların yetkileri karışmaz', () {
      // Ajanda sekmesinin görünürlüğü ve "önce ajanda açılsın mı" iki ayrı
      // soru; karma modda ilkinin yanıtı evet, ikincisinin hayır.
      expect(UsageMode.klasik.showsAgenda, isFalse);
      expect(UsageMode.klasik.opensAgendaFirst, isFalse);

      expect(UsageMode.ajanda.showsAgenda, isTrue);
      expect(UsageMode.ajanda.opensAgendaFirst, isTrue);

      expect(UsageMode.karma.showsAgenda, isTrue);
      expect(
        UsageMode.karma.opensAgendaFirst,
        isFalse,
        reason: 'karma modda seçim kullanıcının',
      );
    });
  });
}
