import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_config.dart';
import '../core/auth_service.dart';
import '../core/connectivity.dart';
import '../core/telemetry.dart';
import '../core/theme_mode_controller.dart';
import '../data/app_store.dart';
import '../data/local_store.dart';
import '../data/persistence_providers.dart';
import '../data/sync/sync_engine.dart';
import '../theme.dart';

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
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 40),
              children: [
                const _ProfileHeader(),
                const SizedBox(height: 28),

                // --- Görünüm ---
                const _GroupLabel('Görünüm'),
                const _ThemeCard(),
                const SizedBox(height: 26),

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
                const SizedBox(height: 10),
                const _DangerZone(),

                const SizedBox(height: 26),

                // --- Hesap ---
                const _GroupLabel('Hesap'),
                const _AccountSection(),

                // --- Henüz backend bekleyenler ---
                const SizedBox(height: 10),
                const _Notice(),
                const SizedBox(height: 10),
                const _Tile(
                  icon: Icons.notifications_rounded,
                  title: 'Bildirimler',
                  subtitle: 'Hatırlatmalar',
                ),

                const SizedBox(height: 26),
                Center(
                  child: Text(
                    'Sürüm 1.0.0  ·  ${AppConfig.environment}',
                    style: TextStyle(
                      color: c.inkFaint,
                      fontSize: 11,
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

    return Row(
      children: [
        Container(
          width: 60,
          height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [c.accent, Color.lerp(c.accent, c.secondary, 0.55)!],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: c.shadowMd,
          ),
          child: Icon(Icons.person_rounded, color: c.onAccent, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user?.email ?? 'Misafir',
                style: Theme.of(context).textTheme.headlineSmall,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                user == null
                    ? 'Oturum açılmadı — veriler bu cihazda'
                    : 'Oturum açık — değişiklikler hesabına eşitleniyor',
                style: TextStyle(
                  color: c.inkFaint,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- Hesap -------------------------------------------------------------------

/// Oturum durumuna göre tek bir eylem gösterir: giriş ya da çıkış.
///
/// İkisini birden göstermek (biri sönük) yer kaplar ve kararı geciktirir; bu
/// ekranda kullanıcının sorusu her zaman tek: "içeride miyim?"
class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final user = ref.watch(authUserProvider).valueOrNull;

    if (user == null) {
      return _ActionTile(
        icon: Icons.login_rounded,
        title: 'Oturum aç',
        subtitle: 'Planların bütün cihazlarında aynı olsun',
        onTap: () => _showSignIn(context, ref),
      );
    }

    return _ActionTile(
      icon: Icons.logout_rounded,
      iconColor: c.inkDim,
      title: 'Çıkış yap',
      // Kullanıcının bu düğmeye basarken en çok korktuğu şey bu; cevabı
      // düğmenin yanında duruyor.
      subtitle: 'Cihazdaki planların silinmez',
      onTap: () => ref.read(authServiceProvider).signOut(),
    );
  }
}

Future<void> _showSignIn(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => Padding(
      // Klavye açıldığında alanlar onun altında kalmasın.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: const _SignInSheet(),
    ),
  );
}

/// E-posta + parola. Sihirli bağlantı ve OAuth bilinçli olarak yok: ikisi de
/// masaüstünde derin bağlantı kaydı ister ve bu ayrı bir platform işi.
class _SignInSheet extends ConsumerStatefulWidget {
  const _SignInSheet();

  @override
  ConsumerState<_SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends ConsumerState<_SignInSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _registering = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;

    // Sunucuya gitmeden yakalanabilecek iki hata. Ağ turu beklemek ve
    // İngilizce bir sunucu mesajı almak gereksiz.
    if (!email.contains('@') || email.length < 3) {
      setState(() => _error = 'Geçerli bir e-posta gir.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Parola en az 6 karakter olmalı.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final auth = ref.read(authServiceProvider);
      if (_registering) {
        await auth.signUp(email: email, password: password);
      } else {
        await auth.signIn(email: email, password: password);
      }
      if (mounted) Navigator.of(context).pop();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _registering ? 'Hesap oluştur' : 'Oturum aç',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Planların şifreli olarak cihazında kalmaya devam eder; '
              'hesap yalnızca onları cihazların arasında taşır.',
              style: TextStyle(
                color: c.inkFaint,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _email,
              enabled: !_busy,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'E-posta'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _busy ? null : _submit(),
              decoration: const InputDecoration(hintText: 'Parola'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded, size: 16, color: c.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: c.danger,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.onAccent,
                      ),
                    )
                  : Text(_registering ? 'Hesap oluştur' : 'Giriş yap'),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _registering = !_registering;
                      _error = null;
                    }),
              child: Text(
                _registering ? 'Zaten hesabım var' : 'Hesabım yok, oluşturayım',
              ),
            ),
          ],
        ),
      ),
    );
  }
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
              Icon(Icons.palette_rounded, size: 18, color: c.inkDim),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Tema',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tercihin bu cihazda saklanır ve uygulama açılır açılmaz uygulanır.',
            style: TextStyle(
              color: c.inkFaint,
              fontSize: 11.5,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
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
                if (o != _options.last) const SizedBox(width: 10),
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
          padding: const EdgeInsets.symmetric(vertical: 14),
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
              Icon(icon, size: 20, color: selected ? c.navActiveInk : c.inkDim),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  color: selected ? c.navActiveInk : c.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                caption,
                style: TextStyle(
                  color: c.inkFaint,
                  fontSize: 10.5,
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
          Icon(Icons.insights_rounded, size: 18, color: c.inkDim),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Anonim kullanım istatistikleri',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Hangi ekranların kullanıldığı gibi sayısal veriler. '
                  'İş başlıkların, notların ve yerlerin asla gönderilmez.',
                  style: TextStyle(
                    color: c.inkFaint,
                    fontSize: 11.5,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: c.danger.withValues(alpha: c.isDark ? 0.07 : 0.05),
            borderRadius: R.radiusMd,
            border: Border.all(color: c.danger.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: [
              Icon(Icons.delete_forever_rounded, size: 18, color: c.danger),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Cihazdaki verileri sil',
                  style: TextStyle(
                    color: c.danger,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
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
          Icon(icon, size: 18, color: iconColor ?? c.inkDim),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: c.inkFaint,
                    fontSize: 11.5,
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
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: c.accentSoft, borderRadius: R.radiusMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_rounded, size: 17, color: c.navActiveInk),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              'Hesap sistemi backend eklendiğinde çalışır hale gelecek. '
              'O zamana kadar uygulama tamamen cihazda, çevrimdışı çalışır.',
              style: TextStyle(
                color: c.isDark ? c.inkDim : c.navActiveInk,
                fontSize: 12.5,
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
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
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
              Icon(icon, size: 18, color: iconColor ?? c.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: c.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: c.inkFaint,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: c.inkFaint),
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
            Icon(icon, size: 18, color: c.inkDim),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: c.inkFaint,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.lock_rounded, size: 14, color: c.inkFaint),
          ],
        ),
      ),
    );
  }
}
