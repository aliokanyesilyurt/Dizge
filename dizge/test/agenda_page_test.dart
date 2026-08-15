import 'package:dizge/data/app_store.dart';
import 'package:dizge/data/local_store.dart';
import 'package:dizge/models/agenda_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A3 — ajanda yaprağının modeli ve kalıcılığı.
///
/// Ajandanın ilk sözü şu: **yazdığın kaybolmaz.** Tanıma yanılsa da, görev
/// oluşmasa da sayfa yerinde durur. Bu dosyadaki testler o sözü tutuyor.
void main() {
  InkStroke stroke(List<Offset> points, {Color color = Colors.black}) =>
      InkStroke(points: points, color: color);

  final day = DateTime(2026, 8, 15, 17, 42);

  group('AgendaPage modeli', () {
    test('gün anahtarı saatten arınır — bir güne bir yaprak', () {
      // Aynı günün sabahı ve akşamı aynı sayfayı açmalı; saat farkı iki ayrı
      // yaprak üretirse "bugünün sayfası" diye bir şey kalmaz.
      final sabah = AgendaPage(day: DateTime(2026, 8, 15, 7));
      final aksam = AgendaPage(day: DateTime(2026, 8, 15, 23, 59));

      expect(sabah.key, aksam.key);
      expect(sabah.key, '2026-08-15');
    });

    test('vuruşlar yazılıp aynen geri okunur', () {
      final page = AgendaPage(
        day: day,
        strokes: [
          stroke(const [Offset(10, 20), Offset(30, 40)], color: Colors.red),
          stroke(const [Offset(1, 2)]),
        ],
        canvasSize: const Size(800, 600),
      );

      final back = AgendaPage.fromJson(page.toJson());

      expect(back.key, page.key);
      expect(back.strokes, hasLength(2));
      expect(back.strokes.first.points, const [Offset(10, 20), Offset(30, 40)]);
      expect(back.strokes.first.color.toARGB32(), Colors.red.toARGB32());
      expect(back.canvasSize, const Size(800, 600));
    });

    test('tek noktalı vuruş yazımda kaybolmaz', () {
      // Noktalar düz bir sayı dizisine açılıyor; tek noktanın (iki sayı) o
      // yolda düşmediğinin kanıtı — "i" harfinin noktası bu.
      final back = AgendaPage.fromJson(
        AgendaPage(
          day: day,
          strokes: [
            stroke(const [Offset(5, 5)]),
          ],
        ).toJson(),
      );

      expect(back.strokes.single.points, const [Offset(5, 5)]);
    });

    test('boş sayfa boş sayılır', () {
      expect(AgendaPage(day: day).isEmpty, isTrue);
      expect(AgendaPage(day: day, strokes: [stroke(const [])]).isEmpty, isTrue);
      expect(
        AgendaPage(
          day: day,
          strokes: [
            stroke(const [Offset.zero]),
          ],
        ).isEmpty,
        isFalse,
      );
    });
  });

  group('depo', () {
    test('yazılan sayfa aynı günün okumasında geri gelir', () {
      final store = AppStore();
      addTearDown(store.dispose);

      expect(store.agendaPage(day).isEmpty, isTrue, reason: 'boş başlar');

      store.saveAgendaPage(
        AgendaPage(
          day: day,
          strokes: [
            stroke(const [Offset(3, 4)]),
          ],
        ),
      );

      // Saati farklı ama günü aynı bir okuma da aynı sayfayı bulmalı.
      expect(store.agendaPage(DateTime(2026, 8, 15)).strokes, hasLength(1));
    });

    test('boşaltılan sayfa kayıt bırakmaz', () {
      // Dokunulup vazgeçilmiş her gün için anlık görüntüde bir satır tutmanın
      // kimseye faydası yok.
      final store = AppStore();
      addTearDown(store.dispose);

      store.saveAgendaPage(
        AgendaPage(
          day: day,
          strokes: [
            stroke(const [Offset(3, 4)]),
          ],
        ),
      );
      expect(store.writtenAgendaDays, hasLength(1));

      store.saveAgendaPage(AgendaPage(day: day));
      expect(store.writtenAgendaDays, isEmpty);
    });

    test('mürekkep uygulama kapanıp açıldığında yerinde', () async {
      // A3'ün asıl ölçütü. İki ayrı store, aynı disk.
      final disk = InMemoryStore();

      final first = AppStore();
      await first.attachPersistence(disk);
      first.saveAgendaPage(
        AgendaPage(
          day: day,
          strokes: [
            stroke(const [Offset(10, 10), Offset(20, 20)], color: Colors.blue),
          ],
          canvasSize: const Size(1024, 768),
        ),
      );
      await first.flush();
      first.dispose();

      final second = AppStore();
      await second.attachPersistence(disk);
      addTearDown(second.dispose);

      final page = second.agendaPage(day);
      expect(page.strokes, hasLength(1));
      expect(page.strokes.single.points, hasLength(2));
      expect(page.strokes.single.color.toARGB32(), Colors.blue.toARGB32());
      expect(page.canvasSize, const Size(1024, 768));
    });

    test('ajanda öncesi bir kayıt açıldığında patlamaz', () {
      // Alan hiç yokken yazılmış anlık görüntüler hâlâ okunabilmeli.
      final store = AppStore();
      addTearDown(store.dispose);

      store.loadJson(const {'nodes': [], 'habits': []});

      expect(store.writtenAgendaDays, isEmpty);
      expect(store.agendaPage(day).isEmpty, isTrue);
    });
  });
}
