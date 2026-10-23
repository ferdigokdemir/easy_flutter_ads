import 'package:easy_flutter_ads/easy_flutter_ads.dart';
import 'package:easy_flutter_ads/src/core/ad_runtime.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A banner whose loads all failed used to stay empty until the app was
/// killed: the retry ladder ends after `maxLoadRetries`, and only a width
/// change started it again. Returning to the foreground now does.
void main() {
  final calls = <bool>[];

  Widget banner() => const Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: SizedBox(width: 320, child: EasyBannerAd())),
  );

  setUp(() {
    calls.clear();
    final runtime = AdRuntime(
      config: const EasyAdsConfig(adUnitIds: EasyAdUnitIds.test()),
    );
    runtime.ensureInitialized = () async {
      calls.add(true);
      return false; // Stop before touching platform channels.
    };
    EasyBannerAd.runtime = runtime;
  });
  tearDown(() => EasyBannerAd.runtime = null);

  /// Background and back, one step at a time — `AppLifecycleListener` asserts
  /// on skipped states, as a real device never skips them.
  Future<void> resume(WidgetTester tester) async {
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
  }

  testWidgets('an empty banner tries again when the app resumes', (
    tester,
  ) async {
    await tester.pumpWidget(banner());
    await tester.pump();
    expect(calls, hasLength(1));

    await resume(tester);

    expect(
      calls,
      hasLength(2),
      reason: 'ön plana dönüşte boş banner yeniden denemeli',
    );
  });

  testWidgets('a disposed banner does not load on resume', (tester) async {
    await tester.pumpWidget(banner());
    await tester.pump();
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.shrink(),
      ),
    );
    calls.clear();

    await resume(tester);

    expect(calls, isEmpty, reason: 'dispose sonrası observer bırakılmalı');
  });
}
