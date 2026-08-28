import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../../features/j1939/domain/models.dart';
import '../../features/knowledge/data/dtc_repository.dart';

/// Base de connaissances PRE-REMPLIE : codes defauts J1939 reels, les plus
/// frequents sur engins de chantier et de manutention (Caterpillar, Komatsu,
/// Volvo CE, Liebherr, Manitou + generiques constructeurs moteurs).
///
/// Rappel lecture d'un code : "SPN 110 FMI 0" = parametre 110 (temperature
/// liquide de refroidissement) dont la donnee valide depasse le seuil critique.
class SeedData {
  SeedData._();

  /// Insere les fiches une seule fois ; la base est ensuite conservee entre
  /// les lancements (les mises a jour futures peuvent tester une colonne
  /// `seed_version` dans la table settings).
  static Future<void> populate(AppDatabase db) async {
    final database = await db.open();
    final rows =
        await database.rawQuery('SELECT COUNT(*) AS c FROM dtc_knowledge');
    final count = Sqflite.firstIntValue(rows) ?? 0;
    if (count > 0) return;

    final batch = database.batch();
    for (final m in kSeedKnowledge) {
      batch.insert(
        'dtc_knowledge',
        DtcRepository.modelToRow(m),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }
}

const List<DtcModel> kSeedKnowledge = <DtcModel>[
  // ---- 100-x : Pression d'huile moteur (SPN 100, PGN EFL/P1) ---------------
  DtcModel(
    code: '100-3',
    spn: 100,
    fmi: 3,
    brand: 'Generique',
    system: 'Lubrification',
    severity: DtcSeverity.majeur,
    description:
        "Pression d'huile moteur : tension du capteur au-dessus de la plage "
        'normale (court-circuit vers le plus). La pression reelle peut etre '
        'correcte : c est souvent le circuit capteur qui est en cause.',
    causes: [
      "Capteur de pression d'huile defectueux ou encrasse",
      'Fil signal en court-circuit vers +5 V / +12 V dans le faisceau',
      'Connecteur oxyde ou broche ecartee (vibrations)',
      'Masse moteur degradée (resistance parasite sur la mesure)',
    ],
    solutionSteps: [
      "Controler la pression REELLE au mano mecanique sur la prise d'essai",
      'Moteur arrete : mesurer alimentation et reference du capteur (5 V)',
      'Controler la continuite du fil signal (pas de contact avec le +)',
      'Nettoyer / reprendre les masses moteur et connecteurs',
      "Remplacer le capteur si hors specification constructeur",
      'Faire disparaitre le code puis controler en live data (SPN 100)',
    ],
  ),
  DtcModel(
    code: '100-4',
    spn: 100,
    fmi: 4,
    brand: 'Generique',
    system: 'Lubrification',
    severity: DtcSeverity.critique,
    description:
        "Pression d'huile moteur : tension sous la plage normale "
        '(court-circuit a la masse) OU pression reellement insuffisante. '
        'Si la lecture est fiable, risque de grippage imminent.',
    causes: [
      'Niveau huile bas ou huile tres degradee',
      'Filtre a huile colmate ou clapet by-pass bloque ouvert',
      "Pompe a huile usée (engrenages, corps) ou crepine colmatee",
      'Fil signal du capteur en court-circuit a la masse',
    ],
    solutionSteps: [
      "ARRETER IMMEDIATEMENT l engin si la pression chute en fonctionnement",
      'Controler niveau et aspect de l huile (limaille, emulsion blanche ?)',
      'Verifier la pression a chaud au ralenti avec un mano mecanique',
      'Sous le seuil constructeur : NE PAS redemarrer - demontage pompe/filtre/coussinets',
      'Pression correcte : investiguer le circuit capteur (fils, masse, capteur)',
    ],
  ),
  DtcModel(
    code: '100-1',
    spn: 100,
    fmi: 1,
    brand: 'Caterpillar',
    system: 'Lubrification',
    severity: DtcSeverity.critique,
    description:
        "Pression d'huile moteur sous le seuil critique severe (donnee valide) "
        '- typique moteurs Cat C4.4 / C6.6 / C7.1 / C9.3 (320D, 336, 950M...). '
        'Le calculateur declenche souvent un derate puis un arret automatique.',
    causes: [
      "Manque d'huile ou dilution carburant (injecteurs qui gouttent)",
      'By-pass du filtre a huile bloque / cartouche non amorcee apres vidange',
      "Pompe a huile fatiguee ou crepine d'aspiration partiellement colmatee",
      'Jeu coussinets excessif (moteur tres haute heures)',
    ],
    solutionSteps: [
      'Arret immediat et controle du niveau a froid',
      "Test pression mecanique : ralenti chaud, comparer aux specs SAE (ex : > 150 kPa)",
      'Remplacer filtre + huile si dilution ou depots ; rechercher la cause',
      'Controler pompe et crepine si la pression reste basse',
      "Apres reparation : effacement via outil CAT ET ou sequence DM3",
    ],
  ),
  // ---- 102-3 : Pression admission turbo (explicitement surveille en live) --
  DtcModel(
    code: '102-3',
    spn: 102,
    fmi: 3,
    brand: 'Generique',
    system: 'Admission / Turbo',
    severity: DtcSeverity.majeur,
    description:
        "Pression absolue du collecteur d'admission : tension capteur au-dessus "
        'de la plage normale, OU surpression reelle (surturbo). Sur les moteurs '
        'modernes un derate de couple peut etre applique.',
    causes: [
      'Capteur MAP / pression admission defectueux',
      'Wastegate ou vanne de geometrie variable (VGT) bloque fermee',
      'Actuateur de suralimentation HS (electrique ou pneumatique)',
      'Fil signal court-circuite vers le plus dans le faisceau',
      'Clapet / durite de recirculation obstrue (cas rares)',
    ],
    solutionSteps: [
      "Moteur au ralenti : la valeur SPN 102 doit avoisiner 100 kPa (atmosphere)",
      "Comparer a un mano : si concordance -> vraie surpression, sinon circuit capteur",
      "Controler l'actuateur wastegate/VGT : course libre, commande (depression/electrique)",
      'Nettoyer la geometrie variable si encrastee (suie)',
      "Mesurer le fil signal vs + : reparer le faisceau si court-circuit",
      'Test en charge : surveiller SPN 102 en live data (max ~250 kPa selon moteur)',
    ],
  ),
  DtcModel(
    code: '105-3',
    spn: 105,
    fmi: 3,
    brand: 'Komatsu',
    system: 'Admission',
    severity: DtcSeverity.mineur,
    description:
        "Temperature de l'air d'admission : tension du capteur au-dessus de la "
        'plage normale - frequent sur moteurs Komatsu SAA4D95 / SAA6D107 '
        '(PC130, PC210...). Peut induire une protection anti-detonation.',
    causes: [
      'Capteur temperature air (dans le collecteur ou apres refroidisseur) HS',
      'Court-circuit vers le plus du fil signal',
      'Connecteur rempli de poussiere / humidite',
    ],
    solutionSteps: [
      'Lire la valeur en live data : comparee a la temperature ambiante',
      'Debrancher le capteur : verifier resistance a froid (typ. quelques kohms)',
      'Controler le faisceau entre ECM et capteur (continuite + isolement)',
      'Remplacer le capteur ; souffler le connecteur et remettre de la graisse dielectrique',
    ],
  ),
  // ---- 110-x : Temperature liquide de refroidissement (ET1) ----------------
  DtcModel(
    code: '110-0',
    spn: 110,
    fmi: 0,
    brand: 'Generique',
    system: 'Refroidissement',
    severity: DtcSeverity.critique,
    description:
        'Temperature du liquide de refroidissement au-dessus du seuil critique '
        '(surchauffe confirmee, donnee valide). Risque joint de culasse, '
        'fissure culasse ou grippage : arret requis.',
    causes: [
      "Niveau bas - fuite radiateur, durite, pompe a eau, colliers",
      'Radiateur colmate exterieurement (poussiere/plumes) ou interieurement',
      'Thermostat bloque ferme',
      'Ventilateur hydraulique non declenche (sonde, relais, moteur fan)',
      "Bouchon de vase d'expansion ne tenant plus la pression",
    ],
    solutionSteps: [
      'ARRET moteur - laisser refroidir AVANT toute ouverture (brulures !)',
      'Controler le niveau et rechercher les traces de fuite',
      'Nettoyer le faisceau du radiateur a l air comprime, sens inverse du flux',
      'Demarrer chaud : verifier le declenchement du ventilateur',
      'Controler thermostat et pompe si la montee en temperature persiste en charge',
      'Remplacer le bouchon de vase si la soupape est morte',
    ],
  ),
  DtcModel(
    code: '110-3',
    spn: 110,
    fmi: 3,
    brand: 'Volvo CE',
    system: 'Refroidissement',
    severity: DtcSeverity.mineur,
    description:
        "Sonde temperature liquide de refroidissement : tension au-dessus de la "
        'plage normale - typique Volvo CE (EC140/EC220/EC300, L60-L120). La '
        'valeur affichee est figee ou aberrante (-40 degC / +215 degC).',
    causes: [
      'Sonde CTN defectueuse',
      'Fil signal court-circuite vers le plus (frottement dans le harnais)',
      'Corrosion des broches du connecteur',
    ],
    solutionSteps: [
      'Comparer SPN 110 live avec un thermometre infrarouge sur le bloc',
      'Mesurer la resistance de la sonde a froid (CTN : ~2-3 kohms a 20 degC)',
      'Secouer le harnais moteur tournant pour reproduire le defaut intermittent',
      'Reparer/remplacer puis valider une courbe de temperature plausible',
    ],
  ),
  DtcModel(
    code: '110-15',
    spn: 110,
    fmi: 15,
    brand: 'Caterpillar',
    system: 'Refroidissement',
    severity: DtcSeverity.mineur,
    description:
        'Temperature liquide de refroidissement au-dessus de la plage normale '
        '(severite faible) - premiere alerte avant le FMI 0. Sur Caterpillar ce '
        'code apparait souvent en travail intensif par forte chaleur.',
    causes: [
      'Charge prolongee proche de la capacite maximale',
      'Grille/radiateur partiellement encrasses',
      "Niveau de liquide juste sous l'optimum",
    ],
    solutionSteps: [
      'Nettoyer le groupe de refroidissement complet (radiateur, huile, charge air)',
      'Verifier le niveau a froid et la qualite du melange (antigel correct)',
      'Surveiller SPN 110 en live data pendant une cycle de travail type',
      'Si recurrence vers FMI 0 : traiter comme surchauffe confirmee',
    ],
  ),
  // ---- Carburant / reseau electrique / regime ------------------------------
  DtcModel(
    code: '94-4',
    spn: 94,
    fmi: 4,
    brand: 'Manitou',
    system: 'Alimentation carburant',
    severity: DtcSeverity.majeur,
    description:
        "Pression d'alimentation gasoil basse / circuit capteur en defaut - "
        'typique telescopiques Manitou MT/MRT (moteurs Deutz/Perkins). Se '
        'traduit par des pertes de puissance en levage ou des a-coups.',
    causes: [
      'Filtre a gasoil colmate (gasoil de chantier charge)',
      "Pompe d'amorçage / gousse de pompe fatiguee",
      "Prise d'air sur la ligne aspiration (durite poreuse, collier)",
      "Capteur de pression court-circuite a la masse",
    ],
    solutionSteps: [
      'Remplacer le filtre a gasoil + purger le circuit complet',
      'Controler SPN 94 en live data : au ralenti puis en pleine charge',
      "Tremper la ligne d'aspiration (test sous vide) pour detecter une prise d'air",
      'Si pression toujours basse : controler la pompe basse pression',
      'Circuit capteur : continuite fil signal vs masse, remplacer si HS',
    ],
  ),
  DtcModel(
    code: '158-3',
    spn: 158,
    fmi: 3,
    brand: 'Generique',
    system: 'Reseau electrique',
    severity: DtcSeverity.majeur,
    description:
        "Tension du reseau embarque trop elevee (>16 V typ.) - regulateur "
        "d'alternateur defectueux. Danger : les calculateurs peuvent se couper "
        'par securite et les batteries bouillent.',
    causes: [
      "Regulateur d'alternateur HS (tension non regulee)",
      'Alternateur debranche du faisceau de regulation en fonctionnement',
      'Mauvaise detection de temperature batterie (regulation adaptee)',
    ],
    solutionSteps: [
      'Mesurer la tension aux bornes batterie moteur tournant (13,8-14,6 V attendu)',
      '>15,5 V : arreter - risque destruction electronique et batteries',
      "Remplacer le regulateur ou l'alternateur",
      'Verifier le fil de compensation temperature vers la batterie',
    ],
  ),
  DtcModel(
    code: '158-4',
    spn: 158,
    fmi: 4,
    brand: 'Generique',
    system: 'Reseau electrique',
    severity: DtcSeverity.majeur,
    description:
        "Tension du reseau embarquee insuffisante (<11,5 V typ.) : alternateur "
        'non productif, courroie cassee/detendue, masses oxydees ou batteries '
        'sulfatees. Cause classique de codes fantomes multiples.',
    causes: [
      "Courroie d'alternateur detendue ou cassee",
      "Alternateur mort (diodes, charbons)",
      'Cosses de masse oxydees (chassis/moteur/cabine)',
      'Batteries sulfatees ou un element en court-circuit',
    ],
    solutionSteps: [
      'Mesurer tension batterie contact coupé puis moteur tournant',
      '<12,5 V moteur tournant = charge absente : alternateur/courroie/regulateur',
      'Reprendre TOUTES les masses (cosses etat de surface, serrage)',
      'Tester les batteries (densite/chargeur), separer si un pack tire l autre',
      'Apres reparation : verifier disparition des codes fantomes (DM2)',
    ],
  ),
  DtcModel(
    code: '190-2',
    spn: 190,
    fmi: 2,
    brand: 'Liebherr',
    system: 'Moteur',
    severity: DtcSeverity.majeur,
    description:
        'Regime moteur : signal erratique ou intermittant - frequent sur '
        "pelles Liebherr (R914-R926) quand le capteur inductif de regime "
        '(volant moteur) est encrasse ou dont le blindage est degrade.',
    causes: [
      "Capteur de regime inductif : entrefer excessif, metal debris colle",
      'Blindage du cable capteur degrade (interferences injecteurs)',
      'Connecteur desserre - vibrations',
      'Couronne dentee abimee (dents manquantes)',
    ],
    solutionSteps: [
      "Observer SPN 190 en live data : regime stable au ralenti ?",
      'Controler l entrefer du capteur et son serrage (spec constructeur)',
      'Nettoyer la face du capteur (copeaux metalliques eventuels)',
      'Verifier continuite + blindage du cable jusqu a l ECM',
      'Inspecter la couronne dentee au demontage si le probleme persiste',
    ],
  ),
  DtcModel(
    code: '96-1',
    spn: 96,
    fmi: 1,
    brand: 'Generique',
    system: 'Carburant',
    severity: DtcSeverity.info,
    description:
        'Niveau de carburant tres bas. Sur chantier, rouler sur la reserve '
        'aspire les impuretes du fond de cuve et provoque des pannes '
        "d'injection couteuses.",
    causes: [
      "Consommation sous-estimee (travail intensif, ralenti prolonge)",
      "Jauge/capteur de niveau fiable mais cuve reellement vide",
      "Retour d'injection anormal (fuite interne) qui vide la cuve",
    ],
    solutionSteps: [
      'Faire le plein AVANT que le code apparaisse a nouveau',
      'Verifier la concordance jauge / jauge baton dans la cuve',
      'Si consommation anormale : controler le retour injecteurs (test volume)',
      'Planifier un remplissage en fin de poste pour condensation reduite',
    ],
  ),
  DtcModel(
    code: '177-0',
    spn: 177,
    fmi: 0,
    brand: 'Caterpillar',
    system: 'Transmission',
    severity: DtcSeverity.majeur,
    description:
        "Temperature huile transmission au-dessus du seuil critique - typique "
        'chargeuses 950/962 et tombereaux 730 (convertisseur de couple). Le '
        'calculateur peut limiter la puissance pour proteger les embrayages.',
    causes: [
      'Radiateur transmission colmate (souvent confondu avec radiateur moteur)',
      "Niveau huile transmission bas ou huile degradee",
      'Embrayages internes qui patinent (usure) - chaleur generee',
      'Thermostat/valve thermique transmission bloque',
      'Travail prolonge en patinage (talus, chargement force)',
    ],
    solutionSteps: [
      'Reduire la charge immediatement et laisser refroidir au ralenti',
      "Controler niveau huile convertisseur/transmission moteur tournant",
      'Souffler le refroidisseur transmission (souvent derriere le radiateur)',
      'Analyser l huile (limaille ? odeur de brule ?) avant remise en charge',
      'Si recurrence : test de patinage des embrayages via outil constructeur',
    ],
  ),
  DtcModel(
    code: '1761-1',
    spn: 1761,
    fmi: 1,
    brand: 'Generique',
    system: 'Emissions SCR',
    severity: DtcSeverity.majeur,
    description:
        "Niveau d'uree (AdBlue) tres bas - machines Stage V / Tier 4F. Sans "
        'recharge, la reglementation impose une limitation progressive du '
        'couple puis un blocage du demarrage au prochain cycle.',
    causes: [
      "Cuve AdBlue non rechargée (oubli apres vidange)",
      "Capteur de niveau encraste (cristaux d'uree)",
      "Ligne/pompe SCR cristalisee par temps froid",
    ],
    solutionSteps: [
      'Remplir la cuve avec de l uree ISO 22241 uniquement',
      'Le code disparait seul apres quelques minutes moteur tourmant',
      'Si persiste cuve pleine : nettoyer/remplacer le capteur de niveau',
      "Controler l absence de cristaux sur la ligne SCR (hiver)",
    ],
  ),
  DtcModel(
    code: '91-3',
    spn: 91,
    fmi: 3,
    brand: 'Manitou',
    system: 'Commandes',
    severity: DtcSeverity.mineur,
    description:
        "Capteur pedale accelerateur : tension au-dessus de la plage normale - "
        'sur telescopiques Manitou cela declenche souvent un mode secours '
        '(regime limite, reponse douce).',
    causes: [
      'Potentiometre / capteur a effet Hall de pedale HS',
      'Double signal incoherent (pedales redondantes 5 V / 2,5 V)',
      'Court-circuit fil vers le plus ; connecteur envahi de poussiere',
    ],
    solutionSteps: [
      'Lire les deux voies du pedalier en live data : elles doivent suivre ensemble',
      'Comparer aux valeurs attendues : repos ~0,6 V / pleine course ~4,5 V',
      'Nettoyer le connecteur pedalier (poste poussiereux classique)',
      'Remplacer le pedalier si les deux voies divergent de facon fixe',
    ],
  ),
];
