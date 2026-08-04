import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_store.dart';
import '../models/node.dart';
import '../services/link_index.dart';
import '../theme.dart';
import 'section_header.dart';
import 'task_list_scaffold.dart' show EmptyState;

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
    final c = context.colors;
    final notes = ref.watch(notesProvider);
    final store = ref.read(appStoreProvider);

    return Scaffold(
      backgroundColor: c.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final note = Note(title: 'Yeni not');
          store.addNote(note);
          onOpen(note.id);
        },
        child: const Icon(Icons.add_rounded, size: 24),
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
            Expanded(
              child: notes.isEmpty
                  ? const EmptyState(
                      icon: Icons.article_rounded,
                      title: 'Henüz not yok.',
                      text: 'Bir görevden [[Not Adı]] yazınca köprü kurulur.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
                      itemCount: notes.length,
                      itemBuilder: (_, i) => _NoteRow(
                        note: notes[i],
                        backlinkCount: store.backlinkNodes(notes[i].id).length,
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

class _NoteRow extends StatefulWidget {
  final Note note;
  final int backlinkCount;
  final VoidCallback onTap;
  const _NoteRow({
    required this.note,
    required this.backlinkCount,
    required this.onTap,
  });

  @override
  State<_NoteRow> createState() => _NoteRowState();
}

class _NoteRowState extends State<_NoteRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final preview = widget.note.body.replaceAll(RegExp(r'\s+'), ' ').trim();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.curve,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: R.radiusMd,
            border: Border.all(color: _hovered ? c.line : c.lineSoft),
            boxShadow: _hovered ? c.shadowMd : c.shadowSm,
          ),
          child: Row(
            children: [
              Icon(Icons.description_rounded, size: 18, color: c.inkDim),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.note.title.isEmpty
                          ? 'Başlıksız'
                          : widget.note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.ink,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                      ),
                    ),
                    if (preview.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.inkFaint,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.backlinkCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: c.hover,
                    borderRadius: R.radiusPill,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.link_rounded, size: 13, color: c.inkDim),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.backlinkCount}',
                        style: TextStyle(
                          color: c.inkDim,
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
    final c = context.colors;
    final store = ref.watch(appStoreProvider);

    final outTitles = LinkIndex.extractLinkTitles(_bodyCtrl.text);
    final backlinks = store.backlinkNodes(widget.note.id);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Üst bar
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _back,
                    tooltip: 'Geri',
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      size: 20,
                      color: c.inkDim,
                    ),
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
              child: Center(
                child: ConstrainedBox(
                  // Uzun satırlar okunmaz olmasın: ölçü ~70 karakter.
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 6, 24, 48),
                    children: [
                      TextField(
                        controller: _titleCtrl,
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                        ),
                        decoration: InputDecoration(
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          hintText: 'Başlık',
                          hintStyle: TextStyle(
                            color: c.inkFaint,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.6,
                          ),
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _bodyCtrl,
                        focusNode: _bodyFocus,
                        maxLines: null,
                        minLines: 6,
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 15,
                          height: 1.6,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          hintText:
                              'Markdown yaz… başka bir nota köprü için [[Not Adı]].',
                          hintStyle: TextStyle(color: c.inkFaint),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 32),
                      if (outTitles.isNotEmpty) ...[
                        const _PanelLabel(
                          icon: Icons.north_east_rounded,
                          text: 'Bu notun bağlantıları',
                        ),
                        const SizedBox(height: 10),
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
                        const SizedBox(height: 26),
                      ],
                      const _PanelLabel(
                        icon: Icons.south_west_rounded,
                        text: 'Backlinks (buraya bağlananlar)',
                      ),
                      const SizedBox(height: 10),
                      if (backlinks.isEmpty)
                        Text(
                          'Henüz kimse bu nota bağlanmadı. Bir görevin ya da '
                          'notun açıklamasında [[${widget.note.title}]] yaz.',
                          style: TextStyle(
                            color: c.inkFaint,
                            fontSize: 12.5,
                            height: 1.5,
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
    final c = context.colors;

    return Row(
      children: [
        Icon(icon, size: 13, color: c.inkFaint),
        const SizedBox(width: 7),
        // Karışık büyük/küçük harf olduğu için `labelSmall`ın geniş harf
        // aralığı yerine daha sıkı bir ölçü.
        Text(
          text,
          style: TextStyle(
            color: c.inkFaint,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
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
    final c = context.colors;
    final broken = target == null;
    final isNote = target?.kind == NodeKind.note;
    final color = broken ? c.warning : c.accent;

    return GestureDetector(
      onTap: isNote ? () => onOpenNote(target!.id) : null,
      child: MouseRegion(
        cursor: isNote ? SystemMouseCursors.click : MouseCursor.defer,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: c.isDark ? 0.13 : 0.09),
            borderRadius: R.radiusPill,
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                broken
                    ? Icons.link_off_rounded
                    : (isNote
                          ? Icons.description_rounded
                          : Icons.check_circle_rounded),
                size: 13,
                color: color,
              ),
              const SizedBox(width: 6),
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
    final c = context.colors;
    final isTask = node.kind == NodeKind.task;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: R.radiusMd,
            border: Border.all(color: c.lineSoft),
            boxShadow: c.shadowSm,
          ),
          child: Row(
            children: [
              Icon(
                isTask ? Icons.check_circle_rounded : Icons.description_rounded,
                size: 16,
                color: isTask ? c.secondary : c.accent,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  node.title.isEmpty ? 'Başlıksız' : node.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                isTask ? 'Görev' : 'Not',
                style: TextStyle(
                  color: c.inkFaint,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
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
    final c = context.colors;
    final q = _query.text.trim().toLowerCase();
    final matches = widget.nodes
        .where((n) => n.title.toLowerCase().contains(q))
        .take(30)
        .toList();
    final canCreate =
        q.isNotEmpty && !widget.nodes.any((n) => n.title.toLowerCase() == q);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 6),
              decoration: BoxDecoration(
                color: c.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
              child: TextField(
                controller: _query,
                autofocus: true,
                style: TextStyle(color: c.ink),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: c.inkFaint,
                  ),
                  hintText: 'Not/görev ara ya da yeni not adı yaz…',
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  if (canCreate)
                    ListTile(
                      shape: RoundedRectangleBorder(borderRadius: R.radiusSm),
                      leading: Icon(Icons.add_rounded, color: c.accent),
                      title: Text(
                        '"${_query.text.trim()}" notunu oluştur ve bağla',
                        style: TextStyle(color: c.ink, fontSize: 14),
                      ),
                      onTap: () => Navigator.pop(context, _query.text.trim()),
                    ),
                  for (final n in matches)
                    ListTile(
                      shape: RoundedRectangleBorder(borderRadius: R.radiusSm),
                      leading: Icon(
                        n.kind == NodeKind.task
                            ? Icons.check_circle_rounded
                            : Icons.description_rounded,
                        size: 18,
                        color: n.kind == NodeKind.task ? c.secondary : c.accent,
                      ),
                      title: Text(
                        n.title.isEmpty ? 'Başlıksız' : n.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.ink, fontSize: 14),
                      ),
                      onTap: () => Navigator.pop(context, n.title),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
