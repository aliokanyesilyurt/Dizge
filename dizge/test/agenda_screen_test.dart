import 'package:dizge/core/navigation_controller.dart';
import 'package:dizge/core/usage_mode_controller.dart';
import 'package:dizge/data/app_store.dart';
import 'package:dizge/data/local_store.dart';
import 'package:dizge/data/persistence_providers.dart';
import 'package:dizge/models/task.dart';
import 'package:dizge/screens/agenda_screen.dart';
import 'package:dizge/screens/app_shell.dart';
import 'package:dizge/widgets/ink_canvas.dart';
import 'package:dizge/widgets/quick_add_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

  group('görev yazma kapısı', () {
    Future<ProviderContainer> pumpGate(
      WidgetTester tester,
      UsageMode mode,
    ) async {
      final store = InMemoryStore();
      await store.writeString(kUsageModeKey, UsageModeController.encode(mode));

      return pumpApp(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showQuickAdd(context, date: DateTime.now()),
                child: const Text('Ekle'),
              ),
            ),
          ),
        ),
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
    }

    testWidgets('ajanda modunda klavye yerine yaprak açılır', (tester) async {
      final container = await pumpGate(tester, UsageMode.ajanda);

      await tester.tap(find.text('Ekle'));
      await tester.pumpAndSettle();

      // Sheet açılmadı; gezinme ajandaya döndü.
      expect(find.byType(QuickAddSheet), findsNothing);
      expect(container.read(navigationProvider).section, AppSection.agenda);
    });

    testWidgets('karma ve klasik modda klavye açılır', (tester) async {
      for (final mode in [UsageMode.karma, UsageMode.klasik]) {
        final container = await pumpGate(tester, mode);

        await tester.tap(find.text('Ekle'));
        await tester.pumpAndSettle();

        expect(find.byType(QuickAddSheet), findsOneWidget, reason: '$mode');
        expect(
          container.read(navigationProvider).section,
          isNot(AppSection.agenda),
          reason: '$mode',
        );

        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      }
    });
  });
}
