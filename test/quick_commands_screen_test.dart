import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:enginscan/src/data/database/app_database.dart';
import 'package:enginscan/src/features/j1939/data/elm327_link.dart';
import 'package:enginscan/src/features/j1939/data/j1939_bluetooth_service.dart';
import 'package:enginscan/src/features/knowledge/data/dtc_repository.dart';
import 'package:enginscan/src/features/quick_tests/data/simple_test_runner.dart';
import 'package:enginscan/src/features/quick_tests/presentation/quick_commands_screen.dart';

void main() {
  testWidgets('Écran commandes rapides : boutons et bandeau déconnecté',
      (WidgetTester tester) async {
    // Surface « petit téléphone » : 360 x 780 dp logiques.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // Runner avec des dépendances fictives (pas de Bluetooth / sqflite).
    final link = _FakeLink();
    final service = _FakeService();
    final runner = SimpleTestRunner(link: link, service: service);
    addTearDown(runner.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<J1939BluetoothService>.value(value: service),
          ChangeNotifierProvider<SimpleTestRunner>.value(value: runner),
        ],
        child: const MaterialApp(home: QuickCommandsScreen()),
      ),
    );
    await tester.pump();

    // Titre + libellés des 3 tests automatiques.
    expect(find.text('Commandes rapides'), findsOneWidget);
    expect(find.text('Test Régime Moteur'), findsOneWidget);
    expect(find.text('Variation de Régime'), findsOneWidget);
    expect(find.text('Test Injecteurs'), findsOneWidget);

    // Contrôle manuel + arrêt d'urgence.
    expect(find.text('Arrêt d\'Urgence'), findsOneWidget);

    // Boîtier non connecté : bandeau visible.
    expect(
      find.text('Boîtier non connecté. Les commandes sont désactivées.'),
      findsOneWidget,
    );
  });
}

// --- Mocks légers pour isoler le widget des dépendances plateforme ---

/// Fake Elm327Link : ne crée pas de StreamSubscription Bluetooth.
class _FakeLink extends Elm327Link {
  @override
  bool get isConnected => false;
}

/// Fake service : on ne passe PAS par le super() de J1939BluetoothService
/// car il appelle `link.lines.listen()` qui bloque dans l'environnement
/// de test (le stream natif n'est jamais fermé).
/// On utilise un ChangeNotifier minimal à la place.
class _FakeService extends ChangeNotifier implements J1939BluetoothService {
  @override
  bool get isConnected => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Fake AppDatabase (jamais utilisé, juste pour satisfaire le typage).
class _FakeDb extends AppDatabase {
  _FakeDb();
}
