import '../../../core/constants/fmi_catalog.dart';

/// Severite metier attribuee a un code defaut (pilote la couleur UI et le tri).
enum DtcSeverity { info, mineur, majeur, critique }

extension DtcSeverityX on DtcSeverity {
  String get label {
    switch (this) {
      case DtcSeverity.info:
        return 'Info';
      case DtcSeverity.mineur:
        return 'Mineur';
      case DtcSeverity.majeur:
        return 'Majeur';
      case DtcSeverity.critique:
        return 'Critique';
    }
  }
}

DtcSeverity severityFromString(String? value) {
  switch (value) {
    case 'critique':
      return DtcSeverity.critique;
    case 'majeur':
      return DtcSeverity.majeur;
    case 'info':
      return DtcSeverity.info;
    default:
      return DtcSeverity.mineur;
  }
}

/// Etat visuel d'un parametre temps reel (jauge).
enum SensorStatus { normal, warning, critical, unknown }

// ---------------------------------------------------------------------------
// DtcModel : sert A LA FOIS de fiche de connaissances (mode offline) et de
// code defaut lu en direct sur le bus (DM1/DM2), avant enrichissement.
// ---------------------------------------------------------------------------
class DtcModel {
  final String code; // ex. "102-3" (SPN-FMI)
  final int spn;
  final int fmi;
  final String brand;
  final String description;
  final List<String> causes;
  final List<String> solutionSteps;
  final String system;
  final DtcSeverity severity;

  // Renseignes uniquement pour une lecture live sur la machine.
  final int occurrenceCount; // compteur du DM1 (7 bits de poids faible)
  final bool isActive; // true = DM1 (actif), false = DM2 (historique)
  final DateTime? capturedAt;
  final String? lampSummary; // voyants du DM1 (MIL, STOP rouge...)

  const DtcModel({
    required this.code,
    required this.spn,
    required this.fmi,
    this.brand = 'Generique',
    this.description = '',
    this.causes = const [],
    this.solutionSteps = const [],
    this.system = '',
    this.severity = DtcSeverity.majeur,
    this.occurrenceCount = 0,
    this.isActive = false,
    this.capturedAt,
    this.lampSummary,
  });

  /// Construit un DTC brut issu du decodage DM1/DM2 (avant fusion avec la
  /// base de connaissances locale).
  factory DtcModel.fromLive({
    required int spn,
    required int fmi,
    required int occurrenceCount,
    required bool isActive,
    String? lampSummary,
  }) {
    return DtcModel(
      code: '$spn-$fmi',
      spn: spn,
      fmi: fmi,
      brand: 'Machine',
      description: 'SPN $spn / FMI $fmi lu en direct sur le bus J1939',
      severity: DtcSeverity.majeur,
      occurrenceCount: occurrenceCount,
      isActive: isActive,
      capturedAt: DateTime.now(),
      lampSummary: lampSummary,
    );
  }

  String get fmiLabel => FmiCatalog.label(fmi);

  /// Fusionne les informations terrain (live) avec la fiche connaissance :
  /// on conserve les valeurs live (occurrence, horodatage) et on recupere
  /// description, causes et procedure documentees.
  DtcModel mergeWithKnowledge(DtcModel knowledge) => copyWith(
        brand: knowledge.brand,
        description:
            knowledge.description.isEmpty ? description : knowledge.description,
        causes: knowledge.causes.isNotEmpty ? knowledge.causes : causes,
        solutionSteps: knowledge.solutionSteps.isNotEmpty
            ? knowledge.solutionSteps
            : solutionSteps,
        system: knowledge.system.isNotEmpty ? knowledge.system : system,
        severity: knowledge.severity,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'code': code,
        'spn': spn,
        'fmi': fmi,
        'brand': brand,
        'description': description,
        'causes': causes.join('\n'),
        'solution_steps': solutionSteps.join('\n'),
        'system': system,
        'severity': severity.name,
        'occurrence_count': occurrenceCount,
        'is_active': isActive,
        'captured_at': capturedAt?.toIso8601String(),
      };

  factory DtcModel.fromJson(Map<String, dynamic> json) {
    return DtcModel(
      code: json['code'] as String,
      spn: (json['spn'] as num).toInt(),
      fmi: (json['fmi'] as num).toInt(),
      brand: (json['brand'] as String?) ?? 'Generique',
      description: (json['description'] as String?) ?? '',
      causes: _lines(json['causes'] as String?),
      solutionSteps: _lines(json['solution_steps'] as String?),
      system: (json['system'] as String?) ?? '',
      severity: severityFromString(json['severity'] as String?),
      occurrenceCount: ((json['occurrence_count'] as num?) ?? 0).toInt(),
      isActive: (json['is_active'] as bool?) ?? false,
      capturedAt: json['captured_at'] == null
          ? null
          : DateTime.tryParse(json['captured_at'] as String),
    );
  }

  static List<String> _lines(String? joined) {
    if (joined == null || joined.trim().isEmpty) return const [];
    return joined
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  DtcModel copyWith({
    String? code,
    int? spn,
    int? fmi,
    String? brand,
    String? description,
    List<String>? causes,
    List<String>? solutionSteps,
    String? system,
    DtcSeverity? severity,
    int? occurrenceCount,
    bool? isActive,
    DateTime? capturedAt,
    String? lampSummary,
  }) {
    return DtcModel(
      code: code ?? this.code,
      spn: spn ?? this.spn,
      fmi: fmi ?? this.fmi,
      brand: brand ?? this.brand,
      description: description ?? this.description,
      causes: causes ?? this.causes,
      solutionSteps: solutionSteps ?? this.solutionSteps,
      system: system ?? this.system,
      severity: severity ?? this.severity,
      occurrenceCount: occurrenceCount ?? this.occurrenceCount,
      isActive: isActive ?? this.isActive,
      capturedAt: capturedAt ?? this.capturedAt,
      lampSummary: lampSummary ?? this.lampSummary,
    );
  }
}

// ---------------------------------------------------------------------------
// LiveSensorModel : une valeur temps reel affichable dans une jauge radiale.
// ---------------------------------------------------------------------------
class LiveSensorModel {
  final int spn;
  final String label;
  final String unit;

  /// null = donnee non disponible ou invalide (tous les bits a 1 en J1939).
  final double? value;

  // Echelle de la jauge + seuils d'alerte (null = seuil desactive).
  final double gaugeMin;
  final double gaugeMax;
  final double? warnLow;
  final double? warnHigh;
  final double? critLow;
  final double? critHigh;

  /// true = mapping proprietaire constructeur, a calibrer selon la machine.
  final bool oemSpecific;

  final DateTime timestamp;

  const LiveSensorModel({
    required this.spn,
    required this.label,
    required this.unit,
    required this.value,
    required this.gaugeMin,
    required this.gaugeMax,
    this.warnLow,
    this.warnHigh,
    this.critLow,
    this.critHigh,
    this.oemSpecific = false,
    required this.timestamp,
  });

  bool get isValid => value != null;

  SensorStatus get status {
    final v = value;
    if (v == null) return SensorStatus.unknown;
    if (_out(v, critLow, critHigh)) return SensorStatus.critical;
    if (_out(v, warnLow, warnHigh)) return SensorStatus.warning;
    return SensorStatus.normal;
  }

  static bool _out(double v, double? low, double? high) =>
      (low != null && v <= low) || (high != null && v >= high);

  /// Position normalisee 0..1 sur l'echelle de la jauge.
  double get normalized {
    final span = gaugeMax - gaugeMin;
    if (span <= 0 || value == null) return 0;
    return ((value! - gaugeMin) / span).clamp(0.0, 1.0).toDouble();
  }

  String get valueText {
    final v = value;
    if (v == null) return '--';
    if (v.abs() >= 100) return v.round().toString();
    return v.toStringAsFixed(1);
  }

  String get statusText {
    switch (status) {
      case SensorStatus.normal:
        return 'Normal';
      case SensorStatus.warning:
        return 'Vigilance';
      case SensorStatus.critical:
        return 'Critique';
      case SensorStatus.unknown:
        return 'En attente';
    }
  }

  LiveSensorModel copyWith({double? value, DateTime? timestamp}) {
    return LiveSensorModel(
      spn: spn,
      label: label,
      unit: unit,
      value: value ?? this.value,
      gaugeMin: gaugeMin,
      gaugeMax: gaugeMax,
      warnLow: warnLow,
      warnHigh: warnHigh,
      critLow: critLow,
      critHigh: critHigh,
      oemSpecific: oemSpecific,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
