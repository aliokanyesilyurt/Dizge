import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/models/task.dart';
import 'package:scheduler_app/screens/section_header.dart';
import 'package:scheduler_app/screens/task_list_scaffold.dart';
import 'package:scheduler_app/theme.dart';

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
}
