import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_config.dart';
import '../core/connectivity.dart';
import '../data/local_store.dart';
import '../data/persistence_providers.dart';
import '../data/sync/sync_engine.dart';
import '../theme.dart';
import 'account/account_tiles.dart';
import 'account/appearance_section.dart';
import 'account/notifications_section.dart';
import 'account/privacy_section.dart';
import 'account/profile_section.dart';
import 'account/session_section.dart';

/// Hesap, görünüm, gizlilik ve veri ayarları.
///
/// Oturum açma/kapama, tema tercihi, telemetri rızası, depolama durumu ve
/// "cihazdaki verileri sil" ve hatırlatmalar burada gerçekten çalışır.
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
                const ProfileHeader(),
                const SizedBox(height: S.lg),
                const DisplayNameField(),
                const SizedBox(height: S.md),
                const AvatarColorField(),
                const SizedBox(height: S.xl),

                // --- Görünüm ---
                const GroupLabel('Görünüm'),
                const ThemeCard(),
                const SizedBox(height: S.md),
                const UsageModeCard(),
                const SizedBox(height: S.xl),

                // --- Bildirimler ---
                const GroupLabel('Bildirimler'),
                const NotificationsCard(),
                const SizedBox(height: S.xl),

                // --- Veri ve gizlilik (çalışıyor) ---
                const GroupLabel('Veri ve gizlilik'),
                StatusTile(
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
                StatusTile(
                  icon: online == NetworkStatus.offline
                      ? Icons.cloud_off_rounded
                      : Icons.cloud_done_rounded,
                  title: _syncTitle(syncState, outbox.length),
                  subtitle:
                      'Uygulama önce cihaza yazar, sonra eşitler. '
                      'İnternet olmadan da tam çalışır.',
                ),
                const TelemetryTile(),
                const SizedBox(height: S.sm),
                const DangerZone(),

                const SizedBox(height: S.xl),

                // --- Hesap ---
                const GroupLabel('Hesap'),
                const AccountSection(),

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
