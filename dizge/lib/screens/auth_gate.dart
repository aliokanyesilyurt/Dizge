import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_service.dart';
import '../data/app_store.dart';
import '../data/local_store.dart';
import '../data/persistence_providers.dart';
import '../data/sync/first_sync.dart';
import '../data/sync/remote_gateway.dart';
import '../theme.dart';
import '../widgets/brand_mark.dart';
import 'app_shell.dart';
import 'welcome_screen.dart';

/// Uygulamanın kapısı: oturum açılmadan takvime girilmez.
///
/// **Kapı ağa değil, cihazdaki oturuma bakar (G1).** Açılışta sunucuya
/// "bu kullanıcı hâlâ geçerli mi?" diye sorsaydık uygulama uçakta, metroda,
/// internet kesikken açılmazdı — ve `Outbox`'tan `SyncEngine`'e kadar yazılmış
/// bütün offline-first mimarisi anlamsızlaşırdı. Jetonu saklamak, yenilemek ve
/// yeniden açılışta geri yüklemek `supabase_flutter`'ın işi; jeton gerçekten
/// geçersizleşirse [authUserProvider] null'a döner ve kapı kendiliğinden
/// kapanır.
///
/// Bedeli dürüstçe: **ilk** giriş internet ister. Karşılama ekranı bunu
/// söylüyor.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Kaçış valfi (G2). Anahtarsız derlemede kimlik doğrulanamaz; kapıyı
    // kapalı tutmak, `--dart-define` vermeyi unutan her koşumu — geliştirme
    // ve testler dahil — hiç açılmayan bir uygulamaya çevirirdi. Kapı
    // "sunucu varken zorunlu", "sunucu yokken anlamsız".
    if (!ref.watch(authServiceProvider).canAuthenticate) {
      return const AppShell();
    }

    // Dinleyici misafir kipinde de kuruluyor ve oturum misafirlikten **önce**
    // okunuyor. Eskiden misafir dalı buradan önce dönüyordu; `guest_mode`
    // yerel depoda kalıcı olduğu için bir kez "misafir olarak devam et" diyen
    // cihaz bir daha oturuma hiç bakmıyordu. Google girişi sunucuda
    // tamamlanıyor, uygulama misafir kabuğunda kalıyordu — kullanıcının
    // "hâlâ giremiyorum" dediği hata buydu.
    _listenForLogin(context, ref);

    final auth = ref.watch(authUserProvider);
    final isGuest = ref.watch(guestModeProvider);

    // Karar A: **gerçek oturum misafir kipini yener.** Misafirlik bir tercih
    // değil, oturum yokken verilen bir izin; oturum açıldığı anda konusu
    // kalmıyor. Bayrağın kendisini de giriş anında dinleyici siliyor.
    final child = switch (auth) {
      // Jeton güvenli kasadan geri yüklenirken bir kare "Hoş geldin" gösterip
      // sonra takvime atlamak, her açılışta bir yanıp sönme olurdu.
      AsyncLoading() => const _Splash(),

      // Oturum akışı düşerse içeride sayılmak yanlış taraf: kapı kapanır.
      // Misafir bunun dışında — o zaten oturuma dayanmıyor, akış düştü diye
      // onu dışarı atmak sebepsiz bir ceza olurdu.
      AsyncError() => isGuest ? const AppShell() : const WelcomeScreen(),

      AsyncValue(:final value) =>
        value != null || isGuest ? const AppShell() : const WelcomeScreen(),
    };

    return AnimatedSwitcher(
      duration: Motion.slow,
      switchInCurve: Motion.curve,
      switchOutCurve: Curves.easeIn,
      child: KeyedSubtree(
        // Anahtar ekranın **türü**: aynı türde kalan geçişler (ör. hata
        // metninin değişmesi) yeniden animasyon tetiklemesin.
        key: ValueKey(child.runtimeType),
        child: child,
      ),
    );
  }

  /// İlk senkronu yalnızca **gerçek bir girişte** tetikler.
  ///
  /// Buradaki ayrım planın en kolay kaçırılan yeri (B4): "kullanıcı var" ile
  /// "kullanıcı az önce giriş yaptı" aynı şey değil. Uygulama açılışında
  /// kayıtlı bir oturum geri yüklendiğinde de değer null'dan kullanıcıya
  /// geçer — ama orada tam çekim yapmak felaket olurdu: artımlı çekim
  /// yazılmadığı için `loadJson` yerel durumu yıkıp yeniden kurar ve son
  /// açılıştan beri çevrimdışı yapılmış her değişiklik silinirdi.
  ///
  /// Ayrımı `previous.hasValue` veriyor: açılışta önceki durum
  /// [AsyncLoading]'dir ve değeri yoktur. Çıkış → giriş yolunda ise önceki
  /// durum "değeri null olan" bir [AsyncData]'dır. Yalnız ikincisi giriştir.
  void _listenForLogin(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<AuthUser?>>(authUserProvider, (previous, next) {
      final wasSignedOut =
          previous != null && previous.hasValue && previous.value == null;
      final nowSignedIn = next.hasValue && next.value != null;

      if (!nowSignedIn) return;

      // "Bu cihazda bir kez girildi" (T3a). Girişin türünden bağımsız: kayıtla
      // da olsa, geri yüklenen bir oturumla da olsa artık yeni kullanıcı
      // değiliz ve karşılama ekranı bir dahaki sefere giriş kipinde açılmalı.
      unawaited(
        ref.read(localStoreProvider).writeString(kHasSignedInKey, 'yes'),
      );

      // Misafirlik bitti (Karar A). Bayrağı burada silmek şart: yalnız kapıda
      // "oturum misafiri yener" demek ekranı düzeltirdi ama bayrak diskte
      // kalır, kullanıcı çıkış yaptığında hiç istemediği hâlde yine misafir
      // olarak içeride uyanırdı.
      if (ref.read(guestModeProvider)) {
        unawaited(ref.read(guestModeProvider.notifier).leaveGuestMode());
      }

      if (wasSignedOut) {
        unawaited(_runFirstSync(context, ref));
      }
    });
  }
}

/// Oturum açıldıktan sonra yerel takvim ile sunucuyu buluşturur.
///
/// Karşılama ekranından değil buradan çağrılıyor: sorulacak bir soru varsa
/// (iki tarafta da veri) onun yeri bir giriş formunun üstü değil.
Future<void> _runFirstSync(BuildContext context, WidgetRef ref) async {
  final coordinator = FirstSyncCoordinator(
    gateway: ref.read(remoteGatewayProvider),
    store: ref.read(appStoreProvider),
    outbox: ref.read(outboxProvider),
  );
  final engine = ref.read(syncEngineProvider);

  FirstSyncDecision decision;
  try {
    decision = await coordinator.inspect();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hesabındaki planlar okunamadı. Daha sonra denenecek.'),
        ),
      );
    }
    return;
  }

  var plan = decision.plan;

  if (plan == FirstSyncPlan.ask) {
    if (!context.mounted) return;
    final chosen = await _askWhichWins(context, ref);
    if (chosen == null) return; // Kullanıcı vazgeçti; hiçbir şey değişmez.
    plan = chosen;
  }

  await coordinator.apply(plan, remote: decision.remote);

  // Motoru dürt: oturum açılana kadar kuyruk bekliyordu.
  await engine?.syncNow();
}

/// İki tarafta da veri varken sorulan tek soru.
///
/// Varsayılan yok ve kapatmak "vazgeç" demek: yanlış tıklanan bir düğme
/// aylardır biriken bir takvimi silebilir.
Future<FirstSyncPlan?> _askWhichWins(BuildContext context, WidgetRef ref) {
  final store = ref.read(appStoreProvider);
  final localCount =
      store.tasks.length + store.notes.length + store.habits.length;

  return showDialog<FirstSyncPlan>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Hangisi kalsın?'),
      content: Text(
        'Bu cihazda $localCount kayıt var, hesabında da planların duruyor. '
        'İkisini birleştiremiyoruz — hangisinin kalacağını seçmen gerek.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Vazgeç'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(FirstSyncPlan.download),
          child: const Text('Hesaptakiler'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(FirstSyncPlan.upload),
          child: const Text('Bu cihazdakiler'),
        ),
      ],
    ),
  );
}

/// Oturum okunurken görünen ara kare.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: I.hero),
            const SizedBox(height: S.xl),
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: c.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Misafir kipinin yerel depodaki anahtarları.
///
/// Üçü de burada duruyor çünkü misafirliğin sahibi kapı. Dizeler koda dağılmış
/// olsaydı (`'guest_mode'` bir dosyada, `'guest_name'` başka bir dosyada) bir
/// harf farkı sessizce ikinci bir misafir yaratırdı — hata vermeyen, yalnız
/// adı unutan bir kusur.
const String kGuestModeKey = 'guest_mode';
const String kGuestNameKey = 'guest_name';
const String kGuestColorKey = 'guest_color';

/// "Bu cihazda hesapsız devam ediliyor."
///
/// Kalıcı: misafir uygulamayı kapatıp açtığında yine takvimine düşmeli, her
/// açılışta aynı kararı yeniden vermeye zorlanmamalı. Kalıcı olduğu için de
/// kapının onu **oturumun altında** okuması gerekiyor (Karar A) — yoksa bayrak
/// bir kere yazıldıktan sonra girişi sonsuza dek yutar.
final guestModeProvider = StateNotifierProvider<GuestModeNotifier, bool>((ref) {
  return GuestModeNotifier(ref.watch(localStoreProvider));
});

/// Misafirin kim olduğu ayrı bir soru ve cevabı `guestProfileProvider`'da.
class GuestModeNotifier extends StateNotifier<bool> {
  GuestModeNotifier(this._store)
    : super(_store.readString(kGuestModeKey) == 'yes');

  final LocalStore _store;

  Future<void> enterGuestMode() async {
    state = true;
    await _store.writeString(kGuestModeKey, 'yes');
  }

  Future<void> leaveGuestMode() async {
    state = false;
    await _store.writeString(kGuestModeKey, 'no');
  }
}
