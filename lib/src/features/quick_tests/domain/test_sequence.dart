/// Modèle d'une étape élémentaire d'un test moteur : libellé affiché au
/// centre de l'écran, commande texte/HEX à envoyer au boîtier (ELM327/STN),
/// puis attente avant l'étape suivante.
class TestStep {
  const TestStep(
    this.label, {
    this.command = '',
    this.delay = const Duration(seconds: 1),
  });

  /// Texte affiché pendant l'exécution de cette étape.
  final String label;

  /// Commande AT/ST ou trame HEX brute (ex: `18EAFFF9CAFE00`).
  /// Chaîne vide = simple pause (aucun octet envoyé).
  final String command;

  /// Délai d'attente après l'envoi (stabilisation/lecture du calculateur).
  final Duration delay;

  bool get sendsFrame => command.trim().isNotEmpty;
}

/// Séquence de test nommée : titre bref + liste ordonnée d'étapes.
class TestSequence {
  const TestSequence(this.title, this.steps);

  final String title;
  final List<TestStep> steps;
}

/// Séquences par défaut proposées par l'application.
///
/// ⚠️ Les commandes de pilotage moteur sont PROPRIÉTAIRES (elles dépendent du
/// constructeur et de l'outil associé : Cat ET, Komatsu Smart, dealer kit...).
/// Les paramètres `command` sont donc injectés depuis la configuration de
/// l'écran : une chaîne vide = étape de pause (labels + délais), le scénario
/// reste visuellement complet et devient actif dès qu'une commande réelle est
/// saisie dans « Paramètres ».
class DefaultTests {
  DefaultTests._();

  /// Test Régime Moteur : commande montée + palier de lecture.
  static TestSequence rpm(String command) =>
      TestSequence('Test Régime Moteur', [
        const TestStep('Préparation de la commande moteur...',
            delay: Duration(seconds: 2)),
        TestStep('Commande « test régime » envoyée...',
            command: command, delay: const Duration(seconds: 2)),
        const TestStep('Stabilisation du régime en cours...',
            delay: Duration(seconds: 3)),
        const TestStep(
            'Mesure du régime terminée — vérifiez l\'écran Diagnostic.',
            delay: Duration(seconds: 1)),
      ]);

  /// Variation de Régime : montée puis descente en paliers.
  static TestSequence variation(String command) =>
      TestSequence('Variation de Régime', [
        TestStep('Commande de variation envoyée...',
            command: command, delay: const Duration(seconds: 2)),
        const TestStep('Palier haut — stabilisation...',
            delay: Duration(seconds: 3)),
        const TestStep('Palier bas — stabilisation...',
            delay: Duration(seconds: 3)),
        const TestStep('Variation terminée — régime revenu au ralenti.',
            delay: Duration(seconds: 1)),
      ]);

  /// Test Injecteurs : contrôle un à un (générique 6 cylindres, ajustable
  /// si le moteur en comporte davantage).
  static TestSequence injectors(String command) => TestSequence(
      'Test Injecteurs',
      List<TestStep>.generate(6, (i) {
        final n = i + 1;
        return TestStep('Test Injecteur $n en cours... Veuillez patienter',
            command: command, delay: const Duration(seconds: 3));
      }));
}
