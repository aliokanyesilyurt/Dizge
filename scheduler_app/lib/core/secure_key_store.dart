import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'app_config.dart';

/// Yerel veritabanının AES-256 anahtarını üretir ve platformun donanım
/// destekli kasasında saklar.
///
/// Mimari karar — **anahtar veriyle aynı yerde durmaz**:
///   * Veri: uygulama dizinindeki Hive kutusu (şifreli, diskte okunamaz).
///   * Anahtar: Android Keystore / iOS Keychain / Windows DPAPI.
/// Telefon rootlanmadıkça kutu dosyasını kopyalayan biri içeriği açamaz.
///
/// Anahtar bir kez üretilir; kaybolursa veri **geri getirilemez** (bu kasıtlı:
/// düz metin yedeği tutmak şifrelemeyi anlamsız kılardı). Bu yüzden anahtar
/// okunamıyorsa çağıran taraf şifresiz düşüşe geçmek yerine hata almalıdır.
class SecureKeyStore {
  SecureKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              // Cihaz kilidi ilk kez açıldıktan sonra erişilebilir, yedeklere
              // taşınmaz: anahtar bu cihaza çakılıdır.
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  /// Mevcut anahtarı okur; yoksa kriptografik olarak güvenli yeni bir tane
  /// üretip kasaya yazar.
  Future<Uint8List> readOrCreateKey() async {
    final existing = await _storage.read(key: AppConfig.encryptionKeyName);
    if (existing != null) {
      final bytes = base64Url.decode(existing);
      if (bytes.length == 32) return Uint8List.fromList(bytes);
      // Bozuk/eksik anahtar: kutuyu açamayacağımız için yenisini üretmek
      // eski veriyi kurtarmaz ama uygulamayı kilitlenmekten çıkarır.
      debugPrint('Şifreleme anahtarı bozuk (${bytes.length} bayt), yenisi üretiliyor.');
    }

    final key = Hive.generateSecureKey(); // 32 bayt, Fortuna CSPRNG
    await _storage.write(
      key: AppConfig.encryptionKeyName,
      value: base64Url.encode(key),
    );
    return Uint8List.fromList(key);
  }

  /// "Cihazdaki verimi sil" akışı: anahtarı yok eder. Kutu dosyası kalsa bile
  /// içeriği bir daha açılamaz (kriptografik silme).
  Future<void> destroyKey() =>
      _storage.delete(key: AppConfig.encryptionKeyName);
}

/// Güvenli kasaya erişilemediğinde (ör. eski Android'de Keystore arızası,
/// masaüstünde kasa servisi yok) fırlatılır. Çağıran taraf kullanıcıya
/// "verileriniz bu cihazda korunamıyor" diyebilsin diye ayrı tip.
class SecureStorageUnavailable implements Exception {
  const SecureStorageUnavailable(this.cause);
  final Object cause;

  @override
  String toString() => 'Güvenli anahtar deposuna erişilemedi: $cause';
}
