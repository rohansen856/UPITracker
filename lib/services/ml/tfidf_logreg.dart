import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Generic binary classifier: TF-IDF (1-2 gram, L2-normalised, sublinear-TF)
/// features fed into a Logistic Regression model. Weights are produced by
/// `scripts/train_all_models.py` and shipped as small JSON blobs.
///
/// This class is the shared inference engine used by all stacked classifiers
/// ([SpamFilter], [TransactionalClassifier], [DirectionClassifier]). A single
/// instance owns one model's weights and answers [score].
///
/// Preprocessing in [preprocess] must stay byte-identical to
/// `scripts/ml_core.py::preprocess` — fixture tests assert 1e-4 parity.
class TfidfLogReg {
  TfidfLogReg({required this.name, required this.assetPath});

  /// Human-readable tag used in debug logs.
  final String name;

  /// Path inside `assets/` that holds the serialised model.
  final String assetPath;

  Map<String, int> _vocab = const {};
  List<double> _idf = const [];
  List<double> _weights = const [];
  double _bias = 0.0;
  double _defaultThreshold = 0.5;
  String _positiveLabel = 'positive';
  String _negativeLabel = 'negative';
  bool _loaded = false;
  Completer<void>? _loading;

  bool get isLoaded => _loaded;
  int get vocabSize => _vocab.length;
  double get defaultThreshold => _defaultThreshold;
  String get positiveLabel => _positiveLabel;
  String get negativeLabel => _negativeLabel;

  /// Loads the model from its bundled asset. Idempotent and safe under
  /// concurrent callers. Errors are swallowed so the pipeline fails-open.
  Future<void> load() async {
    if (_loaded) return;
    if (_loading != null) return _loading!.future;
    final c = Completer<void>();
    _loading = c;
    try {
      final raw = await rootBundle.loadString(assetPath);
      _loadFromJsonString(raw);
      _loaded = true;
    } catch (e, s) {
      debugPrint('TfidfLogReg($name): load failed from $assetPath — $e\n$s');
    } finally {
      _loading = null;
      c.complete();
    }
  }

  @visibleForTesting
  void loadFromJsonStringForTest(String jsonStr) {
    _loadFromJsonString(jsonStr);
    _loaded = true;
  }

  void _loadFromJsonString(String raw) {
    final obj = json.decode(raw) as Map<String, dynamic>;
    final vocab = (obj['vocab'] as Map).cast<String, dynamic>();
    final idf = (obj['idf'] as List).cast<num>();
    final weights = (obj['weights'] as List).cast<num>();
    if (vocab.length != idf.length || vocab.length != weights.length) {
      throw StateError(
        'TfidfLogReg($name): vocab/idf/weights length mismatch '
        '(${vocab.length}/${idf.length}/${weights.length})',
      );
    }
    _vocab = {for (final e in vocab.entries) e.key: (e.value as num).toInt()};
    _idf = idf.map((n) => n.toDouble()).toList(growable: false);
    _weights = weights.map((n) => n.toDouble()).toList(growable: false);
    _bias = (obj['bias'] as num).toDouble();
    _defaultThreshold = (obj['default_threshold'] as num?)?.toDouble() ?? 0.5;
    _positiveLabel = obj['positive_label'] as String? ?? 'positive';
    _negativeLabel = obj['negative_label'] as String? ?? 'negative';
  }

  /// Probability that [text] belongs to the positive class (0..1).
  /// Returns 0.0 if the model isn't loaded — callers are expected to treat
  /// that as "uncertain / do not block".
  double score(String text) {
    if (!_loaded || _vocab.isEmpty) return 0.0;
    final clean = preprocess(text);
    if (clean.isEmpty) return 0.0;

    final tokens = clean.split(' ').where((t) => t.isNotEmpty).toList(growable: false);
    final tf = <int, int>{};

    for (var i = 0; i < tokens.length; i++) {
      final uni = _vocab[tokens[i]];
      if (uni != null) tf[uni] = (tf[uni] ?? 0) + 1;
      if (i + 1 < tokens.length) {
        final bi = _vocab['${tokens[i]} ${tokens[i + 1]}'];
        if (bi != null) tf[bi] = (tf[bi] ?? 0) + 1;
      }
    }
    if (tf.isEmpty) return _sigmoid(_bias);

    double normSq = 0.0;
    final raw = <int, double>{};
    tf.forEach((idx, count) {
      final v = (1.0 + math.log(count)) * _idf[idx];
      raw[idx] = v;
      normSq += v * v;
    });
    final norm = math.sqrt(normSq);
    if (norm == 0.0) return _sigmoid(_bias);

    double logit = _bias;
    raw.forEach((idx, v) {
      logit += (v / norm) * _weights[idx];
    });
    return _sigmoid(logit);
  }

  /// Convenience: does [text] score at or above [threshold] (defaults to
  /// the model-provided default)?
  bool predictsPositive(String text, {double? threshold}) {
    return score(text) >= (threshold ?? _defaultThreshold);
  }

  static double _sigmoid(double x) => 1.0 / (1.0 + math.exp(-x));

  // --------------------------------------------------------------------------
  // Preprocessing — MUST mirror scripts/ml_core.py::preprocess exactly.
  // --------------------------------------------------------------------------

  static final RegExp _urlRe = RegExp(
    r'(?:https?://|www\.)\S+|(?:\b[a-z0-9.-]+\.(?:com|in|org|net|co|io|ly|app|link|me)(?:/\S*)?)',
    caseSensitive: false,
  );
  static final RegExp _amtRe = RegExp(
    r'(?:₹|rs\.?|inr)\s*[\d,]+(?:\.\d{1,2})?',
    caseSensitive: false,
  );
  static final RegExp _longNumRe = RegExp(r'\d{4,}');
  static final RegExp _shortNumRe = RegExp(r'\d+');
  static final RegExp _nonWordRe = RegExp(r'[^a-z0-9<>\s]');
  static final RegExp _wsRe = RegExp(r'\s+');

  /// Canonical preprocessing shared with the Python trainer.
  static String preprocess(String text) {
    if (text.isEmpty) return '';
    var t = text.toLowerCase();
    t = t.replaceAll(_urlRe, ' <url> ');
    t = t.replaceAll(_amtRe, ' <amt> ');
    t = t.replaceAll(_longNumRe, ' <num> ');
    t = t.replaceAll(_shortNumRe, ' <d> ');
    t = t.replaceAll(_nonWordRe, ' ');
    t = t.replaceAll(_wsRe, ' ').trim();
    return t;
  }
}
