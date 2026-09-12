import 'package:dizge/models/task.dart';
import 'package:flutter_test/flutter_test.dart';

/// Z1 — kategori adlarının **görünen** hâli.
///
/// İki ayrı iddia var. Biri kırılırsa öteki hâlâ doğru olabilir, o yüzden ayrı
/// ayrı ölçülüyorlar:
///
/// 1. Depolanan ad değişmedi — kaydın kimliği o metin (§Zd).
/// 2. Görünen ad Başlık Düzeni'nde ve **noktalı** İ taşıyor.
void main() {
  group('Z1 — depolanan ad dokunulmaz', () {
    test('hazır kategoriler eski adlarıyla duruyor', () {
      // Bu liste diskteki ve sunucudaki kayıtların taşıdığı metin. Değişirse
      // eski kayıtlar kategorisiz kalır, senkronda kategori ikiye bölünür.
      expect(AppData.categories.map((c) => c.name), [
        'Kalıcı iş',
        'Günlük rutin',
        'Haftalık / ara sıra',
        'Önemli / acil',
        'Hobi / keyfi',
        'Sosyal',
        'Diğer',
      ]);
    });

    test('görünen ad depoya sızmıyor', () {
      // Kategori seçildiğinde işe yazılan şey `name` olmalı, `label` değil.
      final first = AppData.categories.first;
      final task = Task(
        title: 'deneme',
        date: DateTime(2026, 8, 16),
        color: first.color,
        categoryName: first.name,
      );
      expect(task.categoryName, 'Kalıcı iş');
      expect(task.toJson()['categoryName'], 'Kalıcı iş');
    });
  });

  group('Z1 — görünen ad', () {
    test('hazır adlar tek kısa kelime (K1)', () {
      expect(categoryLabel('Kalıcı iş'), 'Mesai');
      expect(categoryLabel('Günlük rutin'), 'Gündelik');
      expect(categoryLabel('Haftalık / ara sıra'), 'Seyrek');
      expect(categoryLabel('Önemli / acil'), 'Acil');
      expect(categoryLabel('Hobi / keyfi'), 'Hobi');
      for (final label in kCategoryLabels.values) {
        expect(
          label.contains(' '),
          isFalse,
          reason: '"$label" tek kelime değil',
        );
        expect(label.contains('/'), isFalse, reason: '"$label" eğik çizgili');
      }
    });

    test('noktasız I hiçbir görünen adda geçmiyor', () {
      // Türkçe tuzağı: Dart varsayılan yerelde 'iş'.toUpperCase() için IŞ
      // üretir, İŞ değil. Büyük harfe çevirmeyi koda bırakan bir düzeltme
      // ekranda "Kalıcı Iş" yazdırırdı. Adlar elle yazılıyor; bu tarama
      // ileride eklenecek bir ad için de geçerli.
      for (final label in kCategoryLabels.values) {
        expect(
          label.contains('I'),
          isFalse,
          reason: '"$label" noktasız I taşıyor; İ olmalı',
        );
      }
    });

    test('özel kategori olduğu gibi görünüyor', () {
      // Kullanıcının kendi yazdığı ada karışmak, onu kendi verisinde
      // tanınmaz hâle getirirdi.
      expect(categoryLabel('spor salonu'), 'spor salonu');
      expect(categoryLabel('İş görüşmeleri'), 'İş görüşmeleri');
    });

    test('her hazır kategorinin bir görünen adı var', () {
      // Kategori eklenip görünen adı unutulursa ekranda depolanan ad
      // görünür — sessizce eski yazıma dönmek budur.
      for (final cat in AppData.categories) {
        expect(cat.label.isNotEmpty, isTrue);
      }
    });
  });
}
