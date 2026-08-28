import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../j1939/domain/models.dart';

/// Carte compacte d'un code defaut : bandeau couleur severite, code SPN-FMI,
/// badge ACTIF pour les lectures live et compteur d'occurrences.
class DtcCard extends StatelessWidget {
  const DtcCard({super.key, required this.dtc, this.onTap});

  final DtcModel dtc;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.severityColor(dtc.severity);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 6,
                height: 68,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          dtc.code,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 8),
                        if (dtc.isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE53935),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'ACTIF',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white),
                            ),
                          ),
                        const Spacer(),
                        if (dtc.occurrenceCount > 0)
                          Text(
                            'x${dtc.occurrenceCount}',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withOpacity(0.75)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dtc.description.isEmpty
                          ? 'SPN ${dtc.spn} / FMI ${dtc.fmi} - ${dtc.fmiLabel}'
                          : dtc.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13, color: Colors.white.withOpacity(0.75)),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: <Widget>[
                        _MiniBadge(text: 'SPN ${dtc.spn}'),
                        _MiniBadge(text: 'FMI ${dtc.fmi}'),
                        if (dtc.brand.isNotEmpty && dtc.brand != 'Machine')
                          _MiniBadge(text: dtc.brand),
                        if (dtc.system.isNotEmpty) _MiniBadge(text: dtc.system),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.85)),
      ),
    );
  }
}
