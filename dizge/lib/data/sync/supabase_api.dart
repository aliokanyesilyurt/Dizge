import 'dart:async';

import 'package:flutter/foundation.dart';
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

  /// Tablonun bu kullanıcıya **görünen** bütün satırları: kendi satırları ve
  /// üyesi olduğu grupların satırları (Y3).
  ///
  /// Sahiplik koşulu istemcide **tekrarlanmıyor**: RLS onu sunucuda zaten
  /// uyguluyor. Burada tekrar yazmak, güvenliğin istemcide olduğu izlenimi
  /// verirdi — değil. Grup satırlarının kendiliğinden akması da bunun sonucu:
  /// istemci tarafında değişen tek bir satır yok.
  Future<List<Map<String, dynamic>>> fetchAll(String table);

  /// [since]'den **sonra sunucuda** değişmiş satırlar (Y1).
  ///
  /// Ölçü `server_at`; `updated_at` değil. İkincisi cihaz saati ve saati geri
  /// alınmış bir telefonun yazdığı satır, imleç ondan hesaplansaydı bir daha
  /// hiç görünmezdi. `server_at` şemaya tam bu iş için kondu.
  ///
  /// Silinmiş satırlar **süzülmez**: artımlı çekimde "gelmedi" ile "silindi"
  /// ayırt edilemez, mezar taşının gelmesi şart (B3).
  Future<List<Map<String, dynamic>>> fetchSince(String table, DateTime since);

  /// Kullanıcının kendi üyelik satırını siler (Y4.3: gruptan çık).
  ///
  /// Neden bir RPC değil: `group_members_leave` politikası bunu zaten tek
  /// satırlık bir kuralla anlatıyor — "insan kendi üyeliğini bırakabilir".
  /// Aynı şeyi `security definer` bir fonksiyona sarmak, politikanın yanından
  /// dolaşan ikinci bir kapı açmak olurdu.
  ///
  /// `user_id` süzgeci **istemcide yok**: hangi satırın silinebileceğine RLS
  /// karar veriyor. Buraya yazmak, güvenliğin istemcide olduğu izlenimi
  /// verirdi.
  Future<void> leaveGroup(String groupId);

  /// Kullanıcının kendi profil satırını yazar (Y4.4: görünen ad).
  ///
  /// `upsert`: satır normalde kayıt trigger'ıyla doğmuş oluyor ama doğmamış
  /// olabilir de (trigger hatayı yutuyor, §5). `update` yazsaydım o hesapta
  /// ad kaydetmek sessizce hiçbir şey yapmazdı — kullanıcı yazar, kaydeder,
  /// hiçbir şey olmaz.
  ///
  /// `user_id` çağıranın kimliğinden alınır ve parametre değildir: başkasının
  /// satırını hedefleyebilen bir imza, RLS onu reddetse bile yanlış soruyu
  /// sormayı mümkün kılardı.
  Future<void> upsertProfile({required String displayName});

  /// "Sunucuda bir şey değişti" sinyali (Y2). Veri taşımaz.
  Stream<void> get remoteChanges;
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

  @override
  Future<List<Map<String, dynamic>>> fetchSince(
    String table,
    DateTime since,
  ) async {
    final rows = await _guard(
      () => _client
          .from(table)
          .select()
          // Kesin büyük: eşitlik olsaydı her turda son satır tekrar gelirdi.
          // Aynı milisaniyede yazılmış iki satırdan ikincisini kaçırma riski
          // buna karşılık kabul ediliyor — `server_at` mikrosaniye çözünürlükte
          // ve tek kullanıcının iki yazması arasına bir ağ turu giriyor.
          .gt('server_at', since.toUtc().toIso8601String())
          .order('server_at'),
    );
    return [for (final r in rows as List) (r as Map).cast<String, dynamic>()];
  }

  @override
  Future<void> leaveGroup(String groupId) => _guard(
    () => _client.from('group_members').delete().eq('group_id', groupId),
  );

  @override
  Future<void> upsertProfile({required String displayName}) async {
    final uid = currentUserId;
    if (uid == null) {
      throw const RemoteException('Oturum yok.', fatal: true);
    }
    await _guard(
      // `updated_at` gönderilmiyor: onu sunucudaki trigger yazıyor (04 §5b).
      // Cihaz saatine bırakılsaydı, saati ileri kurulmuş bir telefonun yazdığı
      // ad sonsuza dek kazanan olurdu.
      () => _client.from('profiles').upsert({
        'user_id': uid,
        'display_name': displayName,
      }),
    );
  }

  StreamController<void>? _changes;
  RealtimeChannel? _channel;

  /// Üç tabloyu da dinleyen tek bir Realtime kanalı.
  ///
  /// Kanal **tembel** kuruluyor ve bir kez: motor akışı bir kez dinliyor,
  /// ikinci bir abone gelirse aynı kanalı paylaşır (`broadcast`). Her aboneye
  /// yeni bir WebSocket açmak, aynı bilgiyi üç kez taşımak olurdu.
  ///
  /// Sinyalde satır verisi taşınmıyor (bkz. `RemoteGateway.remoteChanges`);
  /// geri çağrının tek işi "bir şey oldu" demek. RLS Realtime'da da geçerli:
  /// kullanıcı yalnız kendi satırlarının olayını alır.
  @override
  Stream<void> get remoteChanges {
    final existing = _changes;
    if (existing != null) return existing.stream;

    // Denetleyici [dispose]'da kapatılıyor; linter alanın üzerinden giden o
    // yolu göremediği için kural burada susturuluyor.
    // ignore: close_sinks
    final controller = StreamController<void>.broadcast();
    _changes = controller;

    var channel = _client.channel('dizge-sync');
    for (final table in const ['nodes', 'habits', 'categories']) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) {
          if (!controller.isClosed) controller.add(null);
        },
      );
    }

    _channel = channel..subscribe();
    return controller.stream;
  }

  /// Kanalı kapatır. Uygulama kapanırken çağrılması **şart değil** (süreç
  /// zaten ölüyor), ama oturum değişiminde sızıntıyı önler.
  Future<void> dispose() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      try {
        await _client.removeChannel(channel);
      } catch (e) {
        debugPrint('Realtime kanalı kapatılamadı: $e');
      }
    }
    await _changes?.close();
    _changes = null;
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
