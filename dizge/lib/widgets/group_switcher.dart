import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/group_context.dart';
import '../screens/auth_gate.dart';
import '../screens/group_create_sheet.dart';
import '../screens/group_screen.dart';
import '../theme.dart';
import 'group_dialogs.dart';

/// Kenar çubuğundaki bağlam seçici: "Kişisel" ile grup adları arasında geçiş,
/// ve grup işlemlerinin (kur / katıl / yönet) tek kapısı.
///
/// **Her zaman görünür**, grup yoksa bile. İki sebep birden: planın en büyük
/// riski "kişisel görünüm grup işlerini sessizce gizler" ve bunun cevabı
/// ekranın sabit bir yerinde durmalı; ayrıca ilk grubun kurulduğu yer de
/// burası — menü gizlenirse hiç grup kurulamazdı.
///
/// Bağlam bir süzgeç, ikinci bir depo değil (Y4b) — seçim yalnız neyin
/// gösterildiğini değiştirir, veri tek yerde durur.
class GroupSwitcher extends ConsumerWidget {
  const GroupSwitcher({super.key, required this.collapsed});

  /// Daraltılmış kenar çubuğunda yalnız simge + ipucu görünür.
  final bool collapsed;

  /// Menüdeki eylem satırlarının değerleri. Grup kimlikleriyle çakışmamaları
  /// için `#` ile başlıyorlar — uuid hiçbir zaman böyle başlamaz.
  static const _yeni = '#yeni';
  static const _katil = '#katil';
  static const _yonet = '#yonet';

  /// Boş dize = Kişisel. `null` kullanılamaz: PopupMenuButton null'ı
  /// "vazgeçildi" sayar ve seçim hiç ulaşmazdı.
  static const _kisisel = '';

  void _onSelected(BuildContext context, WidgetRef ref, String value) {
    switch (value) {
      case _yeni:
        showModalBottomSheet(
          context: context,
          builder: (_) => const GroupCreateSheet(),
          isScrollControlled: true,
        );
      case _katil:
        showAcceptInviteDialog(context);
      case _yonet:
        final active = ref.read(groupContextProvider).active;
        if (active != null) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => GroupScreen(group: active),
          ));
        }
      default:
        ref
            .read(groupContextProvider.notifier)
            .select(value.isEmpty ? null : value);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGuest = ref.watch(guestModeProvider);
    final ctx = ref.watch(groupContextProvider);
    final c = context.colors;
    final inGroup = !ctx.isPersonal;
    final icon = inGroup ? Icons.groups_rounded : Icons.person_outline_rounded;
    // Grup bağlamı vurgulu: bir süzgecin açık olduğu, ada bakmadan da
    // anlaşılmalı.
    final ink = isGuest ? c.inkFaint : (inGroup ? c.navActiveInk : c.inkDim);

    final button = PopupMenuButton<String>(
      enabled: !isGuest,
      tooltip: isGuest ? 'Gruplar için oturum açmalısın' : '',
      position: PopupMenuPosition.under,
      color: c.surfaceAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
      onSelected: (value) => _onSelected(context, ref, value),
      itemBuilder: (_) => [
_context(
          context,
          id: '*all*',
          label: 'Tüm İşler',
          active: ctx.activeId == '*all*',
        ),
        _context(
          context,
          id: _kisisel,
          label: 'Kişisel',
          active: ctx.isPersonal,
        ),
        for (final g in ctx.groups)
          _context(
            context,
            id: g.id,
            label: g.name,
            active: g.id == ctx.activeId,
          ),
        const PopupMenuDivider(),
        _action(
          context,
          value: _yeni,
          icon: Icons.add_rounded,
          label: 'Yeni grup…',
        ),
        _action(
          context,
          value: _katil,
          icon: Icons.mail_outline_rounded,
          label: 'Daveti kabul et…',
        ),
        // Yönetim yalnız bir grubun içindeyken anlamlı: "Kişisel"in davet
        // edilecek üyesi ya da çıkılacak bir kapısı yok.
        if (inGroup)
          _action(
            context,
            value: _yonet,
            icon: Icons.group_rounded,
            label: 'Grup sayfası',
          ),
      ],
      child: AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.curve,
        padding: EdgeInsets.symmetric(
          horizontal: collapsed ? 0 : S.md,
          vertical: S.sm,
        ),
        decoration: BoxDecoration(
          color: inGroup ? c.navActiveFill : c.sidebarHover,
          borderRadius: R.radiusPill,
        ),
        child: collapsed
            ? Center(
                child: Icon(icon, size: I.md, color: ink),
              )
            : Row(
                children: [
                  Icon(icon, size: I.md, color: ink),
                  const SizedBox(width: S.sm),
                  Expanded(
                    child: Text(
                      ctx.label,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: TextStyle(
                        color: ink,
                        fontSize: T.body,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.unfold_more_rounded,
                    size: I.sm,
                    color: c.inkFaint,
                  ),
                ],
              ),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        collapsed ? S.md : S.md,
        0,
        collapsed ? S.md : S.md,
        S.sm,
      ),
      // Daraltılmışken ad görünmüyor; hangi bağlamda olunduğu ipucunda kalsın.
      child: collapsed ? Tooltip(message: ctx.label, child: button) : button,
    );
  }

  /// Bağlam satırı: seçilince süzgeç değişir.
  PopupMenuItem<String> _context(
    BuildContext context, {
    required String id,
    required String label,
    required bool active,
  }) {
    final c = context.colors;
    return PopupMenuItem<String>(
      value: id,
      height: 42,
      child: Row(
        children: [
          Icon(
            id.isEmpty ? Icons.person_outline_rounded : Icons.groups_rounded,
            size: I.sm,
            color: active ? c.navActiveInk : c.inkFaint,
          ),
          const SizedBox(width: S.sm),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? c.navActiveInk : c.ink,
                fontSize: T.body,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          if (active)
            Icon(Icons.check_rounded, size: I.sm, color: c.navActiveInk),
        ],
      ),
    );
  }

  /// Eylem satırı: seçilince diyalog açar. Bağlam satırlarından soluk tonuyla
  /// ayrılıyor — biri "nereye bakıyorum", öteki "ne yapıyorum".
  PopupMenuItem<String> _action(
    BuildContext context, {
    required String value,
    required IconData icon,
    required String label,
  }) {
    final c = context.colors;
    return PopupMenuItem<String>(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: I.sm, color: c.inkFaint),
          const SizedBox(width: S.sm),
          Text(
            label,
            style: TextStyle(
              color: c.inkDim,
              fontSize: T.caption,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
