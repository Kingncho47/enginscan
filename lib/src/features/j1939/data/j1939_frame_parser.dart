import 'dart:async';
import 'dart:typed_data';

import '../domain/j1939_frame.dart';
import '../domain/models.dart';

/// Message J1939 en cours de reassemblage (Transport Protocol, ISO 15765-2
/// adapte par SAE J1939-21 pour les charges > 8 octets).
class _PendingTp {
  _PendingTp(this.pgn, this.totalLength);

  /// PGN du message final transporte (ex : 0xFECA pour un DM1 multi-defauts).
  final int pgn;

  /// Taille totale annoncee dans la trame de controle TP.CM.
  final int totalLength;

  final BytesBuilder buffer = BytesBuilder(copy: false);
}

/// Parseur des lignes HEX emises par le boitier ELM327 en mode moniteur
/// (`AT MA`) et extracteur des DTC contenus dans les trames DM1/DM2.
///
/// Exemple de ligne recue avec ATH1 + ATS0 :
/// ```
///   18FECA00 04FF00FFFFFFFFFF
///   ^ID 29b   ^payload (8 octets max par trame)
/// ```
class J1939FrameParser {
  final StreamController<J1939Frame> _framesCtrl =
      StreamController<J1939Frame>.broadcast();

  /// Trames completes pretes a l'exploitation (TP reassemble inclus).
  Stream<J1939Frame> get frames => _framesCtrl.stream;

  final Map<int, _PendingTp> _pendingTp = <int, _PendingTp>{};
  int framesParsed = 0;
  int parseErrors = 0;

  void addRawLine(String line) {
    final frame = parseLine(line);
    if (frame != null) _process(frame);
  }

  /// Convertit une ligne brute du boitier en [J1939Frame] typee.
  ///
  /// Tolere les espaces (ATS0/ATS1) et rejette tout ce qui n'est pas
  /// strictement hexadecimal : lignes "SEARCHING...", "BUS INIT...", etc.
  J1939Frame? parseLine(String line) {
    final hex = line.trim().replaceAll(' ', '').replaceAll('\t', '').toUpperCase();
    if (hex.length < 8) return null; // trop court : pas un ID 29 bits
    const digits = '0123456789ABCDEF';
    for (var i = 0; i < hex.length; i++) {
      if (!digits.contains(hex[i])) return null;
    }
    final id = int.parse(hex.substring(0, 8), radix: 16);
    final rest = hex.substring(8);
    if (rest.isEmpty || rest.length.isOdd) return null;
    final data = Uint8List(rest.length ~/ 2);
    for (var i = 0; i < data.length; i++) {
      data[i] = int.parse(rest.substring(i * 2, i * 2 + 2), radix: 16);
    }
    framesParsed++;
    return J1939Frame.fromRaw(id, data);
  }

  void _process(J1939Frame frame) {
    // ---- 1) Transport Protocol : trame de CONTROLE (TP.CM, PGN 0xEC00) ----
    if (frame.isTransportControl && frame.data.isNotEmpty) {
      final control = frame.data[0];
      if (control == 0x20 || control == 0x10) {
        // BAM (0x20, broadcast) ou RTS (0x10) :
        //   octet 1-2 : taille totale du message
        //   octets 3-5 : PGN transporte, poids faible en premier
        if (frame.data.length >= 6) {
          final totalLength = frame.data[1] | (frame.data[2] << 8);
          final pgn =
              (frame.data[5] << 16) | (frame.data[4] << 8) | frame.data[3];
          _pendingTp[frame.sourceAddress] = _PendingTp(pgn, totalLength);
        }
      } else if (control == 0xFF) {
        _pendingTp.remove(frame.sourceAddress); // abandon de session
      }
      return;
    }

    // ---- 2) Transport Protocol : trame de DONNEES (TP.DT, PGN 0xEB00) ----
    if (frame.isTransportData && frame.data.isNotEmpty) {
      final pending = _pendingTp[frame.sourceAddress];
      if (pending != null && pending.totalLength > 0) {
        if (pending.buffer.length < pending.totalLength) {
          // Octet 0 = numero de sequence, les 7 suivants sont des donnees.
          pending.buffer.add(frame.data.sublist(1));
        }
        if (pending.buffer.length >= pending.totalLength) {
          _pendingTp.remove(frame.sourceAddress);
          final bytes = pending.buffer.takeBytes();
          final payload = bytes.length > pending.totalLength
              ? Uint8List.sublistView(bytes, 0, pending.totalLength)
              : bytes;
          // On reconstruit une trame avec le VRAI PGN transporte :
          // ID = (priorite << 26) | (PGN << 8) | adresse source.
          final rebuiltId = (frame.priority << 26) |
              ((pending.pgn & 0x3FFFF) << 8) |
              frame.sourceAddress;
          _framesCtrl.add(J1939Frame.fromRaw(rebuiltId, payload));
        }
      }
      return;
    }

    // ---- 3) Trame simple (< 8 octets) : publiee telle quelle --------------
    _framesCtrl.add(frame);
  }

  /// Extrait les codes defauts d'une trame DM1 (actifs) ou DM2 (historiques).
  ///
  /// Structure du DM1 (SAE J1939-73) :
  /// ```
  ///   octet 0 : etat des voyants (MIL, STOP rouge, alerte ambre, protection)
  ///   octet 1 : etat des voyants clignotants
  ///   puis blocs de 4 octets par DTC :
  ///     [SPN pds faibles][SPN pds forts][SPN bits16-18 + FMI][occurrences]
  /// ```
  /// Decodage d'un bloc DTC :
  ///   SPN = b0 | (b1 << 8) | ((b2 & 0x07) << 16)
  ///   FMI = (b2 >> 3) & 0x1F
  ///   Occurrence Count = b3 & 0x7F (bit 8 = CM)
  List<DtcModel> extractDtcs(J1939Frame frame) {
    final dtcs = <DtcModel>[];
    final d = frame.data;
    if (d.length < 4) return dtcs;

    final lamps = _decodeLamps(d[0]);
    final lampsText = lamps.isEmpty ? null : lamps.join(' · ');

    var i = 2;
    while (i + 4 <= d.length) {
      final b0 = d[i], b1 = d[i + 1], b2 = d[i + 2], b3 = d[i + 3];
      i += 4;
      // Emplacements non utilises : remplis de FF ou de 00 selon calculateurs.
      if (b0 == 0xFF && b1 == 0xFF && b2 == 0xFF && b3 == 0xFF) continue;
      if (b0 == 0x00 && b1 == 0x00 && b2 == 0x00 && b3 == 0x00) continue;

      final spn = b0 | (b1 << 8) | ((b2 & 0x07) << 16);
      final fmi = (b2 >> 3) & 0x1F;
      final occurrence = b3 & 0x7F;
      if (spn == 0 || spn >= 524287) continue; // hors plage exploitable

      dtcs.add(DtcModel.fromLive(
        spn: spn,
        fmi: fmi,
        occurrenceCount: occurrence,
        isActive: frame.isDm1,
        lampSummary: lampsText,
      ));
    }
    return dtcs;
  }

  /// Decode l'octet "lamp status" du DM1 : 4 voyants x 2 bits.
  static List<String> _decodeLamps(int byte0) {
    final names = <String>[];
    final mil = byte0 & 0x03; // MIL / check engine
    final stop = (byte0 >> 2) & 0x03; // STOP rouge
    final amber = (byte0 >> 4) & 0x03; // alerte ambre
    final protect = (byte0 >> 6) & 0x03; // protection moteur
    if (mil != 0) names.add('MIL (${J1939Lamps.state(mil)})');
    if (stop != 0) names.add('STOP rouge (${J1939Lamps.state(stop)})');
    if (amber != 0) names.add('Alerte ambre (${J1939Lamps.state(amber)})');
    if (protect != 0) names.add('Protection (${J1939Lamps.state(protect)})');
    return names;
  }

  void dispose() {
    _framesCtrl.close();
    _pendingTp.clear();
  }
}

/// Petites etiquettes d'etat des voyants (reprise de J1939Constants sans
/// dependance circulaire pour la lisibilite du parseur).
class J1939Lamps {
  J1939Lamps._();

  static String state(int twoBits) {
    switch (twoBits) {
      case 0x01:
        return 'allume';
      case 0x02:
        return 'clignote lentement';
      case 0x03:
        return 'clignote rapidement';
      default:
        return 'eteint';
    }
  }
}
