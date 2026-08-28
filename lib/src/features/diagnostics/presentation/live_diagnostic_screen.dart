import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../j1939/data/j1939_bluetooth_service.dart';
import '../../j1939/domain/models.dart';
import '../../knowledge/data/dtc_repository.dart';
import '../../knowledge/presentation/dtc_detail_screen.dart';
import 'widgets/dtc_card.dart';
import 'widgets/radial_gauge.dart';

/// Protocoles ELM proposables selon le boitier et la machine.
const Map<String, String> kProtocols = <String, String>{
  'A': 'J1939 · 29 bits · 250 kbps',
  '7': 'CAN 29 bits · 500 kbps',
  '9': 'CAN 29 bits · 250 kbps',
  '6': 'CAN 11 bits · 500 kbps',
  '8': 'CAN 11 bits · 250 kbps',
};

/// Ecran principal du diagnostic en direct :
///  - connexion Bluetooth au boitier (ELM327 / OBDLink / STN) ;
///  - lecture continue du bus J1939 en mode moniteur (`AT MA`) ;
///  - codes defauts actifs DM1 / historiques DM2 en temps reel ;
///  - jauges live data (regime, temperatures, tension...) ;
///  - terminal AT/ST libre pour le terrain.
class LiveDiagnosticScreen extends StatefulWidget {
  const LiveDiagnosticScreen({super.key});

  @override
  State<LiveDiagnosticScreen> createState() => _LiveDiagnosticScreenState();
}

class _LiveDiagnosticScreenState extends State<LiveDiagnosticScreen> {
  final TextEditingController _cmdCtrl = TextEditingController();
  bool _consoleVisible = false;

  @override
  void dispose() {
    _cmdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<J1939BluetoothService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostic machine'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Enregistrer la session diagnostic',
            icon: const Icon(Icons.save_outlined),
            onPressed:
                service.isConnected ? () => _saveSession(service) : null,
          ),
          IconButton(
            tooltip: 'Console terrain (AT/ST)',
            icon: Icon(_consoleVisible ? Icons.terminal : Icons.terminal_outlined),
            onPressed: () => setState(() => _consoleVisible = !_consoleVisible),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _StatusBar(service: service),
          _ActionBar(
            service: service,
            onPickDevice: _openDevicePicker,
            onQueryDtcs: () => _queryDtcs(service),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 20),
              children: <Widget>[
                _DtcSection(service: service),
                const SizedBox(height: 6),
                _GaugesSection(service: service),
                if (_consoleVisible) _LogConsole(service: service, cmdCtrl: _cmdCtrl),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Actions -------------------------------------------------------------

  Future<void> _openDevicePicker() async {
    final service = context.read<J1939BluetoothService>();
    final messenger = ScaffoldMessenger.of(context);

    // 1) Autorisations runtime Android 12+ (SCAN/CONNECT).
    final statuses = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    final denied =
        statuses.values.any((s) => s.isDenied || s.isPermanentlyDenied);
    if (denied) {
      // Android <= 11 : la localisation est requise pour le Bluetooth.
      await <Permission>[Permission.locationWhenInUse].request();
    }

    try {
      // 2) Activer le Bluetooth si necessaire (boite de dialogue systeme).
      final enabled =
          await FlutterBluetoothSerial.instance.requestEnable() ?? false;
      if (!enabled) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Bluetooth desactive : lecture impossible.')));
        return;
      }
      // 3) Liste des appareils DEJA apparies (dongle vu une premiere fois).
      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.all(14),
                child: Text('Boitiers apparies',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              if (devices.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'Aucun appareil apparie.\nAppairez d abord votre dongle dans '
                    'Reglages Android > Bluetooth, puis revenez ici.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final device in devices)
                ListTile(
                  leading: const Icon(Icons.bluetooth_searching, size: 30),
                  title: Text(device.name ?? '(sans nom)',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(device.address),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    service.connect(device);
                  },
                ),
            ],
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erreur Bluetooth : $e')));
    }
  }

  /// Requete active DM1 vers tous les calculateurs + retour utilisateur.
  Future<void> _queryDtcs(J1939BluetoothService service) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dtcs = await service.queryDtcsNow();
      messenger.showSnackBar(SnackBar(
        content: Text(dtcs.isEmpty
            ? 'Aucun defaut actif retourne par la machine.'
            : '${dtcs.length} code(s) actif(s) recu(s).'),
      ));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Requete impossible : $e')));
    }
  }

  /// Persiste la session (codes + snapshot jauges) dans la base locale.
  Future<void> _saveSession(J1939BluetoothService service) async {
    final repo = context.read<DtcRepository>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final sensorSnapshot = <String, double?>{
        for (final s in service.sensors.values) s.label: s.value,
      };
      final id = await repo.saveSession(
        machineLabel: service.deviceName,
        brand: '',
        dtcs: List<DtcModel>.of(service.activeDtcs),
        sensors: sensorSnapshot,
      );
      messenger.showSnackBar(SnackBar(
          content: Text(
              'Session #$id enregistree (${service.activeDtcs.length} code(s)).')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Enregistrement impossible : $e')));
    }
  }
}

// ---------------------------------------------------------------------------
// Bandeau d'etat de la liaison diagnostic.
// ---------------------------------------------------------------------------
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.service});

  final J1939BluetoothService service;

  Color get _phaseColor {
    switch (service.phase) {
      case LinkPhase.connected:
        return const Color(0xFF43A047);
      case LinkPhase.connecting:
        return const Color(0xFFFFB300);
      case LinkPhase.error:
        return const Color(0xFFE53935);
      case LinkPhase.disconnected:
        return const Color(0xFF90A4AE);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withOpacity(0.30),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _phaseColor.withOpacity(0.8), width: 1.4),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.circle, size: 14, color: _phaseColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(service.phase.label,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: _phaseColor)),
                    const Spacer(),
                    Text('${service.framesSeen} trames',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.6))),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  service.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13, color: Colors.white.withOpacity(0.75)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Barre d'actions : connexion, requete defauts, flux temps reel, protocole.
// ---------------------------------------------------------------------------
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.service,
    required this.onPickDevice,
    required this.onQueryDtcs,
  });

  final J1939BluetoothService service;
  final VoidCallback onPickDevice;
  final VoidCallback onQueryDtcs;

  @override
  Widget build(BuildContext context) {
    final busy = service.phase == LinkPhase.connecting;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          FilledButton.icon(
            onPressed: busy ? null : onPickDevice,
            icon: const Icon(Icons.bluetooth_searching, size: 26),
            label: Text(service.isConnected
                ? service.deviceName
                : 'Choisir boitier'),
          ),
          if (service.isConnected)
            OutlinedButton.icon(
              onPressed: () => service.disconnect(),
              icon: const Icon(Icons.bluetooth_disabled, size: 24),
              label: const Text('Deconnecter'),
            ),
          OutlinedButton.icon(
            onPressed:
                service.isConnected && !busy ? onQueryDtcs : null,
            icon: const Icon(Icons.bug_report, size: 24),
            label: Text('Interroger defauts (${service.activeDtcs.length})'),
          ),
          OutlinedButton.icon(
            onPressed:
                service.isConnected ? () => _toggleMonitor(service) : null,
            icon: Icon(service.monitoring ? Icons.pause : Icons.play_arrow,
                size: 24),
            label: Text(service.monitoring ? 'Stopper le flux' : 'Flux temps reel'),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButton<String>(
              value: kProtocols.containsKey(service.protocolCode)
                  ? service.protocolCode
                  : null,
              underline: const SizedBox.shrink(),
              hint: Text('Protocole (${service.protocolCode})',
                  style: const TextStyle(fontSize: 14)),
              items: <String>[
                for (final entry in kProtocols.entries) entry.key,
              ].map((code) {
                return DropdownMenuItem<String>(
                  value: code,
                  child: Text('$code - ${kProtocols[code]}',
                      style: const TextStyle(fontSize: 13)),
                );
              }).toList(),
              onChanged: (code) {
                if (code == null || code == service.protocolCode) return;
                service.applyProtocol(code);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleMonitor(J1939BluetoothService service) async {
    if (service.monitoring) {
      await service.stopMonitor();
    } else {
      await service.startMonitor();
    }
  }
}

// ---------------------------------------------------------------------------
// Section codes defauts : actifs (DM1) + historiques repliables (DM2).
// ---------------------------------------------------------------------------
class _DtcSection extends StatelessWidget {
  const _DtcSection({required this.service});

  final J1939BluetoothService service;

  void _openDetail(BuildContext context, DtcModel dtc) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DtcDetailScreen(dtc: dtc),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: Row(
            children: <Widget>[
              const Icon(Icons.bug_report, size: 22),
              const SizedBox(width: 8),
              const Text(
                'Codes defauts actifs (DM1)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: service.activeDtcs.isEmpty
                      ? Colors.white12
                      : const Color(0xFFE53935),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${service.activeDtcs.length}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        if (!service.isConnected)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.info_outline,
                        size: 26,
                        color: Colors.white.withOpacity(0.6)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Connectez un boitier sur la prise diagnostic '
                        '(Deutsch 9 broches / adaptateur OBD2) pour lire la machine.',
                        style: TextStyle(
                            fontSize: 13.5,
                            color: Colors.white.withOpacity(0.75)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (service.activeDtcs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'Aucun defaut actif recu pour le moment. Les calculateurs '
                  'diffusent le DM1 periodiquement ; vous pouvez aussi forcer '
                  'une lecture avec "Interroger defauts".',
                  style: TextStyle(
                      fontSize: 13.5, color: Colors.white.withOpacity(0.75)),
                ),
              ),
            ),
          )
        else
          for (final dtc in service.activeDtcs)
            DtcCard(dtc: dtc, onTap: () => _openDetail(context, dtc)),
        if (service.inactiveDtcs.isNotEmpty)
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            title: Text('Historiques (DM2) - ${service.inactiveDtcs.length}',
                style: const TextStyle(fontSize: 14)),
            children: <Widget>[
              for (final dtc in service.inactiveDtcs)
                DtcCard(dtc: dtc, onTap: () => _openDetail(context, dtc)),
            ],
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section live data : grille de jauges radiales.
// ---------------------------------------------------------------------------
class _GaugesSection extends StatelessWidget {
  const _GaugesSection({required this.service});

  final J1939BluetoothService service;

  @override
  Widget build(BuildContext context) {
    final gauges = service.gauges();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Row(
            children: <Widget>[
              Icon(Icons.speed, size: 22),
              SizedBox(width: 8),
              Text('Live data (PGN standards J1939)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.82,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: <Widget>[
            for (final sensor in gauges) RadialGaugeTile(sensor: sensor),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Console terrain : envoi libre de commandes AT/ST + journal des trames.
// ---------------------------------------------------------------------------
class _LogConsole extends StatelessWidget {
  const _LogConsole({required this.service, required this.cmdCtrl});

  final J1939BluetoothService service;
  final TextEditingController cmdCtrl;

  Future<void> _send(BuildContext context) async {
    final command = cmdCtrl.text.trim();
    if (command.isEmpty) return;
    cmdCtrl.clear();
    service.appendLog('> $command', inbound: false);
    await service.sendCustom(command);
  }

  @override
  Widget build(BuildContext context) {
    final entries = service.log.reversed.take(120).toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      decoration: BoxDecoration(
        color: const Color(0xFF07101D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: cmdCtrl,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: "Commande AT/ST (ex : ATRV, ATI, STI)",
                      isDense: true,
                    ),
                    onSubmitted: (_) => _send(context),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => _send(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          SizedBox(
            height: 190,
            child: ListView.builder(
              padding: const EdgeInsets.all(10),
              reverse: false,
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final e = entries[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.5),
                  child: Text.rich(
                    TextSpan(
                      children: <TextSpan>[
                        TextSpan(
                          text: '${e.timeText} ',
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.35)),
                        ),
                        TextSpan(
                          text: e.text,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            color: e.inbound
                                ? Colors.tealAccent.withOpacity(0.85)
                                : Colors.amberAccent.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
