import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/group_context.dart';
import '../core/profile_directory.dart';
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
