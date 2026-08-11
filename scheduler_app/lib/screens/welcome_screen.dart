import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_service.dart';
import '../theme.dart';
import '../widgets/brand_mark.dart';

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

  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  String? _error;
  String? _info;

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
      switch (_mode) {
        case _Mode.signIn:
          await auth.signIn(email: email, password: _password.text);
        case _Mode.signUp:
          await auth.signUp(email: email, password: _password.text);
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final recovering =
        _mode == _Mode.recoverRequest || _mode == _Mode.recoverVerify;

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
                    const Center(child: BrandMark(size: 56)),
                    const SizedBox(height: 24),
                    Text(
                      _title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.inkFaint,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 30),

                    // Kod adımında e-posta alanı gizli: kullanıcı onu az önce
                    // yazdı ve değiştirmesi kodu geçersiz kılardı.
                    if (_mode != _Mode.recoverVerify)
                      TextField(
                        controller: _email,
                        enabled: !_busy,
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
                      const SizedBox(height: 10),
                      TextField(
                        controller: _password,
                        focusNode: _passwordFocus,
                        enabled: !_busy,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _busy ? null : _submit(),
                        decoration: const InputDecoration(hintText: 'Parola'),
                      ),
                    ],

                    if (_mode == _Mode.recoverVerify)
                      TextField(
                        controller: _code,
                        enabled: !_busy,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        autofillHints: const [AutofillHints.oneTimeCode],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _busy ? null : _submit(),
                        decoration: const InputDecoration(
                          hintText: '6 haneli kod',
                        ),
                      ),

                    if (_info != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _info!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: c.inkDim,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 16,
                            color: c.danger,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: c.danger,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: c.onAccent,
                              ),
                            )
                          : Text(_action),
                    ),

                    const SizedBox(height: 6),
                    if (recovering)
                      TextButton(
                        onPressed: _busy ? null : () => _goTo(_Mode.signIn),
                        child: const Text('Girişe dön'),
                      )
                    else ...[
                      TextButton(
                        onPressed: _busy
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
                          onPressed: _busy
                              ? null
                              : () => _goTo(_Mode.recoverRequest),
                          child: const Text('Parolamı unuttum'),
                        ),
                    ],

                    const SizedBox(height: 20),
                    // Kapının tek gerçek maliyeti (G1). Kullanıcı bunu hata
                    // ekranında değil, burada öğrenmeli.
                    Text(
                      'İlk girişte internet gerekir. Sonrasında uygulama '
                      'çevrimdışı da açılır.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.inkFaint,
                        fontSize: 11.5,
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
