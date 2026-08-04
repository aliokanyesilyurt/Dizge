import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

/// Uygulamadaki her "içerik parçası" bir [Node]'dur: hem görevler (Task) hem de
/// dokümanlar (Note) bu tabandan türer. Böylece etiketleme, [[bağlantı]] çözümü
/// ve arama tek bir soyutlama üzerinden çalışır (Obsidian tarzı graph yapısı).
///
/// Mimari karar — Veri formatı: runtime'da JSON, metin gövdesi ([body]) ise
/// Markdown string olarak saklanır. Yani meta veri (JSON) + içerik (Markdown)
/// aynı objede birleşir.
enum NodeKind { task, note }

const _uuid = Uuid();

/// Yeni node'lar için gerçek UUID üretir. (Eski kayıtlar string id'lerini korur.)
String newNodeId() => _uuid.v4();

/// Hem Task hem Note'un uyduğu ortak sözleşme. UI ve servisler mümkün olduğunca
/// bu arayüz üzerinden çalışmalı; tipe özel alanlar (dueDate, status vb.) ilgili
/// sınıfta yaşar.
abstract class Node {
  String get id;
  NodeKind get kind;

  /// Başlık — aynı zamanda [[Başlık]] bağlantılarının çözümlendiği anahtar.
  String get title;

  /// Markdown gövde. Görevlerde "açıklama", notlarda ana metin.
  String get body;

  /// Serbest etiketler (ör. "yazılım", "spor"). '#' işareti olmadan saklanır.
  Set<String> get tags;

  DateTime get createdAt;
  DateTime get updatedAt;

  Map<String, dynamic> toJson();
}

/// Saf doküman (bilgi bankası sayfası). Görev alanları yoktur; sadece metin +
/// bağlantılar. Bir görevden [[Not Adı]] ile buraya köprü kurulur.
class Note implements Node {
  @override
  final String id;
  @override
  String title;
  @override
  String body;
  @override
  final Set<String> tags;
  @override
  final DateTime createdAt;
  @override
  DateTime updatedAt;

  Note({
    String? id,
    this.title = '',
    this.body = '',
    Set<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? newNodeId(),
       tags = tags ?? <String>{},
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  @override
  NodeKind get kind => NodeKind.note;

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'note',
    'id': id,
    'title': title,
    'body': body,
    'tags': tags.toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Note.fromJson(Map<String, dynamic> j) => Note(
    id: j['id'] as String?,
    title: (j['title'] as String?) ?? '',
    body: (j['body'] as String?) ?? '',
    tags: readTags(j['tags']),
    createdAt: readDate(j['createdAt']),
    updatedAt: readDate(j['updatedAt']),
  );
}

// --- Serileştirme yardımcıları (tüm modeller ortak kullanır) ---------------

/// Renk <-> "AARRGGBB" hex string. JSON'da okunur ve platformdan bağımsız.
String colorToHex(Color c) =>
    c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();

Color colorFromHex(String? hex, {Color fallback = const Color(0xFF4FC3F7)}) {
  if (hex == null) return fallback;
  final v = int.tryParse(hex, radix: 16);
  return v == null ? fallback : Color(v);
}

/// Saat/dakika kırpılmış, yalnızca gün taşıyan tarih. Set anahtarı olarak kullanılır.
DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Yalnızca gün hassasiyetli tarih (YYYY-MM-DD).
String dateToKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? dateFromKeyOrNull(String? s) =>
    s == null ? null : DateTime.tryParse(s);

/// Tam zaman damgası; eksik/boşsa "şimdi"ye düşer (geriye dönük kayıtlar için).
DateTime readDate(dynamic v) {
  if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
  return DateTime.now();
}

Set<String> readTags(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toSet() : <String>{};
