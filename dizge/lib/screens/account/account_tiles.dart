/// Hesap ekranının ortak parçaları: kart kabuğu, durum satırı, uyarı kutusu,
/// grup başlığı ve iki tür satır.
///
/// Hiçbiri durum tutmuyor; bölümlerin hepsi bunları kullanıyor.
library;

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Ayar kartlarının ortak kabuğu: yükseltilmiş yüzey + yumuşak köşe.
class AccountCard extends StatelessWidget {
  const AccountCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: S.sm),
      padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: R.radiusMd,
        border: Border.all(color: c.lineSoft),
        boxShadow: c.shadowSm,
      ),
      child: child,
    );
  }
}

class StatusTile extends StatelessWidget {
  const StatusTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AccountCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: I.md, color: iconColor ?? c.inkDim),
          const SizedBox(width: S.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: c.ink,
                    fontSize: T.strong,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: S.xs),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: c.inkFaint,
                    fontSize: T.micro,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class Notice extends StatelessWidget {
  const Notice({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      padding: const EdgeInsets.all(S.lg),
      decoration: BoxDecoration(color: c.accentSoft, borderRadius: R.radiusMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_rounded, size: I.sm, color: c.navActiveInk),
          const SizedBox(width: S.md),
          Expanded(
            child: Text(
              'Hesap sistemi backend eklendiğinde çalışır hale gelecek. '
              'O zamana kadar uygulama tamamen cihazda, çevrimdışı çalışır.',
              style: TextStyle(
                color: c.isDark ? c.inkDim : c.navActiveInk,
                fontSize: T.caption,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GroupLabel extends StatelessWidget {
  final String text;
  const GroupLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.xs, 0, S.xs, S.sm),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

/// Gerçekten bir şey yapan satır.
///
/// [AccountTile]'dan ayrı duruyor çünkü ikisi karşıt şeyler söylüyor: [AccountTile] sönük
/// ve kilitli ("henüz yok"), bu ise dokunulabilir. Aynı widget'a bayrak
/// eklemek, ekranın en önemli ayrımını bir parametreye gömerdi.
class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: R.radiusMd,
        onTap: onTap,
        child: AccountCard(
          child: Row(
            children: [
              Icon(icon, size: I.md, color: iconColor ?? c.accent),
              const SizedBox(width: S.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: c.ink,
                        fontSize: T.strong,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: S.hair),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: c.inkFaint,
                        fontSize: T.caption,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: I.md, color: c.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class AccountTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const AccountTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Opacity(
      opacity: 0.6,
      child: AccountCard(
        child: Row(
          children: [
            Icon(icon, size: I.md, color: c.inkDim),
            const SizedBox(width: S.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: c.ink,
                      fontSize: T.strong,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: S.hair),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: c.inkFaint,
                      fontSize: T.caption,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.lock_rounded, size: I.xs, color: c.inkFaint),
          ],
        ),
      ),
    );
  }
}
