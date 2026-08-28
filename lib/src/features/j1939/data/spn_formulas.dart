import 'dart:typed_data';

import '../../../core/constants/j1939_constants.dart';
import '../domain/models.dart';

/// Formule de conversion d'un SPN vers une grandeur physique affichable.
///
/// Chaque signal J1939 est defini par :
///   - le PGN qui le transporte + son offset en octets dans la charge utile ;
///   - sa resolution : valeur_physique = brut * facteur + decalage ;
///   - l'echelle de jauge et les seuils d'alerte (vigilance / critique).
class SpnFormula {
  final int spn;
  final String label;
  final String unit;
  final int pgn;
  final int byteOffset;
  final int byteLength;
  final double factor;
  final double offset;
  final double gaugeMin;
  final double gaugeMax;
  final double? warnLow;
  final double? warnHigh;
  final double? critLow;
  final double? critHigh;
  final bool oemSpecific;

  const SpnFormula({
    required this.spn,
    required this.label,
    required this.unit,
    required this.pgn,
    required this.byteOffset,
    required this.byteLength,
    required this.factor,
    this.offset = 0,
    required this.gaugeMin,
    required this.gaugeMax,
    this.warnLow,
    this.warnHigh,
    this.critLow,
    this.critHigh,
    this.oemSpecific = false,
  });

  /// Decode la valeur physique depuis une charge utile CAN.
  ///
  /// Rappel J1939 :
  ///  - signaux multi-octets transmis LITTLE ENDIAN (poids faible d'abord) ;
  ///  - une valeur dont TOUS les bits sont a 1 signifie "donnee non
  ///    disponible / erreur" -> on renvoie null pour figer proprement la jauge.
  double? decode(Uint8List payload) {
    if (payload.length < byteOffset + byteLength) return null;
    final raw =
        J1939Constants.readLittleEndian(payload, byteOffset, byteLength);
    if (raw == (1 << (byteLength * 8)) - 1) return null;
    return raw * factor + offset;
  }

  LiveSensorModel newSensor(double? value, DateTime timestamp) {
    return LiveSensorModel(
      spn: spn,
      label: label,
      unit: unit,
      value: value,
      gaugeMin: gaugeMin,
      gaugeMax: gaugeMax,
      warnLow: warnLow,
      warnHigh: warnHigh,
      critLow: critLow,
      critHigh: critHigh,
      oemSpecific: oemSpecific,
      timestamp: timestamp,
    );
  }
}

/// Registre des parametres temps reels supportes nativement.
///
/// Les mappings suivent SAE J1939-71 (EEC1, ET1, EFL/P1, CCVS1, LFE1, AMB).
/// La pression hydraulique n'a PAS de SPN standardise : chaque constructeur
/// (Caterpillar, Komatsu, Liebherr, Manitou...) la diffuse sur un PGN
/// proprietaire -> voir le gabarit marque [oemSpecific] en fin de liste.
const List<SpnFormula> kSpnFormulas = <SpnFormula>[
  // ---- EEC1 - PGN 61444 (0xF004) : controleur moteur #1 -------------------
  SpnFormula(
    spn: 190,
    label: 'Regime moteur',
    unit: 'tr/min',
    pgn: 61444,
    byteOffset: 4,
    byteLength: 2,
    factor: 0.125,
    gaugeMin: 0,
    gaugeMax: 2800,
    warnHigh: 2300,
    critHigh: 2600,
  ),
  SpnFormula(
    spn: 513,
    label: 'Couple moteur reel',
    unit: '%',
    pgn: 61444,
    byteOffset: 2,
    byteLength: 1,
    factor: 1,
    offset: -125,
    gaugeMin: -125,
    gaugeMax: 125,
    warnHigh: 95,
    critHigh: 110,
  ),
  SpnFormula(
    spn: 102,
    label: 'Pression admission turbo',
    unit: 'kPa',
    pgn: 61444,
    byteOffset: 3,
    byteLength: 1,
    factor: 0.5,
    gaugeMin: 0,
    gaugeMax: 400,
    warnHigh: 300,
    critHigh: 350,
  ),
  // ---- ET1 - PGN 65262 (0xFEEE) : temperatures moteur ---------------------
  SpnFormula(
    spn: 110,
    label: 'Temp. liquide refroidissement',
    unit: '°C',
    pgn: 65262,
    byteOffset: 0,
    byteLength: 1,
    factor: 1,
    offset: -40,
    gaugeMin: -40,
    gaugeMax: 140,
    warnHigh: 100,
    critHigh: 108,
  ),
  SpnFormula(
    spn: 175,
    label: 'Temp. huile moteur',
    unit: '°C',
    pgn: 65262,
    byteOffset: 1,
    byteLength: 1,
    factor: 1,
    offset: -40,
    gaugeMin: -40,
    gaugeMax: 150,
    warnHigh: 115,
    critHigh: 125,
  ),
  // ---- EFL/P1 - PGN 65263 (0xFEEF) : fluides et tension reseau ------------
  SpnFormula(
    spn: 94,
    label: 'Pression carburant',
    unit: 'kPa',
    pgn: 65263,
    byteOffset: 0,
    byteLength: 1,
    factor: 7.5,
    gaugeMin: 0,
    gaugeMax: 1000,
    warnLow: 200,
    warnHigh: 800,
    critLow: 120,
  ),
  SpnFormula(
    spn: 183,
    label: 'Consommation carburant',
    unit: 'L/h',
    pgn: 65263,
    byteOffset: 1,
    byteLength: 2,
    factor: 0.05,
    gaugeMin: 0,
    gaugeMax: 80,
    warnHigh: 60,
  ),
  SpnFormula(
    spn: 158,
    label: 'Tension batterie',
    unit: 'V',
    pgn: 65263,
    byteOffset: 3,
    byteLength: 1,
    factor: 0.05,
    gaugeMin: 8,
    gaugeMax: 32,
    warnLow: 12.0,
    warnHigh: 15.0,
    critLow: 11.5,
    critHigh: 16.0,
  ),
  // ---- CCVS1 - PGN 65265 (0xFEF1) : vitesse vehicule ----------------------
  SpnFormula(
    spn: 84,
    label: 'Vitesse vehicule',
    unit: 'km/h',
    pgn: 65265,
    byteOffset: 1,
    byteLength: 2,
    factor: 0.00390625, // 1/256 km/h par bit
    gaugeMin: 0,
    gaugeMax: 60,
    warnHigh: 50,
  ),
  // ---- LFE1 - PGN 65276 (0xFEFC) : niveau carburant -----------------------
  SpnFormula(
    spn: 96,
    label: 'Niveau carburant',
    unit: '%',
    pgn: 65276,
    byteOffset: 0,
    byteLength: 1,
    factor: 0.4,
    gaugeMin: 0,
    gaugeMax: 100,
    warnLow: 20,
    critLow: 10,
  ),
  // ---- AMB - PGN 65269 (0xFEF5) : conditions ambiantes --------------------
  SpnFormula(
    spn: 171,
    label: 'Temperature ambiante',
    unit: '°C',
    pgn: 65269,
    byteOffset: 0,
    byteLength: 1,
    factor: 0.03125,
    offset: -273,
    gaugeMin: -30,
    gaugeMax: 60,
  ),
  // ---- Gabarit PROPRIETAIRE constructeur ----------------------------------
  // Exemple : pression pompe hydraulique principale. Elle circule en general
  // sur un PGN proprietaire (plage 0xEF00-0xEFFF, ou 0xC900-0xCFFF chez
  // Caterpillar). Calibrez pgn/facteur/seuils selon la doc de VOTRE machine.
  SpnFormula(
    spn: 523000, // identifiant interne de gabarit (zone non attribuee)
    label: 'Pression hydraulique',
    unit: 'bar',
    pgn: 61184, // 0xEF00 : exemple de PGN proprietaire
    byteOffset: 0,
    byteLength: 2,
    factor: 0.1,
    gaugeMin: 0,
    gaugeMax: 450,
    warnHigh: 380,
    critHigh: 420,
    oemSpecific: true,
  ),
];

/// Index PGN -> formules, reconstruit une seule fois au chargement.
final Map<int, List<SpnFormula>> kFormulasByPgn = () {
  final map = <int, List<SpnFormula>>{};
  for (final f in kSpnFormulas) {
    map.putIfAbsent(f.pgn, () => <SpnFormula>[]).add(f);
  }
  return map;
}();

/// Index SPN -> formule (pour instancier des jauges vides avant reception).
final Map<int, SpnFormula> kFormulaBySpn = <int, SpnFormula>{
  for (final f in kSpnFormulas) f.spn: f,
};
