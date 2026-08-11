import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_service.dart';
import '../theme.dart';
import '../widgets/brand_mark.dart';

/// Oturum açılmamışken görülen tek ekran.
///
/// Eskiden bu form Hesap ekranında bir alt sayfaydı (`_SignInSheet`) ve girmek
/// isteğe bağlıydı. Kapı geldiğinde alt sayfanın yeri kalmadı: giriş artık
/// uygulamanın bir ayarı değil, kapısı. Form mantığı (istemci tarafı
/// doğrulama, [AuthFailure] gösterimi, gönderim kilidi) olduğu gibi taşındı.
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
  final _passwordFocus = FocusNode();

  bool _registering = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;

    // Sunucuya gitmeden yakalanabilecek iki hata. Ağ turu beklemek ve
    // İngilizce bir sunucu mesajı almak gereksiz.
    if (!email.contains('@') || email.length < 3) {
      setState(() => _error = 'Geçerli bir e-posta gir.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Parola en az 6 karakter olmalı.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final auth = ref.read(authServiceProvider);
      if (_registering) {
        await auth.signUp(email: email, password: password);
      } else {
        await auth.signIn(email: email, password: password);
      }
      // Başarı hâlinde ekranı değiştirmiyoruz — AuthGate yapıyor.
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

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
                      'Programın, her cihazında.',
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
                      'Planların bu cihazda şifreli durur; hesabın onları '
                      'cihazların arasında taşır ve yedekler.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.inkFaint,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 30),

                    TextField(
                      controller: _email,
                      enabled: !_busy,
                      autofocus: true,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _passwordFocus.requestFocus(),
                      decoration: const InputDecoration(hintText: 'E-posta'),
                    ),
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
                          : Text(_registering ? 'Hesap oluştur' : 'Giriş yap'),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _registering = !_registering;
                              _error = null;
                            }),
                      child: Text(
                        _registering
                            ? 'Zaten hesabım var'
                            : 'Hesabım yok, oluşturayım',
                      ),
                    ),

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
