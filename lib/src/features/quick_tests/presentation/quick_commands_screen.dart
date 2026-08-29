import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/simple_test_runner.dart';
import '../domain/test_sequence.dart';

/// Écran de commandes rapides moteur :
///  - 3 tests automatiques (régime, variation, injecteurs) exécutés par
///    [SimpleTestRunner] avec affichage de l'étape en cours au centre ;
///  - contrôle manuel ±100 RPM ;
///  - arrêt d'urgence (coupe la séquence + émet la commande configurée).
///
/// Conçu pour petits écrans : boutons pleine largeur >= 56 dp, libellés
/// lisibles pour une utilisation avec gants.
class QuickCommandsScreen extends StatefulWidget {
  const QuickCommandsScreen({super.key, this.onOpenDiagnostic});

  /// Appelé pour basculer l'utilisateur vers l'onglet Diagnostic (connexion).
  final VoidCallback? onOpenDiagnostic;

  @override
  State<QuickCommandsScreen> createState() => _QuickCommandsScreenState();
}

class _QuickCommandsScreenState extends State<QuickCommandsScreen> {
  static const TextStyle _btnText =
      TextStyle(fontSize: 16, fontWeight: FontWeight.w700);

  // ---- Tests automatiques ----------------------------------------------------

  Future<void> _confirmAndRun(TestSequence sequence) async {
    final runner = context.read<SimpleTestRunner>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Lancer «${sequence.title}» ?'),
        content: const Text(
          'Ce test envoie des commandes sur le bus CAN de la machine.\n'
          'Vérifiez que la zone est dégagée avant de lancer.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Lancer le test'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await runner.runTest(sequence);
    }
  }

  Future<void> _confirmEmergency() async {
    final runner = context.read<SimpleTestRunner>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF3E1212),
        title: const Text('Arrêt d\'urgence ?',
            style: TextStyle(color: Colors.redAccent)),
        content: const Text(
          'Interrompt immédiatement toute séquence en cours et transmet '
          'la commande d\'arrêt configurée (si renseignée).',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.black),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Arrêter la machine'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await runner.emergencyStop();
    }
  }

  // ---- Configuration des commandes -------------------------------------------

  void _openSettings() {
    final runner = context.read<SimpleTestRunner>();
    final rpmCtrl = TextEditingController(text: runner.rpmCommand);
    final variationCtrl = TextEditingController(text: runner.variationCommand);
    final injectorCtrl = TextEditingController(text: runner.injectorCommand);
    final upCtrl = TextEditingController(text: runner.rpmUpCommand);
    final downCtrl = TextEditingController(text: runner.rpmDownCommand);
    final estopCtrl = TextEditingController(text: runner.emergencyCommand);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Commandes du boîtier'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Commandes texte/HEX propriétaires (constructeur). '
                'Vides = étapes de pause, aucun envoi.',
                style: TextStyle(fontSize: 12.5, color: Colors.white70),
              ),
              const SizedBox(height: 12),
              _cfgField(rpmCtrl, 'Test Régime Moteur'),
              _cfgField(variationCtrl, 'Variation de Régime'),
              _cfgField(injectorCtrl, 'Test Injecteurs'),
              _cfgField(upCtrl, 'Augmenter +100 RPM'),
              _cfgField(downCtrl, 'Diminuer -100 RPM'),
              _cfgField(estopCtrl, 'Arrêt d\'urgence'),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              runner.updateCommands(
                rpmCommand: rpmCtrl.text.trim(),
                variationCommand: variationCtrl.text.trim(),
                injectorCommand: injectorCtrl.text.trim(),
                rpmUpCommand: upCtrl.text.trim(),
                rpmDownCommand: downCtrl.text.trim(),
                emergencyCommand: estopCtrl.text.trim(),
              );
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  Widget _cfgField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        autocorrect: false,
        enableSuggestions: false,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5),
        decoration: InputDecoration(
          labelText: label,
          hintText: 'ex : 18EAFFF9CAFE00',
          isDense: true,
        ),
      ),
    );
  }

  // ---- Interface -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final runner = context.watch<SimpleTestRunner>();
    final connected = runner.isConnected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Commandes rapides'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Configurer les commandes du boîtier',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
            body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              if (!connected)
                _DisconnectedBanner(onOpen: widget.onOpenDiagnostic),
              _StatusPanel(runner: runner),
              ListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
                children: <Widget>[
                  const _SectionTitle('Tests automatiques'),
                  _bigAction(
                    icon: Icons.speed,
                    label: 'Test Régime Moteur',
                    legend: 'Monte le régime puis mesure',
                    onPressed: connected
                        ? () => _confirmAndRun(runner.rpmSequence)
                        : null,
                  ),
                  _bigAction(
                    icon: Icons.trending_up,
                    label: 'Variation de Régime',
                    legend: 'Paliers haut / bas',
                    onPressed: connected
                        ? () => _confirmAndRun(runner.variationSequence)
                        : null,
                  ),
                  _bigAction(
                    icon: Icons.settings_input_component,
                    label: 'Test Injecteurs',
                    legend: 'Contrôle un à un (6 injecteurs)',
                    onPressed: connected
                        ? () => _confirmAndRun(runner.injectorSequence)
                        : null,
                  ),
                  const SizedBox(height: 18),
                  const _SectionTitle('Contrôle manuel'),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _manualButton(
                          icon: Icons.add_circle_outline,
                          label: 'Augmenter Régime\n(+100 RPM)',
                          onPressed: connected
                              ? () => runner.sendManualCommand(
                                  'Augmenter Régime (+100 RPM)',
                                  runner.rpmUpCommand)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _manualButton(
                          icon: Icons.remove_circle_outline,
                          label: 'Diminuer Régime\n(-100 RPM)',
                          onPressed: connected
                              ? () => runner.sendManualCommand(
                                  'Diminuer Régime (-100 RPM)',
                                  runner.rpmDownCommand)
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD32F2F),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(76),
                      textStyle: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w800),
                    ),
                    icon: const Icon(Icons.stop_circle, size: 32),
                    label: const Text('Arrêt d\'Urgence'),
                    onPressed: connected ? _confirmEmergency : null,
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bigAction({
    required IconData icon,
    required String label,
    required String legend,
    required VoidCallback? onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(64),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          textStyle: _btnText,
        ),
        icon: Icon(icon, size: 28),
        label: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: _btnText),
            Text(
              legend,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: Colors.white.withOpacity(0.75)),
            ),
          ],
        ),
        onPressed: onPressed,
      ),
    );
  }

  Widget _manualButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(76),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
      icon: Icon(icon, size: 26),
      label: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
      onPressed: onPressed,
    );
  }
}

/// Bandeau d'invitation à la connexion affiché tant que le boîtier est absent.
class _DisconnectedBanner extends StatelessWidget {
  const _DisconnectedBanner({this.onOpen});

  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF3E2D0F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB26A00)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB300)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Boîtier non connecté. Les commandes sont désactivées.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: onOpen,
            child: const Text('Ouvrir Diagnostic'),
          ),
        ],
      ),
    );
  }
}

/// Panneau central : affiche l'action en cours en clair, avec la progression.
class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.runner});

  final SimpleTestRunner runner;

  @override
  Widget build(BuildContext context) {
    final running = runner.isRunning;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1B2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            runner.isAborting ? 'ARRÊT EN COURS...' : runner.currentLabel,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17,
              fontWeight: runner.isAborting ? FontWeight.w900 : FontWeight.w700,
              color: runner.isAborting ? Colors.redAccent : Colors.white,
            ),
          ),
          if (running) ...<Widget>[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: runner.totalSteps == 0 ? null : runner.progress,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 6),
            Text(
              'Étape ${runner.currentStep} / ${runner.totalSteps}',
              style: const TextStyle(
                  fontSize: 12.5,
                  color: Colors.white54,
                  fontFamily: 'monospace'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Titre de section discret du formulaire.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: Color(0xFF8FA8C8),
        ),
      ),
    );
  }
}
