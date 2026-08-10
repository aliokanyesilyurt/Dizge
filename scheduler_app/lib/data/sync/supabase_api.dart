import 'package:supabase_flutter/supabase_flutter.dart';

/// Uzak sunucudan gelen hata — **paket tiplerinden arındırılmış**.
///
/// [SupabaseGateway]'in `PostgrestException` ya da `AuthException` tanıması
/// gerekmiyor; ona lazım olan tek ayrım şu: bu hatayı tekrar denemenin anlamı
/// var mı? Çeviriyi [LiveSupabaseApi] yapar, karar gateway'e kalır.
class RemoteException implements Exception {
  const RemoteException(this.message, {this.fatal = false});

  final String message;

  /// `true` ise tekrar deneme boşuna: yetkisiz, şema uyumsuz, kalıcı ret.
  /// `false` ise geçici: ağ koptu, sunucu meşgul, zaman aşımı.
  final bool fatal;

  @override
  String toString() => 'RemoteException($message, fatal: $fatal)';
}

/// [SupabaseGateway]'in sunucudan ihtiyaç duyduğu **her şey**.
///
/// Neden ikinci bir soyutlama: `RemoteGateway` "backend nedir" sorusunu
/// kapatıyor, bu ise "Supabase istemcisi nasıl konuşur" sorusunu. Aradaki
/// mantık — mutasyonu tele koymak, sonucu ayrıştırmak, çekilen satırları
/// `loadJson` şemasına derlemek — gerçek mantık ve testi hak ediyor; ama
/// gerçek `SupabaseClient` bir HTTP yığını olmadan kurulamıyor. Bu arayüz o
/// düğümü çözüyor: testte üç metotluk bir sahte yeter.
abstract class SupabaseApi {
  /// Oturum açmış kullanıcının kimliği; oturum yoksa null.
  String? get currentUserId;

  /// Bir Postgres fonksiyonunu çağırır (`apply_mutations`, `replace_categories`).
  Future<dynamic> rpc(String function, Map<String, dynamic> params);

  /// Tablonun bu kullanıcıya ait bütün satırları.
  ///
  /// `user_id` koşulu istemcide **tekrarlanmıyor**: RLS onu sunucuda zaten
  /// uyguluyor. Burada tekrar yazmak, güvenliğin istemcide olduğu izlenimi
  /// verirdi — değil.
  Future<List<Map<String, dynamic>>> fetchAll(String table);
}

/// Gerçek Supabase istemcisini saran uygulama.
///
/// `supabase_flutter` paketi uygulamada **yalnızca burada ve `bootstrap`'ta**
/// tanınır.
class LiveSupabaseApi implements SupabaseApi {
  LiveSupabaseApi(this._client);

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<dynamic> rpc(String function, Map<String, dynamic> params) =>
      _guard(() => _client.rpc(function, params: params));

  @override
  Future<List<Map<String, dynamic>>> fetchAll(String table) async {
    final rows = await _guard(() => _client.from(table).select());
    return [for (final r in rows as List) (r as Map).cast<String, dynamic>()];
  }

  /// Paket istisnalarını [RemoteException]'a çevirir ve **kalıcı mı geçici mi**
  /// olduğuna burada karar verilir.
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on AuthException catch (e) {
      // Oturum düştü ya da hiç yok. Tekrar denemek kullanıcı müdahalesi
      // olmadan işe yaramaz.
      throw RemoteException(e.message, fatal: true);
    } on PostgrestException catch (e) {
      throw RemoteException(e.message, fatal: _isPermanent(e));
    } catch (e) {
      // Ağ, DNS, zaman aşımı, TLS… hepsi geçici sayılır: kuyruk beklesin.
      throw RemoteException('$e');
    }
  }

  /// Tekrar denemenin kod değişmeden asla düzeltmeyeceği Postgres durumları.
  static bool _isPermanent(PostgrestException e) {
    const permanent = {
      '42501', // yetersiz yetki — RLS reddetti
      '42P01', // tablo yok — şema uygulanmamış
      '42883', // fonksiyon yok — şema eski
      '22P02', // geçersiz metin gösterimi — bozuk payload
      '23503', // yabancı anahtar — kullanıcı silinmiş
    };
    if (e.code != null && permanent.contains(e.code)) return true;
    // 4xx gövdesi olan her şey istemci hatasıdır; 5xx sunucunun derdi, geçer.
    final status = int.tryParse(e.code ?? '');
    return status != null && status >= 400 && status < 500;
  }
}
