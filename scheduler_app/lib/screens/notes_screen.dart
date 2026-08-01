import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_store.dart';
import '../models/node.dart';
import '../services/link_index.dart';
import '../theme.dart';
import 'section_header.dart';

/// Bilgi bankası: Markdown notlar + Obsidian tarzı [[çift yönlü bağlantı]].
/// Bir notu açınca hem verdiği bağlantılar hem de ona gelen backlink'ler
/// (notlardan VE görevlerden) görünür; her ikisi de tıklanabilir.
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  String? _openId; // null => liste görünümü

  void _open(String id) => setState(() => _openId = id);
  void _close() => setState(() => _openId = null);

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(appStoreProvider);
    if (_openId != null) {
      final note = store.notes.where((n) => n.id == _openId).firstOrNull;
      if (note != null) {
        return _NoteDetail(
          key: ValueKey(note.id),
          note: note,
          onBack: _close,
          onOpenNote: _open,
        );
      }
      // Not silinmişse listeye dön.
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
    }
    return _NoteList(onOpen: _open);
  }
}

// --- Liste görünümü ----------------------------------------------------------

class _NoteList extends ConsumerWidget {
  final ValueChanged<String> onOpen;
  const _NoteList({required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesProvider);
    final store = ref.read(appStoreProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final note = Note(title: 'Yeni not');
          store.addNote(note);
          onOpen(note.id);
        },
        child: const Icon(Icons.add, size: 22),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Notlar',
              subtitle: notes.isEmpty
                  ? 'Bilgi bankası'
                  : '${notes.length} not · [[ ]] ile bağla',
            ),
            const Divider(color: AppColors.lineSoft, height: 1),
            Expanded(
              child: notes.isEmpty
                  ? const _Empty()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
                      itemCount: notes.length,
                      itemBuilder: (_, i) => _NoteRow(
                        note: notes[i],
                        backlinkCount:
                            store.backlinkNodes(notes[i].id).length,
                        onTap: () => onOpen(notes[i].id),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined, size: 34, color: AppColors.inkFaint),
            SizedBox(height: 12),
            Text(
              'Henüz not yok.\nBir görevden [[Not Adı]] yazınca köprü kurulur.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.inkFaint,
                fontSize: 13.5,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
}

class _NoteRow extends StatelessWidget {
  final Note note;
  final int backlinkCount;
  final VoidCallback onTap;
  const _NoteRow({
    required this.note,
    required this.backlinkCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final preview = note.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.lineSoft),
        ),
        child: Row(
          children: [
            const Icon(Icons.description_outlined,
                size: 18, color: AppColors.inkDim),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.title.isEmpty ? 'Başlıksız' : note.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (preview.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.inkFaint,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (backlinkCount > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.hover,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link_rounded,
                        size: 13, color: AppColors.inkDim),
                    const SizedBox(width: 3),
                    Text(
                      '$backlinkCount',
                      style: const TextStyle(
                        color: AppColors.inkDim,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// --- Detay / editör ----------------------------------------------------------

class _NoteDetail extends ConsumerStatefulWidget {
  final Note note;
  final VoidCallback onBack;
  final ValueChanged<String> onOpenNote;
  const _NoteDetail({
    super.key,
    required this.note,
    required this.onBack,
    required this.onOpenNote,
  });

  @override
  ConsumerState<_NoteDetail> createState() => _NoteDetailState();
}

class _NoteDetailState extends ConsumerState<_NoteDetail> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;
  final _bodyFocus = FocusNode();

  /// Store'u initState'te yakala: dispose sırasında `ref` kullanılamaz.
  late final AppStore _store;

  @override
  void initState() {
    super.initState();
    _store = ref.read(appStoreProvider);
    _titleCtrl = TextEditingController(text: widget.note.title);
    _bodyCtrl = TextEditingController(text: widget.note.body);
  }

  @override
  void dispose() {
    // Yalnızca modeli yaz; notifyListeners'ı finalize sırasında tetikleme.
    _writeBack();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  /// Controller'lardaki metni not modeline yazar (bildirim yok).
  void _writeBack() {
    widget.note.title = _titleCtrl.text.trim().isEmpty
        ? 'Başlıksız'
        : _titleCtrl.text.trim();
    widget.note.body = _bodyCtrl.text;
  }

  void _back() {
    _writeBack();
    _store.updateNote(widget.note); // listeyi tazele + updatedAt
    widget.onBack();
  }

  /// İmleç konumuna `[[Başlık]]` ekler.
  void _insertLink(String title) {
    final sel = _bodyCtrl.selection;
    final text = _bodyCtrl.text;
    final insert = '[[$title]]';
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    final newText = text.replaceRange(start, end, insert);
    _bodyCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
    setState(() {}); // bağlantı panelini tazele
  }

  Future<void> _openLinkPicker() async {
    final store = ref.read(appStoreProvider);
    final title = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LinkPicker(
        nodes: store.nodes.where((n) => n.id != widget.note.id).toList(),
      ),
    );
    if (title != null && title.isNotEmpty) {
      // Var olan başlık değilse yeni bir not oluştur (Obsidian davranışı).
      if (store.resolveLink(title) == null) {
        store.addNote(Note(title: title));
      }
      _insertLink(title);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(appStoreProvider);

    final outTitles = LinkIndex.extractLinkTitles(_bodyCtrl.text);
    final backlinks = store.backlinkNodes(widget.note.id);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Üst bar
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _back,
                    icon: const Icon(Icons.arrow_back_rounded,
                        size: 20, color: AppColors.inkDim),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _openLinkPicker,
                    icon: const Icon(Icons.add_link_rounded, size: 18),
                    label: const Text('Bağla'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                children: [
                  TextField(
                    controller: _titleCtrl,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Başlık',
                      hintStyle: TextStyle(color: AppColors.inkFaint),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _bodyCtrl,
                    focusNode: _bodyFocus,
                    maxLines: null,
                    minLines: 6,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 15,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText:
                          'Markdown yaz… başka bir nota köprü için [[Not Adı]].',
                      hintStyle: TextStyle(color: AppColors.inkFaint),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 24),
                  if (outTitles.isNotEmpty) ...[
                    const _PanelLabel(
                        icon: Icons.north_east_rounded,
                        text: 'Bu notun bağlantıları'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in outTitles.toSet())
                          _LinkChip(
                            title: t,
                            target: store.resolveLink(t),
                            onOpenNote: widget.onOpenNote,
                          ),
                      ],
                    ),
                    const SizedBox(height: 22),
                  ],
                  const _PanelLabel(
                      icon: Icons.south_west_rounded,
                      text: 'Backlinks (buraya bağlananlar)'),
                  const SizedBox(height: 8),
                  if (backlinks.isEmpty)
                    Text(
                      'Henüz kimse bu nota bağlanmadı. Bir görevin ya da notun '
                      'açıklamasında [[${widget.note.title}]] yaz.',
                      style: const TextStyle(
                        color: AppColors.inkFaint,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    )
                  else
                    Column(
                      children: [
                        for (final n in backlinks)
                          _BacklinkRow(
                            node: n,
                            onTap: n.kind == NodeKind.note
                                ? () => widget.onOpenNote(n.id)
                                : null,
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelLabel extends StatelessWidget {
  final IconData icon;
  final String text;
  const _PanelLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.inkFaint),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            color: AppColors.inkFaint,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

class _LinkChip extends StatelessWidget {
  final String title;
  final Node? target;
  final ValueChanged<String> onOpenNote;
  const _LinkChip({
    required this.title,
    required this.target,
    required this.onOpenNote,
  });

  @override
  Widget build(BuildContext context) {
    final broken = target == null;
    final isNote = target?.kind == NodeKind.note;
    final color = broken ? AppColors.amber : AppColors.blue;

    return GestureDetector(
      onTap: isNote ? () => onOpenNote(target!.id) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              broken
                  ? Icons.link_off_rounded
                  : (isNote
                      ? Icons.description_outlined
                      : Icons.check_circle_outline_rounded),
              size: 13,
              color: color,
            ),
            const SizedBox(width: 5),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BacklinkRow extends StatelessWidget {
  final Node node;
  final VoidCallback? onTap;
  const _BacklinkRow({required this.node, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isTask = node.kind == NodeKind.task;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.lineSoft),
        ),
        child: Row(
          children: [
            Icon(
              isTask ? Icons.check_circle_outline_rounded : Icons.description_outlined,
              size: 16,
              color: isTask ? AppColors.pink : AppColors.blue,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                node.title.isEmpty ? 'Başlıksız' : node.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              isTask ? 'Görev' : 'Not',
              style: const TextStyle(
                color: AppColors.inkFaint,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Bağlantı seçici ---------------------------------------------------------

class _LinkPicker extends StatefulWidget {
  final List<Node> nodes;
  const _LinkPicker({required this.nodes});

  @override
  State<_LinkPicker> createState() => _LinkPickerState();
}

class _LinkPickerState extends State<_LinkPicker> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim().toLowerCase();
    final matches = widget.nodes
        .where((n) => n.title.toLowerCase().contains(q))
        .take(30)
        .toList();
    final canCreate = q.isNotEmpty &&
        !widget.nodes.any((n) => n.title.toLowerCase() == q);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _query,
                autofocus: true,
                style: const TextStyle(color: AppColors.ink),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 18, color: AppColors.inkFaint),
                  hintText: 'Not/görev ara ya da yeni not adı yaz…',
                  hintStyle: const TextStyle(color: AppColors.inkFaint),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  if (canCreate)
                    ListTile(
                      leading: const Icon(Icons.add_rounded,
                          color: AppColors.blue),
                      title: Text('"${_query.text.trim()}" notunu oluştur ve bağla',
                          style: const TextStyle(
                              color: AppColors.ink, fontSize: 14)),
                      onTap: () =>
                          Navigator.pop(context, _query.text.trim()),
                    ),
                  for (final n in matches)
                    ListTile(
                      leading: Icon(
                        n.kind == NodeKind.task
                            ? Icons.check_circle_outline_rounded
                            : Icons.description_outlined,
                        size: 18,
                        color: n.kind == NodeKind.task
                            ? AppColors.pink
                            : AppColors.blue,
                      ),
                      title: Text(
                        n.title.isEmpty ? 'Başlıksız' : n.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.ink, fontSize: 14),
                      ),
                      onTap: () => Navigator.pop(context, n.title),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
