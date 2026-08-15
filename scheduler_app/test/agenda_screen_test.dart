import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/core/usage_mode_controller.dart';
import 'package:scheduler_app/data/app_store.dart';
import 'package:scheduler_app/data/local_store.dart';
import 'package:scheduler_app/data/persistence_providers.dart';
import 'package:scheduler_app/models/task.dart';
import 'package:scheduler_app/screens/agenda_screen.dart';
import 'package:scheduler_app/screens/app_shell.dart';
import 'package:scheduler_app/widgets/ink_canvas.dart';

import 'helpers.dart';

/// A4 — ajanda yüzeyi.
void main() {
  // Görevlerin tek gerçek kaynağı hâlâ statik `TaskRepository`; testler
  // arasında sızmasın diye deponun yerleşik kalıbı burada da uygulanıyor.
  setUp(TaskRepository.all.clear);

  /// Tuvalin ortasında kısa bir çizgi çizer — bir vuruş.
  Future<void> write(WidgetTester tester, {Offset from = Offset.zero}) async {
    final canvas = find.byType(InkCanvas);
    final origin = tester.getCenter(canvas) + from;

    final gesture = await tester.startGesture(origin);
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(const Offset(20, 10));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('yazma', () {
    testWidgets('çizilen vuruş sayfaya yazılır', (tester) async {
      final container = await pumpApp(tester, const AgendaScreen());
      final store = container.read(appStoreProvider);

      expect(store.agendaPage(DateTime.now()).isEmpty, isTrue);

      await write(tester);

      expect(store.agendaPage(DateTime.now()).strokes, hasLength(1));
    });

    testWidgets('geri al son vuruşu kaldırır', (tester) async {
      final container = await pumpApp(tester, const AgendaScreen());
      final store = container.read(appStoreProvider);

      await write(tester);
      await write(tester, from: const Offset(0, 40));
      expect(store.agendaPage(DateTime.now()).strokes, hasLength(2));

      await tester.tap(find.byTooltip('Geri al'));
      await tester.pumpAndSettle();

      expect(store.agendaPage(DateTime.now()).strokes, hasLength(1));
    });

    testWidgets('yazılan sayfa uygulama yeniden açıldığında yerinde', (
      tester,
    ) async {
      // A4'ün ölçütü: sayfayı yaz, kapat, tekrar aç — aynı görünüyor.
      final disk = InMemoryStore();
      final store = AppStore();
      await store.attachPersistence(disk);

      await pumpApp(
        tester,
        const AgendaScreen(),
        overrides: [appStoreProvider.overrideWith((ref) => store)],
      );
      await write(tester);
      await store.flush();

      final reopened = AppStore();
      await reopened.attachPersistence(disk);
      addTearDown(reopened.dispose);

      expect(reopened.agendaPage(DateTime.now()).strokes, hasLength(1));
    });
  });

  group('gün gezinmesi', () {
    testWidgets('başka güne geçince sayfa boşalır, geri dönünce geri gelir', (
      tester,
    ) async {
      final container = await pumpApp(tester, const AgendaScreen());
      final store = container.read(appStoreProvider);

      await write(tester);
      expect(store.agendaPage(DateTime.now()).strokes, hasLength(1));

      await tester.tap(find.byTooltip('Sonraki gün'));
      await tester.pumpAndSettle();

      // Yarının sayfası boş — dünün yazısı oraya taşınmadı.
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      expect(store.agendaPage(tomorrow).isEmpty, isTrue);

      await tester.tap(find.byTooltip('Önceki gün'));
      await tester.pumpAndSettle();

      expect(store.agendaPage(DateTime.now()).strokes, hasLength(1));
    });
  });

  group('kullanım modu sekmeyi yönetir', () {
    Future<void> pumpShell(WidgetTester tester, UsageMode mode) async {
      final store = InMemoryStore();
      await store.writeString(kUsageModeKey, UsageModeController.encode(mode));

      useScreenSize(tester, const Size(1400, 900));
      await pumpApp(
        tester,
        const AppShell(),
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
    }

    testWidgets('klasik modda ajanda sekmesi çizilmez', (tester) async {
      await pumpShell(tester, UsageMode.klasik);
      expect(find.text('Ajanda'), findsNothing);
    });

    testWidgets('ajanda ve karma modda sekme görünür', (tester) async {
      await pumpShell(tester, UsageMode.ajanda);
      expect(find.text('Ajanda'), findsOneWidget);

      await pumpShell(tester, UsageMode.karma);
      expect(find.text('Ajanda'), findsOneWidget);
    });
  });
}
