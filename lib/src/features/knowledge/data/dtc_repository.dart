import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../data/database/app_database.dart';
import '../../j1939/domain/models.dart';

/// Depot de la base de connaissances DTC (table dtc_knowledge).
///
/// Recherche 100% locale et instantanee : par code ("102-3", "SPN 110"),
/// par marque, par mot-cle dans la description ou le systeme concerne.
class DtcRepository {
  const DtcRepository(this.database);

  final AppDatabase database;

  // ---- Mapping SQL <-> modele ----------------------------------------------

  DtcModel _rowToModel(Map<String, Object?> row) => DtcModel(
        code: row['code'] as String,
        spn: (row['spn'] as num).toInt(),
        fmi: (row['fmi'] as num).toInt(),
        brand: (row['brand'] as String?) ?? 'Generique',
        description: (row['description'] as String?) ?? '',
        causes: _splitLines(row['causes']),
        solutionSteps: _splitLines(row['solution_steps']),
        system: (row['system'] as String?) ?? '',
        severity: severityFromString(row['severity'] as String?),
      );

  /// Public : egalement utilise par [SeedData] pour le pre-remplissage.
  static Map<String, Object?> modelToRow(DtcModel m) => <String, Object?>{
        'code': m.code,
        'spn': m.spn,
        'fmi': m.fmi,
        'brand': m.brand,
        'description': m.description,
        'causes': m.causes.join('\n'),
        'solution_steps': m.solutionSteps.join('\n'),
        'system': m.system,
        'severity': m.severity.name,
      };

  static List<String> _splitLines(Object? joined) {
    final s = joined?.toString() ?? '';
    if (s.trim().isEmpty) return const [];
    return s
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  // ---- Requetes metier ------------------------------------------------------

  /// Recherche plein texte locale (code, SPN, marque, description, systeme).
  Future<List<DtcModel>> search(String query, {String brand = ''}) async {
    final db = await database.open();
    final q = query.trim();
    final where = <String>[];
    final args = <Object?>[];

    if (q.isNotEmpty) {
      final like = '%$q%';
      where.add('(code LIKE ? OR CAST(spn AS TEXT) LIKE ? '
          'OR LOWER(description) LIKE ? OR LOWER(brand) LIKE ? '
          'OR LOWER(system) LIKE ?)');
      args.addAll(<Object?>[
        like,
        like,
        q.toLowerCase(),
        q.toLowerCase(),
        q.toLowerCase(),
      ]);
    }
    if (brand.isNotEmpty && brand != 'Toutes') {
      where.add('brand = ?');
      args.add(brand);
    }

    final rows = await db.query(
      'dtc_knowledge',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'spn ASC, brand ASC',
      limit: 100,
    );
    return rows.map(_rowToModel).toList(growable: false);
  }

  /// Liste des marques presentes dans la base (pour les chips de filtre).
  Future<List<String>> brands() async {
    final db = await database.open();
    final rows = await db
        .rawQuery('SELECT DISTINCT brand FROM dtc_knowledge ORDER BY brand');
    return rows.map((r) => r['brand'] as String).toList(growable: false);
  }

  /// Meilleure fiche pour un couple SPN/FMI lu en direct.
  ///
  /// Priorite : fiche de la marque filtree > autre fiche constructeur >
  /// fiche generique. Renvoie null si le couple est inconnu de la base.
  Future<DtcModel?> findBestMatch(int spn, int fmi,
      {String? preferBrand}) async {
    final db = await database.open();
    final rows = await db.query(
      'dtc_knowledge',
      where: 'spn = ? AND fmi = ?',
      whereArgs: <Object?>[spn, fmi],
    );
    if (rows.isEmpty) return null;

    int rank(Map<String, Object?> r) {
      final b = r['brand'] as String? ?? '';
      if (preferBrand != null &&
          preferBrand.isNotEmpty &&
          preferBrand != 'Toutes' &&
          b == preferBrand) {
        return 0;
      }
      return b == 'Generique' ? 2 : 1;
    }

    rows.sort((a, b) => rank(a).compareTo(rank(b)));
    return _rowToModel(rows.first);
  }

  /// Ajout / mise a jour d'une fiche (extensibilite : import atelier...).
  Future<void> upsert(DtcModel m) async {
    final db = await database.open();
    await db.insert(
      'dtc_knowledge',
      modelToRow(m),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Persiste une session diagnostic complete (codes + snapshot des jauges).
  Future<int> saveSession({
    required String machineLabel,
    required String brand,
    required List<DtcModel> dtcs,
    required Map<String, double?> sensors,
  }) async {
    final db = await database.open();
    return db.insert('diagnostic_sessions', <String, Object?>{
      'machine_label': machineLabel,
      'brand': brand,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'payload': jsonEncode(<String, dynamic>{
        'dtcs': dtcs.map((d) => d.toJson()).toList(),
        'sensors': sensors,
      }),
    });
  }
}
