import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/app.dart';
import 'src/data/database/app_database.dart';
import 'src/data/seed/seed_data.dart';
import 'src/features/checklist/data/checklist_repository.dart';
import 'src/features/j1939/data/elm327_link.dart';
import 'src/features/j1939/data/j1939_bluetooth_service.dart';
import 'src/features/knowledge/data/dtc_repository.dart';
import 'src/features/quick_tests/data/simple_test_runner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Base locale SQLite : creation du schema + pre-remplissage des fiches
  //    DTC. Tout est local : l'application ne fait AUCUN appel reseau.
  final appDatabase = AppDatabase();
  await appDatabase.open();
  await SeedData.populate(appDatabase);

  // 2) Services applicatifs (duree de vie = duree de vie du process).
  final elmLink = Elm327Link();
  final dtcRepository = DtcRepository(appDatabase);
  final j1939Service =
      J1939BluetoothService(link: elmLink, knowledge: dtcRepository);
  final quickTestRunner =
      SimpleTestRunner(link: elmLink, service: j1939Service);

  runApp(
    MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: appDatabase),
        Provider<Elm327Link>.value(value: elmLink),
        Provider<DtcRepository>.value(value: dtcRepository),
        Provider<ChecklistRepository>.value(
          value: ChecklistRepository(appDatabase),
        ),
        ChangeNotifierProvider<J1939BluetoothService>.value(
          value: j1939Service,
        ),
        ChangeNotifierProvider<SimpleTestRunner>.value(
          value: quickTestRunner,
        ),
      ],
      child: const EnginScanApp(),
    ),
  );
}
