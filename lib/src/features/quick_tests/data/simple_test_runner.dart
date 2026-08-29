import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../j1939/data/elm327_link.dart';
import '../../j1939/data/j1939_bluetooth_service.dart';
import '../domain/test_sequence.dart';

/// Exécuteur de séquences de tests moteurs.
///
/// Rôle :
///  - mettre le moniteur CAN en pause pendant un envoi (sinon le flux `AT MA`
///    noierait les réponses du calculateur) puis le relancer ensuite ;
///  - parcourir les étapes d'une [TestSequence] : pour chacune, mettre à jour
///    l'UI (libellé + progression), envoyer la commande texte/HEX au boîtier
///    via [Elm327Link.sendCommand] avec un délai inter-étapes ;
///  - journaliser chaque envoi dans la console commune ([J1939BluetoothService]).
///
/// Sécurité :
///  - [emergencyStop] coupe immédiatement toute séquence et, si une commande
///    d'arrêt est configurée, l'émet en priorité (fire-and-forget) ;
///  - aucune commande n'est envoyée si le boîtier n'est pas connecté.
class SimpleTestRunner extends ChangeNotifier {
  SimpleTestRunner({
    required Elm327Link link,
    required J1939BluetoothService service,
  })  : _link = link,
        _testService = service;

  final Elm327Link _link;
  final J1939BluetoothService _testService;

  // ---- Commandes configurables (propriétaires OEM, vides par défaut) --------
  String rpmCommand = '';
  String variationCommand = '';
  String injectorCommand = '';
  String rpmUpCommand = '';
  String rpmDownCommand = '';
  String emergencyCommand = '';

  // ---- État exposé à l'UI ----------------------------------------------------
  bool _running = false;
  bool _abortRequested = false;
  String _currentLabel = 'Prêt — choisissez un test ci-dessous.';
  int _currentStep = 0;
  int _totalSteps = 0;

  bool get isRunning => _running;
  bool get isAborting => _abortRequested;
  String get currentLabel => _currentLabel;
  int get currentStep => _currentStep;
  int get totalSteps => _totalSteps;
  bool get isConnected => _link.isConnected;

  /// Progression 0..1.
  double get progress =>
      (_totalSteps == 0) ? 0 : ((_currentStep - 1) / _totalSteps).clamp(0, 1);

  /// Séquences prêtes à l'emploi (commandes injectées depuis la config).
  TestSequence get rpmSequence => DefaultTests.rpm(rpmCommand);
  TestSequence get variationSequence =>
      DefaultTests.variation(variationCommand);
  TestSequence get injectorSequence => DefaultTests.injectors(injectorCommand);

  /// Met à jour les commandes propriétaires du boîtier (appelé depuis l'écran
  /// de configuration) puis notifie les écouteurs.
  void updateCommands({
    String? rpmCommand,
    String? variationCommand,
    String? injectorCommand,
    String? rpmUpCommand,
    String? rpmDownCommand,
    String? emergencyCommand,
  }) {
    if (rpmCommand != null) this.rpmCommand = rpmCommand;
    if (variationCommand != null) this.variationCommand = variationCommand;
    if (injectorCommand != null) this.injectorCommand = injectorCommand;
    if (rpmUpCommand != null) this.rpmUpCommand = rpmUpCommand;
    if (rpmDownCommand != null) this.rpmDownCommand = rpmDownCommand;
    if (emergencyCommand != null) this.emergencyCommand = emergencyCommand;
    notifyListeners();
  }

  /// Exécute une séquence de test complète.
  Future<void> runTest(TestSequence sequence) async {
    // Séquence déjà en cours ? On l'interrompt avant de repartir de zéro.
    if (_running) {
      _abortRequested = true;
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (_running) return;
    }

    if (!_link.isConnected) {
      _currentLabel = 'Boîtier non connecté — allez sur l\'onglet Diagnostic.';
      _testService.appendLog(
          '>>> Test «${sequence.title}» refusé : '
          'boîtier déconnecté.',
          inbound: false);
      notifyListeners();
      return;
    }

    _abortRequested = false;
    _running = true;
    final monitorWasOn = _testService.monitoring;
    if (monitorWasOn) await _testService.stopMonitor();

    _testService.appendLog('>>> Test «${sequence.title}» lancé.',
        inbound: false);

    try {
      _totalSteps = sequence.steps.length;
      var aborted = false;

      for (var i = 0; i < sequence.steps.length; i++) {
        if (_abortRequested) {
          aborted = true;
          break;
        }
        final step = sequence.steps[i];
        _currentStep = i + 1;
        _currentLabel = step.label;
        notifyListeners();

        if (step.sendsFrame) {
          _testService.appendLog('> ${step.command}', inbound: false);
          try {
            final replies = await _link.sendCommand(
              step.command,
              timeout: const Duration(seconds: 2),
            );
            for (final r in replies.take(4)) {
              _testService.appendLog(r);
            }
          } catch (e) {
            _testService.appendLog('Envoi échoué : $e', inbound: false);
          }
        }

        if (_abortRequested) {
          aborted = true;
          break;
        }
        await Future<void>.delayed(step.delay);
      }

      _currentLabel = aborted
          ? (_abortRequested
              ? 'ARRÊT DEMANDÉ — vérifiez la machine.'
              : 'Séquence interrompue par l\'opérateur.')
          : 'Test «${sequence.title}» terminé.';
      _testService.appendLog('>>> $_currentLabel', inbound: false);
    } finally {
      _running = false;
      _currentStep = 0;
      _totalSteps = 0;
      _abortRequested = false;
      if (monitorWasOn && _link.isConnected) {
        await _testService.startMonitor();
      }
      notifyListeners();
    }
  }

  /// Envoi ponctuel d'une commande manuelle (+100 / -100 RPM...).
  Future<void> sendManualCommand(String label, String command) async {
    if (!_link.isConnected) {
      _currentLabel = 'Boîtier non connecté — allez sur l\'onglet Diagnostic.';
      notifyListeners();
      return;
    }

    final monitorWasOn = _testService.monitoring;
    if (monitorWasOn) await _testService.stopMonitor();

    _currentStep = 0;
    _totalSteps = 0;
    _currentLabel = '$label...';
    notifyListeners();

    if (command.trim().isEmpty) {
      _testService.appendLog(
          '$label : aucune commande configurée (voir Paramètres).',
          inbound: false);
    } else {
      _testService.appendLog('> $command', inbound: false);
      try {
        final replies = await _link.sendCommand(
          command,
          timeout: const Duration(seconds: 2),
        );
        for (final r in replies.take(4)) {
          _testService.appendLog(r);
        }
      } catch (e) {
        _testService.appendLog('Envoi échoué : $e', inbound: false);
      }
    }

    if (monitorWasOn && _link.isConnected) await _testService.startMonitor();

    _currentLabel = 'Commande «$label» terminée.';
    notifyListeners();
  }

  /// ARRÊT D'URGENCE : interrompt toute séquence immédiatement, puis émet la
  /// commande d'arrêt configurée sans attendre de réponse du boîtier.
  Future<void> emergencyStop() async {
    _abortRequested = true;
    _currentLabel = '';
    _testService.appendLog('!!! ARRÊT D\'URGENCE demandé.', inbound: false);
    notifyListeners();

    if (_link.isConnected) {
      await _testService.stopMonitor();

      final cmd = emergencyCommand.trim();
      if (cmd.isNotEmpty) {
        _testService.appendLog('> $cmd', inbound: false);
        _link.write('$cmd\r'); // émission directe, ne bloque pas la boucle
        await _link.drainOutput();
        _testService.appendLog('Commande d\'urgence transmise au bus CAN.',
            inbound: false);
      } else {
        _testService.appendLog(
            'Aucune commande d\'arrêt configurée — séquence stoppée. '
            'Utilisez l\'arrêt mécanique de la machine.',
            inbound: false);
      }

      await _testService.startMonitor();
    } else {
      _testService.appendLog(
          'Boîtier non connecté — agissez directement sur la machine.',
          inbound: false);
    }

    _currentLabel = 'ARRÊT DEMANDÉ — vérifiez la machine.';
    notifyListeners();
  }

  @override
  void dispose() {
    _abortRequested = true;
    super.dispose();
  }
}
