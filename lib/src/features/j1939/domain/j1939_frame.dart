import 'dart:typed_data';

import '../../../core/constants/j1939_constants.dart';

/// Trame CAN J1939 decodee depuis un identifiant etendu 29 bits + payload.
///
/// Structure de l'identifiant 29 bits (J1939-21) :
/// ```
///   bits 28..26 : Priorite (3 bits, 0 = la plus haute)
///   bits 25..24 : R (reserve) + DP (Data Page)
///   bits 23..16 : PF  (PDU Format)
///   bits 15..08 : PS  (PDU Specific : adresse DESTINATION si PF<240 = PDU1,
///                      sinon extension de groupe = PDU2 broadcast)
///   bits 07..00 : SA  (adresse SOURCE de l'emetteur)
/// ```
/// Le PGN (Parameter Group Number) est code sur 18 bits aux positions
/// 8..25 : PGN = (ID >> 8) & 0x3FFFF, avec masquage du PS si PF < 240.
class J1939Frame {
  final int rawId;
  final int priority;
  final int dataPage;
  final int pduFormat;
  final int pduSpecific;
  final int sourceAddress;
  final int pgn;
  final Uint8List data;
  final DateTime receivedAt;

  const J1939Frame({
    required this.rawId,
    required this.priority,
    required this.dataPage,
    required this.pduFormat,
    required this.pduSpecific,
    required this.sourceAddress,
    required this.pgn,
    required this.data,
    required this.receivedAt,
  });

  factory J1939Frame.fromRaw(int id, Uint8List data) {
    final priority = (id >> 26) & 0x07;
    final dp = (id >> 24) & 0x03;
    final pf = (id >> 16) & 0xFF;
    final ps = (id >> 8) & 0xFF;
    final sa = id & 0xFF;

    final int pgn;
    if (pf < 240) {
      // PDU1 : PS = adresse destination -> exclu du PGN.
      pgn = (dp << 16) | (pf << 8);
    } else {
      // PDU2 : PS fait partie du PGN (diffusion vers un groupe).
      pgn = (dp << 16) | (pf << 8) | ps;
    }

    return J1939Frame(
      rawId: id,
      priority: priority,
      dataPage: dp,
      pduFormat: pf,
      pduSpecific: ps,
      sourceAddress: sa,
      pgn: pgn,
      data: data,
      receivedAt: DateTime.now(),
    );
  }

  bool get isPdu1 => pduFormat < 240;
  bool get isTransportControl => pgn == J1939Constants.pgnTransportCtrl;
  bool get isTransportData => pgn == J1939Constants.pgnTransportData;
  bool get isDm1 => pgn == J1939Constants.pgnDm1;
  bool get isDm2 => pgn == J1939Constants.pgnDm2;

  String get idHex =>
      rawId.toRadixString(16).toUpperCase().padLeft(8, '0');

  String get pgnHex => pgn.toRadixString(16).toUpperCase().padLeft(4, '0');

  String get dataHex => data
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');

  @override
  String toString() =>
      'J1939Frame(0x$idHex, PGN $pgnHex, SA ${sourceAddress.toRadixString(16)}, '
      '${data.length}B)';
}
