import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/group_context.dart';
import '../models/group.dart';
import '../theme.dart';
import 'group_screen.dart';

class GroupCreateSheet extends ConsumerStatefulWidget {
  const GroupCreateSheet({super.key});

  @override
  ConsumerState<GroupCreateSheet> createState() => _GroupCreateSheetState();
}

enum _Step { form, success }

class _GroupCreateSheetState extends ConsumerState<GroupCreateSheet> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _email = TextEditingController();

  int _colorIndex = 0;
  _Step _step = _Step.form;
  bool _busy = false;
  String? _error;
  Group? _createdGroup;
  String? _token;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final desc = _desc.text.trim();
      final group = await ref.read(groupActionsProvider).create(
        name,
        description: desc.isEmpty ? null : desc,
        colorIndex: _colorIndex,
      );
      if (mounted) {
        setState(() {
          _createdGroup = group;
          _step = _Step.success;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Kurulamadı. $e';
          _busy = false;
        });
      }
    }
  }

  Future<void> _invite() async {
    if (_createdGroup == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await ref
          .read(groupActionsProvider)
          .invite(_createdGroup!.id, email: _email.text.trim());
      await Clipboard.setData(ClipboardData(text: token));
      if (mounted) setState(() => _token = token);
    } catch (e) {
      if (mounted) setState(() => _error = 'Davet üretilemedi. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: EdgeInsets.only(
        left: S.lg,
        right: S.lg,
        top: S.lg,
        bottom: S.lg + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _step == _Step.form ? 'Yeni grup' : 'Grup kuruldu',
            style: TextStyle(
              color: c.ink,
              fontSize: T.headline,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: S.lg),
          if (_step == _Step.form) _buildForm(context) else _buildSuccess(context),
        ],
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final c = context.colors;
    final color = kAvatarColors[_colorIndex];
    final previewName = _name.text.trim().isEmpty ? 'Ev' : _name.text.trim();
    final previewInitial = previewName.characters.isEmpty ? 'E' : previewName.characters.first.toUpperCase();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(S.md),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: c.line),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color,
                foregroundColor: inkOn(color),
                child: Text(previewInitial),
              ),
              const SizedBox(width: S.md),
              Expanded(
                child: Text(
                  previewName,
                  style: TextStyle(
                    color: c.ink,
                    fontSize: T.body,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: S.lg),
        TextField(
          controller: _name,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Grup adı', hintText: 'Ev'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: S.md),
        Text('Renk', style: TextStyle(color: c.inkDim, fontSize: T.caption)),
        const SizedBox(height: S.xs),
        Wrap(
          spacing: S.sm,
          runSpacing: S.sm,
          children: List.generate(kAvatarColors.length, (i) {
            final col = kAvatarColors[i];
            final selected = i == _colorIndex;
            return GestureDetector(
              onTap: () => setState(() => _colorIndex = i),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: col,
                  shape: BoxShape.circle,
                  border: selected
                      ? Border.all(color: c.ink, width: 2)
                      : Border.all(color: c.line, width: 1),
                ),
                child: selected
                    ? Icon(Icons.check_rounded, size: I.xs, color: inkOn(col))
                    : null,
              ),
            );
          }),
        ),
        const SizedBox(height: S.md),
        TextField(
          controller: _desc,
          decoration: const InputDecoration(
            labelText: 'Açıklama (isteğe bağlı)',
            hintText: 'Ev işleri ve alışveriş',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: S.md),
          Text(_error!, style: TextStyle(color: c.danger, fontSize: T.micro)),
        ],
        const SizedBox(height: S.xl),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy ? const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2),
          ) : const Text('Grubu kur'),
        ),
      ],
    );
  }

  Widget _buildSuccess(BuildContext context) {
    final c = context.colors;
    final group = _createdGroup!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_rounded, color: c.accent),
            const SizedBox(width: S.sm),
            Expanded(
              child: Text(
                '"${group.name}" kuruldu',
                style: TextStyle(color: c.ink, fontSize: T.body),
              ),
            ),
          ],
        ),
        const SizedBox(height: S.lg),
        Text('Birini davet et:', style: TextStyle(color: c.inkDim, fontSize: T.caption)),
        const SizedBox(height: S.xs),
        TextField(
          controller: _email,
          decoration: const InputDecoration(
            labelText: 'E-posta (isteğe bağlı)',
            hintText: 'ornek@posta.com',
          ),
        ),
        const SizedBox(height: S.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _invite,
            icon: const Icon(Icons.link_rounded, size: I.sm),
            label: const Text('Davet kodu üret'),
          ),
        ),
        if (_token != null) ...[
          const SizedBox(height: S.md),
          Container(
            padding: const EdgeInsets.all(S.md),
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
                    Icon(Icons.check_rounded, size: I.sm, color: c.accent),
                    const SizedBox(width: S.xs),
                    Text(
                      'Panoya kopyalandı',
                      style: TextStyle(
                        color: c.accent,
                        fontSize: T.micro,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: S.sm),
                SelectableText(
                  _token!,
                  style: TextStyle(
                    color: c.inkDim,
                    fontSize: T.micro,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: S.md),
          Text(_error!, style: TextStyle(color: c.danger, fontSize: T.micro)),
        ],
        const SizedBox(height: S.xl),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Sonra'),
            ),
            const SizedBox(width: S.sm),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => GroupScreen(group: group),
                ));
              },
              child: const Text('Gruba git →'),
            ),
          ],
        ),
      ],
    );
  }
}
