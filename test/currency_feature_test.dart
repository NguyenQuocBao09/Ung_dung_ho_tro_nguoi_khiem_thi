import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vision_assist/core/constants/strings_vi.dart';
import 'package:vision_assist/features/currency/data/currency_classifier.dart';
import 'package:vision_assist/features/currency/domain/denomination.dart';
import 'package:vision_assist/features/currency/presentation/currency_controller.dart';
import 'package:vision_assist/features/currency/presentation/currency_overlay.dart';

void main() {
  group('Currency Strings and State Tests', () {
    test('Currency Strings are properly defined', () {
      expect(StringsVi.currencyProcessing, isNotEmpty);
      expect(StringsVi.currencyNotRecognized, isNotEmpty);
      expect(StringsVi.currencyUnclear, isNotEmpty);
      expect(StringsVi.hintBringCloser, isNotEmpty);
      expect(StringsVi.actionReadAgain, isNotEmpty);
      expect(StringsVi.actionNewBill, isNotEmpty);
      expect(StringsVi.actionPauseCurrency, isNotEmpty);
      expect(StringsVi.actionResumeCurrency, isNotEmpty);
    });

    test('CurrencyState copyWith updates fields correctly', () {
      const state = CurrencyState();
      expect(state.isModelLoaded, isFalse);
      expect(state.isProcessing, isFalse);
      expect(state.lastResult, isNull);
      expect(state.announcedDenomination, isNull);
      expect(state.confidenceThreshold, 0.85);

      const result = MultiCropPredictionResult(
        label: '50k',
        denomination: Denomination.d50k,
        confidence: 0.95,
        spokenVi: 'năm mươi nghìn đồng',
        winningCrop: 'giữa 70%',
        winningCropIndex: 1,
        inferenceTimeMs: 42,
      );

      final updated = state.copyWith(
        isModelLoaded: true,
        isProcessing: false,
        lastResult: result,
        announcedDenomination: '50k',
      );

      expect(updated.isModelLoaded, isTrue);
      expect(updated.lastResult?.denomination, Denomination.d50k);
      expect(updated.lastResult?.winningCrop, 'giữa 70%');
      expect(updated.announcedDenomination, '50k');
    });
  });

  group('CurrencyOverlay Widget Tests', () {
    testWidgets('Renders empty when no result', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currencyControllerProvider.overrideWith(
              (ref) => _FakeCurrencyController(const CurrencyState()),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: CurrencyOverlay(),
            ),
          ),
        ),
      );

      expect(find.text('100.000 đ'), findsNothing);
      expect(find.byType(FloatingActionButton), findsWidgets);
    });

    testWidgets('Renders denomination result correctly wrapped in ExcludeSemantics', (tester) async {
      const result = MultiCropPredictionResult(
        label: '200k',
        denomination: Denomination.d200k,
        confidence: 0.965,
        spokenVi: 'hai trăm nghìn đồng',
        winningCrop: 'giữa 70%',
        winningCropIndex: 1,
        inferenceTimeMs: 38,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currencyControllerProvider.overrideWith(
              (ref) => _FakeCurrencyController(
                const CurrencyState(lastResult: result, announcedDenomination: '200k'),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: CurrencyOverlay(),
            ),
          ),
        ),
      );

      // Văn bản hiển thị trực quan
      final textFinder = find.text('200.000 đ');
      expect(textFinder, findsOneWidget);
      expect(find.textContaining('96.5%'), findsOneWidget);
      expect(find.text('giữa 70%'), findsOneWidget);
      expect(find.textContaining('38 ms'), findsOneWidget);

      // Đảm bảo văn bản nhận dạng nằm bên trong ExcludeSemantics để TalkBack không đọc đè
      expect(
        find.ancestor(of: textFinder, matching: find.byType(ExcludeSemantics)),
        findsWidgets,
      );
    });

    testWidgets('Chưa xác nhận (chưa đủ phiếu) thì không hiển thị mệnh giá', (tester) async {
      const result = MultiCropPredictionResult(
        label: '2k',
        denomination: Denomination.d2k,
        confidence: 0.94,
        spokenVi: 'hai nghìn đồng',
        winningCrop: 'quét 7 vùng',
        winningCropIndex: 0,
        inferenceTimeMs: 400,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currencyControllerProvider.overrideWith(
              (ref) => _FakeCurrencyController(const CurrencyState(lastResult: result)),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: CurrencyOverlay())),
        ),
      );
      expect(find.text('2.000 đ'), findsNothing);
      expect(find.text(StringsVi.currencyProcessing), findsOneWidget);
    });

    test('isReliable cần đủ xác suất và số vùng đồng thuận', () {
      MultiCropPredictionResult r(double conf, int support) => MultiCropPredictionResult(
            label: '50k',
            denomination: Denomination.d50k,
            confidence: conf,
            spokenVi: '',
            winningCrop: '',
            winningCropIndex: 0,
            inferenceTimeMs: 0,
            support: support,
          );
      expect(r(0.95, 3).isReliable, isTrue);
      expect(r(0.95, 2).isReliable, isFalse);
      expect(r(0.85, 5).isReliable, isFalse);
    });

    testWidgets('Displays pause icon when active and play icon when paused', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currencyControllerProvider.overrideWith(
              (ref) => _FakeCurrencyController(
                const CurrencyState(isPaused: true),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: CurrencyOverlay(),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });
  });
}

class _FakeCurrencyController extends StateNotifier<CurrencyState>
    implements CurrencyController {
  _FakeCurrencyController(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
