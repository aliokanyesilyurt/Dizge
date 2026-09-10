import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_service.dart';
import '../core/connectivity.dart';
import '../core/telemetry.dart';
import '../data/persistence_providers.dart';
import '../theme.dart';
import '../widgets/brand_mark.dart';
import '../widgets/google_mark.dart';
import 'account/profile_section.dart';
import 'auth_gate.dart';

/// Karşılama ekranının dört hâli.
///
/// Dördü tek ekranda çünkü hepsi aynı soruyu soruyor: "sen kimsin?". Ayrı
/// sayfalara bölmek, kullanıcıyı kurtarma yolunda üç kez geri tuşu arar hâle
/// getirirdi.
enum _Mode {
  signIn,
  signUp,

  /// Parola unutuldu: e-posta alınır, kod gönderilir.
  recoverRequest,

  /// Kod bekleniyor.
  recoverVerify,
}

/// Oturum açılmamışken görülen tek ekran.
///
/// Eskiden bu form Hesap ekranında bir alt sayfaydı (`_SignInSheet`) ve girmek
/// isteğe bağlıydı. Kapı geldiğinde alt sayfanın yeri kalmadı: giriş artık
/// uygulamanın bir ayarı değil, kapısı.
///
/// Başarılı girişten sonra burada **hiçbir yönlendirme yok**: `AuthGate`
/// oturumu izliyor ve ekranı kendisi değiştiriyor. Buradan `Navigator.push`
/// etmek, oturumun iki ayrı yerden yönetilmesi demek olurdu.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _passwordFocus = FocusNode();

  late _Mode _mode;
  bool _busy = false;

  /// Google akışı ayrı bir bayrak taşıyor: iki düğme var ve dönen halkanın
  /// hangisinin üstünde olduğu, kullanıcının neyi beklediğini söylüyor.
  bool _googleBusy = false;
  String? _error;
  String? _info;

  /// Bir iş sürerken bütün form kilitlenir. Tarayıcı açılırken form alanlarını
  /// açık bırakmak, kullanıcıyı iki yerde birden giriş yapıyor sanmaya
  /// bırakırdı.
  bool get _locked => _busy || _googleBusy;

  @override
  void initState() {
    super.initState();

    // T3a — ilk kare "kayıt", "giriş" değil. Uygulamayı ilk kez açan kişiye
    // "Giriş yap" yazan bir düğme göstermek, huninin ilk adımında ondan bir
    // keşif istemek demekti: hesabı yok ve önce alttaki bağlantıyı bulması
    // gerekiyordu.
    final seenBefore =
        ref.read(localStoreProvider).readString(kHasSignedInKey) == 'yes';
    _mode = seenBefore ? _Mode.signIn : _Mode.signUp;

    ref
        .read(telemetryProvider)
        .capture(Ev.welcomeSeen, props: {'returning': seenBefore});
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _goTo(_Mode mode) => setState(() {
    _mode = mode;
    _error = null;
    _info = null;
  });

  Future<void> _submit() async {
    final email = _email.text.trim();

    // Sunucuya gitmeden yakalanabilecek hatalar. Ağ turu beklemek ve İngilizce
    // bir sunucu mesajı almak gereksiz.
    if (!email.contains('@') || email.length < 3) {
      setState(() => _error = 'Geçerli bir e-posta gir.');
      return;
    }
    if (_mode == _Mode.signIn || _mode == _Mode.signUp) {
      if (_password.text.length < 6) {
        setState(() => _error = 'Parola en az 6 karakter olmalı.');
        return;
      }
    }
    if (_mode == _Mode.recoverVerify && _code.text.trim().length < 6) {
      setState(() => _error = 'Kod 6 haneli.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });

    try {
      final auth = ref.read(authServiceProvider);
      final telemetry = ref.read(telemetryProvider);
      switch (_mode) {
        case _Mode.signIn:
          await auth.signIn(email: email, password: _password.text);
          telemetry.capture(Ev.signInSucceeded);
        case _Mode.signUp:
          // Gönderim ve başarı ayrı ölçülüyor: aradaki fark "denedi ama
          // olmadı" demek ve huninin en çok şey öğreten adımı orası.
          telemetry.capture(Ev.signupSubmitted);
          await auth.signUp(email: email, password: _password.text);
          telemetry.capture(Ev.signupSucceeded);
        case _Mode.recoverRequest:
          await auth.sendRecoveryCode(email);
          if (mounted) {
            setState(() {
              _mode = _Mode.recoverVerify;
              _info = '$email adresine bir kod gönderdik.';
            });
          }
        case _Mode.recoverVerify:
          await auth.verifyRecoveryCode(email: email, code: _code.text);
      }
      // Başarı hâlinde ekranı değiştirmiyoruz — AuthGate yapıyor.
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Tarayıcıyı açar ve bırakır.
  ///
  /// Burada `await`'in bittiği yer **giriş değil, tarayıcının açılması**
  /// (G8a). Oturum dönüşte `AuthGate`'in dinlediği akıştan gelir; bu ekran
  /// kendini kapatmaz.
  Future<void> _signInWithGoogle() async {
    setState(() {
      _googleBusy = true;
      _error = null;
      _info = null;
    });

    try {
      ref.read(telemetryProvider).capture(Ev.googleSignInStarted);
      await ref.read(authServiceProvider).signInWithGoogle();
      if (mounted) {
        setState(
          () =>
              _info = 'Tarayıcıda girişi tamamla, sonra bu pencereye geri dön.',
        );
      }
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  /// Hesapsız devam: önce "sen kimsin", sonra takvim.
  ///
  /// Soru sorulmasının sebebi kozmetik değil. Misafirin de bir rozeti var
  /// (kendi yazdığı işlerin üstünde) ve varsayılan bırakılırsa herkes aynı
  /// "Misafir" ve aynı renk olurdu — cihazı iki kişi kullandığında kimin ne
  /// yazdığı kaybolurdu.
  ///
  /// Diyalog kendi durumunu `StatefulBuilder` ile tutuyor: seçilen renk
  /// diyaloğun ömründen uzun yaşamamalı, vazgeçilirse hiçbir yere yazılmamalı.
  Future<void> _continueAsGuest() async {
    final nameController = TextEditingController(text: 'Misafir');
    var colorIdx = 0;

    try {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Misafir profilin'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    hintText: 'Adın ne olsun?',
                    isDense: true,
                    counterText: '',
                  ),
                ),
                const SizedBox(height: S.lg),
                Text(
                  'Rozet rengi',
                  style: TextStyle(
                    color: ctx.colors.ink,
                    fontSize: T.body,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: S.sm),
                AvatarSwatches(
                  selected: colorIdx,
                  onPick: (i) => setDialogState(() => colorIdx = i),
                ),
                const SizedBox(height: S.sm),
                Text(
                  'Bunlar bu cihazda kalır; sunucuya gitmez.',
                  style: TextStyle(
                    color: ctx.colors.inkFaint,
                    fontSize: T.caption,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Başla'),
              ),
            ],
          ),
        ),
      );

      if (proceed != true) return;

      // Boş ad `guestProfileProvider`'da zaten 'Misafir'e düşüyor; yine de
      // kırpılmış hâli yazılıyor ki depoda baştaki/sondaki boşluklar kalmasın.
      final store = ref.read(localStoreProvider);
      await store.writeString(kGuestNameKey, nameController.text.trim());
      await store.writeString(kGuestColorKey, colorIdx.toString());
      await ref.read(guestModeProvider.notifier).enterGuestMode();
    } finally {
      // Diyalog nasıl kapanırsa kapansın — vazgeçilerek, geri tuşuyla ya da
      // bir hata atılarak — denetleyici serbest bırakılır.
      nameController.dispose();
    }
  }

  // --- Metinler --------------------------------------------------------------

  String get _title => switch (_mode) {
    _Mode.signIn || _Mode.signUp => 'Programın, her cihazında.',
    _Mode.recoverRequest => 'Parolanı mı unuttun?',
    _Mode.recoverVerify => 'Kodu gir',
  };

  String get _subtitle => switch (_mode) {
    _Mode.signIn || _Mode.signUp =>
      'Planların bu cihazda şifreli durur; hesabın onları cihazların arasında '
          'taşır ve yedekler.',
    _Mode.recoverRequest =>
      'E-postana tek kullanımlık bir kod göndereceğiz. Kodla girdikten sonra '
          'parolanı Hesap ekranından değiştirebilirsin.',
    _Mode.recoverVerify => 'Kod birkaç dakika geçerli.',
  };

  String get _action => switch (_mode) {
    _Mode.signIn => 'Giriş yap',
    _Mode.signUp => 'Hesap oluştur',
    _Mode.recoverRequest => 'Kod gönder',
    _Mode.recoverVerify => 'Doğrula ve gir',
  };

  IconData get _actionIcon => switch (_mode) {
    _Mode.signIn || _Mode.signUp => Icons.mail_outline_rounded,
    _Mode.recoverRequest => Icons.send_rounded,
    _Mode.recoverVerify => Icons.verified_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final recovering =
        _mode == _Mode.recoverRequest || _mode == _Mode.recoverVerify;
    final offline =
        ref.watch(networkStatusProvider).valueOrNull == NetworkStatus.offline;

    // Google dönüşündeki hata çağrıya değil **akışa** düşer (bkz.
    // `AuthService.signInWithGoogle`). Yalnız çağrı dinlenseydi, sağlayıcı
    // kapalıyken kullanıcı tarayıcıya gidip boş dönerdi ve bu ekran hiçbir şey
    // olmamış gibi durur — G8d'nin kapattığı delik tam burası.
    ref.listen<AsyncValue<AuthUser?>>(authUserProvider, (previous, next) {
      final error = next.error;
      if (error == null) return;
      setState(() {
        _googleBusy = false;
        _info = null;
        _error = error is AuthFailure
            ? error.message
            : 'Giriş tamamlanamadı. Tekrar dene.';
      });
    });

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            // Klavye açıldığında form onun altında kalmasın.
            padding: EdgeInsets.fromLTRB(
              24,
              32,
              24,
              32 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: BrandMark(size: I.hero)),
                    const SizedBox(height: S.xl),
                    Text(
                      _title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.ink,
                        fontSize: T.display,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: S.sm),
                    Text(
                      _subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.inkFaint,
                        fontSize: T.body,
                        fontWeight: FontWeight.w500,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: S.xxl),

                    // Kod adımında e-posta alanı gizli: kullanıcı onu az önce
                    // yazdı ve değiştirmesi kodu geçersiz kılardı.
                    if (_mode != _Mode.recoverVerify)
                      TextField(
                        controller: _email,
                        enabled: !_locked,
                        autofocus: true,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _mode == _Mode.recoverRequest
                            ? _submit()
                            : _passwordFocus.requestFocus(),
                        decoration: const InputDecoration(hintText: 'E-posta'),
                      ),

                    if (_mode == _Mode.signIn || _mode == _Mode.signUp) ...[
                      const SizedBox(height: S.sm),
                      TextField(
                        controller: _password,
                        focusNode: _passwordFocus,
                        enabled: !_locked,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _locked ? null : _submit(),
                        decoration: const InputDecoration(hintText: 'Parola'),
                      ),
                    ],

                    if (_mode == _Mode.recoverVerify)
                      TextField(
                        controller: _code,
                        enabled: !_locked,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        autofillHints: const [AutofillHints.oneTimeCode],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _locked ? null : _submit(),
                        decoration: const InputDecoration(
                          hintText: '6 haneli kod',
                        ),
                      ),

                    if (_info != null) ...[
                      const SizedBox(height: S.md),
                      Text(
                        _info!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: c.inkDim,
                          fontSize: T.caption,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: S.md),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: I.sm,
                            color: c.danger,
                          ),
                          const SizedBox(width: S.sm),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: c.danger,
                                fontSize: T.caption,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: S.lg),
                    // E-posta yolu zarfla, Google yolu G ile, misafir kişiyle:
                    // üç kapı aynı dili konuşuyor, hangisinin ne olduğu
                    // yazıyı okumadan da seçiliyor.
                    FilledButton(
                      onPressed: _locked ? null : _submit,
                      child: IconLabel(
                        icon: _busy
                            ? SizedBox(
                                width: I.sm,
                                height: I.sm,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: c.onAccent,
                                ),
                              )
                            : Icon(_actionIcon, size: I.sm),
                        text: _action,
                      ),
                    ),

                    // Kurtarma adımlarında yok: orada soru "sen kimsin" değil,
                    // "bu adrese gelen kodu girebiliyor musun". Araya bir
                    // Google düğmesi koymak, parolasını unutan kullanıcıyı
                    // üçüncü bir yola saptırırdı.
                    if (!recovering) ...[
                      const SizedBox(height: S.lg),
                      Row(
                        children: [
                          Expanded(
                            child: Divider(color: c.lineSoft, height: 1),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: S.sm,
                            ),
                            child: Text(
                              'ya da',
                              style: TextStyle(
                                color: c.inkFaint,
                                fontSize: T.micro,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(color: c.lineSoft, height: 1),
                          ),
                        ],
                      ),
                      const SizedBox(height: S.lg),
                      // Düğme sağlayıcı kapalıyken de görünür (G8d): bir
                      // yapılandırma bayrağı, tek kişilik bir projede
                      // unutulacak ikinci bir anahtar olurdu. Kapalıysa
                      // kullanıcı sebebini yukarıdaki hata satırında okur.
                      OutlinedButton(
                        onPressed: _locked || offline
                            ? null
                            : _signInWithGoogle,
                        child: IconLabel(
                          icon: _googleBusy
                              ? SizedBox(
                                  width: I.sm,
                                  height: I.sm,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: c.inkDim,
                                  ),
                                )
                              : const GoogleMark(size: I.sm),
                          text: 'Google ile devam et',
                        ),
                      ),
                      if (offline) ...[
                        const SizedBox(height: S.sm),
                        Text(
                          'Google girişi tarayıcı üzerinden olur; çevrimdışıyken '
                          'çalışmaz.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: c.inkFaint,
                            fontSize: T.micro,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: S.sm),
                      OutlinedButton(
                        onPressed: _locked ? null : _continueAsGuest,
                        child: const IconLabel(
                          icon: Icon(Icons.person_outline_rounded, size: I.sm),
                          text: 'Misafir olarak devam et',
                        ),
                      ),
                    ],

                    const SizedBox(height: S.xs),
                    if (recovering)
                      TextButton(
                        onPressed: _locked ? null : () => _goTo(_Mode.signIn),
                        child: const Text('Girişe dön'),
                      )
                    else ...[
                      TextButton(
                        onPressed: _locked
                            ? null
                            : () => _goTo(
                                _mode == _Mode.signUp
                                    ? _Mode.signIn
                                    : _Mode.signUp,
                              ),
                        child: Text(
                          _mode == _Mode.signUp
                              ? 'Zaten hesabım var'
                              : 'Hesabım yok, oluşturayım',
                        ),
                      ),
                      // Kurtarma yolu kapının parçası: sert kapıda unutulan
                      // parola, veriye kalıcı olarak erişilememesi demek.
                      if (_mode == _Mode.signIn)
                        TextButton(
                          onPressed: _locked
                              ? null
                              : () => _goTo(_Mode.recoverRequest),
                          child: const Text('Parolamı unuttum'),
                        ),
                    ],

                    const SizedBox(height: S.lg),
                    // Kapının tek gerçek maliyeti (G1). Kullanıcı bunu hata
                    // ekranında değil, burada öğrenmeli.
                    Text(
                      'İlk girişte internet gerekir. Sonrasında uygulama '
                      'çevrimdışı da açılır.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.inkFaint,
                        fontSize: T.micro,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Düğme etiketi: simge + metin.
///
/// `FilledButton.icon` yerine düz düğmenin çocuğu: `.icon` yapıcıları başka
/// bir alt tür üretiyor ve düğmeyi türüyle arayan her şey (testler,
/// erişilebilirlik denetimleri) onu kaçırıyordu.
class IconLabel extends StatelessWidget {
  const IconLabel({super.key, required this.icon, required this.text});

  final Widget icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      icon,
      const SizedBox(width: S.sm),
      Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
    ],
  );
}
