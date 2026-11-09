import 'dart:async';

import 'package:easy_flutter_ads/easy_flutter_ads.dart';
import 'package:easy_flutter_ads/src/core/ad_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// App Open without the SDK: every load is counted and finishes only when the
/// test says so, so "asked", "waited" and "gave up" can be told apart.
class _SlowAppOpen extends AppOpenAdManager {
  _SlowAppOpen(super.runtime);

  int loads = 0;
  final pending = <Completer<AppOpenAd?>>[];

  @override
  String get adUnitId => 'test-unit';

  @override
  Future<AppOpenAd?> performLoad(String adUnitId, AdRequest request) {
    loads++;
    final c = Completer<AppOpenAd?>();
    pending.add(c);
    return c.future;
  }

  @override
  void assignCallback(
      AppOpenAd ad, FullScreenContentCallback<AppOpenAd> callback) {}

  @override
  Future<void> performShow(AppOpenAd ad) async {}
}

void main() {
  late DateTime now;
  DateTime clock() => now;

  setUp(() => now = DateTime(2026, 11, 9, 12));

  /// A runtime past the first-launch threshold, with no retries so a failed
  /// load does not wait in real time.
  Future<AdRuntime> runtime({int dailyCap = 3}) async {
    final r = AdRuntime(
      config: EasyAdsConfig(
        adUnitIds: const EasyAdUnitIds.test(),
        appOpenMinSessions: 0,
        appOpenDailyCap: dailyCap,
        maxLoadRetries: 0,
      ),
      clock: clock,
    )..ensureInitialized = () async => true;
    await r.startSession();
    return r;
  }

  test('a spent cap returns at once, without loading', () async {
    final r = await runtime(dailyCap: 1);
    await r.noteShown(EasyAdFormat.appOpen);
    final manager = _SlowAppOpen(r);

    final shown =
        await manager.showOnColdStart(maxWait: const Duration(seconds: 30));

    expect(shown, isFalse);
    expect(manager.loads, 0);
  });

  test('an open gate loads and gives up after maxWait', () async {
    final manager = _SlowAppOpen(await runtime());
    final watch = Stopwatch()..start();

    final shown = await manager.showOnColdStart(
        maxWait: const Duration(milliseconds: 80));

    expect(shown, isFalse);
    expect(manager.loads, 1);
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('a failed load returns without waiting out maxWait', () async {
    final manager = _SlowAppOpen(await runtime());
    final watch = Stopwatch()..start();

    final result =
        manager.showOnColdStart(maxWait: const Duration(seconds: 30));
    await Future<void>.delayed(Duration.zero);
    manager.pending.single.complete(null);

    expect(await result, isFalse);
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('without maxWait nothing is waited for', () async {
    final manager = _SlowAppOpen(await runtime());
    final watch = Stopwatch()..start();

    final shown = await manager.showOnColdStart();

    expect(shown, isFalse);
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('the first launches skip before any load, as before', () async {
    final r = AdRuntime(
      config: const EasyAdsConfig(
          adUnitIds: EasyAdUnitIds.test(),
          appOpenMinSessions: 3,
          maxLoadRetries: 0),
      clock: clock,
    )..ensureInitialized = () async => true;
    await r.startSession();
    final manager = _SlowAppOpen(r);

    expect(await manager.showOnColdStart(maxWait: const Duration(seconds: 30)),
        isFalse);
    expect(manager.loads, 0);
  });
}
