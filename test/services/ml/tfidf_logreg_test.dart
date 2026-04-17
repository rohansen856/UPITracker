import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt/services/ml/tfidf_logreg.dart';

/// Unit tests for the generic TF-IDF + Logistic Regression inference engine.
/// The three production classifiers (spam, transactional, direction) all
/// delegate to this engine — any bug here affects all of them, so the tests
/// below are deliberately paranoid.
void main() {
  group('TfidfLogReg.preprocess', () {
    test('lowercases and collapses whitespace', () {
      expect(TfidfLogReg.preprocess('  Hello    WORLD  '), 'hello world');
    });

    test('replaces URLs with <url>', () {
      expect(TfidfLogReg.preprocess('visit https://bit.ly/abc now'), 'visit <url> now');
      expect(TfidfLogReg.preprocess('Go to www.example.com today'), 'go to <url> today');
      expect(TfidfLogReg.preprocess('check cutt.ly/StGmXhY1 quickly'), 'check <url> quickly');
    });

    test('replaces currency amounts with <amt>', () {
      expect(TfidfLogReg.preprocess('paid Rs.250.00 today'), 'paid <amt> today');
      expect(TfidfLogReg.preprocess('Rs 1,200 debited'), '<amt> debited');
      expect(TfidfLogReg.preprocess('₹3,000 received'), '<amt> received');
      expect(TfidfLogReg.preprocess('INR 500 credited'), '<amt> credited');
    });

    test('replaces long and short numbers distinctly', () {
      expect(
        TfidfLogReg.preprocess('ref 602560907627 code 42'),
        'ref <num> code <d>',
      );
    });

    test('strips punctuation but preserves special tokens', () {
      expect(
        TfidfLogReg.preprocess('hello, world! <amt> — paid'),
        'hello world <amt> paid',
      );
    });

    test('empty / punctuation-only inputs become empty', () {
      expect(TfidfLogReg.preprocess(''), '');
      expect(TfidfLogReg.preprocess('!!!???'), '');
    });

    test('canonicalises the original failing user message', () {
      const sample =
          'Your account has been credited with a Rs 3,000 bonus, '
          'available for withdrawal within 24 hours. Click: '
          'cutt.ly/StGmXhY1 NowAssignedL1RBPDA';
      final out = TfidfLogReg.preprocess(sample);
      expect(out.contains('<amt>'), isTrue);
      expect(out.contains('<url>'), isTrue);
      expect(out.contains('<d>'), isTrue, reason: '24 hours → <d>');
      expect(out.contains('http'), isFalse);
      expect(out.contains('cutt'), isFalse);
      // "Rs 3,000" → <amt>; "hours" still contains "rs" substring which is
      // fine, but the bare currency token "rs" must not appear on its own.
      final tokens = out.split(' ').toSet();
      expect(tokens.contains('rs'), isFalse);
    });
  });

  group('TfidfLogReg model loading', () {
    test('rejects mismatched vocab/idf/weights lengths', () {
      final engine = TfidfLogReg(name: 'tmp', assetPath: 'unused');
      final broken = {
        'vocab': {'foo': 0, 'bar': 1},
        'idf': [1.0, 1.0],
        'weights': [0.5],
        'bias': 0.0,
      };
      expect(
        () => engine.loadFromJsonStringForTest(json.encode(broken)),
        throwsStateError,
      );
    });

    test('unloaded engine returns 0 probability (fail-open)', () {
      final engine = TfidfLogReg(name: 'tmp', assetPath: 'unused');
      expect(engine.isLoaded, isFalse);
      expect(engine.score('win Rs 1 crore bit.ly/x'), 0.0);
      expect(engine.predictsPositive('win Rs 1 crore bit.ly/x'), isFalse);
    });

    test('empty-vocab model returns 0 for every input', () {
      final engine = TfidfLogReg(name: 'tmp', assetPath: 'unused');
      // strongly-biased bias to prove the empty-vocab guard wins.
      engine.loadFromJsonStringForTest(json.encode({
        'vocab': <String, int>{},
        'idf': <double>[],
        'weights': <double>[],
        'bias': 5.0,
        'default_threshold': 0.5,
      }));
      expect(engine.score('any text'), 0.0);
      expect(engine.predictsPositive('any text'), isFalse);
    });

    test('exposes metadata on load', () {
      final engine = TfidfLogReg(name: 'tmp', assetPath: 'unused');
      engine.loadFromJsonStringForTest(json.encode({
        'vocab': {'foo': 0, 'bar': 1},
        'idf': [1.0, 2.0],
        'weights': [0.5, -1.0],
        'bias': 0.1,
        'default_threshold': 0.7,
        'positive_label': 'yes',
        'negative_label': 'no',
      }));
      expect(engine.isLoaded, isTrue);
      expect(engine.vocabSize, 2);
      expect(engine.defaultThreshold, 0.7);
      expect(engine.positiveLabel, 'yes');
      expect(engine.negativeLabel, 'no');
    });
  });

  group('TfidfLogReg sparse inference math', () {
    late TfidfLogReg engine;

    setUp(() {
      // Hand-crafted tiny model so we can reason about the math end to end.
      //   vocab = {good: 0, bad: 1, buy now: 2}
      //   idf   = [1.0, 1.0, 2.0]
      //   w     = [-1.0, +2.0, +3.0]
      //   b     = -0.5
      // Text "bad bad buy now" → tokens ["bad","bad","buy","now"]
      //   tf(bad)=2, tf(buy now)=1
      //   raw(bad) = (1+ln 2)*1.0 ≈ 1.693
      //   raw(buy now) = (1+ln 1)*2.0 = 2.0
      //   norm = sqrt(1.693² + 2.0²) ≈ 2.620
      //   contribution = (1.693/2.620)*2 + (2.0/2.620)*3 ≈ 1.292 + 2.290 = 3.583
      //   logit = -0.5 + 3.583 = 3.083  →  σ(3.083) ≈ 0.9561
      engine = TfidfLogReg(name: 'tmp', assetPath: 'unused');
      engine.loadFromJsonStringForTest(json.encode({
        'vocab': {'good': 0, 'bad': 1, 'buy now': 2},
        'idf': [1.0, 1.0, 2.0],
        'weights': [-1.0, 2.0, 3.0],
        'bias': -0.5,
        'default_threshold': 0.5,
      }));
    });

    test('matches hand-calculated probability', () {
      final p = engine.score('bad bad buy now');
      expect((p - 0.9561).abs(), lessThan(5e-3));
    });

    test('empty input → 0', () {
      expect(engine.score(''), 0.0);
      expect(engine.score('!!!'), 0.0);
    });

    test('all-OOV input falls back to sigmoid(bias)', () {
      final p = engine.score('xyzzy plugh');
      // σ(-0.5) ≈ 0.3775
      expect((p - 0.3775).abs(), lessThan(1e-3));
    });

    test('predictsPositive honours threshold override', () {
      final text = 'bad bad buy now';
      expect(engine.predictsPositive(text), isTrue);
      expect(engine.predictsPositive(text, threshold: 0.99), isFalse);
      expect(engine.predictsPositive(text, threshold: 0.1), isTrue);
    });
  });
}
