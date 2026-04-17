import 'tfidf_logreg.dart';

/// Layer 1 — promotional / scam message filter.
///
/// Fires on things like
///     "Your account has been credited with a Rs 3,000 bonus, … cutt.ly/…"
/// while letting real bank notifications through. Tuned for **high precision**
/// (the model's default threshold yields zero false positives on the held-out
/// set); we prefer letting some spam through to dropping real transactions.
class SpamFilter {
  SpamFilter._();
  static final SpamFilter instance = SpamFilter._();

  final TfidfLogReg engine = TfidfLogReg(
    name: 'spam',
    assetPath: 'assets/spam_model.json',
  );

  bool get isLoaded => engine.isLoaded;
  double get defaultThreshold => engine.defaultThreshold;

  Future<void> load() => engine.load();

  /// Probability that [text] is promotional / scam (0..1).
  double spamProbability(String text) => engine.score(text);

  /// Is [text] spam at (or above) [threshold]? Falls back to the model's
  /// tuned default when null. If the model isn't loaded, returns false
  /// (fail-open — never block the pipeline on a missing asset).
  bool isSpam(String text, {double? threshold}) =>
      engine.predictsPositive(text, threshold: threshold);
}

/// Layer 2 — distinguishes real money-movement SMS from other bank / finance
/// messages such as OTPs, balance alerts, bill reminders, card statements,
/// and failed-transaction notices. Runs *after* the spam filter.
///
/// Positive class = "this SMS represents a completed UPI/bank transaction we
/// should record". Threshold defaults to 0.5.
class TransactionalClassifier {
  TransactionalClassifier._();
  static final TransactionalClassifier instance = TransactionalClassifier._();

  final TfidfLogReg engine = TfidfLogReg(
    name: 'transactional',
    assetPath: 'assets/transactional_model.json',
  );

  bool get isLoaded => engine.isLoaded;
  double get defaultThreshold => engine.defaultThreshold;

  Future<void> load() => engine.load();

  /// Probability that [text] is a real transactional message (0..1).
  double transactionalProbability(String text) => engine.score(text);

  /// Does [text] look like a completed transaction at (or above) [threshold]?
  /// Defaults to the model's tuned threshold. When the model isn't loaded,
  /// returns `true` (fail-open — don't drop real messages if the asset is
  /// missing; the downstream regex parser is the next safety net).
  bool isTransactional(String text, {double? threshold}) {
    if (!engine.isLoaded) return true;
    return engine.predictsPositive(text, threshold: threshold);
  }
}

/// Direction of a transactional message as predicted by the model.
enum TxDirection { debit, credit }

/// Layer 3 — debit / credit classifier. Acts as a second opinion for the
/// regex parser's keyword-based detection. Used to log / flag disagreements;
/// the parser remains authoritative unless the caller opts in to overrides.
class DirectionClassifier {
  DirectionClassifier._();
  static final DirectionClassifier instance = DirectionClassifier._();

  final TfidfLogReg engine = TfidfLogReg(
    name: 'direction',
    assetPath: 'assets/direction_model.json',
  );

  bool get isLoaded => engine.isLoaded;

  Future<void> load() => engine.load();

  /// Probability that [text] represents a **credit** (money in). Values
  /// close to 0 mean strongly debit; close to 1 mean strongly credit.
  double creditProbability(String text) => engine.score(text);

  /// Predicted direction, or `null` if the model is not confident enough.
  ///
  /// [confidence] is the minimum probability the model must assign to
  /// either side before committing. At `confidence = 0.5` (default) the
  /// prediction is a simple sign of `creditProbability - 0.5`, so the
  /// method never abstains on a loaded model — callers wanting a "not
  /// sure" band should pass a higher value (e.g. 0.65).
  TxDirection? predict(String text, {double confidence = 0.5}) {
    if (!engine.isLoaded) return null;
    final p = engine.score(text);
    if (p >= confidence) return TxDirection.credit;
    if (p <= (1.0 - confidence)) return TxDirection.debit;
    return null;
  }
}
