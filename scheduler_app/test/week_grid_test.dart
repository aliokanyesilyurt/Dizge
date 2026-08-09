import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/core/time_grid.dart';
import 'package:scheduler_app/models/task.dart';
import 'package:scheduler_app/theme.dart';
import 'package:scheduler_app/widgets/week_time_grid.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'helpers.dart';

/// Izgaranın **jest sözleşmesi**: basılı tutup sürükleme doğru gün/saati,
/// alt kenardan çekme doğru süreyi bildiriyor mu?
///
/// Store'suz, doğrudan widget üzerinde koşar; böylece hata çıkarsa suçlu
/// belli olur (geometri mi, store mu).
void main() {
  // Sabit bir Pazartesi — testler takvim gününe göre kaymasın.
  final monday = DateTime(2026, 7, 20);
  const hourHeight = 60.0;
  const metrics = GridMetrics(hourHeight: hourHeight);

  Task task(
    String title, {
    double? start = 1.0,
    double duration = 1.0,
    DateTime? date,
    Repeat repeat = const Repeat.once(),
  }) => Task(
    title: title,
    color: const Color(0xFF4FC3F7),
    date: date ?? monday,
    startHour: start,
    durationHours: duration,
    repeat: repeat,
  );

  /// [tasksByDay]'i 7 güne yayan kabuk. Geri çağırımlar kaydedilir.
  Future<_Recorder> pumpGrid(
    WidgetTester tester, {
    required Map<int, List<Task>> byDay,
  }) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final rec = _Recorder();
    await tester.pumpWidget(
      // Doğrudan `MaterialApp` değil: blok artık `ShadTooltip` kullanıyor ve
      // ShadTheme ağaçta yoksa gerçek uygulamada sorun yokken test patlar.
      testApp(
        home: Scaffold(
          body: WeekTimeGrid(
            monday: monday,
            tasksByDay: List.generate(7, (i) => byDay[i] ?? const []),
            metrics: metrics,
            today: monday,
            onTapTask: (t, d) => rec.tapped = (t, d),
            onTapEmpty: (d, h) => rec.emptyTap = (d, h),
            onMove: (t, d, h) => rec.moved = (t, d, h),
            onResize: (t, dur) => rec.resized = (t, dur),
            onDuplicate: (t, d) => rec.duplicated = (t, d),
            onDelete: (t) => rec.deleted = t,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return rec;
  }

  /// Bloğu basılı tutup [delta] kadar sürükler.
  Future<void> dragBlock(
    WidgetTester tester,
    String title,
    Offset delta,
  ) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.text(title)),
    );
    // Uzun basma eşiğini geç (parmak sabit dururken).
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveBy(delta);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('saatli işler ızgarada blok olarak çizilir', (tester) async {
    await pumpGrid(
      tester,
      byDay: {
        0: [task('Toplantı')],
        2: [task('Spor', date: monday.add(const Duration(days: 2)))],
      },
    );

    expect(find.text('Toplantı'), findsOneWidget);
    expect(find.text('Spor'), findsOneWidget);
    // Saat sütunu etiketi (05:00 hiçbir blokta geçmiyor, yalnızca sütunda).
    expect(find.text('05:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saatsiz işler ızgaraya çizilmez', (tester) async {
    await pumpGrid(
      tester,
      byDay: {
        0: [task('Saatsiz iş', start: null)],
      },
    );

    // Saatsiz işlerin yeri "Saatsiz" şeridi; zaman ızgarası değil.
    expect(find.text('Saatsiz iş'), findsNothing);
  });

  testWidgets('bloğa dokunmak önce önizleme açar, düzenleyiciyi değil', (
    tester,
  ) async {
    // Yer, blokta hiç görünmüyor — önizlemenin gerçekten açıldığını bu
    // kanıtlar; saat gibi blokta da olan bir alan hiçbir şey ayırt etmezdi.
    final toplanti = Task(
      title: 'Toplantı',
      color: const Color(0xFF4FC3F7),
      date: monday,
      startHour: 1.0,
      durationHours: 2.0,
      place: 'Oda 3',
    );
    final rec = await pumpGrid(
      tester,
      byDay: {
        0: [toplanti],
      },
    );

    expect(find.text('Oda 3'), findsNothing);

    await tester.tap(find.text('Toplantı'));
    await tester.pumpAndSettle();

    // Bir işe *bakmak*, onu değiştirmekten çok daha sık. Tık artık ekranı
    // kaplayan sheet'i açmıyor; hafta arkada durmaya devam ediyor.
    expect(rec.tapped, isNull, reason: 'tık doğrudan düzenleyici açmamalı');
    expect(find.text('Oda 3'), findsOneWidget);
    expect(find.text('Düzenle'), findsOneWidget);

    await tester.tap(find.text('Düzenle'));
    await tester.pumpAndSettle();

    expect(rec.tapped, isNotNull);
    expect(rec.tapped!.$1.title, 'Toplantı');
    expect(rec.tapped!.$2, monday);
  });

  testWidgets('boş alana dokunmak o gün/saat için ekleme çağırır', (
    tester,
  ) async {
    final rec = await pumpGrid(tester, byDay: const {});

    // Salı sütununun 03:00 hizası. Tuval x=kTimeGutterWidth'ten başlar.
    const columnWidth = (800 - kTimeGutterWidth) / 7;
    await tester.tapAt(
      const Offset(
        kTimeGutterWidth + columnWidth * 1.5, // Salı sütununun ortası
        3 * hourHeight + 6, // 03:00'ın biraz altı
      ),
    );
    await tester.pumpAndSettle();

    expect(rec.emptyTap, isNotNull);
    expect(rec.emptyTap!.$1, monday.add(const Duration(days: 1)));
    // Boş slot dokunuşu 30 dakikaya yuvarlanır.
    expect(rec.emptyTap!.$2, 3.0);
  });

  testWidgets('bloğu sürüklemek gün ve saati değiştirir', (tester) async {
    final rec = await pumpGrid(
      tester,
      byDay: {
        0: [task('Toplantı')], // Pazartesi 01:00
      },
    );

    const columnWidth = (800 - kTimeGutterWidth) / 7;
    await dragBlock(tester, 'Toplantı', const Offset(columnWidth, hourHeight));

    expect(rec.moved, isNotNull, reason: 'sürükleme onMove tetiklemeli');
    expect(rec.moved!.$1.title, 'Toplantı');
    expect(rec.moved!.$2, monday.add(const Duration(days: 1)), reason: 'Salı');
    expect(rec.moved!.$3, closeTo(2.0, 1e-9), reason: '01:00 → 02:00');
  });

  testWidgets('sürükleme 15 dakikalık ızgaraya oturur', (tester) async {
    final rec = await pumpGrid(
      tester,
      byDay: {
        0: [task('Toplantı')],
      },
    );

    // 20 piksel = 20 dakika; en yakın çeyrek saate (15 dk) yuvarlanmalı.
    await dragBlock(tester, 'Toplantı', const Offset(0, 20));

    expect(rec.moved, isNotNull);
    expect(rec.moved!.$3, closeTo(1.25, 1e-9));
  });

  testWidgets('gün sonunu taşan sürükleme geri çekilir', (tester) async {
    final rec = await pumpGrid(
      tester,
      byDay: {
        0: [task('Uzun iş', start: 1.0, duration: 3.0)],
      },
    );

    // Çok aşağı sürükle: 24:00'ı aşmamalı, 21:00'de durmalı (3 saatlik iş).
    await dragBlock(tester, 'Uzun iş', const Offset(0, hourHeight * 40));

    expect(rec.moved, isNotNull);
    expect(rec.moved!.$3, closeTo(21.0, 1e-9));
  });

  testWidgets('yerinde bırakılan blok değişiklik bildirmez', (tester) async {
    final rec = await pumpGrid(
      tester,
      byDay: {
        0: [task('Toplantı')],
      },
    );

    // 3 piksel: 15 dakikalık ızgarada aynı saate yuvarlanır.
    await dragBlock(tester, 'Toplantı', const Offset(0, 3));

    expect(rec.moved, isNull, reason: 'gereksiz mutasyon üretilmemeli');
  });

  testWidgets('alt kenardan çekmek süreyi değiştirir', (tester) async {
    final toplanti = task('Toplantı', start: 2.0, duration: 1.0);
    final rec = await pumpGrid(
      tester,
      byDay: {
        0: [toplanti],
      },
    );

    // Süre tutamağı bloğun alt kenarındaki şerit.
    final handle = await tester.startGesture(
      tester.getCenter(find.byKey(ValueKey('resize-${toplanti.id}'))),
    );
    await handle.moveBy(const Offset(0, hourHeight)); // +1 saat
    await tester.pump();
    await handle.up();
    await tester.pumpAndSettle();

    expect(rec.resized, isNotNull, reason: 'tutamak onResize tetiklemeli');
    expect(rec.resized!.$2, closeTo(2.0, 1e-9), reason: '1 sa → 2 sa');
  });

  testWidgets('tamamlanan blok yalnız renge dayanmaz: ✓ + üstü çizili', (
    tester,
  ) async {
    final bitti = task('Biten iş');
    bitti.setDone(monday, true);

    await pumpGrid(
      tester,
      byDay: {
        0: [bitti],
        1: [task('Süren iş', date: monday.add(const Duration(days: 1)))],
      },
    );

    // WCAG 1.4.1: durum yalnız renkle anlatılamaz. Soluk zemin renk körü bir
    // kullanıcıya hiçbir şey söylemez; ikon ve üstü çizili yazı söyler.
    expect(find.byIcon(Icons.check), findsOneWidget);

    final done = tester.widget<Text>(find.text('Biten iş'));
    final open = tester.widget<Text>(find.text('Süren iş'));
    expect(done.style!.decoration, TextDecoration.lineThrough);
    expect(open.style!.decoration, isNot(TextDecoration.lineThrough));
  });

  testWidgets('kısa blokta kırpılan başlık için tooltip var, uzun blokta yok', (
    tester,
  ) async {
    await pumpGrid(
      tester,
      byDay: {
        // 15 dk: başlık kesin kırpılır. 3 saat: başlık zaten görünür.
        0: [task('Kısa iş', start: 1.0, duration: 0.25)],
        1: [
          task(
            'Uzun iş',
            start: 1.0,
            duration: 3.0,
            date: monday.add(const Duration(days: 1)),
          ),
        ],
      },
    );

    // Tooltip kırpılmayı telafi eder; kırpılma yokken sadece gürültü olurdu.
    expect(find.byType(ShadTooltip), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ShadTooltip),
        matching: find.text('Kısa iş'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('çakışan işler yan yana çizilir ve ikisi de görünür', (
    tester,
  ) async {
    await pumpGrid(
      tester,
      byDay: {
        0: [
          task('Sabah toplantısı', start: 1.0, duration: 2.0),
          task('Kod incelemesi', start: 1.5, duration: 1.5),
        ],
      },
    );

    expect(find.text('Sabah toplantısı'), findsOneWidget);
    expect(find.text('Kod incelemesi'), findsOneWidget);

    // Sütunlara bölündükleri için yatay konumları farklı olmalı.
    final a = tester.getRect(find.text('Sabah toplantısı'));
    final b = tester.getRect(find.text('Kod incelemesi'));
    expect(a.left, lessThan(b.left));
    expect(a.overlaps(b), isFalse, reason: 'bloklar üst üste binmemeli');
    expect(tester.takeException(), isNull);
  });
}

/// Geri çağırımları yakalayan basit kayıt defteri.
class _Recorder {
  (Task, DateTime)? tapped;
  (DateTime, double)? emptyTap;
  (Task, DateTime, double)? moved;
  (Task, double)? resized;
  (Task, DateTime)? duplicated;
  Task? deleted;
}
