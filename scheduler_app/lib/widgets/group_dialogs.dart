import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_service.dart';
import '../core/connectivity.dart';
import '../core/group_context.dart';
import '../data/sync/supabase_api.dart';
import '../models/group.dart';
import '../theme.dart';

/// Grup işlemlerinin arayüzü (Y4.3): kur, davet et, daveti kabul et, çık.
///
/// Dördü de birer diyalog — ayrı bir ekran değil. Grup yönetimi arada bir
/// yapılan, başladığı yerde biten bir iş; kullanıcıyı takvimden koparıp
/// başka bir sayfaya götürmek, dönüş yolunu da ona bırakmak olurdu.
///
/// Hepsi **çevrimiçi ister** (Y4f). Düğme çevrimdışıyken pasif ve sebebini
/// yazıyor: sessizce kuyruğa alınsalardı "kurduğum grup nerede?" sorusunun
/// cevabı hiçbir yerde olmazdı.

Future<void> showCreateGroupDialog(BuildContext context) => showDialog(
  context: context,
  builder: (_) => const _GroupDialog(
    title: 'Yeni grup',
    description:
        'Grup, takvimini paylaştığın kişilerle ortak alanın. Kurduğunda '
        'içine düşersin; sonra davet edersin.',
    label: 'Grup adı',
    hint: 'Ev, Ekip, Proje…',
    action: 'Kur',
    mode: _Mode.create,
  ),
);

Future<void> showAcceptInviteDialog(BuildContext context) => showDialog(
  context: context,
  builder: (_) => const _GroupDialog(
    title: 'Daveti kabul et',
    description:
        'Sana gönderilen davet kodunu yapıştır. Kod tek kullanımlık ve '
        'süresi dolabilir.',
    label: 'Davet kodu',
    hint: 'Uzun harf-rakam dizisi',
    action: 'Katıl',
    mode: _Mode.accept,
  ),
);

Future<void> showManageGroupDialog(BuildContext context, Group group) =>
    showDialog(context: context, builder: (_) => _ManageGroupDialog(group));

enum _Mode { create, accept }

/// Diyalogların açıklama metni — tek yerde, üç diyalogda aynı ton.
TextStyle _faint(BuildContext context) =>
    TextStyle(color: context.colors.inkFaint, fontSize: 12, height: 1.4);

/// Tek alanlı iki diyalog (kur / kabul et) aynı iskeleti paylaşıyor: metin
/// alanı, çevrimdışı uyarısı, hata satırı, bekleme durumu.
class _GroupDialog extends ConsumerStatefulWidget {
  const _GroupDialog({
    required this.title,
    required this.description,
    required this.label,
    required this.hint,
    required this.action,
    required this.mode,
  });

  final String title;
  final String description;
  final String label;
  final String hint;
  final String action;
  final _Mode mode;

  @override
  ConsumerState<_GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends ConsumerState<_GroupDialog> {
  final _field = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _field.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Boş bırakılamaz.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final actions = ref.read(groupActionsProvider);
      if (widget.mode == _Mode.create) {
        await actions.create(value);
      } else {
        await actions.accept(value);
      }
      if (mounted) Navigator.of(context).pop();
    } on RemoteException catch (e) {
      // Sunucunun kendi cümlesi burada kullanıcıya en yakın olanı: "davet
      // zaten kullanılmış", "süresi dolmuş" gibi.
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'İşlem tamamlanamadı. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offline =
        ref.watch(networkStatusProvider).valueOrNull == NetworkStatus.offline;

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.description, style: _faint(context)),
          const SizedBox(height: 16),
          TextField(
            controller: _field,
            autofocus: true,
            enabled: !_busy && !offline,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
            ),
            onSubmitted: (_) => offline ? null : _submit(),
          ),
          if (offline) const _OfflineNote(),
          if (_error != null) _ErrorNote(_error!),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: (_busy || offline) ? null : _submit,
          child: _busy ? const _Spinner() : Text(widget.action),
        ),
      ],
    );
  }
}

/// Grup yönetimi: davet üret ve gruptan çık.
class _ManageGroupDialog extends ConsumerStatefulWidget {
  const _ManageGroupDialog(this.group);

  final Group group;

  @override
  ConsumerState<_ManageGroupDialog> createState() => _ManageGroupDialogState();
}

class _ManageGroupDialogState extends ConsumerState<_ManageGroupDialog> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _token;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() body) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await body();
    } on RemoteException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'İşlem tamamlanamadı. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _invite() => _run(() async {
    final token = await ref
        .read(groupActionsProvider)
        .invite(widget.group.id, email: _email.text);
    await Clipboard.setData(ClipboardData(text: token));
    if (mounted) setState(() => _token = token);
  });

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Gruptan çık'),
        content: Text(
          '"${widget.group.name}" grubunun işleri bu cihazdan kaldırılacak. '
          'Gruptaki diğer kişilerde durmaya devam eder — silinmiyorlar, '
          'yalnız senin görüşünden çıkıyorlar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Çık'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await _run(() async {
      await ref.read(groupActionsProvider).leave(widget.group.id);
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final offline =
        ref.watch(networkStatusProvider).valueOrNull == NetworkStatus.offline;
    // Davet etme hakkı yalnız sahipte (Y3f). Sunucu da reddediyor; düğmeyi
    // burada göstermemek, reddedilecek bir yolu hiç açmamak için.
    final isOwner = widget.group.isOwnedBy(
      ref.watch(authUserProvider).valueOrNull?.id,
    );

    return AlertDialog(
      title: Text(widget.group.name),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isOwner) ...[
              Text(
                'Davet kodu üret ve karşı tarafa ilet. Kod tek kullanımlık; '
                'bir adres yazarsan yalnız o hesapta çalışır.',
                style: _faint(context),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _email,
                enabled: !_busy && !offline,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-posta (isteğe bağlı)',
                  hintText: 'ornek@posta.com',
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: (_busy || offline) ? null : _invite,
                  icon: const Icon(Icons.link_rounded, size: 17),
                  label: const Text('Davet kodu üret'),
                ),
              ),
              if (_token != null) _TokenBox(_token!),
              const SizedBox(height: 8),
              Divider(color: c.lineSoft),
            ],
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: (_busy || offline) ? null : _leave,
                icon: Icon(Icons.logout_rounded, size: 17, color: c.danger),
                label: Text('Gruptan çık', style: TextStyle(color: c.danger)),
              ),
            ),
            if (offline) const _OfflineNote(),
            if (_error != null) _ErrorNote(_error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Kapat'),
        ),
      ],
    );
  }
}

/// Üretilen davet kodu. Panoya zaten kopyalandı; burada görünmesi, kopyalanın
/// gerçekten bir şey olduğunu göstermek için.
class _TokenBox extends StatelessWidget {
  const _TokenBox(this.token);

  final String token;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: c.lineSoft),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_rounded, size: 15, color: c.accent),
                const SizedBox(width: 6),
                Text(
                  'Panoya kopyalandı',
                  style: TextStyle(
                    color: c.accent,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            SelectableText(
              token,
              style: TextStyle(
                color: c.inkDim,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineNote extends StatelessWidget {
  const _OfflineNote();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      children: [
        Icon(Icons.cloud_off_rounded, size: 14, color: context.colors.inkFaint),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            'Grup işlemleri sunucuya bağlanmayı gerektiriyor; '
            'bağlantı gelince tekrar dene.',
            style: _faint(context),
          ),
        ),
      ],
    ),
  );
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 14, color: c.danger),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: c.danger, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 15,
    height: 15,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}
