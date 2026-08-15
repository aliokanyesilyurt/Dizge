import '../models/task.dart';

/// "Günü kurtar" düğmesinin ne yapacağının kararı — uygulanmadan önce.
///
/// Plan §6'nın davranış sözleşmesi burada, arayüzden ayrı duruyor. Sebebi
/// tek: tek tıkla sekiz işi kımıldatan bir düğmenin kuralları bir widget
/// testinin arkasına saklanamaz. Burası saf bir fonksiyon — hangi işin neden
/// seçildiği ekran açılmadan sınanabiliyor.
class DayRescuePlan {
  const DayRescuePlan({
    required this.day,
    required this.toPool,
    required this.toSkip,
  });

  const DayRescuePlan.empty(this.day) : toPool = const [], toSkip = const [];

  final DateTime day;

  /// Havuza taşınacak tek günlük işler. `date` korunur (bkz. K1).
  final List<Task> toPool;

  /// Bugünlüğüne atlanacak rutinler. Havuza girmezler (K2): "her gün
  /// tekrarlayan ama hiçbir gün görünmeyen iş" tanımsız bir şey.
  final List<Task> toSkip;

  int get total => toPool.length + toSkip.length;
  bool get isEmpty => total == 0;

  /// "6 iş kenara alındı" / "2 rutin atlandı" — onay ekranının ve bildirimin
  /// ortak metni. İki tür ayrı sayılıyor çünkü kullanıcı için ayrı şeyler:
  /// biri kenara alındı, biri bugünlük geçildi.
  String describe() {
    final parts = <String>[];
    if (toPool.isNotEmpty) parts.add('${toPool.length} iş kenara alındı');
    if (toSkip.isNotEmpty) parts.add('${toSkip.length} rutin atlandı');
    return parts.join(' · ');
  }
}

/// [day] gününde, [afterHour] saatinden sonrası için kurtarma planı çıkarır.
///
/// [dayTasks] o günün görünen işleri (havuzdakiler `occursOn` kapısından zaten
/// düşmüş olur).
///
/// Zaman kuralı — bilinçli: **başlamış bir iş süpürülmez.** Ölçüt bitiş değil
/// başlangıç saati: 14:00'te başlayıp 16:00'da biten bir işe 15:00'te
/// basıldığında iş muhtemelen o an yapılıyordur; onu kenara almak kullanıcının
/// elindeki şeyi masadan almak olurdu.
///
/// Saatsiz işler **her zaman** kapsamda: saatleri olmadığı için "geçmiş"
/// sayılamazlar ve zaten günün en çok suçluluk üreten yığını onlar.
DayRescuePlan planDayRescue(
  Iterable<Task> dayTasks, {
  required DateTime day,
  required double afterHour,
}) {
  final d = Task.dayKey(day);
  final toPool = <Task>[];
  final toSkip = <Task>[];

  for (final task in dayTasks) {
    if (!task.isRescuableOn(d)) continue;
    final start = task.startHour;
    if (start != null && start < afterHour) continue;

    (task.isRoutine ? toSkip : toPool).add(task);
  }

  return DayRescuePlan(day: d, toPool: toPool, toSkip: toSkip);
}

/// Saati kesirli saate çevirir: 14:30 -> 14.5.
double hourOf(DateTime time) => time.hour + time.minute / 60.0;
