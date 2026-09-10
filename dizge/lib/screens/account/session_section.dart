/// Oturum bölümü: kim açtı, parola değişikliği ve çıkış.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth_service.dart';
import '../../data/app_store.dart';
import '../../data/persistence_providers.dart';
import '../../theme.dart';
import '../auth_gate.dart';
import '../password_screens.dart';
import 'account_tiles.dart';

/// Oturum bilgisi ve çıkış.
///
/// "Oturum aç" satırı buradan kalktı: kapı geldiğinden beri bu ekrana yalnız
/// oturum açmış biri ulaşabiliyor (`AuthGate`). Bulunmadığın bir yerin giriş
/// düğmesini göstermek, kullanıcıya cevabını zaten bildiği bir soruyu sormaktı.
class AccountSection extends ConsumerWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final user = ref.watch(authUserProvider).valueOrNull;

    // Anahtarsız (yerel) derlemede kapı açık kalıyor (G2) ve oturum kavramı
    // hiç yok; bu bölümün gösterecek bir şeyi de yok.
    if (user == null) {
      if (ref.watch(guestModeProvider)) {
        return Column(
          children: [
            ActionTile(
              icon: Icons.login_rounded,
              iconColor: c.inkDim,
              title: 'Oturum aç',
              subtitle: 'Bulut eşitleme ve grupları kullan',
              onTap: () async {
                await ref.read(guestModeProvider.notifier).leaveGuestMode();
              },
            ),
          ],
        );
      }
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        // Ayrı sayfa (P4): mevcut parola ya da e-postaya giden kodla
        // doğrulama, yeni parola + tekrar, kural listesi.
        ActionTile(
          icon: Icons.password_rounded,
          iconColor: c.inkDim,
          title: user.hasPassword ? 'Parolanı değiştir' : 'Parola belirle',
          subtitle: user.hasPassword
              ? 'Mevcut parolanla ya da e-postana gelen kodla'
              : 'Google hesabına bir de e-posta parolası ekle',
          onTap: () => showChangePasswordScreen(context),
        ),
        // "Hesap değiştir" ayrı bir mekanizma değil, çıkışın kısayolu
        // (Karar B). Hive kutusu tek ve kullanıcıdan bağımsız; iki hesabın
        // verisini aynı anda cihazda tutmanın yolu yok, dolayısıyla çıkmadan
        // geçiş de yok. Ayrı bir satır olması yine de değerli: kullanıcı
        // aradığı şeye "çıkış" demiyor, "hesap değiştir" diyor.
        //
        // Bedeli gizlenmiyor — alt metin çıkıştakiyle aynı şeyi söylüyor.
        ActionTile(
          icon: Icons.switch_account_rounded,
          iconColor: c.inkDim,
          title: 'Hesap değiştir',
          subtitle: 'Çıkıp başka hesapla gir — bu cihazdaki planlar silinir',
          onTap: () => _signOut(context, ref, switchAccount: true),
        ),
        ActionTile(
          icon: Icons.logout_rounded,
          iconColor: c.inkDim,
          title: 'Çıkış yap',
          // Kullanıcının bu düğmeye basarken en çok merak ettiği şey bu; cevabı
          // düğmenin yanında duruyor. Eskiden "planların silinmez" yazıyordu —
          // kapı geldiğinden beri doğru değil.
          subtitle: 'Bu cihazdaki planlar da silinir',
          onTap: () => _signOut(context, ref),
        ),
      ],
    );
  }
}

/// Çıkış: önce yükle, sonra sil.
///
/// Kapıdan önce çıkış yerel veriye dokunmuyordu ve o doğru karardı — çıkmak
/// "senkronu kapat" demekti, cihazdaki takvim kullanıcınındı. Kapı bunu
/// değiştirdi: aynı cihazda ikinci bir kişi giriş yaparsa öncekinin bütün
/// takvimini görür, çünkü Hive kutusu tek ve kullanıcıdan bağımsız. Bu açığı
/// kapının kendisi yarattı; kapatmak da onun borcu.
///
/// Sıra bilinçli. **Gönderilmemiş değişiklik varken silmek veri kaybıdır**:
/// önce kuyruk boşaltılmaya çalışılır, boşalmıyorsa kullanıcı ne kaybedeceğini
/// bilerek karar verir. Oturum kapatma başarısız olursa (ağ yok) hiçbir şey
/// silinmez — yarım kalmış bir çıkış, kullanıcıyı hem içeride hem verisiz
/// bırakırdı.
Future<void> _signOut(
  BuildContext context,
  WidgetRef ref, {
  bool switchAccount = false,
}) async {
  // Kapı, oturum kapanır kapanmaz bu ekranı ağaçtan söküyor. Sökülmüş bir
  // widget'ın `ref`'inden okumak hata; ihtiyacımız olan her şey şimdi alınır.
  final outbox = ref.read(outboxProvider);
  final engine = ref.read(syncEngineProvider);
  final auth = ref.read(authServiceProvider);
  final localStore = ref.read(localStoreProvider);
  final appStore = ref.read(appStoreProvider);
  final messenger = ScaffoldMessenger.of(context);

  if (!outbox.isEmpty) {
    await engine?.syncNow();
  }

  if (!outbox.isEmpty) {
    if (!context.mounted) return;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yüklenmemiş değişiklikler var'),
        content: Text(
          '${outbox.length} değişiklik henüz hesabına gönderilemedi. '
          '${switchAccount ? 'Şimdi hesap değiştirirsen' : 'Şimdi çıkarsan'} '
          'bu cihazdan silinecekler ve geri gelmeyecekler.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              switchAccount ? 'Yine de değiştir' : 'Yine de çık',
              style: TextStyle(color: ctx.colors.danger),
            ),
          ),
        ],
      ),
    );
    if (proceed != true) return;
  }

  try {
    await auth.signOut();
  } on AuthFailure catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  }

  await outbox.clear();
  await localStore.wipe();
  appStore.loadJson(const {});

  // `wipe()` her şeyi siliyor — `kHasSignedInKey` dahil. O bayrak olmadan
  // karşılama ekranı bu cihazı "ilk kez açılıyor" sanıp **kayıt** kipinde
  // açılır: az önce çıkmış ya da hesap değiştirmek isteyen kullanıcının
  // önüne yeni hesap formu gelirdi. Bayrak bir sır değil, bir cihaz
  // gerçeği; silinmesi gereken veri değil.
  await localStore.writeString(kHasSignedInKey, 'yes');

  // Misafirlik de sıfırlanıyor: bayrak `wipe()` ile zaten gitti ama bellekteki
  // durum kalıyordu ve kapı çıkıştan sonra takvimi misafir olarak açardı.
  await ref.read(guestModeProvider.notifier).leaveGuestMode();
}
