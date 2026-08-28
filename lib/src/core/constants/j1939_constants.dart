import 'dart:typed_data';

/// Constantes SAE J1939 utilisees par le decodeur de trames.
///
/// Memoire des PGN surveilles (decimal / hex) :
///   65226 0xFECA -> DM1  : codes defauts ACTIFS
///   65227 0xFECB -> DM2  : codes defauts HISTORIQUES (inactifs)
///   60416 0xEC00 -> TP.CM : transport protocol - controle (>8 octets)
///   60160 0xEB00 -> TP.DT : transport protocol - donnees
///   61444 0xF004 -> EEC1  : controleur moteur 1 (regime, couple, turbo...)
///   65262 0xFEEE -> ET1   : temperatures moteur (refroidissement, huile)
///   65263 0xFEEF -> EFL/P1: fluides moteur (pression carburant, tension...)
///   65265 0xFEF1 -> CCVS1 : vitesse vehicule / regulateur
///   65269 0xFEF5 -> AMB   : conditions ambiantes
///   65276 0xFEFC -> LFE1  : niveau liquides (carburant)
class J1939Constants {
  J1939Constants._();

  static const int pgnRequest = 59904; // 0xEA00 : requete globale de PGN
  static const int pgnTransportCtrl = 60416; // 0xEC00
  static const int pgnTransportData = 60160; // 0xEB00
  static const int pgnEec1 = 61444; // 0xF004
  static const int pgnEt1 = 65262; // 0xFEEE
  static const int pgnEflP1 = 65263; // 0xFEEF
  static const int pgnCcvs1 = 65265; // 0xFEF1
  static const int pgnAmb = 65269; // 0xFEF5
  static const int pgnLfe1 = 65276; // 0xFEFC
  static const int pgnDm1 = 65226; // 0xFECA
  static const int pgnDm2 = 65227; // 0xFECB

  /// Adresse source (SA) de notre outil de diagnostic : 0xF9 est dedie aux
  /// "service tools" dans J1939-81. Utilisee pour signer nos requetes DM1.
  static const int toolSourceAddress = 0xF9;

  /// Adresses sources les plus courantes sur engins (J1939-81).
  static const Map<int, String> sourceAddresses = <int, String>{
    0x00: 'Calculateur moteur #1',
    0x01: 'Controleur moteur avance',
    0x03: 'Transmission #1',
    0x09: 'Retarder',
    0x0B: 'Freinage (ABS/EBS)',
    0x11: 'Instrumentation #1',
    0x17: 'Instrumentation #2',
    0x21: 'Calculateur caisse/carrosserie',
    0x27: 'Transmission #2',
    0x44: 'Hydraulique auxiliaire',
    0x49: 'Commande auxiliaire #1',
    0xD8: 'Passerelle OEM',
    0xF9: 'Outil de diagnostic (nous)',
    0xFF: 'Adresse globale (broadcast)',
  };

  static String sourceName(int sa) => sourceAddresses[sa] ??
      'Noeud 0x${sa.toRadixString(16).toUpperCase().padLeft(2, '0')}';

  /// Etat d'un voyant code sur 2 bits dans l'en-tete du DM1 :
  /// 00=eteint, 01=allume, 10=clignotement lent, 11=clignotement rapide.
  static String lampState(int twoBits) {
    switch (twoBits) {
      case 0x00:
        return 'eteint';
      case 0x01:
        return 'allume';
      case 0x02:
        return 'clignote lentement';
      default:
        return 'clignote rapidement';
    }
  }

  /// Lecture d'un signal multi-octets dans la charge utile CAN.
  ///
  /// Convention SAE J1939 : les signaux multi-octets sont transmis avec
  /// L'OCTET DE POIDS FAIBLE EN PREMIER (little endian).
  /// Exemple - regime moteur SPN 190 (octets 4-5 de l'EEC1) :
  ///   brut = data[4] | (data[5] << 8)
  ///   rpm  = brut * 0,125
  static int readLittleEndian(Uint8List data, int offset, int length) {
    var value = 0;
    for (var i = length - 1; i >= 0; i--) {
      value = (value << 8) | (data[offset + i] & 0xFF);
    }
    return value;
  }
}
