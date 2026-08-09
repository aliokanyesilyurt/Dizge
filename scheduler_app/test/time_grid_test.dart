import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/core/time_grid.dart';

/// Yerleşim testleri için asgari etkinlik: kimlik + zaman aralığı.
class Ev {
  const Ev(this.id, this.start, this.end);
  final String id;
  final double start;
  final double end;
}

Ev ev(String id, double start, double end) => Ev(id, start, end);

/// Izgaranın saf mantığı. Bu testler widget ağacı kurmadan koşar; çakışma
/// yerleşimi gibi asıl kırılgan kısım burada kilitlenir.
void main() {
  group('GridMetrics', () {
    const m = GridMetrics(hourHeight: 60);

    test('saat ↔ piksel dönüşümü simetriktir', () {
      expect(m.yFor(9), 540);
      expect(m.hourAt(540), 9);
      expect(m.totalHeight, 1440);
    });

    test('ızgara dışı piksel gün sınırına kırpılır', () {
      expect(m.hourAt(-200), 0);
      expect(m.hourAt(99999), 24);
    });

    test('ölçekleme min/max sınırlarına oturur', () {
      expect(m.scaled(100).hourHeight, GridMetrics.maxHourHeight);
      expect(m.scaled(0.001).hourHeight, GridMetrics.minHourHeight);
    });
  });

  group('snapHour', () {
    test('15 dakikalık ızgaraya yuvarlar', () {
      expect(snapHour(9.10), closeTo(9.0, 1e-9));
      expect(snapHour(9.20), closeTo(9.25, 1e-9));
      expect(snapHour(9.60), closeTo(9.5, 1e-9));
      expect(snapHour(9.90), closeTo(10.0, 1e-9));
    });

    test('adım değiştirilebilir (boş slot dokunuşu 30 dakika)', () {
      expect(snapHour(9.20, minutes: 30), closeTo(9.0, 1e-9));
      expect(snapHour(9.40, minutes: 30), closeTo(9.5, 1e-9));
    });
  });

  group('clampStartWithin', () {
    test('süre gün sonunu taşarsa başlangıç geri çekilir', () {
      // 23:30'a bırakılan 2 saatlik iş 22:00'de başlar.
      expect(clampStartWithin(23.5, 2.0), 22.0);
    });

    test('sığan iş olduğu yerde kalır', () {
      expect(clampStartWithin(9.0, 1.5), 9.0);
    });

    test('negatif başlangıç gün başına çekilir', () {
      expect(clampStartWithin(-3, 1), 0);
    });
  });

  group('layoutEvents — çakışma yerleşimi', () {
    List<EventSlot<Ev>> layout(List<Ev> items) =>
        layoutEvents(items, startOf: (i) => i.start, endOf: (i) => i.end);

    EventSlot<Ev> byId(List<EventSlot<Ev>> slots, String id) =>
        slots.firstWhere((s) => s.item.id == id);

    test('çakışmayan işler tam genişlik alır', () {
      final slots = layout([ev('a', 9, 10), ev('b', 11, 12)]);
      for (final s in slots) {
        expect(s.columns, 1);
        expect(s.widthFraction, 1.0);
      }
    });

    test('bitişik işler (10:00 biten / 10:00 başlayan) çakışmaz', () {
      final slots = layout([ev('a', 9, 10), ev('b', 10, 11)]);
      expect(slots.every((s) => s.columns == 1), isTrue);
    });

    test('iki çakışan iş yarı yarıya paylaşır', () {
      final slots = layout([ev('a', 9, 11), ev('b', 10, 12)]);
      expect(byId(slots, 'a').columns, 2);
      expect(byId(slots, 'a').column, 0);
      expect(byId(slots, 'b').column, 1);
      expect(byId(slots, 'a').widthFraction, 0.5);
    });

    test('üç çakışan iş üç sütuna dağılır', () {
      final slots = layout([ev('a', 9, 12), ev('b', 9.5, 11), ev('c', 10, 13)]);
      expect(slots.every((s) => s.columns == 3), isTrue);
      expect({for (final s in slots) s.column}, {0, 1, 2});
    });

    test('uzun iş en solda kalır, kısa olanlar sağa dizilir', () {
      // b 9-12 en uzun → sütun 0. a 9-10 sütun 1. c 10.5-11, a bittiği için
      // onun sütununu yeniden kullanır.
      final slots = layout([ev('a', 9, 10), ev('b', 9, 12), ev('c', 10.5, 11)]);
      expect(byId(slots, 'b').column, 0);
      expect(byId(slots, 'a').column, 1);
      expect(byId(slots, 'c').column, 1);
    });

    test('boşalan sütunlara sağa genişleme yapılır', () {
      // uzun 9-13 sütun 0; a ve b 9-10 sütun 1 ve 2 → 3 sütun.
      // d 10.5-11'de a ve b bitmiş olduğu için sütun 1'den 2'ye taşar.
      final slots = layout([
        ev('uzun', 9, 13),
        ev('a', 9, 10),
        ev('b', 9, 10),
        ev('d', 10.5, 11),
      ]);
      final d = byId(slots, 'd');
      expect(d.columns, 3);
      expect(d.column, 1);
      expect(d.span, 2, reason: 'boşalan üçüncü sütuna genişlemeli');
      expect(d.widthFraction, closeTo(2 / 3, 1e-9));
      // Uzun iş sabit: sol sütunun tamamı onun.
      expect(byId(slots, 'uzun').span, 1);
    });

    test('ayrı zaman kümeleri birbirinin genişliğini etkilemez', () {
      // Sabah tek iş, akşam üçlü çakışma.
      final slots = layout([
        ev('sabah', 8, 9),
        ev('x', 18, 20),
        ev('y', 18.5, 20),
        ev('z', 19, 21),
      ]);
      expect(
        byId(slots, 'sabah').columns,
        1,
        reason: 'akşamki kalabalık sabahı daraltmamalı',
      );
      expect(byId(slots, 'x').columns, 3);
    });

    test('sıfır süreli kayıt en az bir adım yer kaplar', () {
      final slots = layout([ev('a', 9, 9)]);
      expect(slots.single.duration, kMinDurationHours);
    });

    test('çakışanlarda uzun iş solda durur', () {
      final slots = layout([ev('kısa', 9, 9.5), ev('uzun', 9, 12)]);
      expect(byId(slots, 'uzun').column, 0);
      expect(byId(slots, 'kısa').column, 1);
    });
  });

  group('hafta yardımcıları', () {
    test('mondayOf her günü kendi pazartesisine götürür', () {
      // 2026-08-01 bir Cumartesi.
      final saturday = DateTime(2026, 8, 1);
      expect(saturday.weekday, DateTime.saturday);
      expect(mondayOf(saturday), DateTime(2026, 7, 27));
      // Pazartesi kendisidir.
      expect(mondayOf(DateTime(2026, 7, 27)), DateTime(2026, 7, 27));
    });

    test('mondayOf saat bilgisini kırpar', () {
      expect(mondayOf(DateTime(2026, 8, 1, 23, 45)), DateTime(2026, 7, 27));
    });

    test('weeksBetween ileri ve geri yönde çalışır', () {
      final a = DateTime(2026, 7, 27);
      expect(weeksBetween(a, a.add(const Duration(days: 21))), 3);
      expect(weeksBetween(a, a.subtract(const Duration(days: 14))), -2);
    });

    test('hourOfDay ondalık saati verir', () {
      expect(hourOfDay(DateTime(2026, 8, 1, 14, 30)), closeTo(14.5, 1e-9));
    });
  });
}
