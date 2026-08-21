/// Mutasyondan sonra çıkan "Geri al" bildirimi.
library;

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Yapılan işi duyurur ve beş saniye boyunca geri alma kapısı açık tutar.
///
/// Haftalık ızgaranın kendi metodu olarak doğdu; iptal kapısı dört ekrana
/// yayılınca (plan K3) aynı bildirimi dört yerde yeniden yazmak yerine buraya
/// çıktı. Bildirim metni her yerde aynı ritimde okunsun diye tek yer:
/// önce ne olduğu, sonra tek bir "Geri al".
void offerUndo(
  BuildContext context,
  String label,
  VoidCallback undo, {
  Duration duration = const Duration(seconds: 5),
}) {
  final sonner = ShadSonner.maybeOf(context);
  // Toaster yoksa (ör. ekranı tek başına kuran bir test) sessizce geç:
  // geri alma bir kolaylık, mutasyonun kendisi zaten gerçekleşti.
  if (sonner == null) return;

  final id = UniqueKey();
  sonner.show(
    ShadToast(
      id: id,
      title: Text(label),
      duration: duration,
      action: ShadButton.ghost(
        child: const Text('Geri al'),
        onPressed: () {
          undo();
          // Bildirim kendini kapatmıyor; geri alındıktan sonra ekranda
          // kalması "hâlâ geri alınabilir" izlenimi verirdi.
          sonner.hide(id);
        },
      ),
    ),
  );
}
