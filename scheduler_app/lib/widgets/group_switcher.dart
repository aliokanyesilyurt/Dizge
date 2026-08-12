import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/group_context.dart';
import '../theme.dart';

/// Kenar çubuğundaki bağlam seçici: "Kişisel" ile grup adları arasında geçiş.
///
/// **Grubu olmayan kullanıcıda hiç görünmez.** Planın en büyük riski "kişisel
/// görünüm grup işlerini sessizce gizler" idi; hiç grup yokken gizlenebilecek
/// bir iş de yok, o yüzden seçici o durumda yalnız gürültü olurdu. Bir grup
/// belirdiği anda seçici de belirir ve **hep açıkta durur**: sorunun cevabı
/// ("işlerim nerede?") ekranın sabit bir yerinde yazılı olmalı.
///
/// Bağlam bir süzgeç, ikinci bir depo değil (Y4b) — seçim yalnız neyin
/// gösterildiğini değiştirir, veri tek yerde durur.
class GroupSwitcher extends ConsumerWidget {
  const GroupSwitcher({super.key, required this.collapsed});

  /// Daraltılmış kenar çubuğunda yalnız simge + ipucu görünür.
  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctx = ref.watch(groupContextProvider);
    if (ctx.groups.isEmpty) return const SizedBox.shrink();

    final c = context.colors;
    final inGroup = !ctx.isPersonal;
    final icon = inGroup ? Icons.groups_rounded : Icons.person_outline_rounded;
    // Grup bağlamı vurgulu: bir süzgecin açık olduğu, ada bakmadan da
    // anlaşılmalı.
    final ink = inGroup ? c.navActiveInk : c.inkDim;

    final button = PopupMenuButton<String>(
      tooltip: '',
      position: PopupMenuPosition.under,
      color: c.surfaceAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
      // Boş dize = Kişisel. `null` kullanılamaz: PopupMenuButton null'ı
      // "vazgeçildi" sayar ve seçim hiç ulaşmazdı.
      onSelected: (id) => ref
          .read(groupContextProvider.notifier)
          .select(id.isEmpty ? null : id),
      itemBuilder: (_) => [
        _entry(context, id: '', label: 'Kişisel', active: ctx.isPersonal),
        for (final g in ctx.groups)
          _entry(
            context,
            id: g.id,
            label: g.name,
            active: g.id == ctx.activeId,
          ),
      ],
      child: AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.curve,
        padding: EdgeInsets.symmetric(
          horizontal: collapsed ? 0 : 12,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: inGroup ? c.navActiveFill : c.sidebarHover,
          borderRadius: R.radiusPill,
        ),
        child: collapsed
            ? Center(child: Icon(icon, size: 18, color: ink))
            : Row(
                children: [
                  Icon(icon, size: 18, color: ink),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      ctx.label,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: TextStyle(
                        color: ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                  Icon(Icons.unfold_more_rounded, size: 15, color: c.inkFaint),
                ],
              ),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        collapsed ? 12 : 14,
        0,
        collapsed ? 12 : 14,
        10,
      ),
      // Daraltılmışken ad görünmüyor; hangi bağlamda olunduğu ipucunda kalsın.
      child: collapsed ? Tooltip(message: ctx.label, child: button) : button,
    );
  }

  PopupMenuItem<String> _entry(
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
            size: 17,
            color: active ? c.navActiveInk : c.inkFaint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? c.navActiveInk : c.ink,
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          if (active)
            Icon(Icons.check_rounded, size: 15, color: c.navActiveInk),
        ],
      ),
    );
  }
}
