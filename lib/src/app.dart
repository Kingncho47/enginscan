import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/checklist/presentation/pre_shift_checklist_screen.dart';
import 'features/diagnostics/presentation/live_diagnostic_screen.dart';
import 'features/knowledge/presentation/knowledge_search_screen.dart';
import 'features/quick_tests/presentation/quick_commands_screen.dart';

/// Racine applicative : Material Design 3, theme sombre par defaut pour une
/// lisibilite maximale en exterieur (fort contraste, gros elements tactiles).
class EnginScanApp extends StatelessWidget {
  const EnginScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EnginScan',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const _HomeShell(),
    );
  }
}

/// Coquille de navigation : [IndexedStack] conserve les ecrans vivants entre
/// les onglets (la session Bluetooth/CAN continue pendant la consultation des
/// fiches ou de la checklist).
class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _index = 0;

  late final List<Widget> _screens = <Widget>[
    const LiveDiagnosticScreen(),
    const KnowledgeSearchScreen(),
    const PreShiftChecklistScreen(),
    QuickCommandsScreen(
      onOpenDiagnostic: () => setState(() => _index = 0),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        height: 68, // barre haute : cibles tactiles confortables avec gants
        onDestinationSelected: (int i) => setState(() => _index = i),
        destinations: const <Widget>[
          NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            selectedIcon: Icon(Icons.monitor_heart),
            label: 'Diagnostic',
          ),
          NavigationDestination(
            icon: Icon(Icons.manage_search_outlined),
            selectedIcon: Icon(Icons.manage_search),
            label: 'Codes DTC',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Pre-shift',
          ),
          NavigationDestination(
            icon: Icon(Icons.bolt_outlined),
            selectedIcon: Icon(Icons.bolt),
            label: 'Tests rapides',
          ),
        ],
      ),
    );
  }
}
