/// Bildirimler bölümü (N3): aç/kapa, ne kadar önce, rutinler, izin, deneme.
///
/// Eskiden burada dokununca hiçbir şey yapmayan sönük bir "Bildirimler"
/// satırı ve üstünde "backend eklendiğinde çalışacak" diyen eski bir uyarı
/// vardı. İkisi de gitti; ayar gerçek, deneme düğmesi de "çalışıyor mu"
/// sorusunun tek dokunuşluk cevabı.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/reminders.dart';
import '../../theme.dart';
import '../../widgets/editor/editor_controls.dart';
import 'account_tiles.dart';

class NotificationsCard extends ConsumerStatefulWidget {
  const NotificationsCard({super.key});

  @override
  ConsumerState<NotificationsCard> createState() => _NotificationsCardState();
}

class _NotificationsCardState extends ConsumerState<NotificationsCard>
    with WidgetsBindingObserver {
  ReminderPermission _permission = ReminderPermission.unknown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Kullanıcı sistem ayarlarından izni açıp geri dönünce satır tazelensin.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final p = await ref.read(reminderGatewayProvider).permission();
    if (mounted) setState(() => _permission = p);
  }

  Future<void> _requestPermission() async {
    final gateway = ref.read(reminderGatewayProvider);
    var p = await gateway.requestPermission();
    // Android bir kez "hayır" denince bir daha sormuyor; o durumda tek yol
    // sistem ayarları.
    if (p == ReminderPermission.denied) {
      await gateway.openSystemSettings();
      p = await gateway.permission();
    }
    if (mounted) setState(() => _permission = p);
  }

  Future<void> _sendTest() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(reminderGatewayProvider)
          .showNow(title: 'Dizge', body: 'Hatırlatmalar çalışıyor.');
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Gönderildi — birkaç saniye içinde görünmeli.'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Bildirim gönderilemedi.')),
      );
    }
  }

  void _update(ReminderSettings next) =>
      ref.read(reminderSettingsProvider.notifier).update(next);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final settings = ref.watch(reminderSettingsProvider);

    return AccountCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                settings.enabled
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_off_rounded,
                size: I.md,
                color: c.inkDim,
              ),
              const SizedBox(width: S.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hatırlatmalar',
                      style: TextStyle(
                        color: c.ink,
                        fontSize: T.strong,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: S.xs),
                    Text(
                      'Saati olan işler başlamadan önce bildirilir. '
                      'Tercih bu cihazda saklanır.',
                      style: _faint(c),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: S.sm),
              Switch(
                value: settings.enabled,
                onChanged: (v) => _update(settings.copyWith(enabled: v)),
              ),
            ],
          ),
          if (settings.enabled) ...[
            const SizedBox(height: S.lg),
            Text('Ne zaman?', style: _label(c)),
            const SizedBox(height: S.sm),
            Wrap(
              spacing: S.sm,
              runSpacing: S.sm,
              children: [
                for (final m in kReminderLeadChoices)
                  ChoiceChipTile(
                    text: m == 0 ? 'Tam saatinde' : '$m dk önce',
                    selected: settings.leadMinutes == m,
                    onTap: () => _update(settings.copyWith(leadMinutes: m)),
                  ),
              ],
            ),
            const SizedBox(height: S.md),
            Row(
              children: [
                Expanded(
                  child: Text('Rutinleri de hatırlat', style: _label(c)),
                ),
                Switch(
                  value: settings.includeRoutines,
                  onChanged: (v) =>
                      _update(settings.copyWith(includeRoutines: v)),
                ),
              ],
            ),
            const SizedBox(height: S.sm),
            _PermissionRow(
              permission: _permission,
              onRequest: _requestPermission,
              onOpenSettings: () =>
                  ref.read(reminderGatewayProvider).openSystemSettings(),
            ),
            const SizedBox(height: S.md),
            OutlinedButton.icon(
              onPressed: _sendTest,
              icon: const Icon(Icons.send_rounded, size: I.sm),
              label: const Text('Deneme bildirimi gönder'),
            ),
          ],
        ],
      ),
    );
  }
}

TextStyle _faint(AppPalette c) => TextStyle(
  color: c.inkFaint,
  fontSize: T.micro,
  height: 1.4,
  fontWeight: FontWeight.w500,
);

TextStyle _label(AppPalette c) =>
    TextStyle(color: c.ink, fontSize: T.body, fontWeight: FontWeight.w600);

/// İznin durumu ve (gerekirse) tek düzeltme yolu.
class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.permission,
    required this.onRequest,
    required this.onOpenSettings,
  });

  final ReminderPermission permission;
  final VoidCallback onRequest;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final (icon, color, text) = switch (permission) {
      ReminderPermission.granted => (
        Icons.check_circle_rounded,
        c.accent,
        'Bildirim izni verildi.',
      ),
      ReminderPermission.denied => (
        Icons.warning_amber_rounded,
        c.warning,
        'Bildirim izni kapalı — hatırlatmalar görünmez.',
      ),
      // Masaüstünde izin ayrı bir adım değil; sistem ayarından kapatılabilir.
      ReminderPermission.unknown => (
        Icons.info_outline_rounded,
        c.inkFaint,
        'Sistem bildirim ayarlarından da kapatılabilir.',
      ),
    };

    return Row(
      children: [
        Icon(icon, size: I.sm, color: color),
        const SizedBox(width: S.sm),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: permission == ReminderPermission.denied
                  ? c.warning
                  : c.inkDim,
              fontSize: T.caption,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (permission == ReminderPermission.denied)
          TextButton(onPressed: onRequest, child: const Text('İzin ver'))
        else if (permission == ReminderPermission.unknown)
          TextButton(
            onPressed: onOpenSettings,
            child: const Text('Sistem ayarları'),
          ),
      ],
    );
  }
}
