import 'package:easy_flutter_ads/easy_flutter_ads.dart';
import 'package:easy_flutter_ads/src/core/ad_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// A manager that counts load attempts instead of talking to the SDK, so the
/// preload gates can be observed without an ad server.
class _CountingManager extends FullScreenAdManager<InterstitialAd> {
  _CountingManager(super.runtime);

  int loads = 0;

  @override
  EasyAdFormat get format => EasyAdFormat.interstitial;

  @override
  String get adUnitId => 'test-unit';

  @override
  Duration get ttl => const Duration(minutes: 50);

  @override
  Future<InterstitialAd?> performLoad(String adUnitId, AdRequest request) async {
    loads++;
    return null;
  }

  @override
  void assignCallback(
    InterstitialAd ad,
    FullScreenContentCallback<InterstitialAd> callback,
  ) {}

  @override
  Future<void> performShow(InterstitialAd ad) async {}
}

void main() {
  late DateTime now;
  DateTime clock() => now;

  // No retries: the backoff would make the test wait in real time, and one
  // attempt is enough to tell "requested" from "did not request".
  const config = EasyAdsConfig(
    adUnitIds: EasyAdUnitIds.test(),
    interstitialDailyCap: 1,
    maxLoadRetries: 0,
  );

  AdRuntime buildRuntime() =>
      AdRuntime(config: config, clock: clock)
        ..ensureInitialized = () async => true;

  setUp(() => now = DateTime(2026, 7, 20, 12));

  group('preload and the daily cap', () {
    test('a spent cap stops the request', () async {
      final runtime = buildRuntime();
      await runtime.noteShown(EasyAdFormat.interstitial);

      final manager = _CountingManager(runtime);
      await manager.preload();

      expect(manager.loads, 0);
    });

    test('an unspent cap lets it through', () async {
      final manager = _CountingManager(buildRuntime());

      await manager.preload();

      expect(manager.loads, 1);
    });

    test('a running cooldown does not stop the request', () async {
      final runtime = AdRuntime(
        config: const EasyAdsConfig(
          adUnitIds: EasyAdUnitIds.test(),
          interstitialCooldown: Duration(minutes: 3),
          maxLoadRetries: 0,
        ),
        clock: clock,
      )..ensureInitialized = () async => true;
      await runtime.noteShown(EasyAdFormat.interstitial);

      final manager = _CountingManager(runtime);
      await manager.preload();

      // The ad has to be cached by the time the cooldown expires; declining to
      // load through it would empty the cache exactly when it is needed.
      expect(manager.loads, 1);
    });

    test('a spent hour stops a request that would expire waiting', () async {
      final runtime = AdRuntime(
        config: const EasyAdsConfig(
          adUnitIds: EasyAdUnitIds.test(),
          interstitialHourlyCap: 1,
          // The window reopens in 60 minutes; an ad loaded now dies at 50.
          fullScreenAdTtl: Duration(minutes: 50),
          maxLoadRetries: 0,
        ),
        clock: clock,
      )..ensureInitialized = () async => true;
      await runtime.noteShown(EasyAdFormat.interstitial);

      final manager = _CountingManager(runtime);
      await manager.preload();

      expect(manager.loads, 0);
    });

    test('a spent hour still loads once the ad would survive the wait', () async {
      final runtime = AdRuntime(
        config: const EasyAdsConfig(
          adUnitIds: EasyAdUnitIds.test(),
          interstitialHourlyCap: 1,
          fullScreenAdTtl: Duration(minutes: 50),
          maxLoadRetries: 0,
        ),
        clock: clock,
      )..ensureInitialized = () async => true;
      await runtime.noteShown(EasyAdFormat.interstitial);

      // 15 minutes left in the window, well inside the 50 minute TTL: loading
      // now puts the ad on screen the moment the cap lifts.
      now = now.add(const Duration(minutes: 45));
      final manager = _CountingManager(runtime);
      await manager.preload();

      expect(manager.loads, 1);
    });

    test('the cap clears when the date rolls over', () async {
      final runtime = buildRuntime();
      await runtime.noteShown(EasyAdFormat.interstitial);

      now = now.add(const Duration(days: 1));
      final manager = _CountingManager(runtime);
      await manager.preload();

      expect(manager.loads, 1);
    });
  });
}
