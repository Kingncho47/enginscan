import '../../../data/database/app_database.dart';
import '../domain/checklist_models.dart';

/// Depot des controles avant mise en service (table checklist_runs).
class ChecklistRepository {
  const ChecklistRepository(this.database);

  final AppDatabase database;

  /// Enregistre un controle termine et renvoie son identifiant.
  Future<int> save({
    required String operator,
    required String machineLabel,
    required int okCount,
    required int nokCount,
    required int naCount,
    required String itemsJson,
  }) async {
    final db = await database.open();
    return db.insert('checklist_runs', <String, Object?>{
      'operator': operator,
      'machine_label': machineLabel,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'ok_count': okCount,
      'nok_count': nokCount,
      'na_count': naCount,
      'items_json': itemsJson,
    });
  }

  /// Historique des controles, du plus recent au plus ancien.
  Future<List<ChecklistRunSummary>> history({int limit = 30}) async {
    final db = await database.open();
    final rows = await db.query(
      'checklist_runs',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(ChecklistRunSummary.fromRow).toList(growable: false);
  }

  Future<void> delete(int id) async {
    final db = await database.open();
    await db.delete('checklist_runs',
        where: 'id = ?', whereArgs: <Object?>[id]);
  }
}
