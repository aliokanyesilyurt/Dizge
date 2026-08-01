import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/data/app_store.dart';
import 'package:scheduler_app/models/node.dart';
import 'package:scheduler_app/models/task.dart';
import 'package:scheduler_app/services/link_index.dart';

void main() {
  setUp(TaskRepository.all.clear);

  test('Task JSON round-trip tüm alanları korur', () {
    final task = Task(
      title: 'Telemetri kodu',
      note: 'Pinout için [[ESP32 Pinout]] notuna bak',
      color: const Color(0xFF4FC3F7),
      date: DateTime(2026, 7, 20),
      startHour: 14.0,
      durationHours: 1.5,
      tags: {'yazılım', 'donanım'},
      status: TaskStatus.doing,
      priority: 2,
      timeSpentMinutes: 45,
      repeat: const Repeat(RepeatType.weekly, weekdays: {1, 3, 5}),
    );

    final clone = Task.fromJson(task.toJson());

    expect(clone.id, task.id);
    expect(clone.title, 'Telemetri kodu');
    expect(clone.body, contains('[[ESP32 Pinout]]'));
    expect(clone.startHour, 14.0);
    expect(clone.tags, {'yazılım', 'donanım'});
    expect(clone.status, TaskStatus.doing);
    expect(clone.priority, 2);
    expect(clone.timeSpentMinutes, 45);
    expect(clone.repeat.type, RepeatType.weekly);
    expect(clone.repeat.weekdays, {1, 3, 5});
  });

  test('LinkIndex çift yönlü bağlantı kurar', () {
    final note = Note(title: 'ESP32 Pinout', body: '# SDA=21, SCL=22');
    final task = Task(
      title: 'Telemetri kodu',
      note: 'Pinout için [[ESP32 Pinout]] notuna bak',
      color: const Color(0xFF4FC3F7),
      date: DateTime(2026, 7, 20),
    );

    final index = LinkIndex.build([task, note]);

    // İleri bağlantı: görev -> not
    expect(index.linksFrom(task.id), {note.id});
    // Backlink (çift yönlü): not <- görev
    expect(index.linksTo(note.id), {task.id});
    expect(index.resolveTitle('esp32 pinout'), note.id); // case-insensitive
  });

  test('AppStore görev + not birlikte bağlantıyı çözer', () {
    final store = AppStore();
    final note = Note(title: 'ESP32 Pinout', body: 'pinler');
    store.addNote(note);
    store.addTask(Task(
      title: 'Kod',
      note: 'bkz [[ESP32 Pinout]]',
      color: const Color(0xFF4FC3F7),
      date: DateTime(2026, 7, 20),
    ));

    expect(store.resolveLink('ESP32 Pinout')?.id, note.id);
    expect(store.backlinkNodes(note.id), hasLength(1));
  });

  test('çözülemeyen [[ ]] bağlantı kırık olarak işaretlenir', () {
    final task = Task(
      title: 'Kod',
      note: 'henüz olmayan [[Gizli Not]]',
      color: const Color(0xFF4FC3F7),
      date: DateTime(2026, 7, 20),
    );
    final index = LinkIndex.build([task]);

    expect(index.linksFrom(task.id), isEmpty);
    expect(index.unresolvedByNode[task.id], {'Gizli Not'});
  });
}
