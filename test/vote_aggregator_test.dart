import 'package:flutter_test/flutter_test.dart';
import 'package:vision_assist/features/currency/domain/denomination.dart';
import 'package:vision_assist/features/currency/domain/vote_aggregator.dart';

void main() {
  group('Denomination Enum Tests', () {
    test('Correctly maps all 10 model labels', () {
      expect(Denomination.fromCode('100k'), Denomination.d100k);
      expect(Denomination.fromCode('10k'), Denomination.d10k);
      expect(Denomination.fromCode('1k'), Denomination.d1k);
      expect(Denomination.fromCode('200k'), Denomination.d200k);
      expect(Denomination.fromCode('20k'), Denomination.d20k);
      expect(Denomination.fromCode('2k'), Denomination.d2k);
      expect(Denomination.fromCode('500k'), Denomination.d500k);
      expect(Denomination.fromCode('50k'), Denomination.d500k != Denomination.d50k ? Denomination.d50k : null);
      expect(Denomination.fromCode('5k'), Denomination.d5k);
      expect(Denomination.fromCode('none'), Denomination.none);
      expect(Denomination.fromCode('invalid'), Denomination.unknown);
    });

    test('isMoney property is accurate', () {
      expect(Denomination.d100k.isMoney, isTrue);
      expect(Denomination.d500k.isMoney, isTrue);
      expect(Denomination.none.isMoney, isFalse);
      expect(Denomination.unknown.isMoney, isFalse);
    });

    test('displayName returns Vietnamese format', () {
      expect(Denomination.d100k.displayName, '100.000 đ');
      expect(Denomination.d500k.displayName, '500.000 đ');
      expect(Denomination.none.displayName, 'Không phải tiền');
      expect(Denomination.unknown.displayName, 'Chưa rõ');
    });
  });

  group('VoteAggregator Tests', () {
    test('Does not confirm with fewer than 3 votes', () {
      final aggregator = VoteAggregator(
        windowSize: 5,
        requiredConsensus: 3,
        confidenceThreshold: 0.85,
      );

      const r1 = CurrencyRecognitionResult(
        label: '100k',
        denomination: Denomination.d100k,
        confidence: 0.90,
        spokenVi: 'một trăm nghìn đồng',
      );
      const r2 = CurrencyRecognitionResult(
        label: '100k',
        denomination: Denomination.d100k,
        confidence: 0.92,
        spokenVi: 'một trăm nghìn đồng',
      );

      expect(aggregator.addPrediction(r1), isNull);
      expect(aggregator.addPrediction(r2), isNull);
    });

    test('Confirms result on 3/5 consensus with confidence >= 0.85', () {
      final aggregator = VoteAggregator(
        windowSize: 5,
        requiredConsensus: 3,
        confidenceThreshold: 0.85,
      );

      const r1 = CurrencyRecognitionResult(
        label: '100k',
        denomination: Denomination.d100k,
        confidence: 0.88,
        spokenVi: 'một trăm nghìn đồng',
      );
      const r2 = CurrencyRecognitionResult(
        label: '50k',
        denomination: Denomination.d50k,
        confidence: 0.89,
        spokenVi: 'năm mươi nghìn đồng',
      );
      const r3 = CurrencyRecognitionResult(
        label: '100k',
        denomination: Denomination.d100k,
        confidence: 0.95,
        spokenVi: 'một trăm nghìn đồng',
      );
      const r4 = CurrencyRecognitionResult(
        label: '100k',
        denomination: Denomination.d100k,
        confidence: 0.91,
        spokenVi: 'một trăm nghìn đồng',
      );

      expect(aggregator.addPrediction(r1), isNull);
      expect(aggregator.addPrediction(r2), isNull);
      expect(aggregator.addPrediction(r3), isNull);

      // Frame 4: 3 votes for 100k in window [100k, 50k, 100k, 100k] -> confirmed!
      final confirmed = aggregator.addPrediction(r4);
      expect(confirmed, isNotNull);
      expect(confirmed!.denomination, Denomination.d100k);
      expect(confirmed.confidence, 0.91);
    });

    test('Ignores predictions below confidence threshold (0.85)', () {
      final aggregator = VoteAggregator(
        windowSize: 5,
        requiredConsensus: 3,
        confidenceThreshold: 0.85,
      );

      const lowConf = CurrencyRecognitionResult(
        label: '20k',
        denomination: Denomination.d20k,
        confidence: 0.80, // Dưới 0.85
        spokenVi: 'hai mươi nghìn đồng',
      );

      expect(aggregator.addPrediction(lowConf), isNull);
      expect(aggregator.addPrediction(lowConf), isNull);
      expect(aggregator.addPrediction(lowConf), isNull);
      expect(aggregator.addPrediction(lowConf), isNull);
      expect(aggregator.addPrediction(lowConf), isNull);
    });

    test('Sliding window drops old votes when exceeding windowSize', () {
      final aggregator = VoteAggregator(
        windowSize: 5,
        requiredConsensus: 3,
        confidenceThreshold: 0.85,
      );

      const r100k = CurrencyRecognitionResult(
        label: '100k',
        denomination: Denomination.d100k,
        confidence: 0.90,
        spokenVi: 'một trăm nghìn đồng',
      );
      const r500k = CurrencyRecognitionResult(
        label: '500k',
        denomination: Denomination.d500k,
        confidence: 0.92,
        spokenVi: 'năm trăm nghìn đồng',
      );

      aggregator.addPrediction(r100k);
      aggregator.addPrediction(r100k);
      // Window: [100k, 100k]

      aggregator.addPrediction(r500k);
      aggregator.addPrediction(r500k);
      aggregator.addPrediction(r500k);
      // Window: [100k, 100k, 500k, 500k, 500k] -> 500k has 3 votes!
      // Add another 500k, oldest 100k drops out
      final confirmed = aggregator.addPrediction(r500k);
      expect(confirmed, isNotNull);
      expect(confirmed!.denomination, Denomination.d500k);
    });

    test('reset() clears all voting history', () {
      final aggregator = VoteAggregator(
        windowSize: 5,
        requiredConsensus: 3,
        confidenceThreshold: 0.85,
      );

      const r = CurrencyRecognitionResult(
        label: '10k',
        denomination: Denomination.d10k,
        confidence: 0.95,
        spokenVi: 'mười nghìn đồng',
      );

      aggregator.addPrediction(r);
      aggregator.addPrediction(r);
      expect(aggregator.history.length, 2);

      aggregator.reset();
      expect(aggregator.history, isEmpty);
      expect(aggregator.addPrediction(r), isNull);
    });
  });
}
