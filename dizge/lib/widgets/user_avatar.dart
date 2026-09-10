import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../theme.dart';

/// Bir kişiyi tek bir dairede anlatan işaret (Y4.4c).
///
/// Üç durumu da kendi içinde çözer:
///
///   1. fotoğraf varsa fotoğraf,
///   2. yoksa (ya da inemezse) kimlikten türeyen renkli baş harfler,
///   3. profil hiç bilinmiyorsa nötr `?`.
///
/// **Fotoğraf diske yazılmıyor.** `cached_network_image` eklemek, başkasının
/// fotoğrafını kullanıcının cihazında kalıcılaştırmak olurdu; bir rozet için
/// ağır bir borç. Flutter'ın bellek içi `ImageCache`'i oturum boyunca yeter:
/// uygulama açıkken fotoğraf bir kez iner. Çevrimdışı açılışta baş harfler
/// görünür — bu bir kusur değil, bilinçli sınır (plan §3).
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.profile,
    required this.userId,
    this.size = 20,
    this.showTooltip = true,
  });

  /// Bilinen profil; null ise `?` rozeti çizilir.
  final Profile? profile;

  /// Renk buradan türer — profil bilinmese bile kişi hep aynı renkte görünür.
  final String? userId;

  final double size;

  /// Tam adı asılı ipucunda göstersin mi. Ad zaten yanında yazılıyorsa
  /// (önizleme, hesap ekranı) kapatılır: aynı şeyi iki kez söylemek.
  final bool showTooltip;

  /// Rozetin taşıdığı ad. Ekran okuyucu ve ipucu bunu okur.
  String get _label => profile?.label ?? 'Bilinmeyen kişi';

  @override
  Widget build(BuildContext context) {
    // Renk profilin kendi alanından, yoksa kimlikten (`avatarColorOf`).
    // Bir ara burada `userId.startsWith('guest_color_')` diye bir kırpma
    // vardı: misafirin rengi kimliğin **içine** gömülüydü. Kimliğe veri
    // gömmek, ileride `userId` karşılaştıran her yeri sessizce bozar —
    // renk artık `Profile`'ın kendi alanı.
    final fill = avatarColorOf(profile, userId);
    final ink = inkOn(fill);

    // Harf yüksekliği çapın %44'ü: 14px rozette 6.2px, 60px'te 26px. Sabit bir
    // oran, her boyutta elle ayarlanmış bir tabloya yeğ — ara boy eklendiğinde
    // kendiliğinden tutar.
    final letters = Text(
      profile?.initials ?? '?',
      textAlign: TextAlign.center,
      maxLines: 1,
      style: TextStyle(
        color: ink,
        fontSize: size * 0.44,
        height: 1,
        fontWeight: FontWeight.w700,
        // Baş harfler dar bir dairede duruyor; varsayılan aralık iki harfi
        // kenarlara dayıyordu.
        letterSpacing: -0.2,
      ),
    );

    Widget circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      // `clipBehavior` yerine `ClipOval`: fotoğraf daireyi tam doldurmalı,
      // köşelerinden taşmamalı.
      child: ClipOval(child: _content(letters, fill)),
    );

    // Metin ölçeği rozeti büyütmez: 200%'te 14px'lik bir daire bloğun yarısını
    // kaplardı. Tam ad zaten ipucunda ve ekran okuyucuda — bilgi kaybı yok.
    circle = MediaQuery.withNoTextScaling(child: circle);

    // `excludeSemantics`: içerideki baş harf metni de bir düğüm üretiyor ve
    // okuyucu "Ali Okan, A O" derdi. Rozetin anlamı tek bir cümle.
    circle = Semantics(
      label: _label,
      image: true,
      excludeSemantics: true,
      child: circle,
    );

    // Bekleme süresi `Motion.slow`: tasarım sözleşmesi "yeni süre eklenmez"
    // diyor ve mevcut üç süreden bu iş için doğru olanı en uzunu.
    //
    // `excludeFromSemantics`: ipucu kendi etiketini de ağaca koyuyor ve ekran
    // okuyucu adı iki kez okuyordu ("Ali Okan, Ali Okan"). İpucu görsel bir
    // kolaylık; anlamı yukarıdaki [Semantics] taşıyor.
    return showTooltip
        ? Tooltip(
            message: _label,
            waitDuration: Motion.slow,
            excludeFromSemantics: true,
            child: circle,
          )
        : circle;
  }

  Widget _content(Widget letters, Color fill) {
    final url = profile?.avatarUrl;
    if (url == null || url.isEmpty) return letters;

    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      // İnerken **boşluk değil baş harf** duruyor: yerinde bir gri kutu
      // titretmek, listedeki her satırı bir kare boyunca boşaltırdı.
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : letters,
      // Ağ yok, adres ölmüş, hesap silinmiş — hepsinin cevabı aynı ve
      // sessiz: baş harflere dön.
      errorBuilder: (context, error, stack) => letters,
    );
  }
}
