import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Acces SQLite local via sqflite.
///
/// Principe OFFLINE-FIRST : tout est stocke sur l'appareil, l'application
/// n'effectue aucun appel reseau (chantiers sans couverture).
class AppDatabase {
  Database? _db;

  Future<Database> open() async {
    final existing = _db;
    if (existing != null && existing.isOpen) return existing;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'enginscan.db'),
      version: 1,
      onCreate: _createSchema,
    );
    return _db!;
  }

  Future<void> _createSchema(Database db, int version) async {
    final batch = db.batch();
    // Base de connaissances DTC pre-remplie par SeedData.
    batch.execute('''
      CREATE TABLE dtc_knowledge (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL,
        spn INTEGER NOT NULL,
        fmi INTEGER NOT NULL,
        brand TEXT NOT NULL DEFAULT 'Generique',
        description TEXT NOT NULL DEFAULT '',
        causes TEXT NOT NULL DEFAULT '',
        solution_steps TEXT NOT NULL DEFAULT '',
        system TEXT NOT NULL DEFAULT '',
        severity TEXT NOT NULL DEFAULT 'mineur'
      )
    ''');
    batch.execute(
        'CREATE UNIQUE INDEX idx_dtc_unique ON dtc_knowledge (spn, fmi, brand)');
    // Sessions diagnostic exportables (JSON : codes + snapshot jauges).
    batch.execute('''
      CREATE TABLE diagnostic_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        machine_label TEXT NOT NULL,
        brand TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        payload TEXT NOT NULL
      )
    ''');
    // Controles avant mise en service (pre-shift inspection).
    batch.execute('''
      CREATE TABLE checklist_runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operator TEXT NOT NULL,
        machine_label TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        ok_count INTEGER NOT NULL,
        nok_count INTEGER NOT NULL,
        na_count INTEGER NOT NULL,
        items_json TEXT NOT NULL
      )
    ''');
    // Reglages persistes (protocole par defaut, filtre marque...).
    batch.execute(
        'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    await batch.commit(noResult: true);
  }

  Future<String?> getSetting(String key) async {
    final db = await open();
    final rows = await db.query('settings',
        where: 'key = ?', whereArgs: <Object?>[key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await open();
    await db.insert(
      'settings',
      <String, Object?>{'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
