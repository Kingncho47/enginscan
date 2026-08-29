import 'package:flutter_test/flutter_test.dart';

import 'package:enginscan/src/data/database/app_database.dart';
import 'package:enginscan/src/features/j1939/data/elm327_link.dart';
import 'package:enginscan/src/features/j1939/data/j1939_bluetooth_service.dart';
import 'package:enginscan/src/features/knowledge/data/dtc_repository.dart';
import 'package:enginscan/src/features/quick_tests/data/simple_test_runner.dart';
import 'package:enginscan/src/features/quick_tests/domain/test_sequence.dart';

/// Liaison factice : aucun vrai Bluetooth, les réponses sont simulées.
class _FakeLink extends Elm327Link {
  final List<String> sent = <String>[];
  bool connected = true;

  @override
  bool get isConnected => connected;

  @override
  Future<List<String>> sendCommand(
    String command, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    sent.add(command);
    return <String>['OK'];
  }

  @override
  void write(String text) {
    sent.add('WRITE:$text');
  }

  @override
  Future<void> drainOutput() async {}
}

void main() {
  late _FakeLink link;
  late J1939BluetoothService service;
  late SimpleTestRunner runner;

  setUp(() {
    link = _FakeLink();
    service = J1939BluetoothService(
      link: link,
      knowledge: DtcRepository(AppDatabase()),
    );
    runner = SimpleTestRunner(link: link, service: service);
  });

  tearDown(() {
    service.dispose();
    runner.dispose();
  });

  test('runTest envoie la commande configurée et restaure le moniteur',
      () async {
    await service.startMonitor();
    expect(service.monitoring, isTrue);

    runner.rpmCommand = '18EAFFF9CAFE00';
    await runner.runTest(runner.rpmSequence);

    expect(runner.isRunning, isFalse);
    expect(link.sent, contains('18EAFFF9CAFE00'));
    expect(runner.currentLabel, contains('terminé'));
    // Le moniteur a été mis en pause puis relancé.
    expect(service.monitoring, isTrue);
  });

  test('sequence sans commande = simple pause, aucun envoi', () async {
    await runner.runTest(const TestSequence('Pause', [
      TestStep('Attente...', delay: Duration(milliseconds: 20)),
    ]));

    expect(link.sent, isEmpty);
    expect(runner.isRunning, isFalse);
  });

  test('boîtier déconnecté : refus immédiat, aucun envoi', () async {
    link.connected = false;
    runner.rpmCommand = '18EAFFF9CAFE00';

    await runner.runTest(runner.rpmSequence);

    expect(link.sent, isEmpty);
    expect(runner.currentLabel, contains('non connecté'));
  });

  test('arrêt d\'urgence interrompt la séquence et émet le commande', () async {
    runner.emergencyCommand = 'ARRETCMD';
    runner.injectorCommand = 'INJ';

    final runFuture = runner.runTest(runner.injectorSequence);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await runner.emergencyStop();
    await runFuture;

    expect(link.sent, contains('WRITE:ARRETCMD\r'));
    expect(runner.isRunning, isFalse);
    expect(runner.currentLabel, contains('ARRÊT DEMANDÉ'));
  });

  test('envoi manuel +100 RPM', () async {
    runner.rpmUpCommand = 'RPMUP';
    await runner.sendManualCommand(
        'Augmenter Régime (+100 RPM)', runner.rpmUpCommand);

    expect(link.sent, contains('RPMUP'));
    expect(runner.currentLabel, contains('terminée'));
  });
}
