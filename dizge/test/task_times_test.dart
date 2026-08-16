import 'package:dizge/models/task.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Z6 — aynı işin gün içinde birden çok kez tekrarlanması.
///
/// Pencereden farkı: pencere bir kısıt (iş bir kez olur), bu bir çoğalma
/// (iş birkaç kez olur ve **her tekrar ayrı tamamlanır**).
void main() {
  final day = DateTime(2026, 8, 17);

  Task ilac({List<double>? times}) => Task(
    title: 'İlaç',
    color: const Color(0xFF38BDF8),
    date: day,
    startHour: 8,
    durationHours: 10 / 60,
    timesOfDay: times,
  );

  group('Z6 — saat listesi', () {
    test('sıralanıp yinelenenler atılıyor', () {
      // Izgara sıralı bekliyor; aynı saati iki kez eklemek görünmeyen bir
      // çift blok üretirdi.
      final t = ilac(times: [20, 8, 14, 8]);
      expect(t.timesOfDay, [8, 14, 20]);
    });

    test('tek saat listeyi boşaltıyor', () {
      // "Tek sefer"in gösterimi boş liste: tek saat zaten startHour'da
      // duruyor, iki yerde iki ayrı doğru er geç ayrışırdı.
      expect(ilac(times: [9]).timesOfDay, isEmpty);
    });

    test('setTimes startHour aynasını koruyor', () {
      final t = ilac();
      t.setTimes([14, 8, 20]);

      expect(t.timesOfDay, [8, 14, 20]);
      expect(t.startHour, 8);
    });

    test('occurrenceHours tek kapı', () {
      // Çağıran taraf "bir mi çok mu" ayrımını yapmak zorunda kalmasın.
      expect(ilac().occurrenceHours, [8]);
      expect(ilac(times: [8, 14, 20]).occurrenceHours, [8, 14, 20]);

      final saatsiz = Task(
        title: 'Saatsiz',
        color: const Color(0xFF38BDF8),
        date: day,
      );
      expect(saatsiz.occurrenceHours, isEmpty);
    });
  });

  group('Z6 — her tekrar ayrı tamamlanıyor', () {
    test('üç tekrar üç kez işaretleniyor', () {
      final t = ilac(times: [8, 14, 20]);

      t.setSlotDone(day, 8, true);
      expect(t.isSlotDone(day, 8), isTrue);
      expect(t.isSlotDone(day, 14), isFalse);
    });

    test('ikisi işaretliyken gün tamamlanmış sayılmıyor', () {
      // Üç kez içilecek ilacın ilk dozunda "bitti" demek olurdu.
      final t = ilac(times: [8, 14, 20]);

      t.setSlotDone(day, 8, true);
      t.setSlotDone(day, 14, true);
      expect(t.isDoneOn(day), isFalse);

      t.setSlotDone(day, 20, true);
      expect(t.isDoneOn(day), isTrue);
    });

    test('işareti geri almak günü de geri alıyor', () {
      final t = ilac(times: [8, 14]);
      t.setSlotDone(day, 8, true);
      t.setSlotDone(day, 14, true);
      expect(t.isDoneOn(day), isTrue);

      t.setSlotDone(day, 14, false);
      expect(t.isDoneOn(day), isFalse);
    });

    test('bir saat çıkarılınca kalanların geçmişi yerinde', () {
      // Anahtar saat değeri, dizin değil: dizinle anahtarlansaydı 14:00'i
      // silmek 20:00'nin tamamlanmışlığını kaydırırdı.
      final t = ilac(times: [8, 14, 20]);
      t.setSlotDone(day, 8, true);
      t.setSlotDone(day, 20, true);

      t.setTimes([8, 20]);

      expect(t.isSlotDone(day, 8), isTrue);
      expect(t.isSlotDone(day, 20), isTrue);
    });

    test('başka gün ayrı sayılıyor', () {
      final t = ilac(times: [8, 14]);
      t.setSlotDone(day, 8, true);
      expect(t.isSlotDone(DateTime(2026, 8, 18), 8), isFalse);
    });
  });

  group('Z6 — kalıcılık ve kopyalar', () {
    test('tur kayıpsız', () {
      final t = ilac(times: [8, 14, 20]);
      t.setSlotDone(day, 14, true);

      final back = Task.fromJson(t.toJson());
      expect(back.timesOfDay, [8, 14, 20]);
      expect(back.isSlotDone(day, 14), isTrue);
      expect(back.isSlotDone(day, 8), isFalse);
    });

    test('eski kayıt tek sefer okunuyor', () {
      final back = Task.fromJson({
        'id': 'a1',
        'title': 'Eski',
        'startHour': 9.0,
        'date': '2026-08-17',
      });
      expect(back.timesOfDay, isEmpty);
      expect(back.occurrenceHours, [9.0]);
    });

    test('gün kopyası saatleri alıyor, geçmişi almıyor', () {
      final t = ilac(times: [8, 14]);
      t.setSlotDone(day, 8, true);

      final yarin = t.duplicateTo(DateTime(2026, 8, 18));
      expect(yarin.timesOfDay, [8, 14]);
      expect(yarin.completedSlots, isEmpty);
    });
  });
}
