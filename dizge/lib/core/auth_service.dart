import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Oturum açmış kullanıcının uygulamaya görünen yüzü.
///
/// Sağlayıcının kullanıcı nesnesi değil, ondan alınan **iki alan**. Uygulamanın
/// geri kalanı jeton, yenileme süresi ya da sağlayıcıya özgü meta veriyi
/// tanımıyor.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    this.hasPassword = true,
  });

  /// Sunucudaki `owner_id` — satırı kimin oluşturduğu buna yazılıyor.
  final String id;

  final String email;

  /// Hesap e-posta + parolayla mı açıldı? Yalnız Google ile açılmış hesapta
  /// "mevcut parola" diye bir şey yok; parola sayfası orada "Parola belirle"
  /// olur ve doğrulamayı e-postaya giden kodla yapar (P4).
  final bool hasPassword;

  @override
  bool operator ==(Object other) =>
      other is AuthUser &&
      other.id == id &&
      other.email == email &&
      other.hasPassword == hasPassword;

  @override
  int get hashCode => Object.hash(id, email, hasPassword);
}

/// Kaydın sonucu: oturum hemen mi açıldı, yoksa e-posta doğrulaması mı
/// bekleniyor? Sunucuda "Confirm email" açıksa ikincisi (P2).
enum SignUpOutcome { signedIn, needsConfirmation }

/// Kullanıcıya **gösterilebilir** oturum hatası.
///
/// Sağlayıcı istisnaları İngilizce ve teknik ("Invalid login credentials").
/// Çeviri, hatayı üreten katmanın işi; ekranın işi onu göstermek.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Oturum açma/kapama ve oturumun izlenmesi.
///
/// `RemoteGateway` gibi bu da bir kapı: uygulamanın hiçbir ekranı `supabase`
/// paketini tanımıyor.
abstract class AuthService {
  /// Bu servis gerçekten kimlik doğrulayabiliyor mu?
  ///
  /// `false` ise giriş kapısı **açık kalır** (G2): anahtarsız bir derlemede
  /// hiç kimse giriş yapamaz, kapıyı kapalı tutmak uygulamayı açılamaz hâle
  /// getirirdi.
  ///
  /// Kapının `AppConfig.backendAvailable`'ı doğrudan okumaması bilinçli: o bir
  /// derleme zamanı sabiti, testte hiçbir zaman doğru olmaz ve kapı
  /// sınanamazdı. Soru zaten burada daha doğru duruyor — "sunucu tanımlı mı"
  /// değil, "bu kapı kimlik doğrulayabiliyor mu".
  bool get canAuthenticate;

  /// Şu anki kullanıcı; oturum yoksa null.
  AuthUser? get currentUser;

  /// Oturum değişiklikleri — giriş, çıkış, jeton yenileme, süre dolması.
  ///
  /// Ekranın bunu dinlemesi şart: oturum yalnız kullanıcı düğmeye bastığında
  /// değil, jeton yenilenemediğinde de değişir.
  Stream<AuthUser?> get changes;

  Future<void> signIn({required String email, required String password});

  /// Hesap açar. E-posta doğrulaması gerekiyorsa oturum açılmaz ve
  /// [SignUpOutcome.needsConfirmation] döner; kullanıcı e-postasına gelen
  /// kodu [verifySignupCode] ile girer.
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
  });

  /// Kayıt doğrulama kodunu doğrular ve oturumu açar.
  Future<void> verifySignupCode({required String email, required String code});

  /// Kayıt doğrulama kodunu yeniden gönderir.
  Future<void> resendSignupCode(String email);

  /// Oturumu kapatır. Yerel veriye ne olacağı bu katmanın işi değil; çağıran
  /// karar verir (bkz. `account_screen._signOut`).
  Future<void> signOut();

  /// Google hesabıyla giriş — **sistem tarayıcısında** (G8a).
  ///
  /// Dönen `Future`, girişin bittiğini değil **tarayıcının açıldığını**
  /// söyler. Oturum, kullanıcı tarayıcıda işini bitirip uygulamaya
  /// döndüğünde [changes] üzerinden gelir; çağıran sonucu buradan değil
  /// akıştan öğrenir. Bu, e-posta yolundan farkı: orada `signIn` döndüğünde
  /// iş bitmiştir.
  ///
  /// Tarayıcı hiç açılamazsa ya da sunucuda Google sağlayıcısı kapalıysa
  /// [AuthFailure] fırlatır (G8d). Dönüş yolunda çıkan hatalar (kullanıcı
  /// izni reddetti, sağlayıcı hata döndürdü) çağrıya değil **[changes]
  /// akışına** düşer — ekran ikisini birden dinlemeli.
  Future<void> signInWithGoogle();

  // --- Parola kurtarma -------------------------------------------------------
  //
  // Sert kapı, unutulan parolayı **kalıcı kilitlenmeye** çevirir: uygulamaya
  // girilemez, veriye ulaşılamaz, yapacak bir şey kalmaz. Bu yüzden kurtarma
  // isteğe bağlı bir nezaket değil, kapının parçası.
  //
  // Sağlayıcının standart sıfırlama akışı e-postadaki **bağlantıyla** çalışır
  // ve Windows'ta derin bağlantı kaydı ister — OAuth'u eleyen sebebin aynısı.
  // Onun yerine e-postaya bir kod gidiyor ve kod uygulamaya yazılıyor: hiçbir
  // platform yapılandırması gerekmiyor.

  /// E-postaya parola sıfırlama kodu gönderir.
  ///
  /// Kayıtlı olmayan adres için de **hata vermez** (P3): "bu adres kayıtlı
  /// değil" demek, herhangi birinin bir e-postanın burada hesabı olup
  /// olmadığını sorgulayabilmesi demekti. Ekran bu yüzden "kayıtlıysa
  /// gönderdik" diyor. Hesap da açmaz.
  Future<void> sendRecoveryCode(String email);

  /// Kodu doğrular ve oturumu açar.
  ///
  /// Kurtarma burada bitmiyor: kapı [passwordResetPendingProvider] yanarken
  /// takvim yerine "Yeni parolanı belirle" ekranını gösterir. Kod tek başına
  /// zaten bir oturum anahtarı; parolayı ondan önce değiştirmenin yolu yok.
  Future<void> verifyRecoveryCode({
    required String email,
    required String code,
  });

  /// Açık oturumun **mevcut** parolasını sunucuda doğrular (P4).
  ///
  /// Yanlışsa [AuthFailure] ("Mevcut parola hatalı.") ve hiçbir şey değişmez.
  /// Parolayı değiştirmeden önce çağrılır: oturumu açık bırakılmış bir
  /// cihazda başkası parolayı değiştiremesin.
  Future<void> verifyCurrentPassword(String password);

  /// Açık oturumun e-postasına yeniden doğrulama kodu gönderir — mevcut
  /// parolayı hatırlamayan ya da hiç parolası olmayan (Google) hesap için.
  Future<void> sendReauthCode();

  /// Açık oturumun parolasını değiştirir. [code], [sendReauthCode] ile gelen
  /// kod; [current], az önce doğrulanan mevcut parola (sunucu isterse).
  Future<void> updatePassword(String password, {String? code, String? current});

  /// Bu cihaz dışındaki bütün oturumları kapatır. Parola sızdı diye
  /// değiştiren kişinin asıl istediği budur.
  Future<void> signOutOtherSessions();
}

/// Kurtarma kodu doğrulandı, yeni parola henüz belirlenmedi.
///
/// Kodla açılan oturum gerçek bir oturum; kapı bunu görünce takvimi açardı ve
/// kurtarma "parolanı sonra Hesap'tan değiştir" diye yarım kalırdı. Bayrak
/// bellekte: uygulama bu arada kapanırsa kullanıcı içeride uyanır, parolasını
/// Hesap ekranından yine değiştirebilir.
final passwordResetPendingProvider = StateProvider<bool>((ref) => false);

/// Backend yapılandırılmamışken bağlanan uygulama.
///
/// Giriş denemeleri sessizce başarısız olmaz, açıkça söyler: sessiz `return`
/// olsaydı kullanıcı düğmeye basar, hiçbir şey olmaz ve nedenini asla
/// öğrenemezdi.
class NoopAuthService implements AuthService {
  const NoopAuthService();

  @override
  bool get canAuthenticate => false;

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> get changes => const Stream.empty();

  @override
  Future<void> signIn({required String email, required String password}) async {
    throw const AuthFailure('Sunucu bu sürümde yapılandırılmadı.');
  }

  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
  }) async {
    throw const AuthFailure('Sunucu bu sürümde yapılandırılmadı.');
  }

  @override
  Future<void> verifySignupCode({
    required String email,
    required String code,
  }) async {
    throw const AuthFailure('Sunucu bu sürümde yapılandırılmadı.');
  }

  @override
  Future<void> resendSignupCode(String email) async {
    throw const AuthFailure('Sunucu bu sürümde yapılandırılmadı.');
  }

  /// Oturum yokken çıkmak, zaten istenen durumda olmak demek — hata değil.
  @override
  Future<void> signOut() async {}

  @override
  Future<void> signInWithGoogle() async {
    throw const AuthFailure('Sunucu bu sürümde yapılandırılmadı.');
  }

  @override
  Future<void> sendRecoveryCode(String email) async {
    throw const AuthFailure('Sunucu bu sürümde yapılandırılmadı.');
  }

  @override
  Future<void> verifyRecoveryCode({
    required String email,
    required String code,
  }) async {
    throw const AuthFailure('Sunucu bu sürümde yapılandırılmadı.');
  }

  @override
  Future<void> verifyCurrentPassword(String password) async {
    throw const AuthFailure('Sunucu bu sürümde yapılandırılmadı.');
  }

  @override
  Future<void> sendReauthCode() async {
    throw const AuthFailure('Sunucu bu sürümde yapılandırılmadı.');
  }

  @override
  Future<void> updatePassword(
    String password, {
    String? code,
    String? current,
  }) async {
    throw const AuthFailure('Sunucu bu sürümde yapılandırılmadı.');
  }

  @override
  Future<void> signOutOtherSessions() async {}
}

/// Bu cihazda **daha önce** oturum açılmış mı?
///
/// Karşılama ekranının hangi kipte başlayacağını bu belirliyor (T3a): uygulamayı
/// ilk kez açan kişi doğrudan kayıt formunu görür, daha önce girmiş biri giriş
/// formunu.
///
/// Oturum jetonu bu soruyu cevaplayamaz — çıkışta silinir ve her çıkış
/// kullanıcıyı yeniden "yeni kullanıcı" yapardı.
const String kHasSignedInKey = 'has_signed_in_before';

/// Üretimde `bootstrap()` gerçek uygulamayı geçirir.
final authServiceProvider = Provider<AuthService>(
  (ref) => const NoopAuthService(),
);

/// Oturumun izlenebilir hâli.
///
/// Akıştan **önce** mevcut kullanıcıyı yayıyor: yalnız `changes` dinlenseydi
/// ekran, ilk değişiklik olana kadar "oturum yok" gösterirdi — oysa uygulama
/// açılışta zaten oturumlu olabilir.
final authUserProvider = StreamProvider<AuthUser?>((ref) async* {
  final service = ref.watch(authServiceProvider);
  yield service.currentUser;
  yield* service.changes;
});
