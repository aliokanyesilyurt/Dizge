import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/app_config.dart';
import '../local_store.dart';
import 'mutation.dart';

/// Gönderilmeyi bekleyen mutasyonların kalıcı kuyruğu.
///
/// Neden var: kullanıcı uçakta plan yaptığında değişiklikler kaybolmamalı.
/// Uygulama kapansa bile kuyruk şifreli depoda durur, bir sonraki açılışta
/// kaldığı yerden devam eder.
///
/// **Daraltma (compaction):** aynı kayda arka arkaya 20 kez dokunulduysa
/// (sürükle-bırak sırasında tipik) sunucuya 20 istek göndermenin anlamı yok.
/// [enqueue] aynı `entityId` için bekleyen eski `upsert`'ü **değiştirir**;
/// böylece kuyruk kaydın son hâlini taşır. `delete` gelirse o kayda ait tüm
/// bekleyenler düşer.
class Outbox {
  Outbox(this._store);

  final LocalStore _store;
  final List<Mutation> _pending = [];

  static const _storageKey = 'outbox';

  /// Kuyruk değişince tetiklenir (senkron motoru dinler).
  final _changes = StreamController<int>.broadcast();
  Stream<int> get changes => _changes.stream;

  List<Mutation> get pending => List.unmodifiable(_pending);
  int get length => _pending.length;
  bool get isEmpty => _pending.isEmpty;

  /// Diskteki kuyruğu belleğe alır. Bootstrap'ta bir kez çağrılır.
  void load() {
    _pending
      ..clear()
      ..addAll(_store.readList(_storageKey).map(Mutation.fromJson));
    if (_pending.isNotEmpty) {
      debugPrint('Outbox: ${_pending.length} bekleyen değişiklik yüklendi.');
    }
  }

  void enqueue(Mutation mutation) {
    if (mutation.op == MutationOp.delete) {
      // Silinen kaydın bekleyen güncellemelerini göndermenin anlamı yok.
      _pending.removeWhere((m) => m.entityId == mutation.entityId);
      _pending.add(mutation);
    } else {
      final i = _pending.indexWhere(
        (m) => m.entityId == mutation.entityId && m.op == MutationOp.upsert,
      );
      // Yerini koru: kuyruğun genel sırası (nedensellik) bozulmasın.
      i == -1 ? _pending.add(mutation) : _pending[i] = mutation;
    }

    // Sınırı aşarsa en eskiler düşer. Bu, uzak veriyle yerelin ayrışması
    // demektir; bayrağı kaldırıp tam anlık görüntü senkronu istiyoruz.
    if (_pending.length > AppConfig.outboxLimit) {
      final overflow = _pending.length - AppConfig.outboxLimit;
      _pending.removeRange(0, overflow);
      needsFullPush = true;
      debugPrint('Outbox taştı: $overflow kayıt düştü, tam senkron gerekli.');
    }

    _notify();
  }

  /// Kuyruk taştığı için artımlı senkron güvenilir değil; bir sonraki fırsatta
  /// tüm anlık görüntü gönderilmeli.
  bool needsFullPush = false;

  /// Gönderimi başarılı olan mutasyonları kuyruktan düşürür.
  void ack(Iterable<String> mutationIds) {
    final ids = mutationIds.toSet();
    if (ids.isEmpty) return;
    _pending.removeWhere((m) => ids.contains(m.id));
    _notify();
  }

  /// Gönderimi başarısız olanların deneme sayacını artırır. Belirli sayıdan
  /// sonra "zehirli" kabul edilip düşürülür — tek bozuk kayıt tüm kuyruğu
  /// sonsuza dek tıkamasın.
  void markFailed(Iterable<String> mutationIds, {int maxAttempts = 8}) {
    final ids = mutationIds.toSet();
    if (ids.isEmpty) return;
    for (var i = _pending.length - 1; i >= 0; i--) {
      if (!ids.contains(_pending[i].id)) continue;
      final next = _pending[i].withAttempt();
      if (next.attempts >= maxAttempts) {
        debugPrint('Outbox: $next $maxAttempts denemede gönderilemedi, düşürüldü.');
        _pending.removeAt(i);
        needsFullPush = true;
      } else {
        _pending[i] = next;
      }
    }
    _notify();
  }

  Future<void> persist() =>
      _store.writeList(_storageKey, [for (final m in _pending) m.toJson()]);

  Future<void> clear() async {
    _pending.clear();
    needsFullPush = false;
    await persist();
    _notify();
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(_pending.length);
  }

  Future<void> dispose() async {
    await _changes.close();
  }
}
