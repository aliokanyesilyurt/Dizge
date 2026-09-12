import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_service.dart';
import '../core/group_context.dart';
import '../core/profile_directory.dart';
import '../models/group.dart';
import '../theme.dart';
import '../widgets/user_avatar.dart';

class GroupScreen extends ConsumerStatefulWidget {
  const GroupScreen({super.key, required this.group});

  final Group group;

  @override
  ConsumerState<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends ConsumerState<GroupScreen> {
  late Group _group;
  List<GroupMember>? _members;
  String? _error;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    try {
      final members = await ref.read(groupActionsProvider).members(_group.id);
      if (mounted) setState(() => _members = members);
    } catch (e) {
      if (mounted) setState(() => _error = 'Üyeler yüklenemedi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = groupColorOf(_group);
    final isOwner = _group.isOwnedBy(ref.watch(authUserProvider).valueOrNull?.id);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        iconTheme: IconThemeData(color: c.ink),
        title: const Text('Grup sayfası', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(S.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(width: 8, height: 48, color: color),
                const SizedBox(width: S.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _group.name,
                        style: TextStyle(color: c.ink, fontSize: T.headline, fontWeight: FontWeight.bold),
                      ),
                      if (_group.description != null)
                        Text(
                          _group.description!,
                          style: TextStyle(color: c.inkDim, fontSize: T.body),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.xl),
            
            // Members
            Text('Üyeler', style: TextStyle(color: c.ink, fontSize: T.title, fontWeight: FontWeight.w600)),
            const SizedBox(height: S.sm),
            if (_error != null)
              Text(_error!, style: TextStyle(color: c.danger))
            else if (_members == null)
              const Align(alignment: Alignment.centerLeft, child: CircularProgressIndicator())
            else
              ..._members!.map((m) => _MemberTile(member: m)),
            
            const SizedBox(height: S.xl),

            // Invite
            if (isOwner) ...[
              Text('Davet et', style: TextStyle(color: c.ink, fontSize: T.title, fontWeight: FontWeight.w600)),
              const SizedBox(height: S.sm),
              _InviteSection(group: _group),
              const SizedBox(height: S.xl),
            ],

            // Settings
            if (isOwner) ...[
              Text('Ayarlar', style: TextStyle(color: c.ink, fontSize: T.title, fontWeight: FontWeight.w600)),
              const SizedBox(height: S.sm),
              _SettingsSection(
                group: _group,
                onUpdated: (g) => setState(() => _group = g),
              ),
              const SizedBox(height: S.xl),
            ],
            
            // Leave Group
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _leaveGroup,
                icon: Icon(Icons.logout_rounded, color: c.danger),
                label: Text('Gruptan çık', style: TextStyle(color: c.danger)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _leaveGroup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Gruptan çık'),
        content: Text(
          '"${_group.name}" grubunun işleri bu cihazdan kaldırılacak. '
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

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await ref.read(groupActionsProvider).leave(_group.id);
      if (mounted) nav.pop();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({required this.member});
  final GroupMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final directory = ref.watch(profileDirectoryProvider);
    final profile = directory[member.userId];
    final name = profile?.displayName ?? 'Bilinmiyor';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.xs),
      child: Row(
        children: [
          UserAvatar(profile: profile, userId: member.userId, size: I.xl),
          const SizedBox(width: S.md),
          Text(name, style: TextStyle(color: c.ink, fontSize: T.body)),
          if (member.isOwner) ...[
            const SizedBox(width: S.sm),
            Icon(Icons.star_rounded, size: I.xs, color: c.accent),
          ],
        ],
      ),
    );
  }
}

class _InviteSection extends ConsumerStatefulWidget {
  const _InviteSection({required this.group});
  final Group group;

  @override
  ConsumerState<_InviteSection> createState() => _InviteSectionState();
}

class _InviteSectionState extends ConsumerState<_InviteSection> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _token;

  Future<void> _invite() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final token = await ref
          .read(groupActionsProvider)
          .invite(widget.group.id, email: _email.text.trim());
      await Clipboard.setData(ClipboardData(text: token));
      if (mounted) setState(() => _token = token);
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _email,
                decoration: const InputDecoration(
                  labelText: 'E-posta (isteğe bağlı)',
                  hintText: 'ornek@posta.com',
                ),
              ),
            ),
            const SizedBox(width: S.md),
            OutlinedButton.icon(
              onPressed: _busy ? null : _invite,
              icon: const Icon(Icons.link_rounded, size: I.sm),
              label: const Text('Davet kodu üret'),
            ),
          ],
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
            child: Row(
              children: [
                Icon(Icons.check_rounded, size: I.sm, color: c.accent),
                const SizedBox(width: S.xs),
                Expanded(
                  child: SelectableText(
                    _token!,
                    style: TextStyle(color: c.inkDim, fontFamily: 'monospace'),
                  ),
                ),
                Text('Panoya kopyalandı', style: TextStyle(color: c.accent, fontSize: T.micro)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SettingsSection extends ConsumerStatefulWidget {
  const _SettingsSection({required this.group, required this.onUpdated});
  final Group group;
  final ValueChanged<Group> onUpdated;

  @override
  ConsumerState<_SettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends ConsumerState<_SettingsSection> {
  late TextEditingController _name;
  late TextEditingController _desc;
  late int _colorIndex;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.group.name);
    _desc = TextEditingController(text: widget.group.description ?? '');
    _colorIndex = widget.group.colorIndex ?? 0;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final desc = _desc.text.trim();
      final updated = widget.group.copyWith(
        name: name,
        description: desc.isEmpty ? '' : desc,
        colorIndex: _colorIndex,
      );
      await ref.read(groupActionsProvider).update(updated);
      widget.onUpdated(updated);
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('Ayarlar kaydedildi')));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Grup adı'),
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
                child: selected ? Icon(Icons.check_rounded, size: I.xs, color: inkOn(col)) : null,
              ),
            );
          }),
        ),
        const SizedBox(height: S.md),
        TextField(
          controller: _desc,
          decoration: const InputDecoration(labelText: 'Açıklama'),
        ),
        const SizedBox(height: S.md),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy ? const CircularProgressIndicator() : const Text('Kaydet'),
          ),
        ),
      ],
    );
  }
}
