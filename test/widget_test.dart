import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:enginscan/src/data/database/app_database.dart';
import 'package:enginscan/src/features/diagnostics/presentation/live_diagnostic_screen.dart';
import 'package:enginscan/src/features/j1939/data/elm327_link.dart';
import 'package:enginscan/src/features/j1939/data/j1939_bluetooth_service.dart';
import 'package:enginscan/src/features/knowledge/data/dtc_repository.dart';

void main() {
  testWidgets('Ecran diagnostic : bandeau Deconnecte visible au demarrage',
      (WidgetTester tester) async {
    final service = J1939BluetoothService(
      link: Elm327Link(),
      knowledge: DtcRepository(AppDatabase()),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<J1939BluetoothService>.value(
        value: service,
        child: const MaterialApp(home: LiveDiagnosticScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Deconnecte'), findsOneWidget);
    expect(find.text('Choisir boitier'), findsOneWidget);
  });
}
