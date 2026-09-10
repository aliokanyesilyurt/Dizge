/// Parola ekranları (P3, P4).
///
///   * [SetNewPasswordScreen] — kurtarma kodundan sonra, takvimden önce.
///   * [ChangePasswordScreen] — Hesap ekranından; mevcut parola ya da
///     e-postaya giden kodla doğrulanır.
///
/// İkisi de ayrı sayfa, diyalog değil: üç alan, kural listesi, güç göstergesi
/// ve bir seçenek dar bir diyaloğa sığmıyordu. Eski diyalog tek alan soruyor,
/// ne eski parolayı ne tekrarı istiyordu — oturumu açık bırakılmış bir
/// cihazda herkes parolayı değiştirebiliyordu.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_service.dart';
import '../core/password_policy.dart';
import '../theme.dart';
import '../widgets/password_fields.dart';

/// Kurtarma kodu doğrulandıktan sonra kapının gösterdiği ekran.
///
/// Kapı [passwordResetPendingProvider] yanarken takvim yerine bunu çiziyor;
/// bayrak sönünce (kaydet ya da "şimdilik geç") takvim açılıyor.
class SetNewPasswordScreen extends ConsumerStatefulWidget {
  const SetNewPasswordScreen({super.key});

  @override
  ConsumerState<SetNewPasswordScreen> createState() =>
      _SetNewPasswordScreenState();
}

class _SetNewPasswordScreenState extends ConsumerState<SetNewPasswordScreen> {
  final _password = TextEditingController();
  final _repeat = TextEditingController();

  /// Parolasını unutan kişinin en olası sebebi "başka biri biliyor olabilir"
  /// değil ama maliyeti düşük: varsayılan açık.
  bool _signOutOthers = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!newPasswordReady(_password.text, _repeat.text)) {
      setState(
        () => _error = passwordAcceptableMessage(_password.text, _repeat.text),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = ref.read(authServiceProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await auth.updatePassword(_password.text);
      if (_signOutOthers) await auth.signOutOtherSessions();
      ref.read(passwordResetPendingProvider.notifier).state = false;
      messenger?.showSnackBar(
        const SnackBar(content: Text('Yeni parolan kaydedildi.')),
      );
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(authUserProvider).valueOrNull?.email ?? '';

    return _FormPage(
      icon: Icons.lock_reset_rounded,
      title: 'Yeni parolanı belirle',
      subtitle: email.isEmpty
          ? 'Kod doğrulandı. Şimdi yeni parolanı seç.'
          : 'Kod doğrulandı: $email. Şimdi yeni parolanı seç.',
      children: [
        NewPasswordFields(
          password: _password,
          repeat: _repeat,
          enabled: !_busy,
          autofocus: true,
          onSubmitted: _save,
        ),
        const SizedBox(height: S.md),
        _SignOutOthersBox(
          value: _signOutOthers,
          enabled: !_busy,
          onChanged: (v) => setState(() => _signOutOthers = v),
        ),
        if (_error != null) _ErrorLine(_error!),
        const SizedBox(height: S.lg),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy ? const _Spinner() : const Text('Parolayı kaydet'),
        ),
        const SizedBox(height: S.xs),
        TextButton(
          onPressed: _busy
              ? null
              : () => ref.read(passwordResetPendingProvider.notifier).state =
                    false,
          child: const Text('Şimdilik geç'),
        ),
      ],
    );
  }
}

/// Kurala uymayan ya da eşleşmeyen yeni parola için tek cümle.
String passwordAcceptableMessage(String password, String repeat) {
  if (!passwordAcceptable(password)) {
    return 'Parola kurala uymuyor: en az 8 karakter, harf ve rakam içermeli.';
  }
  return 'Parolalar aynı değil.';
}

// --- Parola değiştir -----------------------------------------------------------

Future<void> showChangePasswordScreen(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const ChangePasswordScreen()));

/// Doğrulamanın iki yolu. Google ile açılmış hesapta mevcut parola yok; o
/// hesap doğrudan kod yolundan başlıyor.
enum _Verify { current, code }

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();

  late _Verify _verify;
  bool _codeSent = false;
  bool _signOutOthers = false;
  bool _busy = false;
  String? _error;
  String? _info;

  /// Yeniden kod isteme beklemesi. Sağlayıcı zaten ~60 sn'den sık izin
  /// vermiyor; düğmeyi o süre boyunca kapalı tutmak, "bastım ama gelmedi"
  /// ile "sunucu reddetti" arasındaki farkı kullanıcıya yüklemiyor.
  int _cooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    // Akış henüz ilk değerini vermemiş olabilir; servisin anlık kullanıcısı
    // eşzamanlı. Yoksa Google hesabı bir kare "mevcut parola" sorardı.
    final user =
        ref.read(authUserProvider).valueOrNull ??
        ref.read(authServiceProvider).currentUser;
    _verify = (user?.hasPassword ?? true) ? _Verify.current : _Verify.code;
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _current.dispose();
    _code.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).sendReauthCode();
      if (!mounted) return;
      final email = ref.read(authUserProvider).valueOrNull?.email ?? '';
      setState(() {
        _verify = _Verify.code;
        _codeSent = true;
        _info = email.isEmpty
            ? 'E-postana 6 haneli bir kod gönderdik.'
            : '$email adresine 6 haneli bir kod gönderdik.';
      });
      _startCooldown();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final auth = ref.read(authServiceProvider);

    if (_verify == _Verify.current && _current.text.isEmpty) {
      setState(() => _error = 'Mevcut parolanı yaz.');
      return;
    }
    if (_verify == _Verify.code && _code.text.trim().length < 6) {
      setState(() => _error = 'E-postana gelen 6 haneli kodu yaz.');
      return;
    }
    if (!newPasswordReady(_password.text, _repeat.text)) {
      setState(
        () => _error = passwordAcceptableMessage(_password.text, _repeat.text),
      );
      return;
    }
    if (_verify == _Verify.current && _current.text == _password.text) {
      setState(() => _error = 'Yeni parola eskisiyle aynı olamaz.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_verify == _Verify.current) {
        // Önce doğrula: yanlışsa hiçbir şey değişmez.
        await auth.verifyCurrentPassword(_current.text);
        await auth.updatePassword(_password.text, current: _current.text);
      } else {
        await auth.updatePassword(_password.text, code: _code.text);
      }
      if (_signOutOthers) await auth.signOutOtherSessions();
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            _signOutOthers
                ? 'Parolan değiştirildi; diğer cihazlardaki oturumlar kapatıldı.'
                : 'Parolan değiştirildi.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user =
        ref.watch(authUserProvider).valueOrNull ??
        ref.read(authServiceProvider).currentUser;
    final hasPassword = user?.hasPassword ?? true;

    return _FormPage(
      icon: Icons.password_rounded,
      title: hasPassword ? 'Parolanı değiştir' : 'Parola belirle',
      subtitle: hasPassword
          ? 'Önce kim olduğunu doğrula, sonra yeni parolanı seç.'
          : 'Google ile giriyorsun. Bir parola belirlersen e-postanla da '
                'girebilirsin; doğrulama e-postana gelen kodla yapılır.',
      showBack: true,
      children: [
        if (_verify == _Verify.current) ...[
          PasswordField(
            controller: _current,
            hint: 'Mevcut parola',
            enabled: !_busy,
            autofocus: true,
            textInputAction: TextInputAction.next,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy ? null : _sendCode,
              child: const Text('Mevcut parolanı hatırlamıyor musun?'),
            ),
          ),
        ] else ...[
          if (!_codeSent)
            OutlinedButton.icon(
              onPressed: _busy ? null : _sendCode,
              icon: const Icon(Icons.mail_outline_rounded, size: I.sm),
              label: const Text('E-postama doğrulama kodu gönder'),
            )
          else ...[
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
              decoration: const InputDecoration(hintText: '6 haneli kod'),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Gelmediyse gereksiz (spam) klasörüne de bak.',
                    style: TextStyle(color: c.inkFaint, fontSize: T.caption),
                  ),
                ),
                TextButton(
                  onPressed: _busy || _cooldown > 0 ? null : _sendCode,
                  child: Text(
                    _cooldown > 0
                        ? 'Yeniden gönder ($_cooldown)'
                        : 'Yeniden gönder',
                  ),
                ),
              ],
            ),
          ],
        ],
        if (_info != null) _InfoLine(_info!),
        const SizedBox(height: S.lg),
        NewPasswordFields(
          password: _password,
          repeat: _repeat,
          enabled: !_busy && (_verify == _Verify.current || _codeSent),
          onSubmitted: _save,
        ),
        const SizedBox(height: S.md),
        _SignOutOthersBox(
          value: _signOutOthers,
          enabled: !_busy,
          onChanged: (v) => setState(() => _signOutOthers = v),
        ),
        if (_error != null) _ErrorLine(_error!),
        const SizedBox(height: S.lg),
        FilledButton(
          onPressed: _busy || (_verify == _Verify.code && !_codeSent)
              ? null
              : _save,
          child: _busy
              ? const _Spinner()
              : Text(hasPassword ? 'Parolayı değiştir' : 'Parolayı belirle'),
        ),
      ],
    );
  }
}

// --- Ortak parçalar -------------------------------------------------------------

/// Ortalanmış, dar sütunlu form sayfası — karşılama ekranıyla aynı ölçüler.
class _FormPage extends StatelessWidget {
  const _FormPage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
    this.showBack = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: showBack
          ? AppBar(backgroundColor: c.bg, surfaceTintColor: c.bg)
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              S.xl,
              S.xl,
              S.xl,
              S.xl + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Icon(icon, size: I.hero, color: c.accent),
                    ),
                    const SizedBox(height: S.lg),
                    Text(
                      title,
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
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.inkFaint,
                        fontSize: T.body,
                        fontWeight: FontWeight.w500,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: S.xxl),
                    ...children,
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

class _SignOutOthersBox extends StatelessWidget {
  const _SignOutOthersBox({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CheckboxListTile(
      value: value,
      onChanged: enabled ? (v) => onChanged(v ?? false) : null,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      title: Text(
        'Diğer cihazlardaki oturumları kapat',
        style: TextStyle(color: c.ink, fontSize: T.body),
      ),
      subtitle: Text(
        'Parolanın başkasında olabileceğini düşünüyorsan işaretle.',
        style: TextStyle(color: c.inkFaint, fontSize: T.caption),
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: S.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: I.sm, color: c.danger),
          const SizedBox(width: S.sm),
          Expanded(
            child: Text(
              message,
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
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: S.sm),
    child: Text(
      message,
      style: TextStyle(
        color: context.colors.inkDim,
        fontSize: T.caption,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: I.sm,
    height: I.sm,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: context.colors.onAccent,
    ),
  );
}
