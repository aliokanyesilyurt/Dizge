// Paket de `AuthUser` diye bir tip ihraç ediyor. Gizleniyor: bu dosyadaki
// `AuthUser` her zaman **bizim** modelimiz olmalı, yoksa çeviri katmanının
// anlamı kalmaz.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../core/app_config.dart';
import '../core/auth_service.dart';
import 'oauth_loopback.dart';

/// [AuthService]'in Supabase uygulaması.
///
/// Oturum jetonunu saklamak, süresi dolunca yenilemek ve uygulama yeniden
/// açıldığında geri yüklemek `supabase_flutter`'ın işi — bu sınıf yalnız
/// çeviri yapar: paket tipleri → [AuthUser] / [AuthFailure].
class SupabaseAuthService implements AuthService {
  SupabaseAuthService(
    this._auth, {
    OAuthLoopback? loopback,
    this.onBrowserReturn,
  }) : _loopback = loopback ?? (_isDesktop ? OAuthLoopback() : null);

  final GoTrueClient _auth;

  /// Masaüstünde Google dönüşünün yerel dinleyicisi (G1); mobilde null —
  /// orada özel şema zaten uygulamaya geçiyor.
  final OAuthLoopback? _loopback;

  /// Tarayıcı dönüşünden sonra pencereyi öne getirmek için (bootstrap
  /// bağlıyor). Bu katman pencere yöneticisini tanımıyor.
  final void Function()? onBrowserReturn;

  /// Yerel dönüşte çıkan hatalar. Sağlayıcının kendi akışına düşmüyorlar
  /// (kodu oturuma çeviren burası), ama ekran hatayı yine **akıştan**
  /// bekliyor (bkz. [AuthService.signInWithGoogle]); o yüzden aynı akışa
  /// katılıyorlar.
  final _returnErrors = StreamController<AuthUser?>.broadcast();

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// Bu sınıf yalnızca anahtarlar verilmişken kurulur (`bootstrap._initBackend`);
  /// var olması, kimlik doğrulanabildiği anlamına gelir.
  @override
  bool get canAuthenticate => true;

  @override
  AuthUser? get currentUser => _toUser(_auth.currentUser);

  @override
  Stream<AuthUser?> get changes => Stream.multi((out) {
    final a = _auth.onAuthStateChange
        .map((e) => _toUser(e.session?.user))
        .listen(out.add, onError: out.addError);
    final b = _returnErrors.stream.listen(out.add, onError: out.addError);
    out.onCancel = () async {
      await a.cancel();
      await b.cancel();
    };
  }, isBroadcast: true);

  @override
  Future<void> signIn({required String email, required String password}) =>
      _guard(
        () => _auth.signInWithPassword(email: email.trim(), password: password),
      );

  /// Sunucuda "Confirm email" açıksa kayıt oturum **açmaz**; yanıtta oturum
  /// yoksa doğrulama bekleniyor demektir (P2).
  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
  }) async {
    final res = await _guardValue(
      () => _auth.signUp(email: email.trim(), password: password),
    );
    return res.session == null
        ? SignUpOutcome.needsConfirmation
        : SignUpOutcome.signedIn;
  }

  @override
  Future<void> verifySignupCode({
    required String email,
    required String code,
  }) => _guard(
    () => _auth.verifyOTP(
      email: email.trim(),
      token: code.trim(),
      type: OtpType.signup,
    ),
  );

  @override
  Future<void> resendSignupCode(String email) =>
      _guard(() => _auth.resend(type: OtpType.signup, email: email.trim()));

  @override
  Future<void> signOut() => _guard(_auth.signOut);

  /// Google akışı `_guard`'ın dışında duruyor, çünkü buradaki başarısızlıklar
  /// ağ hatası değil: `signInWithOAuth` sunucuya gitmez, adresi kendi kurar ve
  /// tarayıcıyı açar. "Sunucuya ulaşılamadı" demek yanlış teşhis olurdu.
  ///
  /// `externalApplication`: giriş sayfası uygulamanın içindeki bir web
  /// görünümünde değil, gerçek tarayıcıda açılır. Google gömülü görünümlerde
  /// girişi zaten reddediyor (`disallowed_useragent`); üstelik kullanıcının
  /// tarayıcıda kayıtlı oturumu ancak orada işe yarar.
  @override
  Future<void> signInWithGoogle() async {
    try {
      final launched = await _auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: await _redirectUrl(),
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw const AuthFailure(
          'Tarayıcı açılamadı. E-posta ve parolayla girebilirsin.',
        );
      }
    } on AuthException catch (e) {
      throw _translate(e);
    } on AuthFailure {
      rethrow;
    } catch (e) {
      // url_launcher platformda tarayıcı bulamazsa PlatformException atar.
      throw const AuthFailure(
        'Tarayıcı açılamadı. E-posta ve parolayla girebilirsin.',
      );
    }
  }

  /// Dönüş adresi: masaüstünde yerel dinleyici, açılamazsa özel şema.
  ///
  /// Web'de dönüş sayfanın kendi adresi (`null`); özel şema orada anlamsız
  /// ve verilirse tarayıcı çalıştıramayacağı bir adrese yönlenir.
  Future<String?> _redirectUrl() async {
    if (kIsWeb) return null;
    final loopback = _loopback;
    if (loopback != null && await loopback.start(onCallback: _completeReturn)) {
      return loopback.redirectUrl;
    }
    return AppConfig.oauthCallbackUrl;
  }

  /// Tarayıcı yerel adrese döndü: kodu oturuma çevir, pencereyi öne getir.
  ///
  /// Dönen metin tarayıcıdaki sayfaya yazılıyor; `null` = başarı.
  Future<String?> _completeReturn(Uri uri) async {
    onBrowserReturn?.call();

    final providerError = oauthErrorOf(uri);
    if (providerError != null) {
      _returnErrors.addError(AuthFailure(providerError));
      return providerError;
    }
    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      const message = 'Dönüş adresinde giriş kodu yok. Tekrar dene.';
      _returnErrors.addError(const AuthFailure(message));
      return message;
    }
    try {
      await _auth.exchangeCodeForSession(code);
      return null;
    } on AuthException catch (e) {
      final failure = _translate(e);
      _returnErrors.addError(failure);
      return failure.message;
    } catch (_) {
      const message =
          'Sunucuya ulaşılamadı. Bağlantını kontrol edip tekrar dene.';
      _returnErrors.addError(const AuthFailure(message));
      return message;
    }
  }

  /// Sağlayıcının "parola sıfırlama" akışı: "Reset password" şablonu gider
  /// ve kod `recovery` türüyle doğrulanır. Eskiden sihirli bağlantı (OTP
  /// giriş) kullanılıyordu; o yol kayıtsız adres için "hesap bulunamadı"
  /// diyerek adresin burada kayıtlı olup olmadığını ele veriyordu.
  @override
  Future<void> sendRecoveryCode(String email) =>
      _guard(() => _auth.resetPasswordForEmail(email.trim()));

  @override
  Future<void> verifyRecoveryCode({
    required String email,
    required String code,
  }) => _guard(
    () => _auth.verifyOTP(
      email: email.trim(),
      token: code.trim(),
      type: OtpType.recovery,
    ),
  );

  /// Mevcut parolayı yeniden girişle doğrular. Doğruysa oturum tazelenir
  /// (zararsız, hatta "yakın zamanda giriş" şartını da karşılar); yanlışsa
  /// sağlayıcının "invalid credentials" hatası bu bağlama çevrilir.
  @override
  Future<void> verifyCurrentPassword(String password) async {
    final email = _auth.currentUser?.email;
    if (email == null || email.isEmpty) {
      throw const AuthFailure('Oturum bulunamadı. Yeniden giriş yap.');
    }
    try {
      await _auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      if (e.code == 'invalid_credentials' ||
          m.contains('invalid login credentials')) {
        throw const AuthFailure('Mevcut parola hatalı.');
      }
      throw _translate(e);
    } catch (_) {
      throw const AuthFailure(
        'Sunucuya ulaşılamadı. Bağlantını kontrol edip tekrar dene.',
      );
    }
  }

  @override
  Future<void> sendReauthCode() => _guard(_auth.reauthenticate);

  @override
  Future<void> updatePassword(
    String password, {
    String? code,
    String? current,
  }) => _guard(
    () => _auth.updateUser(
      UserAttributes(
        password: password,
        nonce: code?.trim(),
        // Sunucuda "mevcut parola şart" ayarı açıksa gerekli; kapalıysa
        // sunucu yok sayıyor.
        currentPassword: current,
      ),
    ),
  );

  @override
  Future<void> signOutOtherSessions() =>
      _guard(() => _auth.signOut(scope: SignOutScope.others));

  static AuthUser? _toUser(User? user) {
    if (user == null) return null;
    return AuthUser(
      id: user.id,
      email: user.email ?? '',
      hasPassword: _hasEmailIdentity(user),
    );
  }

  /// Hesabın e-posta/parola kimliği var mı? Sağlayıcı listesi
  /// `app_metadata.providers`'ta; eski hesaplarda yalnız `provider` alanı
  /// dolu olabiliyor. İkisi de yoksa "var" varsayılıyor: parola sayfası
  /// mevcut parolayı sorar, hatırlamayan kullanıcı yine kodla değiştirebilir.
  static bool _hasEmailIdentity(User user) {
    final meta = user.appMetadata;
    final providers = meta['providers'];
    if (providers is List) return providers.contains('email');
    final provider = meta['provider'];
    if (provider is String) return provider == 'email';
    return true;
  }

  Future<void> _guard(Future<void> Function() body) => _guardValue(body);

  Future<T> _guardValue<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on AuthException catch (e) {
      throw _translate(e);
    } catch (e) {
      // Ağ, DNS, TLS… Kullanıcıya teknik metin göstermenin faydası yok.
      throw const AuthFailure(
        'Sunucuya ulaşılamadı. Bağlantını kontrol edip tekrar dene.',
      );
    }
  }

  /// Sağlayıcının İngilizce ve teknik metnini kullanıcının okuyabileceği bir
  /// cümleye çevirir.
  ///
  /// Eşleşmeyen bir durumda ham mesaj geçiyor: uydurma bir "bir şeyler ters
  /// gitti" metni, gerçek sebebi gizleyip desteği imkânsızlaştırırdı.
  static AuthFailure _translate(AuthException e) {
    final m = e.message.toLowerCase();

    // Önce sağlayıcının kodları: metinden daha kararlılar.
    switch (e.code) {
      case 'weak_password':
        return const AuthFailure(
          'Parola kurala uymuyor: en az 8 karakter, harf ve rakam içermeli.',
        );
      case 'same_password':
        return const AuthFailure('Yeni parola eskisiyle aynı olamaz.');
      case 'reauthentication_needed':
        return const AuthFailure(
          'Güvenlik için doğrulama gerekiyor: e-postana gelecek kodu kullan.',
        );
      case 'reauthentication_not_valid':
        return const AuthFailure(
          'Doğrulama kodu geçersiz ya da süresi dolmuş. Yeni kod iste.',
        );
      case 'otp_expired':
        return const AuthFailure(
          'Kod geçersiz ya da süresi dolmuş. Yeni bir kod iste.',
        );
      case 'over_email_send_rate_limit':
      case 'over_request_rate_limit':
        return const AuthFailure(
          'Çok fazla deneme yapıldı. Birkaç dakika sonra tekrar dene.',
        );
      case 'email_address_invalid':
        return const AuthFailure('E-posta adresi geçersiz görünüyor.');
      case 'user_already_exists':
      case 'email_exists':
        return const AuthFailure(
          'Bu e-posta zaten kayıtlı. Giriş yapmayı dene.',
        );
    }

    if (m.contains('invalid login credentials')) {
      return const AuthFailure('E-posta veya parola hatalı.');
    }
    if (m.contains('already registered') || m.contains('already exists')) {
      return const AuthFailure('Bu e-posta zaten kayıtlı. Giriş yapmayı dene.');
    }
    if (m.contains('email not confirmed')) {
      return const AuthFailure(
        'E-postanı doğrulaman gerekiyor. Gelen kutuna bak.',
      );
    }
    if (m.contains('password should')) {
      return const AuthFailure(
        'Parola kurala uymuyor: en az 8 karakter, harf ve rakam içermeli.',
      );
    }
    // "For security purposes, you can only request this after 45 seconds."
    if (m.contains('for security purposes')) {
      return const AuthFailure('Yeni kod istemeden önce biraz bekle.');
    }
    // `shouldCreateUser: false` ile kayıtsız bir adrese kod istendiğinde gelen
    // hata. Sağlayıcının metni ("signups not allowed for otp") kullanıcının
    // yaptığı şeyle hiç ilgisiz.
    if (m.contains('signups not allowed') || m.contains('user not found')) {
      return const AuthFailure('Bu e-postayla kayıtlı bir hesap bulunamadı.');
    }
    if (m.contains('token has expired') || m.contains('invalid token')) {
      return const AuthFailure(
        'Kod geçersiz ya da süresi dolmuş. Yeni bir kod iste.',
      );
    }
    // Sunucuda Google sağlayıcısı açılmamış (G8d). Kullanıcının yaptığı şeyle
    // ilgisi yok — kendi hesabında değil, kurulumda eksik var.
    if (m.contains('provider is not enabled') ||
        m.contains('unsupported provider')) {
      return const AuthFailure(
        'Google girişi bu sunucuda açık değil. E-posta ve parolayla girebilirsin.',
      );
    }
    // Kullanıcı tarayıcıda "izin verme" dedi ya da akışı yarıda bıraktı.
    if (m.contains('access_denied') || m.contains('access denied')) {
      return const AuthFailure('Google girişi tamamlanmadı.');
    }
    if (m.contains('rate limit') || m.contains('too many')) {
      return const AuthFailure(
        'Çok fazla deneme yapıldı. Birkaç dakika sonra tekrar dene.',
      );
    }
    if (m.contains('invalid email') || m.contains('unable to validate email')) {
      return const AuthFailure('E-posta adresi geçersiz görünüyor.');
    }

    return AuthFailure(e.message);
  }
}
