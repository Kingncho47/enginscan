import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

import '../../knowledge/data/dtc_repository.dart';
import '../domain/j1939_frame.dart';
import '../domain/models.dart';
import 'elm327_link.dart';
import 'j1939_frame_parser.dart';
import 'spn_formulas.dart';

/// Phase de la liaison diagnostic affichee dans le bandeau superieur.
enum LinkPhase { disconnected, connecting, connected, error }

extension LinkPhaseX on LinkPhase {
  String get label {
    switch (this) {
      case LinkPhase.disconnected:
        return 'Deconnecte';
      case LinkPhase.connecting:
        return 'Connexion...';
      case LinkPhase.connected:
        return 'Connecte';
      case LinkPhase.error:
        return 'Erreur';
    }
  }
}

/// Une ligne du journal console terrain.
class LogEntry {
  const LogEntry(this.time, this.text, {required this.inbound});

  final DateTime time;
  final String text;
  final bool inbound;

  String get timeText {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

// ---------------------------------------------------------------------------
// J1939BluetoothService : coeur de la fonctionnalite "diagnostic en direct".
//
// Sequence appliquee a chaque connexion (boitier ELM327 / STN compatible) :
//
//   ATZ     -> reset du boitier
//   ATE0    -> echo OFF (fiabilise le parsing des reponses)
//   ATL0    -> pas de line feed supplementaires
//   ATS0    -> pas d'espaces entre les octets HEX
//   ATH1    -> AFFICHAGE DES EN-TETES 29 bits (INDISPENSABLE : sans lui,
//              impossible de retrouver PGN / adresse source d'une trame)
//   ATAT1   -> timing adaptatif selon la reponse de la machine
//   ATSP A  -> protocole SAE J1939 : CAN 29 bits @ 250 kbps
//              ('7' = CAN 29 bits @ 500 kbps pour certaines machines recentes)
//   ATCAF1  -> formatage CAN automatique ON
//   ATCRA   -> efface les filtres de reception : on accepte TOUTES les adresses
//   AT MA   -> mode MONITEUR : le boitier streame en continu toutes les trames
//              du bus ; chaque ligne recue est un ID 29 bits + payload HEX.
//
// Le decodage se fait ensuite integralement cote application (offline) :
//   - extraction SPN/FMI/Occurrences des DM1/DM2 (avec reassemblage TP) ;
//   - conversion des PGN standards en grandeurs physiques (live data).
// ---------------------------------------------------------------------------
class J1939BluetoothService extends ChangeNotifier {
  J1939BluetoothService({
    required Elm327Link link,
    required DtcRepository knowledge,
  })  : _link = link,
        _knowledge = knowledge {
    _lineSub = link.lines.listen(_onLine);
  }

  final Elm327Link _link;
  final DtcRepository _knowledge;
  final J1939FrameParser _parser = J1939FrameParser();

  StreamSubscription<String>? _lineSub;
  StreamSubscription<J1939Frame>? _frameSub;
  Timer? _notifyThrottle;
  Timer? _staleTimer;
  bool _staleNotified = false;

  // ---- Etat expose a l'UI --------------------------------------------------
  LinkPhase phase = LinkPhase.disconnected;
  String detail = 'Choisissez un boitier Bluetooth pour demarrer.';
  String deviceName = '';
  String adapterIdentity = '';

  /// Code protocole ELM courant : 'A' par defaut (J1939 250 kbps).
  String protocolCode = 'A';

  bool _monitoring = false;
  bool get monitoring => _monitoring;
  int framesSeen = 0;
  DateTime? lastFrameAt;

  /// Filtre optionnel de marque pour prioriser les fiches constructeur lors
  /// de l'enrichissement des codes lus en direct.
  String brandFilter = '';

  final List<DtcModel> activeDtcs = <DtcModel>[];
  final List<DtcModel> inactiveDtcs = <DtcModel>[];
  final Map<int, LiveSensorModel> sensors = <int, LiveSensorModel>{};
  final List<LogEntry> log = <LogEntry>[];

  bool get isConnected => phase == LinkPhase.connected && _link.isConnected;

  // ---- Gestion de l'etat / notifications -----------------------------------

  void _setPhase(LinkPhase p, String message) {
    phase = p;
    detail = message;
    notifyListeners();
  }

  void appendLog(String text, {bool inbound = true}) {
    log.add(LogEntry(DateTime.now(), text, inbound: inbound));
    if (log.length > 300) log.removeRange(0, log.length - 300);
    _throttledNotify();
  }

  /// Notifie l'UI au plus toutes les 120 ms : le bus peut livrer plusieurs
  /// centaines de trames/seconde, inutile de reconstruire l'ecran pour chacune.
  void _throttledNotify() {
    if (_notifyThrottle != null && _notifyThrottle!.isActive) return;
    _notifyThrottle = Timer(const Duration(milliseconds: 120), () {
      notifyListeners();
    });
  }

  /// Ordre d'affichage fixe des jauges du tableau de bord.
  static const List<int> coreGaugeSpns = <int>[
    190, // regime moteur
    110, // temperature liquide de refroidissement
    175, // temperature huile moteur
    158, // tension batterie
    94, // pression carburant
    96, // niveau carburant
    84, // vitesse vehicule
    102, // pression admission turbo
  ];

  /// Jauges du tableau de bord, avec gabarits vides tant qu'aucune trame
  /// correspondante n'a ete recue.
  List<LiveSensorModel> gauges() {
    final now = DateTime.now();
    final result = <LiveSensorModel>[];
    for (final spn in coreGaugeSpns) {
      final live = sensors[spn];
      if (live != null) {
        result.add(live);
      } else {
        result.add(kFormulaBySpn[spn]!.newSensor(null, now));
      }
    }
    return result;
  }

  static int _severityRank(DtcSeverity s) {
    switch (s) {
      case DtcSeverity.critique:
        return 0;
      case DtcSeverity.majeur:
        return 1;
      case DtcSeverity.mineur:
        return 2;
      case DtcSeverity.info:
        return 3;
    }
  }

  void _sortDtcs(List<DtcModel> list) {
    list.sort((a, b) {
      final r = _severityRank(a.severity).compareTo(_severityRank(b.severity));
      if (r != 0) return r;
      return a.spn.compareTo(b.spn);
    });
  }

  // ---- Connexion / initialisation du boitier -------------------------------

  /// Ouvre la liaison SPP, initialise l'ELM327 puis demarre le moniteur CAN.
  Future<bool> connect(BluetoothDevice device) async {
    if (_link.isConnected) await disconnect(resetData: false);
    deviceName = device.name ?? device.address;
    _setPhase(LinkPhase.connecting,
        'Ouverture du canal serie vers $deviceName...');

    try {
      await _link.connect(device.address);
    } catch (e) {
      _setPhase(LinkPhase.error,
          'Connexion impossible a $deviceName : $e\nVerifiez que le boitier est alimente (contact mis).');
      return false;
    }
    appendLog('Canal SPP ouvert (${device.address})', inbound: false);

    _frameSub?.cancel();
    _frameSub = _parser.frames.listen(_onFrame);

    try {
      adapterIdentity = await _initializeAdapter();
    } catch (e) {
      await _link.disconnect();
      _setPhase(LinkPhase.error,
          'Initialisation ELM327 echouee : $e\nAstuce : mettez le contact de la machine, ou changez de protocole.');
      return false;
    }

    // Surveillance "bus silencieux" (moteur arrete / mauvais protocole).
    _staleNotified = false;
    _staleTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
      _checkStale();
    });

    _setPhase(LinkPhase.connected,
        'Pret · ${adapterIdentity.isEmpty ? 'boitier initialise' : adapterIdentity}');
    await startMonitor();
    return true;
  }

  /// Sequence d'initialisation AT/ST documentee dans l'en-tete de classe.
  /// Renvoie la chaine d'identite du boitier (reponse a `ATI`).
  Future<String> _initializeAdapter() async {
    Future<List<String>> cmd(String c,
        {Duration timeout = const Duration(seconds: 3)}) async {
      final replies = await _link.sendCommand(c, timeout: timeout);
      appendLog('> $c', inbound: false);
      for (final r in replies) {
        appendLog(r);
      }
      return replies;
    }

    await _link.drainOutput();
    await cmd('ATZ', timeout: const Duration(seconds: 4)); // reset
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await cmd('ATE0'); // echo off
    await cmd('ATL0'); // line feeds off
    await cmd('ATS0'); // espaces off -> trames compactes
    await cmd('ATH1'); // EN-TETES ON -> decodage PGN/SA possible
    await cmd('ATAT1'); // adaptive timing

    final protoReplies =
        await cmd('ATSP$protocolCode'); // 'A' = J1939 250 kbps
    if (protoReplies.contains('?')) {
      throw StateError(
          "Protocole ATSP '$protocolCode' refuse par ce boitier (trop ancien ?)");
    }

    final idReplies = await cmd('ATI');
    final identity = idReplies
        .where((r) =>
            r.isNotEmpty &&
            r != 'OK' &&
            !r.toUpperCase().startsWith('SEARCHING') &&
            !r.toUpperCase().startsWith('BUS INIT'))
        .join(' ')
        .trim();

    await cmd('ATCAF1'); // formatage CAN automatique
    await cmd('ATCRA'); // accepter TOUTES les adresses sources
    return identity;
  }

  // ---- Moniteur CAN temps reel ---------------------------------------------

  /// `AT MA` : le boitier streame TOUTES les trames du bus en continu.
  /// Aucun prompt n'est emis -> ecriture bas niveau via [Elm327Link.write].
  Future<void> startMonitor() async {
    if (!_link.isConnected || _monitoring) return;
    _monitoring = true;
    appendLog('> AT MA  (moniteur CAN temps reel)', inbound: false);
    _link.write('ATMA\r');
    notifyListeners();
  }

  /// N'importe quel caractere envoye au boitier interrompt le mode moniteur.
  Future<void> stopMonitor() async {
    if (!_monitoring) return;
    _monitoring = false;
    _link.write('\r');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await _link.drainOutput();
    appendLog('Moniteur arrete', inbound: false);
  }

  /// Requete ACTIVE des defauts (DM1) vers TOUS les calculateurs.
  ///
  /// Principe J1939 : on emet une trame "Request" (PGN 0xEA00) depuis notre
  /// adresse outil 0xF9 vers l'adresse globale 0xFF, avec en charge utile le
  /// PGN demande en poids faible d'abord :
  ///
  ///   ID     = 18 EA FF F9   (priorite 6, PGN EA00, dest FF, source F9)
  ///   donnee = CA FE 00      (PGN 65226 = 0xFECA, little endian)
  ///
  /// Les calculateurs repondent par leurs DM1 ; ceux qui n'ont aucun defaut
  /// actif repondent "NO DATA" ou ne repondent pas du tout.
  Future<List<DtcModel>> queryDtcsNow({
    Duration listenWindow = const Duration(milliseconds: 1800),
  }) async {
    if (!_link.isConnected) throw StateError('Non connecte');
    await stopMonitor();
    await _link.sendCommand('ATCAF0'); // on emet une trame BRUTE
    appendLog('> Requete DM1 globale : 18EAFFF9 CA FE 00', inbound: false);
    await _link.sendCommand('18EAFFF9CAFE00', timeout: listenWindow);
    await _link.sendCommand('ATCAF1');
    await startMonitor();
    notifyListeners();
    return List<DtcModel>.unmodifiable(activeDtcs);
  }

  // ---- Pipeline de decodage -------------------------------------------------

  /// Chaque ligne du boitier passe ici : soit c'est une trame CAN (-> parseur),
  /// soit un message de statut ELM (-> journal console).
  void _onLine(String line) {
    if (line == Elm327Link.closedMarker) {
      _monitoring = false;
      if (phase == LinkPhase.connected || phase == LinkPhase.connecting) {
        _setPhase(LinkPhase.disconnected, 'Liaison Bluetooth perdue.');
      }
      return;
    }
    final before = _parser.framesParsed;
    _parser.addRawLine(line);
    if (_parser.framesParsed == before && !_isNoise(line)) {
      appendLog(line); // BUS INIT, SEARCHING, NO DATA, STOPPED, erreurs...
    }
  }

  bool _isNoise(String line) {
    const noise = <String>{
      'OK',
      'NO DATA',
      'STOPPED',
      'UNABLE TO CONNECT',
      'CAN ERROR',
      'BUS ERROR',
      'BUS INIT',
      'BUFFER FULL',
      'FB ERROR',
      'DATA ERROR',
    };
    final u = line.trim().toUpperCase();
    return u.isEmpty ||
        u == '>' ||
        noise.contains(u) ||
        u.startsWith('SEARCHING') ||
        u.startsWith('BUS INIT');
  }

  /// Recoit chaque trame decodee : DM1/DM2 -> codes defauts ; PGN standards
  /// -> grandeurs physiques pour les jauges.
  void _onFrame(J1939Frame frame) {
    framesSeen++;
    lastFrameAt = DateTime.now();
    _staleNotified = false;

    if (frame.isDm1 || frame.isDm2) {
      final found = _parser.extractDtcs(frame);
      final target = frame.isDm1 ? activeDtcs : inactiveDtcs;
      for (final dtc in found) {
        target.removeWhere((d) => d.code == dtc.code);
        target.add(dtc);
      }
      if (found.isNotEmpty) {
        _sortDtcs(activeDtcs);
        _sortDtcs(inactiveDtcs);
        appendLog('${frame.isDm1 ? "DM1" : "DM2"} ${frame.idHex} <- '
            '${found.map((d) => d.code).join(', ')}');
        // Enrichissement asynchrone avec la base de connaissances locale.
        _enrichAsync(List<DtcModel>.of(found));
      }
      _throttledNotify();
      return;
    }

    final formulas = kFormulasByPgn[frame.pgn];
    if (formulas == null) return; // PGN non exploite (economie CPU)
    var changed = false;
    final now = DateTime.now();
    for (final formula in formulas) {
      final value = formula.decode(frame.data);
      if (value == null) continue;
      final existing = sensors[formula.spn];
      if (existing == null) {
        sensors[formula.spn] = formula.newSensor(value, now);
      } else {
        sensors[formula.spn] =
            existing.copyWith(value: value, timestamp: now);
      }
      changed = true;
    }
    if (changed) _throttledNotify();
  }

  /// Fusionne chaque code lu en direct avec sa fiche connaissance (offline).
  Future<void> _enrichAsync(List<DtcModel> liveDtos) async {
    try {
      for (final live in liveDtos) {
        final kb = await _knowledge.findBestMatch(live.spn, live.fmi,
            preferBrand: brandFilter);
        if (kb == null) continue;
        final merged = live.mergeWithKnowledge(kb);
        void patch(List<DtcModel> list) {
          final idx = list.indexWhere((d) => d.code == merged.code);
          if (idx >= 0) list[idx] = merged;
        }

        patch(activeDtcs);
        patch(inactiveDtcs);
        _sortDtcs(activeDtcs);
        _sortDtcs(inactiveDtcs);
        _throttledNotify();
      }
    } catch (_) {
      // L'enrichissement ne doit jamais faire tomber la session live.
    }
  }

  /// Alerte terrain si le bus reste muet (contact coupe ou mauvais protocole).
  void _checkStale() {
    if (!_monitoring || !_link.isConnected || _staleNotified) return;
    final last = lastFrameAt;
    if (last != null &&
        DateTime.now().difference(last).inSeconds >= 5) {
      _staleNotified = true;
      appendLog(
          '! Aucune trame depuis 5 s - bus silencieux. Contact mis ? Protocole correct ?',
          inbound: false);
    }
  }

  // ---- Actions utilisateur --------------------------------------------------

  /// Change le protocole a chaud (stop moniteur -> ATSP x -> re-filtres ->
  /// redemarrage du moniteur). Exemples de codes :
  ///   'A' = J1939 29 bits / 250 kbps (defaut)
  ///   '7' = CAN 29 bits / 500 kbps   '9' = CAN 29 bits / 250 kbps
  ///   '6' = CAN 11 bits / 500 kbps   '8' = CAN 11 bits / 250 kbps
  Future<void> applyProtocol(String code) async {
    protocolCode = code;
    if (!_link.isConnected) {
      appendLog('Protocole par defaut defini sur $code (hors connexion).',
          inbound: false);
      notifyListeners();
      return;
    }
    await stopMonitor();
    final replies = await _link.sendCommand('ATSP$code');
    if (replies.contains('?')) {
      appendLog("ATSP$code refuse par le boitier.", inbound: false);
    } else {
      appendLog('ATSP$code applique.', inbound: false);
      await _link.sendCommand('ATCRA');
    }
    detail = 'Protocole ATSP $code applique.';
    await startMonitor();
    notifyListeners();
  }

  /// Terminal terrain : envoi libre d'une commande AT/ST (ex : `STI` sur
  /// OBDLink, `ATRV` pour la tension, `0100` pour un test OBD...).
  Future<String> sendCustom(String command) async {
    if (!_link.isConnected) return 'Non connecte';
    final wasMonitoring = _monitoring;
    if (wasMonitoring) await stopMonitor();
    final replies =
        await _link.sendCommand(command, timeout: const Duration(seconds: 3));
    for (final r in replies) {
      appendLog(r);
    }
    if (wasMonitoring) await startMonitor();
    return replies.isEmpty ? '(aucune reponse)' : replies.join('\n');
  }

  /// Vide les donnees live (nouvelle session sur une autre machine).
  void clearLiveData() {
    activeDtcs.clear();
    inactiveDtcs.clear();
    sensors.clear();
    framesSeen = 0;
    lastFrameAt = null;
    _staleNotified = false;
    notifyListeners();
  }

  Future<void> disconnect({bool resetData = true}) async {
    if (_monitoring) await stopMonitor();
    await _link.disconnect();
    _monitoring = false;
    if (resetData) clearLiveData();
    _setPhase(LinkPhase.disconnected, 'Deconnecte du boitier.');
  }

  @override
  void dispose() {
    _staleTimer?.cancel();
    _notifyThrottle?.cancel();
    _lineSub?.cancel();
    _frameSub?.cancel();
    _parser.dispose();
    _link.dispose();
    super.dispose();
  }
}
