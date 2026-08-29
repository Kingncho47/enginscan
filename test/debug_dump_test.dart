import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:enginscan/src/data/database/app_database.dart';
import 'package:enginscan/src/features/j1939/data/elm327_link.dart';
import 'package:enginscan/src/features/j1939/data/j1939_bluetooth_service.dart';
import 'package:enginscan/src/features/knowledge/data/dtc_repository.dart';
import 'package:enginscan/src/features/quick_tests/data/simple_test_runner.dart';
import 'package:enginscan/src/features/quick_tests/presentation/quick_commands_screen.dart';

void main() {
  testWidgets('debug dump', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final link = Elm327Link();
    final service = J1939BluetoothService(
      link: link,
      knowledge: DtcRepository(AppDatabase()),
    );
    final runner = SimpleTestRunner(link: link, service: service);
    addTearDown(service.dispose);
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
    final buffer = StringBuffer();
    debugDumpRenderTree();
    final dyn = tester.binding.renderViewElement!;
    // ignore: avoid_print
    print('RENDER_TREE_START');
    debugDumpRenderTree();
    // ignore: avoid_print
    print('RENDER_TREE_END');
    expect(dyn, isNotNull);
    expect(buffer, isA<StringBuffer>());
  });
}