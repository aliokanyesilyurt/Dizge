import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_service.dart';
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

    final auth = ref.watch(authUserProvider);

    final child = switch (auth) {
      // Jeton güvenli kasadan geri yüklenirken bir kare "Hoş geldin" gösterip
      // sonra takvime atlamak, her açılışta bir yanıp sönme olurdu.
      AsyncLoading() => const _Splash(),

      // Oturum akışı düşerse içeride sayılmak yanlış taraf: kapı kapanır.
      AsyncError() => const WelcomeScreen(),

      AsyncValue(:final value) =>
        value == null ? const WelcomeScreen() : const AppShell(),
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
            const BrandMark(size: 56),
            const SizedBox(height: 24),
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
