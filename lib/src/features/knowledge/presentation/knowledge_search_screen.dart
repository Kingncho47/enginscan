import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../diagnostics/presentation/widgets/dtc_card.dart';
import '../../j1939/domain/models.dart';
import '../data/dtc_repository.dart';
import 'dtc_detail_screen.dart';

/// Recherche instantanee OFFLINE dans la base de connaissances DTC :
/// par code ("110-3"), par SPN ("110"), par marque ou par mot-cle.
class KnowledgeSearchScreen extends StatefulWidget {
  const KnowledgeSearchScreen({super.key});

  @override
  State<KnowledgeSearchScreen> createState() => _KnowledgeSearchScreenState();
}

class _KnowledgeSearchScreenState extends State<KnowledgeSearchScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  String _brand = 'Toutes';
  List<String> _brands = const <String>[];
  List<DtcModel> _results = const <DtcModel>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final repo = context.read<DtcRepository>();
    final brands = await repo.brands();
    if (!mounted) return;
    setState(() => _brands = brands);
    await _runSearch();
  }

  Future<void> _runSearch() async {
    final repo = context.read<DtcRepository>();
    setState(() => _loading = true);
    // Petite latence artificielle pour laisser le clavier se rendre la main.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final results =
        await repo.search(_searchCtrl.text, brand: _brand);
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _runSearch();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: "Code (ex : 102-3), SPN, marque, mot-cle...",
                prefixIcon: const Icon(Icons.search, size: 26),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _runSearch();
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('Toutes marques'),
                    selected: _brand == 'Toutes',
                    onSelected: (_) {
                      setState(() => _brand = 'Toutes');
                      _runSearch();
                    },
                  ),
                ),
                for (final b in _brands)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(b),
                      selected: _brand == b,
                      onSelected: (_) {
                        setState(() => _brand = b);
                        _runSearch();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Aucune fiche trouvee.\nEssayez un autre code ou mot-cle.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.6)),
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _runSearch,
                        child: ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (context, index) {
                            final dtc = _results[index];
                            return DtcCard(
                              dtc: dtc,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      DtcDetailScreen(dtc: dtc),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
