import 'dart:io';

import 'package:dizge/models/task.dart';
import 'package:dizge/screens/section_header.dart';
import 'package:dizge/screens/task_list_scaffold.dart';
import 'package:dizge/theme.dart';
import 'package:dizge/widgets/content_column.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Düzen kuralları: hizalama ve okuma genişliği.
///
/// Bu testlerin varlık sebebi, depoda golden test olmaması. Renk ve kontrast
/// kuralları `theme_test.dart`'ta bekçilenmiş durumda; **ölçü** tarafında ise
/// bir kayma gözle görülene kadar sessiz kalıyordu. Buradaki iki kural o
/// sessizliği kapatıyor.
void main() {
  Widget scaffoldWith(List<Task> tasks) => TaskListScaffold(
    title: 'Yapılacaklar',
    subtitle: '${tasks.length} iş',
    emptyIcon: Icons.check_circle_outline_rounded,
    emptyText: 'Boş',
    tasks: tasks,
    trailingTextFor: (_) => '',
    onTap: (_) {},
    onAdd: () {},
  );

  Task sampleTask() =>
      Task(title: 'Rapor yaz', color: Colors.blue, date: DateTime(2026, 8, 15));

  group('hizalama', () {
    testWidgets('başlık ile liste aynı kenardan başlar', (tester) async {
      // Eskiden `SectionHeader` soldan 24, listeler 20 kullanıyordu. Dört
      // piksel tek ekranda fark edilmiyor; sekme değiştirildiğinde başlığın
      // yatayda zıplaması olarak okunuyordu.
      await pumpApp(tester, scaffoldWith([sampleTask()]));

      final headerPadding = tester
          .widgetList<Padding>(
            find.descendant(
              of: find.byType(SectionHeader),
              matching: find.byType(Padding),
            ),
          )
          .first
          .padding
          .resolve(TextDirection.ltr);

      final listPadding = tester
          .widget<ListView>(find.byType(ListView))
          .padding!
          .resolve(TextDirection.ltr);

      expect(headerPadding.left, S.gutter);
      expect(headerPadding.right, S.gutter);
      expect(listPadding.left, headerPadding.left);
      expect(listPadding.right, headerPadding.right);
    });
  });

  group('tipografi göçü', () {
    /// `lib/` altındaki her Dart dosyası, yoluyla birlikte.
    Iterable<({String path, String source})> libSources() sync* {
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        yield (
          path: entity.path.replaceAll(r'\', '/'),
          source: entity.readAsStringSync(),
        );
      }
    }

    test('hiçbir yerde elle yazılmış yazı boyu kalmadı', () {
      // Ölçeğin tek gerçek koruması bu: bir dosyada `fontSize: 13.5` yazmak
      // serbest kaldığı sürece ölçek bir öneriden ibaret olur.
      final offenders = <String>[];

      for (final file in libSources()) {
        for (final match in RegExp(
          r'fontSize: [0-9]',
        ).allMatches(file.source)) {
          offenders.add('${file.path} (${match.group(0)}…)');
        }
      }

      expect(offenders, isEmpty, reason: 'ölçek dışı yazı boyu');
    });

    test('simge boyları ölçekten okunur', () {
      // İkon, avatar ve marka işareti aynı şey: yazının yanında duran kare bir
      // kutu. On altı ayrı boy vardı ve aralarındaki fark hiçbir yerde bir
      // anlam taşımıyordu — yalnız iki ikonu yan yana koyunca eşitsizlik
      // görülüyordu.
      final offenders = [
        for (final file in libSources())
          if (RegExp(r'(?<![\w.])size: [0-9]').hasMatch(file.source)) file.path,
      ];

      expect(offenders, isEmpty, reason: 'ölçek dışı simge boyu');
    });

    test('T.dense yalnız yoğun yüzeylerde kullanılır', () {
      // `dense` ölçeğin en küçük kademesi ve bir **istisna**: metnin sabit
      // boyutlu bir hücreye sığmak zorunda olduğu takvim/grafik yüzeyleri.
      // Sıradan bir ekranda kullanılırsa okunabilirlik sessizce düşer.
      const allowed = {
        'lib/widgets/week_time_grid.dart',
        // Izgaranın kendisi; M1'de aynı yüzey dosyalara bölündü.
        'lib/widgets/week_grid/event_block.dart',
        'lib/widgets/week_grid/grid_chrome.dart',
        'lib/widgets/habit_heatmap.dart',
        'lib/widgets/day_pie_chart.dart',
        'lib/widgets/report_charts.dart',
        'lib/screens/monthly_view_screen.dart',
        'lib/screens/year_view_screen.dart',
        'lib/screens/week/daily_habit_strip.dart',
        'lib/screens/week/pool_panel.dart',
        'lib/screens/week_view_screen.dart',
        // Aynı hafta yüzeyi; M4'te dosyalara bölündü.
        'lib/screens/week/day_headers.dart',
        'lib/screens/week/untimed_row.dart',
        // Kademenin tanımlandığı yer.
        'lib/theme.dart',
      };

      final offenders = [
        for (final file in libSources())
          if (file.source.contains('T.dense') && !allowed.contains(file.path))
            file.path,
      ];

      expect(offenders, isEmpty, reason: 'yoğun kademe yoğun olmayan yüzeyde');
    });
  });

  group('boşluk göçü', () {
    test('ara vericiler ve kenar boşlukları ölçekten okunur', () {
      // Ölçeğin ikinci yarısı. Yazı boyu gibi burada da tek koruma, elle
      // sayı yazmanın imkânsız hâle gelmesi: bir dosyada `SizedBox(height: 11)`
      // serbest kaldığı sürece dikey ritim yeniden dağılır.
      //
      // İki kalıp denetleniyor:
      //   * çocuksuz `SizedBox` — saf ara verici (çocuklu olan bir **ölçü**dür,
      //     boşluk değil, ve ölçeğe girmesi gerekmez),
      //   * iç içe parantez içermeyen `EdgeInsets.*` çağrıları (hesaplı
      //     olanlar — `MediaQuery.viewInsetsOf(context).bottom` gibi — zaten
      //     bir sayı yazmıyor).
      //
      // `0` serbest: sıfır bir kademe değil, boşluğun yokluğu.
      // Kapanan parantez desenin parçası: yalnız **çocuksuz** biçim yakalanır.
      // `SizedBox(width: 3, child: ColoredBox(...))` bir renk şeridinin
      // kalınlığıdır — ölçü, boşluk değil.
      final spacer = RegExp(r'SizedBox\((?:height|width): [0-9.]+\)');
      final inset = RegExp(r'EdgeInsets\.\w+\(([^()]*)\)', dotAll: true);
      final rawNumber = RegExp(r'(?<![\w.])[1-9][0-9]*(\.[0-9]+)?(?![\w.])');

      final offenders = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        final source = entity.readAsStringSync();

        if (spacer.hasMatch(source)) {
          offenders.add('$path — elle yazılmış ara verici');
        }
        for (final match in inset.allMatches(source)) {
          if (rawNumber.hasMatch(match.group(1)!)) {
            offenders.add('$path — ${match.group(0)}');
          }
        }
      }

      expect(offenders, isEmpty, reason: 'ölçek dışı boşluk');
    });
  });

  group('okuma genişliği', () {
    testWidgets('geniş pencerede içerik sütunda durur', (tester) async {
      // 1600 piksellik bir pencerede satır, gözün sonundan başına dönemeyeceği
      // kadar uzuyordu: solda renk vuruşu, sağda tarih, arada 1400 piksel boş.
      useScreenSize(tester, const Size(1600, 900));
      await pumpApp(tester, scaffoldWith([sampleTask()]));

      expect(
        tester.getSize(find.byType(ListView)).width,
        ContentColumn.maxWidth,
      );
    });

    testWidgets('dar pencerede sınır devreye girmez', (tester) async {
      // Sınırın üst sınır olduğunun kanıtı: 600'de içerik daralmıyor, pencere
      // ne veriyorsa onu alıyor.
      useScreenSize(tester, const Size(600, 900));
      await pumpApp(tester, scaffoldWith([sampleTask()]));

      expect(tester.getSize(find.byType(ListView)).width, 600);
    });

    testWidgets('başlık da aynı sütunda kalır', (tester) async {
      // Yalnız liste sınırlansaydı başlık tam genişlikte kalır ve hizalama
      // geri bozulurdu — sarmal ikisini birden içine alıyor.
      useScreenSize(tester, const Size(1600, 900));
      await pumpApp(tester, scaffoldWith([sampleTask()]));

      expect(
        tester.getTopLeft(find.byType(SectionHeader)).dx,
        tester.getTopLeft(find.byType(ListView)).dx,
      );
    });
  });
}
