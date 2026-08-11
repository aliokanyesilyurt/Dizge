import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Oturum açmış kullanıcının uygulamaya görünen yüzü.
///
/// Sağlayıcının kullanıcı nesnesi değil, ondan alınan **iki alan**. Uygulamanın
/// geri kalanı jeton, yenileme süresi ya da sağlayıcıya özgü meta veriyi
/// tanımıyor.
class AuthUser {
  const AuthUser({required this.id, required this.email});

  /// Sunucudaki `user_id` — satırların sahipliği buna bağlı.
  final String id;

  final String email;

  @override
  bool operator ==(Object other) =>
      other is AuthUser && other.id == id && other.email == email;

  @override
  int get hashCode => Object.hash(id, email);
}

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
  Future<void> signUp({required String email, required String password});

  /// Oturumu kapatır. **Yerel veriye dokunmaz** — cihazdaki takvim
  /// kullanıcınındır; silmek ayrı ve açıkça istenmiş bir karardır.
  Future<void> signOut();
}

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
  Future<void> signUp({required String email, required String password}) async {
    throw const AuthFailure('Sunucu bu sürümde yapılandırılmadı.');
  }

  /// Oturum yokken çıkmak, zaten istenen durumda olmak demek — hata değil.
  @override
  Future<void> signOut() async {}
}

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
