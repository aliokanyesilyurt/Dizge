import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/connectivity.dart';
import '../core/group_context.dart';
import '../data/sync/supabase_api.dart';
import '../theme.dart';

/// Grup işlemlerinin arayüzü (Y4.3).

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
  ),
);

TextStyle _faint(BuildContext context) =>
    TextStyle(color: context.colors.inkFaint, fontSize: T.caption, height: 1.4);

class _GroupDialog extends ConsumerStatefulWidget {
  const _GroupDialog({
    required this.title,
    required this.description,
    required this.label,
    required this.hint,
    required this.action,
  });

  final String title;
  final String description;
  final String label;
  final String hint;
  final String action;

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
      await ref.read(groupActionsProvider).accept(value);
      if (mounted) Navigator.of(context).pop();
    } on RemoteException catch (e) {
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
          const SizedBox(height: S.lg),
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

class _OfflineNote extends StatelessWidget {
  const _OfflineNote();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: S.md),
    child: Row(
      children: [
        Icon(
          Icons.cloud_off_rounded,
          size: I.xs,
          color: context.colors.inkFaint,
        ),
        const SizedBox(width: S.sm),
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
      padding: const EdgeInsets.only(top: S.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: I.xs, color: c.danger),
          const SizedBox(width: S.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: c.danger, fontSize: T.micro),
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
