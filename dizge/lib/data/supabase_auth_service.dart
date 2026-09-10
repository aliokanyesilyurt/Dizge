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

  @override
  Future<void> signUp({required String email, required String password}) =>
      _guard(() => _auth.signUp(email: email.trim(), password: password));

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

  /// `shouldCreateUser: false` bilinçli: varsayılan `true` olsaydı yanlış
  /// yazılmış bir e-posta sessizce yeni bir hesap açar, kullanıcı da kodu girip
  /// bomboş bir takvimle karşılaşırdı — "verilerim gitti" diye okunan bir hata.
  @override
  Future<void> sendRecoveryCode(String email) => _guard(
    () => _auth.signInWithOtp(email: email.trim(), shouldCreateUser: false),
  );

  @override
  Future<void> verifyRecoveryCode({
    required String email,
    required String code,
  }) => _guard(
    () => _auth.verifyOTP(
      email: email.trim(),
      token: code.trim(),
      type: OtpType.email,
    ),
  );

  @override
  Future<void> updatePassword(String password) =>
      _guard(() => _auth.updateUser(UserAttributes(password: password)));

  static AuthUser? _toUser(User? user) {
    if (user == null) return null;
    return AuthUser(id: user.id, email: user.email ?? '');
  }

  Future<void> _guard(Future<void> Function() body) async {
    try {
      await body();
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
    if (m.contains('password') && m.contains('6')) {
      return const AuthFailure('Parola en az 6 karakter olmalı.');
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
