import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_config.dart';
import '../core/auth_service.dart';
import '../core/connectivity.dart';
import '../core/profile_directory.dart';
import '../core/telemetry.dart';
import '../core/theme_mode_controller.dart';
import '../core/usage_mode_controller.dart';
import '../data/app_store.dart';
import '../data/local_store.dart';
import '../data/persistence_providers.dart';
import '../data/sync/supabase_api.dart';
import '../data/sync/sync_engine.dart';
import '../theme.dart';
import '../widgets/user_avatar.dart';

/// Hesap, görünüm, gizlilik ve veri ayarları.
///
/// Oturum açma/kapama, tema tercihi, telemetri rızası, depolama durumu ve
/// "cihazdaki verileri sil" burada gerçekten çalışır. Yalnız bildirimler hâlâ
/// bekliyor ve o satır bilerek sönük duruyor ([_Tile]).
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final store = ref.watch(localStoreProvider);
    final encrypted = store is HiveLocalStore;
    final outbox = ref.watch(outboxProvider);
    final syncState =
        ref.watch(syncStateProvider).valueOrNull ?? SyncState.idle;
    final online = ref.watch(networkStatusProvider).valueOrNull;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // Geniş ekranda satırlar okunmaz uzunlukta gerilmesin.
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.xl, S.xl, S.xl, S.xxl),
              children: [
                const _ProfileHeader(),
                const SizedBox(height: S.lg),
                const _DisplayNameField(),
                const SizedBox(height: S.xl),

                // --- Görünüm ---
                const _GroupLabel('Görünüm'),
                const _ThemeCard(),
                const SizedBox(height: S.md),
                const _UsageModeCard(),
                const SizedBox(height: S.xl),

                // --- Veri ve gizlilik (çalışıyor) ---
                const _GroupLabel('Veri ve gizlilik'),
                _StatusTile(
                  icon: encrypted
                      ? Icons.lock_rounded
                      : Icons.lock_open_rounded,
                  iconColor: encrypted ? c.accent : c.warning,
                  title: encrypted
                      ? 'Veriler şifreli'
                      : 'Şifreleme kullanılamıyor',
                  subtitle: encrypted
                      ? 'Planların AES-256 ile bu cihazda saklanıyor. '
                            'Anahtar cihazın güvenli kasasında; sunucuya gitmiyor.'
                      : 'Cihazın güvenli anahtar deposuna erişilemedi. '
                            'Veriler yalnızca uygulama açıkken bellekte tutuluyor.',
                ),
                _StatusTile(
                  icon: online == NetworkStatus.offline
                      ? Icons.cloud_off_rounded
                      : Icons.cloud_done_rounded,
                  title: _syncTitle(syncState, outbox.length),
                  subtitle:
                      'Uygulama önce cihaza yazar, sonra eşitler. '
                      'İnternet olmadan da tam çalışır.',
                ),
                const _TelemetryTile(),
                const SizedBox(height: S.sm),
                const _DangerZone(),

                const SizedBox(height: S.xl),

                // --- Hesap ---
                const _GroupLabel('Hesap'),
                const _AccountSection(),

                // --- Henüz backend bekleyenler ---
                const SizedBox(height: S.sm),
                const _Notice(),
                const SizedBox(height: S.sm),
                const _Tile(
                  icon: Icons.notifications_rounded,
                  title: 'Bildirimler',
                  subtitle: 'Hatırlatmalar',
                ),

                const SizedBox(height: S.xl),
                Center(
                  child: Text(
                    'Sürüm 1.0.0  ·  ${AppConfig.environment}',
                    style: TextStyle(
                      color: c.inkFaint,
                      fontSize: T.micro,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _syncTitle(SyncState state, int pending) => switch (state) {
    SyncState.idle when pending == 0 => 'Her şey kaydedildi',
    SyncState.idle => '$pending değişiklik bekliyor',
    SyncState.syncing => 'Eşitleniyor…',
    SyncState.waitingForNetwork => '$pending değişiklik bağlantı bekliyor',
    SyncState.failed => 'Eşitleme durdu',
  };
}

class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final user = ref.watch(authUserProvider).valueOrNull;
    final me = ref.watch(profileProvider(user?.id));
    final title = me?.label ?? user?.email ?? 'Misafir';

    return Row(
      children: [
        // Gradyanlı kutu ve jenerik ikon kalktı (Y4.4e): o kutu "bir hesap"
        // diyordu, bu daire "senin hesabın" diyor — grup arkadaşlarının
        // gördüğü rozetin ta kendisi, aynı renk ve aynı harflerle.
        UserAvatar(
          profile: me,
          userId: user?.id,
          size: I.hero,
          showTooltip: false,
        ),
        const SizedBox(width: S.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                // Başlık artık ad; e-posta bir satır aşağı indi. Bu ekranın
                // ilk satırı, kullanıcının başkalarına nasıl göründüğü olmalı.
                title,
                style: Theme.of(context).textTheme.headlineSmall,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: S.xs),
              Text(
                // Ad bilinmiyorsa başlık zaten e-posta oldu; onu bir de altına
                // yazmak aynı şeyi iki kez söylemek olurdu.
                switch ((user, title == user?.email)) {
                  (null, _) => 'Oturum açılmadı — veriler bu cihazda',
                  (final u?, false) => u.email,
                  _ => 'Oturum açık — değişiklikler hesabına eşitleniyor',
                },
                style: TextStyle(
                  color: c.inkFaint,
                  fontSize: T.caption,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Görünen adı değiştirme (Y4.4g).
///
/// Yalnız oturum açıkken görünür: adı olmayan bir hesabın değiştirilecek adı
/// da yok.
///
/// Çevrimdışıyken kaydet düğmesi **pasif** (Y4f'nin aynı gerekçesi): bu bir
/// `Mutation` değil, outbox'a giremez. Sessizce kuyruğa almak, kullanıcıya
/// adının değiştiğini söyleyip karşı tarafta eskisini bırakmak olurdu.
class _DisplayNameField extends ConsumerStatefulWidget {
  const _DisplayNameField();

  @override
  ConsumerState<_DisplayNameField> createState() => _DisplayNameFieldState();
}

class _DisplayNameFieldState extends ConsumerState<_DisplayNameField> {
  final _controller = TextEditingController();
  bool _saving = false;

  /// Denetleyiciye hangi adın yazıldığı. Sunucudan gelen ad değiştiğinde
  /// kutuyu tazelemek gerekiyor ama kullanıcı yazarken **değil** — bu alan
  /// o ikisini ayırıyor.
  String? _seeded;

  static const _maxLength = 40;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save(String userId) async {
    final name = _controller.text.trim();
    final messenger = ScaffoldMessenger.of(context);

    if (name.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Görünen ad boş olamaz.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(profileDirectoryProvider.notifier)
          .updateDisplayName(userId, name);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Adın kaydedildi.')));
    } on RemoteException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Ad kaydedilemedi. Sonra tekrar dene.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = ref.watch(authUserProvider).valueOrNull;
    if (user == null) return const SizedBox.shrink();

    final me = ref.watch(profileProvider(user.id));
    final serverName = me?.displayName ?? '';
    if (_seeded != serverName) {
      _seeded = serverName;
      _controller.text = serverName;
    }

    final online = ref.watch(networkStatusProvider).valueOrNull;
    final offline = online == NetworkStatus.offline;
    final canSave = !_saving && !offline;

    return Container(
      padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: R.radiusMd,
        border: Border.all(color: c.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Görünen ad',
            style: TextStyle(
              color: c.ink,
              fontSize: T.body,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: S.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLength: _maxLength,
                  textInputAction: TextInputAction.done,
                  onSubmitted: canSave ? (_) => _save(user.id) : null,
                  decoration: const InputDecoration(
                    isDense: true,
                    // Sayaç gizli: 40 karakter kimsenin çarptığı bir sınır
                    // değil ve altında duran "0/40" gürültüden ibaret.
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: S.md),
              FilledButton(
                onPressed: canSave ? () => _save(user.id) : null,
                child: Text(_saving ? 'Kaydediliyor…' : 'Kaydet'),
              ),
            ],
          ),
          const SizedBox(height: S.sm),
          Text(
            offline
                ? 'Ad değiştirmek bağlantı gerektiriyor.'
                : 'Grup arkadaşların bu adı görür.',
            style: TextStyle(
              color: offline ? c.warning : c.inkFaint,
              fontSize: T.caption,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// --- Hesap -------------------------------------------------------------------

/// Oturum bilgisi ve çıkış.
///
/// "Oturum aç" satırı buradan kalktı: kapı geldiğinden beri bu ekrana yalnız
/// oturum açmış biri ulaşabiliyor (`AuthGate`). Bulunmadığın bir yerin giriş
/// düğmesini göstermek, kullanıcıya cevabını zaten bildiği bir soruyu sormaktı.
class _AccountSection extends ConsumerWidget {
  const _AccountSection();

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
        _ActionTile(
          icon: Icons.password_rounded,
          iconColor: c.inkDim,
          title: 'Parolanı değiştir',
          subtitle: 'Bu hesabın parolası',
          onTap: () => _changePassword(context, ref),
        ),
        _ActionTile(
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
// --- Görünüm -----------------------------------------------------------------

/// Tema seçici: üç büyük, dokunulası kart. Anahtar yerine kart tercih edildi
/// çünkü "sistem" üçüncü bir durum ve iki konumlu bir anahtara sığmaz.
class _ThemeCard extends ConsumerWidget {
  const _ThemeCard();

  static const _options = <(IconData, String, String, ThemeMode)>[
    (Icons.light_mode_rounded, 'Açık', 'Gündüz', ThemeMode.light),
    (Icons.dark_mode_rounded, 'Koyu', 'Gece', ThemeMode.dark),
    (Icons.brightness_auto_rounded, 'Sistem', 'Otomatik', ThemeMode.system),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final mode = ref.watch(themeModeProvider);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette_rounded, size: I.md, color: c.inkDim),
              const SizedBox(width: S.md),
              Expanded(
                child: Text(
                  'Tema',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: T.strong,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: S.xs),
          Text(
            'Tercihin bu cihazda saklanır ve uygulama açılır açılmaz uygulanır.',
            style: TextStyle(
              color: c.inkFaint,
              fontSize: T.micro,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: S.md),
          Row(
            children: [
              for (final o in _options) ...[
                Expanded(
                  child: _ThemeOptionCard(
                    icon: o.$1,
                    title: o.$2,
                    caption: o.$3,
                    selected: mode == o.$4,
                    onTap: () => ref.read(themeModeProvider.notifier).set(o.$4),
                  ),
                ),
                if (o != _options.last) const SizedBox(width: S.sm),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Görev yazmanın hangi yoldan gideceği (A2).
///
/// Tema kartıyla aynı kalıpta ve onun hemen altında duruyor — ikisi de
/// "uygulama bana nasıl görünsün/davransın" sorusunun yanıtı ve ikisi de bu
/// cihaza özel.
class _UsageModeCard extends ConsumerWidget {
  const _UsageModeCard();

  static const _icons = <UsageMode, IconData>{
    UsageMode.klasik: Icons.keyboard_rounded,
    UsageMode.ajanda: Icons.draw_rounded,
    UsageMode.karma: Icons.auto_awesome_motion_rounded,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final mode = ref.watch(usageModeProvider);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note_rounded, size: I.md, color: c.inkDim),
              const SizedBox(width: S.md),
              Expanded(
                child: Text(
                  'Yazma biçimi',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: T.strong,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: S.xs),
          Text(
            'Hiçbir ekran kaybolmaz; değişen tek şey yeni bir iş eklerken '
            'önce neyin açıldığı.',
            style: TextStyle(
              color: c.inkFaint,
              fontSize: T.micro,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: S.md),
          Row(
            children: [
              for (final option in UsageMode.values) ...[
                Expanded(
                  child: _ThemeOptionCard(
                    icon: _icons[option]!,
                    title: option.label,
                    caption: option.description,
                    selected: mode == option,
                    onTap: () =>
                        ref.read(usageModeProvider.notifier).set(option),
                  ),
                ),
                if (option != UsageMode.values.last)
                  const SizedBox(width: S.sm),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeOptionCard extends StatelessWidget {
  const _ThemeOptionCard({
    required this.icon,
    required this.title,
    required this.caption,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String caption;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: Motion.base,
          curve: Motion.curve,
          padding: const EdgeInsets.symmetric(vertical: S.md),
          decoration: BoxDecoration(
            color: selected ? c.accentSoft : c.bg,
            borderRadius: R.radiusSm,
            border: Border.all(
              color: selected ? c.accent : c.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: I.md,
                color: selected ? c.navActiveInk : c.inkDim,
              ),
              const SizedBox(height: S.sm),
              Text(
                title,
                style: TextStyle(
                  color: selected ? c.navActiveInk : c.ink,
                  fontSize: T.body,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: S.hair),
              Text(
                caption,
                style: TextStyle(
                  color: c.inkFaint,
                  fontSize: T.micro,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Veri ve gizlilik --------------------------------------------------------

/// Telemetri rızası. Varsayılan **kapalı**; kullanıcı açmadan tek olay gitmez.
class _TelemetryTile extends ConsumerStatefulWidget {
  const _TelemetryTile();

  @override
  ConsumerState<_TelemetryTile> createState() => _TelemetryTileState();
}

class _TelemetryTileState extends ConsumerState<_TelemetryTile> {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final telemetry = ref.watch(telemetryProvider);
    final gate = telemetry is ConsentGate ? telemetry : null;
    final available = gate != null;

    return _Card(
      child: Row(
        children: [
          Icon(Icons.insights_rounded, size: I.md, color: c.inkDim),
          const SizedBox(width: S.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Anonim kullanım istatistikleri',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: T.strong,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: S.xs),
                Text(
                  'Hangi ekranların kullanıldığı gibi sayısal veriler. '
                  'İş başlıkların, notların ve yerlerin asla gönderilmez.',
                  style: TextStyle(
                    color: c.inkFaint,
                    fontSize: T.micro,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                // Anahtar çalışıyor ama gidecek bir sunucu yoksa bunu söylemek
                // zorundayız. Çalışıyormuş gibi yapan bir anahtar, kapalı bir
                // anahtardan daha kötüdür.
                if (available && !AppConfig.telemetryAvailable) ...[
                  const SizedBox(height: S.xs),
                  Text(
                    'Bu derlemede analitik sunucusu yapılandırılmadı; '
                    'tercihin yine de saklanıyor.',
                    style: TextStyle(
                      color: c.warning,
                      fontSize: T.micro,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: S.sm),
          Switch(
            value: gate?.enabled ?? false,
            onChanged: available
                ? (v) async {
                    await gate.setEnabled(v);
                    if (mounted) setState(() {});
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

/// Geri alınamaz işlemler. Ayrı ve görsel olarak uyarılı tutuluyor.
class _DangerZone extends ConsumerWidget {
  const _DangerZone();

  Future<void> _wipe(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cihazdaki verileri sil'),
        content: const Text(
          'Tüm işler, rutinler, notlar ve alışkanlıklar bu cihazdan '
          'kalıcı olarak silinecek. Şifreleme anahtarı da yok edileceği için '
          'bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sil', style: TextStyle(color: ctx.colors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(outboxProvider).clear();
    await ref.read(localStoreProvider).wipe();
    ref.read(appStoreProvider).loadJson(const {});

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cihazdaki veriler silindi.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: R.radiusMd,
        onTap: () => _wipe(context, ref),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.lg),
          decoration: BoxDecoration(
            color: c.danger.withValues(alpha: c.isDark ? 0.07 : 0.05),
            borderRadius: R.radiusMd,
            border: Border.all(color: c.danger.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: [
              Icon(Icons.delete_forever_rounded, size: I.md, color: c.danger),
              const SizedBox(width: S.md),
              Expanded(
                child: Text(
                  'Cihazdaki verileri sil',
                  style: TextStyle(
                    color: c.danger,
                    fontSize: T.strong,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: I.md,
                color: c.danger.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Ortak parçalar ----------------------------------------------------------

/// Ayar kartlarının ortak kabuğu: yükseltilmiş yüzey + yumuşak köşe.
class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: S.sm),
      padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: R.radiusMd,
        border: Border.all(color: c.lineSoft),
        boxShadow: c.shadowSm,
      ),
      child: child,
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: I.md, color: iconColor ?? c.inkDim),
          const SizedBox(width: S.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: c.ink,
                    fontSize: T.strong,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: S.xs),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: c.inkFaint,
                    fontSize: T.micro,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      padding: const EdgeInsets.all(S.lg),
      decoration: BoxDecoration(color: c.accentSoft, borderRadius: R.radiusMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_rounded, size: I.sm, color: c.navActiveInk),
          const SizedBox(width: S.md),
          Expanded(
            child: Text(
              'Hesap sistemi backend eklendiğinde çalışır hale gelecek. '
              'O zamana kadar uygulama tamamen cihazda, çevrimdışı çalışır.',
              style: TextStyle(
                color: c.isDark ? c.inkDim : c.navActiveInk,
                fontSize: T.caption,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.xs, 0, S.xs, S.sm),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

/// Gerçekten bir şey yapan satır.
///
/// [_Tile]'dan ayrı duruyor çünkü ikisi karşıt şeyler söylüyor: [_Tile] sönük
/// ve kilitli ("henüz yok"), bu ise dokunulabilir. Aynı widget'a bayrak
/// eklemek, ekranın en önemli ayrımını bir parametreye gömerdi.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: R.radiusMd,
        onTap: onTap,
        child: _Card(
          child: Row(
            children: [
              Icon(icon, size: I.md, color: iconColor ?? c.accent),
              const SizedBox(width: S.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: c.ink,
                        fontSize: T.strong,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: S.hair),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: c.inkFaint,
                        fontSize: T.caption,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: I.md, color: c.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Opacity(
      opacity: 0.6,
      child: _Card(
        child: Row(
          children: [
            Icon(icon, size: I.md, color: c.inkDim),
            const SizedBox(width: S.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: c.ink,
                      fontSize: T.strong,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: S.hair),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: c.inkFaint,
                      fontSize: T.caption,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.lock_rounded, size: I.xs, color: c.inkFaint),
          ],
        ),
      ),
    );
  }
}
