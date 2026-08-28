/// Catalogue officiel des FMI (Failure Mode Identifier) definis par
/// SAE J1939-73.
///
/// Le FMI est code sur 5 bits dans les trames DM1/DM2 (valeurs 0 a 31) et
/// precise le mode de defaillance associe au SPN : capteur court-circuite,
/// valeur hors plage mecanique, etc. Il est affiche sous forme textuelle dans
/// l'application pour aider immediatement le mecanicien sur le terrain.
class FmiCatalog {
  FmiCatalog._();

  static const Map<int, String> _labels = <int, String>{
    0: "Donnee valide mais au-dessus de la plage normale (severite la plus elevee)",
    1: "Donnee valide mais en dessous de la plage normale (severite la plus elevee)",
    2: "Donnee erratique, intermittente ou incorrecte",
    3: "Tension anormalement haute / court-circuit au plus",
    4: "Tension anormalement basse / court-circuit a la masse",
    5: "Courant anormalement bas / circuit ouvert",
    6: "Courant anormalement eleve",
    7: "Systeme mecanique ne repondant pas correctement",
    8: "Frequence / largeur d'impulsion / cadence anormale",
    9: "Cadence de mise a jour anormale",
    10: "Vitesse de variation anormale",
    11: "Cause racine non identifiable",
    12: "Composant ou dispositif intelligent defectueux",
    13: "Hors calibration",
    14: "Instructions speciales",
    15: "Donnee valide mais au-dessus de la plage normale (severite faible)",
    16: "Au-dessus de la plage normale (severite moderee)",
    17: "Donnee valide mais en dessous de la plage normale (severite faible)",
    18: "En dessous de la plage normale (severite moderee)",
    19: "Donnees reseaux recues en erreur",
    20: "Condition generique reservee J1939",
    21: "Condition generique reservee J1939",
    22: "Reserve",
    23: "Reserve",
    24: "Reserve",
    25: "Reserve",
    26: "Taux de signal / qualite reserve",
    27: "Reserve",
    28: "Reserve",
    29: "Reserve",
    30: "Condition specifique constructeur",
    31: "Aucune condition detectee / non disponible",
  };

  /// Libelle francais complet d'un FMI, avec repli securise si inconnu.
  static String label(int fmi) =>
      _labels[fmi] ?? 'FMI reserve ou inconnu ($fmi)';
}
