import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_store.dart';
import 'sync/outbox.dart';
import 'sync/sync_engine.dart';

/// Kalıcılık ve senkron nesnelerinin provider'ları.
///
/// Hepsi `bootstrap()` tarafından override edilir. Override edilmezse
/// (widget testleri) belleğe düşerler — testler diske yazmaz, ağa çıkmaz.

final localStoreProvider = Provider<LocalStore>((ref) => InMemoryStore());

final outboxProvider = Provider<Outbox>(
  (ref) => Outbox(ref.watch(localStoreProvider)),
);

/// Senkron motoru. Yalnızca gerçek bir [RemoteGateway] bağlıysa çalışır;
/// varsayılan (backend yok) durumda `null` kalır ki test ve yerel kullanımda
/// boşuna zamanlayıcı dönmesin.
final syncEngineProvider = Provider<SyncEngine?>((ref) => null);

/// Senkronun kullanıcıya gösterilebilir durumu. Motor yoksa hep [SyncState.idle].
final syncStateProvider = StreamProvider<SyncState>((ref) {
  final engine = ref.watch(syncEngineProvider);
  if (engine == null) return Stream.value(SyncState.idle);

  final controller = StreamController<SyncState>();
  void emit() => controller.add(engine.state.value);
  engine.state.addListener(emit);
  emit();
  ref.onDispose(() {
    engine.state.removeListener(emit);
    controller.close();
  });
  return controller.stream;
});
