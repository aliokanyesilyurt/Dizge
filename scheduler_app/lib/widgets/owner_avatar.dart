import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/group_context.dart';
import '../core/profile_directory.dart';
import '../theme.dart';
import 'user_avatar.dart';

/// Bir işin **sahibini** gösteren rozet (Y4.4d).
///
/// Kişisel bağlamda kendini gizler ve bu kararın tamamı burada durur: her
/// yüzeyin ayrı ayrı "grupta mıyım" diye sorması, dört ekranda dört kez
/// unutulabilecek bir kural olurdu. Kişisel görünümde zaten her satır senin;
/// oradaki avatar yalnız gürültü.
///
/// Grup bağlamında **herkes** rozet taşır, seninkiler dahil. Alternatif
/// ("yalnız başkalarınınkiler işaretlensin") daha sessiz görünüyor ama
/// işaretin yokluğunu anlamlı kılardı: öğrenilmesi gereken sessiz bir kural,
/// ve boş bir haftada öğrenilemez.
class OwnerAvatar extends ConsumerWidget {
  const OwnerAvatar({super.key, required this.ownerId, this.size = 14});

  /// Satırın sahibi. Sunucu yazıyor; yerelde üretilmiş ve henüz gönderilmemiş
  /// bir işte **null** olur — o durumda da rozet çizilmez: iş zaten senin ve
  /// bir kare sonra sunucudan kimliğiyle dönecek.
  final String? ownerId;

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inGroup = ref.watch(activeGroupIdProvider) != null;
    if (!inGroup || ownerId == null || ownerId!.isEmpty) {
      return const SizedBox.shrink();
    }

    return UserAvatar(
      profile: ref.watch(profileProvider(ownerId)),
      userId: ownerId,
      size: size,
    );
  }
}

/// Sahibin **tam adı**, grup bağlamında; kişisel bağlamda null.
///
/// Rozet yüzeyde, ad detayda: 14px'lik bir dairede "Ali Okan" yazamayız ama
/// önizlemede, düzenleyicide ve ekran okuyucuda kısaltmaya gerek de yok.
///
/// Bir widget değil düz bir işlev, çünkü çağıranların biri metin cümlesi
/// kuruyor (ekran okuyucu), diğeri satır çiziyor.
String? ownerNameFor(WidgetRef ref, String? ownerId) {
  if (ownerId == null || ownerId.isEmpty) return null;
  if (ref.watch(activeGroupIdProvider) == null) return null;
  return ref.watch(profileProvider(ownerId))?.label ?? 'Bilinmeyen kişi';
}

/// Detay yüzeylerinde "kimin işi" satırı: rozet + tam ad (Y4.4f).
///
/// Kişisel bağlamda hiç çizilmez — [OwnerAvatar] ile aynı kural, aynı sebep.
class OwnerLine extends ConsumerWidget {
  const OwnerLine({super.key, required this.ownerId, this.style});

  final String? ownerId;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ownerNameFor(ref, ownerId);
    if (name == null) return const SizedBox.shrink();

    return Row(
      children: [
        // İpucu kapalı: ad zaten hemen yanında yazıyor.
        UserAvatar(
          profile: ref.watch(profileProvider(ownerId)),
          userId: ownerId,
          size: I.sm,
          showTooltip: false,
        ),
        const SizedBox(width: S.xs),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}
