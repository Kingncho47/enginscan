import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../j1939/domain/models.dart';

/// Couleur associee a l'etat d'un parametre temps reel.
/// Public : reutilisee par l'ecran diagnostic pour les textes d'etat.
Color gaugeStatusColor(SensorStatus status) {
  switch (status) {
    case SensorStatus.normal:
      return const Color(0xFF43A047);
    case SensorStatus.warning:
      return const Color(0xFFFFB300);
    case SensorStatus.critical:
      return const Color(0xFFE53935);
    case SensorStatus.unknown:
      return const Color(0xFF90A4AE);
  }
}

/// Tuile de jauge radiale haute lisibilite pour l'exterieur :
/// arc 270 degres, gros chiffres, reperes de seuils vigilance/critique.
class RadialGaugeTile extends StatelessWidget {
  const RadialGaugeTile({super.key, required this.sensor});

  final LiveSensorModel sensor;

  @override
  Widget build(BuildContext context) {
    final color = gaugeStatusColor(sensor.status);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withOpacity(0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.55), width: 1.2),
      ),
      child: Column(
        children: <Widget>[
          Text(
            sensor.oemSpecific ? '${sensor.label} (OEM)' : sensor.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: CustomPaint(
              painter: _GaugePainter(sensor: sensor),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      sensor.valueText,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: sensor.isValid
                            ? Colors.white
                            : Colors.white.withOpacity(0.4),
                      ),
                    ),
                    Text(
                      sensor.unit,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Text(
            sensor.statusText + (sensor.oemSpecific ? ' · calibrage requis' : ''),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({required this.sensor});

  final LiveSensorModel sensor;

  static const double _startDeg = 135; // arc ouvert en bas
  static const double _sweepDeg = 270;

  static double _degToRad(double deg) => deg * math.pi / 180.0;

  double _fractionOf(double v) {
    final span = sensor.gaugeMax - sensor.gaugeMin;
    if (span <= 0) return 0;
    return ((v - sensor.gaugeMin) / span).clamp(0.0, 1.0).toDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 14;
    if (radius <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Piste de fond.
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withOpacity(0.12);
    canvas.drawArc(rect, _degToRad(_startDeg), _degToRad(_sweepDeg), false, track);

    // Reperes de seuils sur l'arc : ambre = vigilance, rouge = critique.
    void tick(double? value, Color color) {
      if (value == null) return;
      final t = _fractionOf(value);
      if (t <= 0 || t >= 1) return;
      final angle = _degToRad(_startDeg + _sweepDeg * t);
      final dir = Offset(math.cos(angle), math.sin(angle));
      final paint = Paint()
        ..strokeWidth = 3
        ..color = color;
      canvas.drawLine(center + dir * (radius - 9), center + dir * (radius + 9), paint);
    }

    tick(sensor.warnLow, const Color(0xFFFFB300));
    tick(sensor.warnHigh, const Color(0xFFFFB300));
    tick(sensor.critLow, const Color(0xFFE53935));
    tick(sensor.critHigh, const Color(0xFFE53935));

    // Arc de progression colore selon l'etat du capteur.
    final value = sensor.value;
    if (value != null) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..color = gaugeStatusColor(sensor.status);
      canvas.drawArc(
          rect, _degToRad(_startDeg), _degToRad(_sweepDeg * _fractionOf(value)),
          false, arc);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.sensor.value != sensor.value ||
      oldDelegate.sensor.status != sensor.status;
}
