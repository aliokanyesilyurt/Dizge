import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_config.dart';
import '../core/connectivity.dart';
import '../core/telemetry.dart';
import '../data/app_store.dart';
import '../data/local_store.dart';
import '../data/persistence_providers.dart';
import '../data/sync/sync_engine.dart';
import '../theme.dart';

/// Hesap, gizlilik ve veri ayarları.
///
/// Oturum/profil kısmı hâlâ backend bekliyor; ancak **veri ve gizlilik**
/// bölümü artık gerçek: telemetri rızası, depolama durumu ve "cihazdaki
/// verileri sil" burada çalışır. Üretime çıkan bir uygulamada bu üçü
/// pazarlık konusu değildir.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(localStoreProvider);
    final encrypted = store is HiveLocalStore;
    final outbox = ref.watch(outboxProvider);
    final syncState = ref.watch(syncStateProvider).valueOrNull ?? SyncState.idle;
    final online = ref.watch(networkStatusProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.blue, AppColors.pink],
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Icon(Icons.person, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Misafir',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Oturum açılmadı — veriler bu cihazda',
                      style: TextStyle(
                        color: AppColors.inkFaint,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 22),

            // --- Veri ve gizlilik (çalışıyor) ---
            const _GroupLabel('Veri ve gizlilik'),
            _StatusTile(
              icon: encrypted ? Icons.lock_outline : Icons.lock_open_outlined,
              iconColor: encrypted ? AppColors.blue : AppColors.pink,
              title: encrypted ? 'Veriler şifreli' : 'Şifreleme kullanılamıyor',
              subtitle: encrypted
                  ? 'Planların AES-256 ile bu cihazda saklanıyor. '
                      'Anahtar cihazın güvenli kasasında; sunucuya gitmiyor.'
                  : 'Cihazın güvenli anahtar deposuna erişilemedi. '
                      'Veriler yalnızca uygulama açıkken bellekte tutuluyor.',
            ),
            _StatusTile(
              icon: online == NetworkStatus.offline
                  ? Icons.cloud_off_outlined
                  : Icons.cloud_done_outlined,
              title: _syncTitle(syncState, outbox.length),
              subtitle: 'Uygulama önce cihaza yazar, sonra eşitler. '
                  'İnternet olmadan da tam çalışır.',
            ),
            const _TelemetryTile(),
            const SizedBox(height: 6),
            const _DangerZone(),

            const SizedBox(height: 22),

            // --- Henüz backend bekleyenler ---
            const _GroupLabel('Hesap'),
            const _Notice(),
            const SizedBox(height: 10),
            const _Tile(
              icon: Icons.login_rounded,
              title: 'Oturum aç',
              subtitle: 'Backend bağlanınca etkinleşecek',
            ),
            const _Tile(
              icon: Icons.badge_outlined,
              title: 'Profil bilgileri',
              subtitle: 'Ad, e-posta, avatar',
            ),
            const SizedBox(height: 18),
            const _GroupLabel('Uygulama'),
            const _Tile(
              icon: Icons.notifications_none_rounded,
              title: 'Bildirimler',
              subtitle: 'Hatırlatmalar',
            ),
            const SizedBox(height: 20),
            const Center(
              child: Text(
                'Sürüm 1.0.0  ·  ${AppConfig.environment}',
                style: TextStyle(
                  color: AppColors.inkFaint,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
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

/// Telemetri rızası. Varsayılan **kapalı**; kullanıcı açmadan tek olay gitmez.
class _TelemetryTile extends ConsumerStatefulWidget {
  const _TelemetryTile();

  @override
  ConsumerState<_TelemetryTile> createState() => _TelemetryTileState();
}

class _TelemetryTileState extends ConsumerState<_TelemetryTile> {
  @override
  Widget build(BuildContext context) {
    final telemetry = ref.watch(telemetryProvider);
    final gate = telemetry is ConsentGate ? telemetry : null;
    final available = gate != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(13, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.lineSoft),
      ),
      child: Row(
        children: [
          const Icon(Icons.insights_outlined, size: 18, color: AppColors.inkDim),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Anonim kullanım istatistikleri',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Hangi ekranların kullanıldığı gibi sayısal veriler. '
                  'İş başlıkların, notların ve yerlerin asla gönderilmez.',
                  style: TextStyle(
                    color: AppColors.inkFaint,
                    fontSize: 11.5,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
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
            child: const Text('Sil',
                style: TextStyle(color: Color(0xFFE57373))),
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
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () => _wipe(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0x33E57373)),
        ),
        child: const Row(
          children: [
            Icon(Icons.delete_forever_outlined,
                size: 18, color: Color(0xFFE57373)),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Cihazdaki verileri sil',
                style: TextStyle(
                  color: Color(0xFFE57373),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: AppColors.inkFaint),
          ],
        ),
      ),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.lineSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor ?? AppColors.inkDim),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.inkFaint,
                    fontSize: 11.5,
                    height: 1.35,
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
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.blue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.28)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 17, color: AppColors.blue),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Hesap sistemi backend eklendiğinde çalışır hale gelecek. '
              'O zamana kadar uygulama tamamen cihazda, çevrimdışı çalışır.',
              style: TextStyle(
                color: AppColors.inkDim,
                fontSize: 12.5,
                height: 1.4,
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
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.inkFaint,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
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
    return Opacity(
      opacity: 0.65,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.lineSoft),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.inkDim),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.inkFaint,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.lock_outline, size: 14, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }
}
