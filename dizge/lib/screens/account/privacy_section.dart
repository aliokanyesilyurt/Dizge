/// Veri ve gizlilik bölümü: telemetri rızası ve cihazdaki veriyi silme.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_config.dart';
import '../../core/telemetry.dart';
import '../../data/app_store.dart';
import '../../data/persistence_providers.dart';
import '../../theme.dart';
import 'account_tiles.dart';

/// Telemetri rızası. Varsayılan **kapalı**; kullanıcı açmadan tek olay gitmez.
class TelemetryTile extends ConsumerStatefulWidget {
  const TelemetryTile({super.key});

  @override
  ConsumerState<TelemetryTile> createState() => _TelemetryTileState();
}

class _TelemetryTileState extends ConsumerState<TelemetryTile> {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final telemetry = ref.watch(telemetryProvider);
    final gate = telemetry is ConsentGate ? telemetry : null;
    final available = gate != null;

    return AccountCard(
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
class DangerZone extends ConsumerWidget {
  const DangerZone({super.key});

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
