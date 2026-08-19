/// Profil bölümü: avatar, görünen ad ve adın kaydedilmesi.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth_service.dart';
import '../../core/connectivity.dart';
import '../../core/profile_directory.dart';
import '../../data/sync/supabase_api.dart';
import '../../theme.dart';
import '../../widgets/user_avatar.dart';

class ProfileHeader extends ConsumerWidget {
  const ProfileHeader({super.key});

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
class DisplayNameField extends ConsumerStatefulWidget {
  const DisplayNameField({super.key});

  @override
  ConsumerState<DisplayNameField> createState() => _DisplayNameFieldState();
}

class _DisplayNameFieldState extends ConsumerState<DisplayNameField> {
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
