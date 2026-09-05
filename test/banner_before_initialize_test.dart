import 'package:easy_flutter_ads/easy_flutter_ads.dart';
import 'package:easy_flutter_ads/src/core/ad_runtime.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A banner may be built before `EasyAds.initialize()` has run — the host app
/// can defer it behind a premium check, a remote config fetch, or a deliberate
/// delay so the UMP form does not land on a cold screen.
///
/// Such a banner used to be lost for the rest of the session: it returned
/// before subscribing to anything, so neither the request gate nor the arrival
/// of the runtime could revive it, and only a resize would try again. That
/// shipped as "no banner on the home screen in production" while every
/// emulator — slower to reach the first screen — happened to look fine.
void main() {
  /// Records whether the banner got as far as asking the SDK to come up, which
  /// is the first thing a real load does once the runtime exists.
  ({AdRuntime runtime, List<bool> calls}) buildRuntime() {
    final calls = <bool>[];
    final runtime = AdRuntime(
      config: const EasyAdsConfig(adUnitIds: EasyAdUnitIds.test()),
    );
    runtime.ensureInitialized = () async {
      calls.add(true);
      return false; // Stop before touching platform channels.
    };
    return (runtime: runtime, calls: calls);
  }

  Widget banner() => const Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: SizedBox(width: 320, child: EasyBannerAd())),
  );

  setUp(() => EasyBannerAd.runtime = null);
  tearDown(() => EasyBannerAd.runtime = null);

  testWidgets('a banner mounted before the runtime exists loads once it arrives', (
    tester,
  ) async {
    await tester.pumpWidget(banner());
    final r = buildRuntime();
    expect(r.calls, isEmpty, reason: 'runtime yokken istek çıkmamalı');

    EasyBannerAd.runtime = r.runtime;
    await tester.pump();

    expect(
      r.calls,
      isNotEmpty,
      reason: 'runtime bağlanınca banner ikinci şansını kullanmalı',
    );
  });

  testWidgets('a disposed banner does not load when the runtime arrives', (
    tester,
  ) async {
    await tester.pumpWidget(banner());
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.shrink(),
      ),
    );

    final r = buildRuntime();
    EasyBannerAd.runtime = r.runtime;
    await tester.pump();

    expect(r.calls, isEmpty, reason: 'dispose sonrası dinleyici bırakılmalı');
  });

  test('attaching a runtime notifies, re-attaching the same one does not', () {
    final before = EasyBannerAd.runtimeAttached.value;
    final runtime = buildRuntime().runtime;

    EasyBannerAd.runtime = runtime;
    expect(EasyBannerAd.runtimeAttached.value, before + 1);

    EasyBannerAd.runtime = runtime;
    expect(
      EasyBannerAd.runtimeAttached.value,
      before + 1,
      reason: 'aynı runtime yeniden atanınca boş yere yükleme tetiklenmemeli',
    );
  });

  test('clearing the runtime is silent', () {
    EasyBannerAd.runtime = buildRuntime().runtime;
    final after = EasyBannerAd.runtimeAttached.value;

    EasyBannerAd.runtime = null;
    expect(EasyBannerAd.runtimeAttached.value, after);
  });
}
