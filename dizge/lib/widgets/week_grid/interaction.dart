/// Haftalık ızgaranın sürükleme ve yeniden boyutlandırma durumu.
///
/// Ekranda hiçbir şey çizmez; `WeekTimeGrid` state'inin elinde tuttuğu iki
/// küçük veri kabıdır. Kendi dosyasında duruyorlar ki ızgaranın yerleşim
/// kodunu okurken araya girmesinler.
library;

import 'dart:ui' show Offset;

import '../../models/task.dart';

/// Sürükleme sırasında taşınan bloğun geçici durumu.
class DragState {
  DragState({
    required this.task,
    required this.sourceDayIndex,
    required this.grabDy,
    required this.dayIndex,
    required this.startHour,
  });

  final Task task;
  final int sourceDayIndex;

  /// Parmağın blok içindeki dikey konumu — blok parmağın altından kaymasın.
  final double grabDy;

  int dayIndex;
  double startHour;

  /// Parmağın en son bulunduğu küresel nokta. Bırakma anında "ızgaranın
  /// içinde mi, havuzun üstünde mi" sorusunu cevaplayan tek bilgi;
  /// `LongPressEndDetails` bunu güvenilir biçimde vermiyor.
  Offset lastGlobal = Offset.zero;

  /// Havuzun üstünde mi (görsel geri bildirim ve bırakma kararı için).
  bool overPool = false;
}

/// Alt kenardan süre değiştirme durumu.
class ResizeState {
  ResizeState({required this.task, required this.duration})
    : startDuration = duration;

  final Task task;

  /// Çekmenin başladığı andaki süre. Yuvarlama bunun üstüne eklenen
  /// **toplam** harekete uygulanıyor, tek tek olaylara değil.
  final double startDuration;

  /// Çekme başından beri biriken ham dikey hareket (piksel).
  ///
  /// Neden birikiyor: fare her olayda 1–5 px ilerliyor. Her adım ayrı ayrı
  /// 15 dakikaya yuvarlandığında 3 px (≈3 dk) sıfıra iniyor ve yavaş çekilen
  /// tutamak süreyi hiç değiştirmiyordu.
  double accumulatedDy = 0;

  double duration;
}
