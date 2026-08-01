import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../core/app_config.dart';
import '../core/secure_key_store.dart';

/// Cihaz içi **şifreli** kalıcılık katmanı.
///
/// Neden Hive + JSON (adapter/codegen değil):
/// Modellerinde (`Task`, `Note`, `Habit`) zaten olgun `toJson/fromJson` var.
/// TypeAdapter üretmek aynı bilgiyi ikinci kez, bu kez alan sırasına bağımlı
/// ve kırılgan biçimde tanımlamak olurdu. Bunun yerine kutuya tek bir şifreli
/// anlık görüntü (snapshot) yazıyoruz: şema evrimi JSON alanı ekleyip
/// çıkarmak kadar kolay kalıyor.
///
/// Şifreleme: kutu `HiveAesCipher` ile açılır; anahtar [SecureKeyStore]
/// üzerinden platform kasasından gelir. Diskteki `.hive` dosyası okunduğunda
/// yalnızca şifreli baytlar görünür.
abstract class LocalStore {
  /// Depoyu hazırlar. Başarısız olursa fırlatır — çağıran taraf
  /// [InMemoryStore]'a düşebilir.
  Future<void> init();

  /// Kayıtlı anlık görüntü; hiç yazılmamışsa null.
  Map<String, dynamic>? readSnapshot();

  /// Anlık görüntüyü yazar (tam üzerine yazma).
  Future<void> writeSnapshot(Map<String, dynamic> snapshot);

  /// Outbox gibi yardımcı kayıtlar için serbest alan.
  List<Map<String, dynamic>> readList(String key);
  Future<void> writeList(String key, List<Map<String, dynamic>> value);

  /// Tüm yerel veriyi ve şifreleme anahtarını yok eder ("cihazdan sil").
  Future<void> wipe();

  Future<void> close();
}

/// Anahtarları:
const _kSnapshot = 'snapshot';

/// Hive tabanlı, AES-256 şifreli uygulama.
class HiveLocalStore implements LocalStore {
  HiveLocalStore({SecureKeyStore? keyStore})
      : _keyStore = keyStore ?? SecureKeyStore();

  final SecureKeyStore _keyStore;
  Box<String>? _box;

  Box<String> get _requireBox {
    final box = _box;
    if (box == null) {
      throw StateError('LocalStore.init() çağrılmadan kullanıldı.');
    }
    return box;
  }

  @override
  Future<void> init() async {
    await Hive.initFlutter();

    final Uint8List key;
    try {
      key = await _keyStore.readOrCreateKey();
    } catch (e) {
      throw SecureStorageUnavailable(e);
    }

    _box = await Hive.openBox<String>(
      AppConfig.boxName,
      encryptionCipher: HiveAesCipher(key),
    );
  }

  @override
  Map<String, dynamic>? readSnapshot() {
    final raw = _requireBox.get(_kSnapshot);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return _migrate(decoded.cast<String, dynamic>());
    } catch (e) {
      // Bozuk kayıt uygulamayı açılışta kilitlemesin: boş başla, bir sonraki
      // yazma sağlam kaydı geri koyar. (Sessiz veri kaybı riski var; bu yüzden
      // bozuk hâli ayrı anahtarda saklıyoruz ki destek incelemesi mümkün olsun.)
      debugPrint('Anlık görüntü çözümlenemedi, karantinaya alınıyor: $e');
      unawaited(_requireBox.put('$_kSnapshot.corrupt', raw));
      return null;
    }
  }

  /// Şema evrimi. Eski sürümden okunan görüntüyü güncel şekle taşır.
  ///
  /// v1 → v2: kategoriler artık anlık görüntüde taşınıyor (önceden yalnızca
  /// bellekteydi ve uygulama kapanınca özel kategoriler kayboluyordu).
  Map<String, dynamic> _migrate(Map<String, dynamic> json) {
    final version = (json['schemaVersion'] as num?)?.toInt() ?? 1;
    if (version >= AppConfig.kSchemaVersion) return json;

    var migrated = json;
    if (version < 2) {
      migrated = {...migrated, 'categories': migrated['categories'] ?? const []};
    }
    return {...migrated, 'schemaVersion': AppConfig.kSchemaVersion};
  }

  @override
  Future<void> writeSnapshot(Map<String, dynamic> snapshot) =>
      _requireBox.put(_kSnapshot, jsonEncode(snapshot));

  @override
  List<Map<String, dynamic>> readList(String key) {
    final raw = _requireBox.get(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    } catch (e) {
      debugPrint('"$key" listesi çözümlenemedi: $e');
      return const [];
    }
  }

  @override
  Future<void> writeList(String key, List<Map<String, dynamic>> value) =>
      _requireBox.put(key, jsonEncode(value));

  @override
  Future<void> wipe() async {
    await _box?.clear();
    // Kriptografik silme: anahtar gidince eski baytlar zaten çözülemez.
    await _keyStore.destroyKey();
  }

  @override
  Future<void> close() async {
    await _box?.close();
    _box = null;
  }
}

/// Diske hiç yazmayan uygulama. İki yerde kullanılır:
///   * testler (dosya sistemi/kasa eklentisi olmadan koşsun diye),
///   * güvenli depolama açılamadığında acil düşüş — kullanıcı en azından
///     oturum boyunca uygulamayı kullanabilir.
class InMemoryStore implements LocalStore {
  Map<String, dynamic>? _snapshot;
  final Map<String, List<Map<String, dynamic>>> _lists = {};

  @override
  Future<void> init() async {}

  @override
  Map<String, dynamic>? readSnapshot() => _snapshot;

  @override
  Future<void> writeSnapshot(Map<String, dynamic> snapshot) async {
    // Kopyalayarak sakla: çağıran taraf haritayı sonradan değiştirirse
    // "kayıtlı" hâl sessizce bozulmasın.
    _snapshot = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
  }

  @override
  List<Map<String, dynamic>> readList(String key) => _lists[key] ?? const [];

  @override
  Future<void> writeList(String key, List<Map<String, dynamic>> value) async {
    _lists[key] = List.of(value);
  }

  @override
  Future<void> wipe() async {
    _snapshot = null;
    _lists.clear();
  }

  @override
  Future<void> close() async {}
}
