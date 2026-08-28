/// Etat de validation d'un point de controle avant mise en service.
enum CheckState { ok, nok, na }

extension CheckStateX on CheckState {
  String get label {
    switch (this) {
      case CheckState.ok:
        return 'OK';
      case CheckState.nok:
        return 'NOK';
      case CheckState.na:
        return 'N/A';
    }
  }
}

/// Un point du controle visuel/fonctionnel avant demarrage du poste.
class ChecklistItem {
  const ChecklistItem(
    this.id,
    this.category,
    this.title, {
    this.critical = false,
  });

  final String id;
  final String category;
  final String title;

  /// Un point critique en NOK doit BLOQUER la mise en service.
  final bool critical;
}

/// Catalogue officiel du controle avant mise en service (pre-shift).
const List<ChecklistItem> kPreShiftChecklist = <ChecklistItem>[
  ChecklistItem('doc', 'Securite & documentation',
      'Permis / consignes chantier et carnet de bord presents'),
  ChecklistItem('extincteur', 'Securite & documentation',
      'Extincteur present, charge et accessible',
      critical: true),
  ChecklistItem('ceinture', 'Securite & documentation',
      'Ceinture de securite et siege conformes',
      critical: true),
  ChecklistItem('huile_moteur', 'Niveaux & fuites',
      "Niveau d'huile moteur entre mini et maxi",
      critical: true),
  ChecklistItem('refroidissant', 'Niveaux & fuites',
      'Niveau liquide de refroidissement (a froid)',
      critical: true),
  ChecklistItem('huile_hydro', 'Niveaux & fuites',
      'Niveau huile hydraulique (viseur / jauge)',
      critical: true),
  ChecklistItem('carburant', 'Niveaux & fuites',
      'Gasoil suffisant pour le poste de travail'),
  ChecklistItem('fuites', 'Niveaux & fuites',
      'Absence de fuite sous la machine et sur les flexibles',
      critical: true),
  ChecklistItem('pneumatique', 'Chassis & organes',
      'Pneumatiques corrects ou chenilles bien tendues',
      critical: true),
  ChecklistItem('attelage', 'Chassis & organes',
      'Attelage / fourche / accessoires verrouilles',
      critical: true),
  ChecklistItem('eclairage', 'Chassis & organes',
      'Eclairage, gyrophares et balais essuie-glace operationnels'),
  ChecklistItem('demarrage', 'Fonctions cabine',
      'Demarrage propre : pas de fumee anormale ni bruit suspect',
      critical: true),
  ChecklistItem('commandes', 'Fonctions cabine',
      'Reponse des commandes (leviers, joystick, pedales)',
      critical: true),
  ChecklistItem('freins', 'Fonctions cabine',
      'Freins de service et frein de parking efficaces',
      critical: true),
  ChecklistItem('avertisseurs', 'Fonctions cabine',
      'Klaxon, feux de recul et alarme de marche fonctionnels'),
  ChecklistItem('arret_urgence', 'Fonctions cabine',
      "Arret d'urgence teste et rearmable",
      critical: true),
];

/// Resume d'un controle enregistre (affichage historique).
class ChecklistRunSummary {
  const ChecklistRunSummary({
    required this.id,
    required this.operator,
    required this.machineLabel,
    required this.createdAt,
    required this.okCount,
    required this.nokCount,
    required this.naCount,
  });

  final int id;
  final String operator;
  final String machineLabel;
  final DateTime createdAt;
  final int okCount;
  final int nokCount;
  final int naCount;

  factory ChecklistRunSummary.fromRow(Map<String, Object?> row) {
    return ChecklistRunSummary(
      id: (row['id'] as num).toInt(),
      operator: row['operator'] as String? ?? '',
      machineLabel: row['machine_label'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (row['created_at'] as num?)?.toInt() ?? 0,
      ),
      okCount: (row['ok_count'] as num?)?.toInt() ?? 0,
      nokCount: (row['nok_count'] as num?)?.toInt() ?? 0,
      naCount: (row['na_count'] as num?)?.toInt() ?? 0,
    );
  }
}
