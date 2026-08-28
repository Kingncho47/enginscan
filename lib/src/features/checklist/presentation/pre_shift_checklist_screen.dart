import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/checklist_repository.dart';
import '../domain/checklist_models.dart';

/// Controle de securite avant mise en service (pre-shift inspection) :
/// points critiques a valider un par un, historique persiste en local.
class PreShiftChecklistScreen extends StatefulWidget {
  const PreShiftChecklistScreen({super.key});

  @override
  State<PreShiftChecklistScreen> createState() =>
      _PreShiftChecklistScreenState();
}

class _PreShiftChecklistScreenState extends State<PreShiftChecklistScreen> {
  final TextEditingController _operatorCtrl = TextEditingController();
  final TextEditingController _machineCtrl = TextEditingController();

  /// Reponses par identifiant de point ; absence = pas encore traite.
  final Map<String, CheckState> _answers = <String, CheckState>{};
  final Map<String, String> _notes = <String, String>{};
  int _historyRefresh = 0;

  int get _okCount =>
      _answers.values.where((s) => s == CheckState.ok).length;
  int get _nokCount =>
      _answers.values.where((s) => s == CheckState.nok).length;
  int get _naCount =>
      _answers.values.where((s) => s == CheckState.na).length;

  bool get _isComplete =>
      _answers.length == kPreShiftChecklist.length &&
      !_answers.containsValue(null);

  String get _operatorName {
    final t = _operatorCtrl.text.trim();
    return t.isEmpty ? 'Non renseigne' : t;
  }

  String get _machineLabel {
    final t = _machineCtrl.text.trim();
    return t.isEmpty ? 'Machine non renseignee' : t;
  }

  @override
  void dispose() {
    _operatorCtrl.dispose();
    _machineCtrl.dispose();
    super.dispose();
  }

  // ---- Validation ----------------------------------------------------------

  Future<void> _validate() async {
    final remaining = kPreShiftChecklist.length - _answers.length;
    final messenger = ScaffoldMessenger.of(context);
    final repo = context.read<ChecklistRepository>();

    if (remaining > 0) {
      messenger.showSnackBar(SnackBar(
          content: Text('Il reste $remaining point(s) a controler.')));
      return;
    }

    // Confirmation obligatoire si des points sont non conformes.
    final noks = kPreShiftChecklist
        .where((i) => _answers[i.id] == CheckState.nok)
        .toList(growable: false);
    var confirmed = true;
    if (noks.isNotEmpty) {
      final criticalNoks =
          noks.where((i) => i.critical).map((i) => i.title).toList();
      confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Points non conformes'),
              content: Text(
                '${noks.length} point(s) NOK dont '
                '${criticalNoks.length} critique(s).\n\n'
                'Mise en service A DECONSEILLER tant que les points critiques '
                "ne sont pas corriges :\n\n"
                '- ${criticalNoks.join('\n- ')}',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Enregistrer quand meme'),
                ),
              ],
            ),
          ) ??
          false;
    }
    if (!confirmed || !mounted) return;

    try {
      final itemsJson = jsonEncode(<Map<String, String>>[
        for (final item in kPreShiftChecklist)
          <String, String>{
            'id': item.id,
            'state': _answers[item.id]!.name,
            'note': _notes[item.id] ?? '',
          },
      ]);
      final id = await repo.save(
        operator: _operatorName,
        machineLabel: _machineLabel,
        okCount: _okCount,
        nokCount: _nokCount,
        naCount: _naCount,
        itemsJson: itemsJson,
      );
      if (!mounted) return;
      setState(() {
        _answers.clear();
        _notes.clear();
        _historyRefresh++;
      });
      messenger.showSnackBar(
          SnackBar(content: Text('Controle #$id enregistre.')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text("Enregistrement impossible : $e")));
    }
  }

  // ---- Interface -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final categories = <String>[];
    for (final item in kPreShiftChecklist) {
      if (!categories.contains(item.category)) categories.add(item.category);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Controle avant mise en service'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Historique des controles',
            icon: const Icon(Icons.history),
            onPressed: _showHistory,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _operatorCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Operateur'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _machineCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                        labelText: 'Machine / parc n°'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: <Widget>[
                for (final category in categories) ...<Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
                    child: Text(
                      category.toUpperCase(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: Colors.white.withOpacity(0.65),
                      ),
                    ),
                  ),
                  for (final item in kPreShiftChecklist)
                    if (item.category == category)
                      _ChecklistItemCard(
                        item: item,
                        state: _answers[item.id],
                        note: _notes[item.id],
                        onEditNote: () => _editNote(item),
                        onSelected: (state) =>
                            setState(() => _answers[item.id] = state),
                        onNoteEdited: (note) =>
                            setState(() => _notes[item.id] = note),
                      ),
                ],
              ],
            ),
          ),
          // ---- Barre de synthese -------------------------------------------
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withOpacity(0.35),
              border:
                  const Border(top: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: <Widget>[
                _CountChip(label: 'OK $_okCount', color: const Color(0xFF43A047)),
                const SizedBox(width: 6),
                _CountChip(label: 'NOK $_nokCount', color: const Color(0xFFE53935)),
                const SizedBox(width: 6),
                _CountChip(label: 'N/A $_naCount', color: const Color(0xFF90A4AE)),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _validate,
                  icon: Icon(_isComplete ? Icons.check_circle : Icons.pending),
                  label: Text(_isComplete ? 'Valider' : 'Valider ($_okCount/${kPreShiftChecklist.length})'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Note par point -------------------------------------------------------

  Future<void> _editNote(ChecklistItem item) async {
    final controller = TextEditingController(text: _notes[item.id] ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Observation - ${item.title}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
              hintText: 'Ex : fuite legere au flexible n°3...'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (result == null) return;
    setState(() {
      if (result.isEmpty) {
        _notes.remove(item.id);
      } else {
        _notes[item.id] = result;
      }
    });
  }

  // ---- Historique -----------------------------------------------------------

  Future<void> _showHistory() async {
    final repo = context.read<ChecklistRepository>();
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: 420,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text('Historique des controles',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: FutureBuilder<List<ChecklistRunSummary>>(
                  key: ValueKey<int>(_historyRefresh),
                  future: repo.history(),
                  builder:
                      (context, AsyncSnapshot<List<ChecklistRunSummary>> snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    final runs = snap.data ?? const <ChecklistRunSummary>[];
                    if (runs.isEmpty) {
                      return const Center(child: Text('Aucun controle enregistre.'));
                    }
                    return ListView.builder(
                      itemCount: runs.length,
                      itemBuilder: (context, index) {
                        final run = runs[index];
                        return ListTile(
                          leading: Icon(
                            run.nokCount > 0
                                ? Icons.error_outline
                                : Icons.check_circle_outline,
                            color: run.nokCount > 0
                                ? const Color(0xFFE53935)
                                : const Color(0xFF43A047),
                          ),
                          title: Text('${run.machineLabel} - ${run.operator}',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(_formatDate(run.createdAt)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                  'OK ${run.okCount} · NOK ${run.nokCount} · N/A ${run.naCount}',
                                  style: const TextStyle(fontSize: 12)),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 22),
                                onPressed: () async {
                                  await repo.delete(run.id);
                                  setState(() => _historyRefresh++);
                                  if (sheetContext.mounted) {
                                    Navigator.of(sheetContext).pop();
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day}/${d.month}/${d.year} a $hh:$mm';
  }
}

// ---------------------------------------------------------------------------
// Carte d'un point de controle : titre + boutons segmentes OK/NOK/N/A.
// ---------------------------------------------------------------------------
class _ChecklistItemCard extends StatelessWidget {
  const _ChecklistItemCard({
    required this.item,
    required this.state,
    required this.note,
    required this.onEditNote,
    required this.onSelected,
    required this.onNoteEdited,
  });

  final ChecklistItem item;
  final CheckState? state;
  final String? note;
  final VoidCallback onEditNote;
  final ValueChanged<CheckState> onSelected;
  final ValueChanged<String> onNoteEdited;

  Color get _borderColor {
    switch (state) {
      case CheckState.ok:
        return const Color(0xFF43A047).withOpacity(0.7);
      case CheckState.nok:
        return const Color(0xFFE53935);
      case CheckState.na:
        return const Color(0xFF90A4AE).withOpacity(0.6);
      default:
        return Colors.white12;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _borderColor, width: state == null ? 1 : 1.6),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    item.title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                if (item.critical)
                  const Tooltip(
                    message: 'Point critique : NOK = mise en service bloquee',
                    child: Icon(Icons.priority_high_rounded,
                        size: 20, color: Color(0xFFFFB300)),
                  ),
                IconButton(
                  tooltip: 'Ajouter une observation',
                  icon: Icon(
                    (note == null || note!.isEmpty)
                        ? Icons.notes_outlined
                        : Icons.sticky_note_2,
                    size: 22,
                  ),
                  onPressed: onEditNote,
                ),
              ],
            ),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<CheckState>(
                showSelectedIcon: false,
                segments: const <ButtonSegment<CheckState>>[
                  ButtonSegment<CheckState>(
                    value: CheckState.ok,
                    icon: Icon(Icons.check_circle_outline, size: 22),
                    label: Text('OK'),
                  ),
                  ButtonSegment<CheckState>(
                    value: CheckState.nok,
                    icon: Icon(Icons.cancel_outlined, size: 22),
                    label: Text('NOK'),
                  ),
                  ButtonSegment<CheckState>(
                    value: CheckState.na,
                    icon: Icon(Icons.remove_circle_outline, size: 22),
                    label: Text('N/A'),
                  ),
                ],
                selected: <CheckState>{
                  if (state != null) state!,
                },
                onSelectionChanged: (Set<CheckState> selection) {
                  if (selection.isEmpty) return;
                  onSelected(selection.first);
                },
              ),
            ),
            if (note != null && note!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Note : $note',
                  style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: Colors.white.withOpacity(0.65)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Petit badge de compteur coloré pour la barre de synthese.
class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: color)),
    );
  }
}
