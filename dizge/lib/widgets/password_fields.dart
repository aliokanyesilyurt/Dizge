/// Parola alanları (P1): tek alan ve "yeni parola + tekrar" çifti.
///
/// Çift, kayıtta, kurtarmada ve parola değiştirmede aynı: kural listesi
/// yazılırken işaretleniyor, güç göstergesi ve eşleşme satırı altta. Kullanıcı
/// hatayı ancak gönderince görmesin — "neye göre" olduğu baştan belli olsun.
library;

import 'package:flutter/material.dart';

import '../core/password_policy.dart';
import '../theme.dart';

/// Yeni parola iki alana da aynı yazılmış ve kurala uyuyor mu?
bool newPasswordReady(String password, String repeat) =>
    passwordAcceptable(password) && password == repeat;

/// Göster/gizle düğmeli tek parola alanı.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.hint,
    this.focusNode,
    this.enabled = true,
    this.autofocus = false,
    this.autofillHints = const [AutofillHints.password],
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final FocusNode? focusNode;
  final bool enabled;
  final bool autofocus;
  final Iterable<String> autofillHints;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      obscureText: !_visible,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        hintText: widget.hint,
        suffixIcon: IconButton(
          tooltip: _visible ? 'Parolayı gizle' : 'Parolayı göster',
          icon: Icon(
            _visible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            size: I.sm,
          ),
          onPressed: () => setState(() => _visible = !_visible),
        ),
      ),
    );
  }
}

/// Yeni parola + tekrar, kural listesi, güç ve eşleşme.
class NewPasswordFields extends StatefulWidget {
  const NewPasswordFields({
    super.key,
    required this.password,
    required this.repeat,
    this.enabled = true,
    this.autofocus = false,
    this.onSubmitted,
    this.passwordHint = 'Yeni parola',
  });

  final TextEditingController password;
  final TextEditingController repeat;
  final bool enabled;
  final bool autofocus;
  final VoidCallback? onSubmitted;
  final String passwordHint;

  @override
  State<NewPasswordFields> createState() => _NewPasswordFieldsState();
}

class _NewPasswordFieldsState extends State<NewPasswordFields> {
  final _repeatFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.password.addListener(_changed);
    widget.repeat.addListener(_changed);
  }

  @override
  void dispose() {
    widget.password.removeListener(_changed);
    widget.repeat.removeListener(_changed);
    _repeatFocus.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.password.text;
    final r = widget.repeat.text;
    final strength = strengthOf(p);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PasswordField(
          controller: widget.password,
          hint: widget.passwordHint,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _repeatFocus.requestFocus(),
        ),
        const SizedBox(height: S.sm),
        for (final rule in kPasswordRules)
          _Check(ok: rule.test(p), text: rule.label),
        if (p.isNotEmpty) ...[
          const SizedBox(height: S.xs),
          _StrengthMeter(strength: strength),
        ],
        const SizedBox(height: S.md),
        PasswordField(
          controller: widget.repeat,
          focusNode: _repeatFocus,
          hint: 'Parola (tekrar)',
          enabled: widget.enabled,
          autofillHints: const [AutofillHints.newPassword],
          onSubmitted: (_) => widget.onSubmitted?.call(),
        ),
        if (r.isNotEmpty) ...[
          const SizedBox(height: S.sm),
          _Check(
            ok: p == r,
            text: p == r ? 'Eşleşiyor' : 'Parolalar aynı değil',
            failColor: c.danger,
          ),
        ],
      ],
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.ok, required this.text, this.failColor});

  final bool ok;
  final String text;

  /// Karşılanmamış kural kırmızı değil, soluk: henüz yazılmamış bir
  /// parolaya "hata" demek erken. Eşleşme satırı ise kırmızı — orada
  /// kullanıcı zaten ikinci alana yazdı.
  final Color? failColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = ok ? c.accent : (failColor ?? c.inkFaint);

    return Padding(
      padding: const EdgeInsets.only(bottom: S.hair),
      child: Semantics(
        checked: ok,
        label: text,
        excludeSemantics: true,
        child: Row(
          children: [
            Icon(
              ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              size: I.xs,
              color: color,
            ),
            const SizedBox(width: S.sm),
            Text(
              text,
              style: TextStyle(
                color: ok ? c.inkDim : (failColor ?? c.inkFaint),
                fontSize: T.caption,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.strength});

  final PasswordStrength strength;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final level = strength.index; // 1..4
    final color = switch (strength) {
      PasswordStrength.empty || PasswordStrength.weak => c.danger,
      PasswordStrength.fair => c.warning,
      PasswordStrength.good || PasswordStrength.strong => c.accent,
    };

    return Row(
      children: [
        Text(
          'Güç',
          style: TextStyle(color: c.inkFaint, fontSize: T.caption),
        ),
        const SizedBox(width: S.sm),
        for (var i = 1; i <= 4; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: Motion.fast,
              height: S.xs,
              decoration: BoxDecoration(
                color: i <= level ? color : c.lineSoft,
                borderRadius: R.radiusPill,
              ),
            ),
          ),
          if (i < 4) const SizedBox(width: S.xs),
        ],
        const SizedBox(width: S.sm),
        SizedBox(
          width: 44,
          child: Text(
            strength.label,
            style: TextStyle(
              color: color,
              fontSize: T.caption,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
