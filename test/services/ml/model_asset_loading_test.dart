import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt/services/ml/message_pipeline.dart';
import 'package:receipt/services/ml/tfidf_logreg.dart';

/// Exercises the production load path (`rootBundle`) that the rest of the ML
/// suite bypasses via `loadFromJsonStringForTest`. Assets come from the
/// bundle `flutter test` builds out of pubspec.yaml, so a missing or
/// misspelled asset declaration fails here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all three shipped models load through rootBundle', () async {
    await MessagePipeline.instance.load();
    expect(MessagePipeline.instance.isLoaded, isTrue);
  });

  test('a missing asset leaves the engine unloaded (fail-open)', () async {
    final e = TfidfLogReg(name: 'missing', assetPath: 'assets/does_not_exist.json');
    await e.load();
    expect(e.isLoaded, isFalse);
    expect(e.score('anything'), 0.0);
  });

  test('a corrupt model (length mismatch) is rejected, not half-loaded', () async {
    const path = 'assets/corrupt_model.json';
    final corrupt = json.encode({
      'vocab': {'a': 0, 'b': 1},
      'idf': [1.0],
      'weights': [0.5, 0.5],
      'bias': 0.0,
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (ByteData? message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key != path) return null;
      return ByteData.sublistView(Uint8List.fromList(utf8.encode(corrupt)));
    });
    addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));

    final e = TfidfLogReg(name: 'corrupt', assetPath: path);
    await e.load();
    expect(e.isLoaded, isFalse);
  });
}
