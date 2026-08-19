/// Oturum bölümü: kim açtı, parola değişikliği ve çıkış.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth_service.dart';
import '../../data/app_store.dart';
import '../../data/persistence_providers.dart';
import '../../theme.dart';
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
    if (user == null) return const SizedBox.shrink();

    return Column(
      children: [
        // Kurtarma yolunun son adımı: kodla giren kullanıcı parolasını
        // burada değiştirir. Kodu doğrudan "yeni parola belirle" ekranına
        // bağlamak, oturum açmadan parola değiştirmek olurdu.
        ActionTile(
          icon: Icons.password_rounded,
          iconColor: c.inkDim,
          title: 'Parolanı değiştir',
          subtitle: 'Bu hesabın parolası',
          onTap: () => _changePassword(context, ref),
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

/// Yeni parola sorar ve yazar.
///
/// Eski parola sorulmuyor: oturum zaten açık ve sağlayıcı onu istemiyor.
/// İstemek, kurtarma yolundan gelen kullanıcıyı — yani parolasını **bilmeyen**
/// kişiyi — kapıda bırakırdı.
Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final auth = ref.read(authServiceProvider);
  final messenger = ScaffoldMessenger.of(context);

  final password = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Parolanı değiştir'),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: true,
        decoration: const InputDecoration(hintText: 'Yeni parola'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Kaydet'),
        ),
      ],
    ),
  );
  controller.dispose();

  if (password == null) return;
  if (password.length < 6) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Parola en az 6 karakter olmalı.')),
    );
    return;
  }

  try {
    await auth.updatePassword(password);
    messenger.showSnackBar(
      const SnackBar(content: Text('Parolan değiştirildi.')),
    );
  } on AuthFailure catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
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
Future<void> _signOut(BuildContext context, WidgetRef ref) async {
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
          'Şimdi çıkarsan bu cihazdan silinecekler ve geri gelmeyecekler.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Yine de çık',
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
}
