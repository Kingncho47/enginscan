import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

/// Couche liaison serie bas niveau vers le boitier diagnostic.
///
/// Responsabilites :
///  - ouvrir / fermer le canal Bluetooth Classic SPP (profil serie) ;
///  - envoyer les commandes ASCII terminees par CR ('\r') ;
///  - decouper le flux entrant en lignes : une ligne se termine par CR/LF,
///    et le prompt '>' signale la fin d'une reponse ELM327.
///
/// Le flux [lines] est diffuse a tous les abonnes (broadcast) : le service
/// J1939 y branche a la fois la console terrain et le parseur de trames.
class Elm327Link {
  /// Ligne publiee quand la liaison tombe ; le service J1939 s'en sert pour
  /// rebasculer proprement son etat UI sur "deconnecte".
  static const String closedMarker = '__BT_CLOSED__';

  BluetoothConnection? _connection;
  StreamSubscription<Uint8List>? _subscription;
  final StreamController<String> _linesCtrl =
      StreamController<String>.broadcast();
  final StringBuffer _buffer = StringBuffer();

  /// Complete quand le prompt '>' est recue (fin de reponse ELM327).
  Completer<void>? _promptCompleter;

  bool get isConnected => _connection?.isConnected ?? false;

  Stream<String> get lines => _linesCtrl.stream;

  Future<void> connect(String address) async {
    await disconnect(); // securite en cas de reconnexion
    final connection = await BluetoothConnection.toAddress(address);
    _connection = connection;
    _subscription = connection.input!.listen(
      _onData,
      onDone: _teardown,
      onError: (Object e) => _teardown(),
      cancelOnError: true,
    );
  }

  void _onData(Uint8List bytes) {
    final text = ascii.decode(bytes, allowInvalid: true);
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '\r' || ch == '\n') {
        _flushLine(withPrompt: false);
      } else if (ch == '>') {
        _flushLine(withPrompt: true);
      } else {
        _buffer.write(ch);
      }
    }
  }

  void _flushLine({required bool withPrompt}) {
    final line = _buffer.toString().trim();
    _buffer.clear();
    if (line.isNotEmpty) _linesCtrl.add(line);
    if (withPrompt) {
      final completer = _promptCompleter;
      _promptCompleter = null;
      if (completer != null && !completer.isCompleted) completer.complete();
    }
  }

  /// Envoie une commande et collecte toutes les lignes jusqu'au prompt '>'.
  ///
  /// Certaines commandes n'emettent jamais de prompt (ex : `AT MA` demarre un
  /// flux continu) -> a l'echance du [timeout] on rend simplement ce qui a
  /// deja ete recu : c'est le comportement voulu pour AT MA.
  Future<List<String>> sendCommand(
    String command, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (!isConnected) throw StateError('Boitier non connecte');
    final collected = <String>[];
    final done = Completer<void>();
    _promptCompleter = done;
    write('$command\r');
    final sub = lines.listen(collected.add);
    try {
      await done.future.timeout(timeout);
    } on TimeoutException {
      // Attendu pour AT MA ou en cas de NO DATA : non bloquant.
    } finally {
      await sub.cancel();
      if (identical(_promptCompleter, done)) _promptCompleter = null;
    }
    // Filtre l'echo eventuel de la commande (ATE0 devrait l'avoir supprime).
    collected.removeWhere((l) => l.toUpperCase() == command.toUpperCase());
    return collected;
  }

  /// Ecriture bas niveau sans attente de prompt (utilisee pour `AT MA` et
  /// pour interrompre le moniteur avec un simple caractere).
  void write(String text) {
    final connection = _connection;
    if (connection == null || !connection.isConnected) return;
    connection.output.add(Uint8List.fromList(utf8.encode(text)));
  }

  Future<void> drainOutput() async {
    try {
      await _connection?.output.allSent;
    } catch (_) {
      // La liaison peut tomber entre-temps : non bloquant.
    }
  }

  void _teardown() {
    _subscription?.cancel();
    _subscription = null;
    _connection = null;
    _linesCtrl.add(closedMarker);
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    final connection = _connection;
    _connection = null;
    if (connection != null) {
      try {
        await connection.close();
      } catch (_) {
        // Deja fermee cote OS : on continue.
      }
    }
    if (_promptCompleter != null && !_promptCompleter!.isCompleted) {
      _promptCompleter!.complete(); // reveille un sendCommand en attente
    }
    _promptCompleter = null;
    _linesCtrl.add(closedMarker);
  }

  Future<void> dispose() async {
    await disconnect();
    await _linesCtrl.close();
  }
}
