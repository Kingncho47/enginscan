import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../j1939/domain/models.dart';

/// Fiche detaillee d'un code defaut : severite, description, causes probables
/// et procedure d'intervention etape par etape. Partagee entre la recherche
/// offline (base de connaissances) et le diagnostic en direct (DM1).
class DtcDetailScreen extends StatelessWidget {
  const DtcDetailScreen({super.key, required this.dtc});

  final DtcModel dtc;

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            color: Colors.white.withOpacity(0.65),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final severityColor = AppTheme.severityColor(dtc.severity);
    return Scaffold(
      appBar: AppBar(title: Text('Code ${dtc.code}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          // ---- Bandeau severite + systeme ---------------------------------
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: severityColor.withOpacity(0.16),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: severityColor.withOpacity(0.7)),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.warning_amber_rounded, color: severityColor, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${dtc.severity.label}'
                    ' · ${dtc.system.isEmpty ? 'Systeme non precise' : dtc.system}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ---- Badges d'identification -----------------------------------
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _Chip(label: 'SPN ${dtc.spn}'),
              _Chip(label: 'FMI ${dtc.fmi}'),
              if (dtc.brand.isNotEmpty) _Chip(label: dtc.brand),
              if (dtc.occurrenceCount > 0)
                _Chip(label: 'Occurrences : ${dtc.occurrenceCount}'),
              if (dtc.capturedAt != null)
                _Chip(label: dtc.isActive ? 'Defaut ACTIF' : 'Historique'),
            ],
          ),
          _sectionTitle('Description'),
          Text(
            dtc.description.isEmpty
                ? "Pas de description enregistree pour ce couple SPN/FMI."
                : dtc.description,
            style: const TextStyle(fontSize: 15, height: 1.45),
          ),

          if (dtc.causes.isNotEmpty) ...<Widget>[
            _sectionTitle('Causes probables'),
            for (final cause in dtc.causes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('  •  ', style: TextStyle(fontSize: 15)),
                    Expanded(
                        child:
                            Text(cause, style: const TextStyle(fontSize: 15))),
                  ],
                ),
              ),
          ],

          if (dtc.solutionSteps.isNotEmpty) ...<Widget>[
            _sectionTitle("Procedure d'intervention"),
            for (var i = 0; i < dtc.solutionSteps.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.white.withOpacity(0.14),
                      child: Text('${i + 1}',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(dtc.solutionSteps[i],
                          style: const TextStyle(fontSize: 15, height: 1.35)),
                    ),
                  ],
                ),
              ),
          ],

          const SizedBox(height: 18),
          Text(
            'FMI ${dtc.fmi} : ${dtc.fmiLabel}',
            style: TextStyle(
                fontSize: 12.5, color: Colors.white.withOpacity(0.55)),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
    );
  }
}
