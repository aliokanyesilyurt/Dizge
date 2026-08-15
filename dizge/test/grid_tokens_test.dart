import 'package:dizge/core/time_grid.dart';
import 'package:dizge/theme.dart';
import 'package:dizge/widgets/week_time_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Izgaranın **görsel sözleşmesi**: saat sütunu okunuyor mu, çizgi hiyerarşisi
/// doğru sırada mı, iki temada da ayakta mı?
///
/// Jetonu değil widget'ın gerçekten çizdiği rengi ölçüyor: biri `_HourGutter`
/// içindeki stili değiştirirse palet jetonu doğru kalsa bile test düşmeli.
void main() {
  final themes = [
    ('açık tema', AppPalette.light, Brightness.light),
    ('koyu tema', AppPalette.dark, Brightness.dark),
  ];

  group('saat sütunu', () {
    for (final (name, palette, brightness) in themes) {
      testWidgets('$name: saat etiketi 4.5:1 kontrastı geçer', (tester) async {
        useScreenSize(tester, const Size(1000, 800));

        await tester.pumpWidget(
          testApp(
            brightness: brightness,
            home: Scaffold(
              // Izgara gerçek uygulamada kendi yaprağına çizilir; kontrast da
              // sayfa zeminine değil bu yüzeye göre ölçülmeli.
              backgroundColor: palette.surface,
              body: WeekTimeGrid(
                monday: DateTime(2026, 7, 20),
                tasksByDay: List.generate(7, (_) => const []),
                metrics: const GridMetrics(hourHeight: 60),
                today: DateTime(2026, 7, 20),
                onTapTask: (task, day) {},
                onTapEmpty: (day, hour) {},
                onMove: (task, day, hour) {},
                onResize: (task, duration) {},
                onDuplicate: (task, day) {},
                onDelete: (task) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final label = tester.widget<Text>(find.text('09:00'));
        final color = label.style!.color!;

        // 10.5px "büyük yazı" sayılmaz; WCAG AA eşiği 3:1 değil 4.5:1.
        // Saat sütunu dekorasyon da değil — saati oradan okuyorsun.
        expect(
          contrastRatio(color, palette.surface),
          greaterThanOrEqualTo(4.5),
          reason: '$name saat etiketi okunmuyor',
        );
      });
    }
  });

  group('ızgara çizgileri', () {
    for (final (name, p, _) in themes) {
      test('$name: hiyerarşi saat > gün ayracı > yarım saat', () {
        double vs(Color line) => contrastRatio(line, p.gridDay);

        // Sıralama bilinçli: gün sınırı yarım saat tikinden daha güçlü bir
        // ayrım. Tersi olsaydı alt bölme, ana bölmeden baskın çıkardı.
        expect(vs(p.gridHourLine), greaterThan(vs(p.gridColumnLine)));
        expect(vs(p.gridColumnLine), greaterThan(vs(p.gridHalfLine)));
      });

      test('$name: her çizgi görünür ama hiçbiri bağırmıyor', () {
        for (final (label, line) in [
          ('saat', p.gridHourLine),
          ('gün ayracı', p.gridColumnLine),
          ('yarım saat', p.gridHalfLine),
        ]) {
          final ratio = contrastRatio(line, p.gridDay);
          // Alt sınır: zeminden ayrışmayan çizgi hiç çizilmemiş demektir.
          expect(ratio, greaterThan(1.02), reason: '$name $label görünmüyor');
          // Üst sınır: ızgara kafes değil zemin. Çizgi öne çıkarsa bloklar
          // arkada kalır (plan §4 — "ayrım gölgeyle değil çizgiyle", hafif).
          expect(ratio, lessThan(1.6), reason: '$name $label fazla baskın');
        }
      });
    }
  });
}
