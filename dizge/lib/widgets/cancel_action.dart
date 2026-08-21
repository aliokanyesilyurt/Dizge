/// "Bugün iptal" eyleminin arayüz tarafı.
library;

import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../models/task.dart';
import 'undo_toast.dart';

/// Menüde ve düğmelerde yazan etiket. Tek kelime değişse bile dört ekranda
/// birden değişsin diye burada.
String cancelLabel(bool cancelled) =>
    cancelled ? 'İptali geri al' : 'Bugün iptal';

/// İptalin ikonu: geri almak "geri", iptal etmek "atla".
IconData cancelIcon(bool cancelled) =>
    cancelled ? Icons.undo_rounded : Icons.redo_rounded;

/// İşi o gün için iptal eder — iptalliyse geri alır — ve bildirimi gösterir.
///
/// Rutin/tek-günlük ayrımını [AppStore.cancelOn] yapıyor; buranın işi yalnız
/// hangi yöne gidileceğini seçmek ve dönen cümleyi ekrana taşımak. Dört ekran
/// (haftalık blok, aylık hücre, Rutinler, Yapılacaklar) bu tek çağrıyı
/// paylaşıyor: etiket de, bildirim de, geri alma da her yerde aynı.
void toggleCancelOn(
  BuildContext context,
  AppStore store,
  Task task,
  DateTime day, {
  String source = 'block',
}) {
  if (store.isCancelledOn(task, day)) {
    store.undoCancelOn(task, day, source: source);
    offerUndo(
      context,
      'İptal geri alındı',
      () => store.cancelOn(task, day, source: source),
    );
    return;
  }

  // Ne olduğunu mağaza söylüyor: "kenara alındı" mı "bugünlük atlandı" mı,
  // ekranın bilmesi gerekmiyor.
  final notice = store.cancelOn(task, day, source: source);
  offerUndo(
    context,
    notice,
    () => store.undoCancelOn(task, day, source: source),
  );
}
