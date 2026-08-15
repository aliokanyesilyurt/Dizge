import 'package:dizge/core/telemetry.dart';
import 'package:dizge/data/local_store.dart';
import 'package:dizge/screens/account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('rıza geçidi', () {
    test('kapalıyken hiçbir olay içeriye ulaşmaz', () {
      final inner = RecordingTelemetry();
      final gate = ConsentGate(inner);

      gate.capture('week_changed');
      gate.screen('week');

      expect(inner.events, isEmpty);
      expect(inner.screens, isEmpty);
    });

    test('varsayılan kapalı — cevaplanmamış soru "evet" sayılmaz', () {
      expect(ConsentGate(RecordingTelemetry()).enabled, isFalse);
    });

    test('açıldığında olaylar geçer', () async {
      final inner = RecordingTelemetry();
      final gate = ConsentGate(inner);

      await gate.setEnabled(true);
      gate.capture('week_changed');
      gate.screen('week');

      expect(inner.events, ['week_changed']);
      expect(inner.screens, ['week']);
    });

    test('kapatmak kimliği de siler', () async {
      // Kapatmak yalnız "bundan sonra gönderme" demek değil; sunucudaki
      // profille bağı da koparmalı, yoksa rıza geri çekilmiş sayılmaz.
      final inner = RecordingTelemetry();
      final gate = ConsentGate(inner, enabled: true);

      await gate.setEnabled(false);

      expect(inner.resetCount, 1);
    });

    test('geçmiş olaylar biriktirilip sonradan gönderilmez', () async {
      // Sessiz izleme yok: kapalıyken olan olaylar kaybolur, açılınca
      // geri dönmez.
      final inner = RecordingTelemetry();
      final gate = ConsentGate(inner);

      gate.capture('kapaliyken');
      await gate.setEnabled(true);

      expect(inner.events, isEmpty);
    });

    test('tercih değişince kalıcılaştırma çağrılır', () async {
      final yazilanlar = <bool>[];
      final gate = ConsentGate(
        RecordingTelemetry(),
        onPersist: (v) async => yazilanlar.add(v),
      );

      await gate.setEnabled(true);
      await gate.setEnabled(false);
      // Aynı değeri ikinci kez yazmak gereksiz iş.
      await gate.setEnabled(false);

      expect(yazilanlar, [true, false]);
    });
  });

  group('rıza kalıcılığı', () {
    test('açık bırakılan tercih sonraki açılışta geri okunur', () async {
      // T4'ün ikinci kusuru buydu: geçit kurulduğu durumda bile `enabled`
      // yalnız bellekteydi ve uygulama kapanınca rıza sessizce kapanıyordu.
      // Her açılışta sıfırlanan bir onay, onay değildir.
      final disk = InMemoryStore();
      await disk.init();

      final ilkAcilis = ConsentGate(
        RecordingTelemetry(),
        enabled: disk.readString(kTelemetryConsentKey) == 'on',
        onPersist: (v) =>
            disk.writeString(kTelemetryConsentKey, v ? 'on' : 'off'),
      );
      expect(ilkAcilis.enabled, isFalse);

      await ilkAcilis.setEnabled(true);

      final ikinciAcilis = ConsentGate(
        RecordingTelemetry(),
        enabled: disk.readString(kTelemetryConsentKey) == 'on',
      );
      expect(ikinciAcilis.enabled, isTrue);
    });

    test('kapatılan tercih de hatırlanır', () async {
      final disk = InMemoryStore();
      await disk.init();
      await disk.writeString(kTelemetryConsentKey, 'on');

      final gate = ConsentGate(
        RecordingTelemetry(),
        enabled: true,
        onPersist: (v) =>
            disk.writeString(kTelemetryConsentKey, v ? 'on' : 'off'),
      );
      await gate.setEnabled(false);

      expect(disk.readString(kTelemetryConsentKey), 'off');
    });
  });

  group('hesap ekranı anahtarı', () {
    /// Ayarlar listesi uzun ve `ListView` tembel çiziyor.
    void useTallScreen(WidgetTester tester) =>
        useScreenSize(tester, const Size(900, 1800));

    testWidgets('geçit bağlıyken anahtar çevrilebilir', (tester) async {
      // Kusurun kendisi: geçit kurulmadığında `onChanged` null kalıyor ve
      // düğme "bozuk" görünüyordu.
      useTallScreen(tester);
      final gate = ConsentGate(RecordingTelemetry());

      await pumpApp(
        tester,
        const AccountScreen(),
        overrides: [telemetryProvider.overrideWithValue(gate)],
      );

      final anahtar = find.byType(Switch);
      expect(anahtar, findsOneWidget);
      expect(
        tester.widget<Switch>(anahtar).onChanged,
        isNotNull,
        reason: 'anahtar pasif kalmamalı',
      );

      await tester.tap(anahtar);
      await tester.pumpAndSettle();

      expect(gate.enabled, isTrue);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('anahtarı çevirmek tercihi depoya yazar', (tester) async {
      useTallScreen(tester);
      final disk = InMemoryStore();
      await disk.init();

      final gate = ConsentGate(
        RecordingTelemetry(),
        onPersist: (v) =>
            disk.writeString(kTelemetryConsentKey, v ? 'on' : 'off'),
      );

      await pumpApp(
        tester,
        const AccountScreen(),
        overrides: [telemetryProvider.overrideWithValue(gate)],
      );

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(disk.readString(kTelemetryConsentKey), 'on');
    });

    testWidgets('sunucu yapılandırılmamışken bu dürüstçe söylenir', (
      tester,
    ) async {
      // Anahtar çalışıyor ama gidecek bir yer yok. Çalışıyormuş gibi yapan
      // bir anahtar, kapalı bir anahtardan daha kötüdür.
      useTallScreen(tester);

      await pumpApp(
        tester,
        const AccountScreen(),
        overrides: [
          telemetryProvider.overrideWithValue(
            ConsentGate(RecordingTelemetry()),
          ),
        ],
      );

      // Testler `--dart-define` almadan koşuyor: AppConfig.telemetryAvailable
      // false, yani not görünmeli.
      expect(
        find.textContaining('analitik sunucusu yapılandırılmadı'),
        findsOneWidget,
      );
    });
  });
}
