import 'package:easy_flutter_ads/easy_flutter_ads.dart';
import 'package:easy_flutter_ads/src/core/ad_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  DateTime clock() => now;

  AdRuntime buildRuntime([EasyAdsConfig? config]) => AdRuntime(
    config:
        config ?? const EasyAdsConfig(adUnitIds: EasyAdUnitIds.test()),
    clock: clock,
  );

  setUp(() => now = DateTime(2026, 7, 20, 12));

  group('kill switches', () {
    test('the master switch blocks every format', () async {
      final runtime = buildRuntime(
        const EasyAdsConfig(adUnitIds: EasyAdUnitIds.test(), enabled: false),
      );

      for (final format in EasyAdFormat.values) {
        expect(
          await runtime.evaluateGates(format),
          EasyAdSkipReason.adsDisabled,
          reason: format.name,
        );
      }
    });

    test('a format switch blocks only that format', () async {
      final runtime = buildRuntime(
        const EasyAdsConfig(
          adUnitIds: EasyAdUnitIds.test(),
          interstitialEnabled: false,
        ),
      );

      expect(
        await runtime.evaluateGates(EasyAdFormat.interstitial),
        EasyAdSkipReason.formatDisabled,
      );
      expect(await runtime.evaluateGates(EasyAdFormat.rewarded), isNull);
    });
  });

  group('app open placement gates', () {
    test('suppressed while another full screen ad is on screen', () async {
      final runtime = buildRuntime()..isShowingFullScreenAd = true;

      expect(
        await runtime.evaluateGates(EasyAdFormat.appOpen),
        EasyAdSkipReason.alreadyShowing,
      );
    });

    test('suppressed right after another full screen ad closed', () async {
      // The trap this exists for: the user taps a rewarded ad, lands in the
      // Play Store, comes back, and the resume handler fires.
      final runtime = buildRuntime()
        ..lastOtherFullScreenAdClosedAt = now.subtract(
          const Duration(seconds: 5),
        );

      expect(
        await runtime.evaluateGates(EasyAdFormat.appOpen),
        EasyAdSkipReason.adjacentToAnotherAd,
      );
    });

    test('allowed once the gap has elapsed', () async {
      final runtime = buildRuntime()
        ..lastOtherFullScreenAdClosedAt = now.subtract(
          const Duration(seconds: 31),
        );

      expect(await runtime.evaluateGates(EasyAdFormat.appOpen), isNull);
    });

    test('an interstitial is not blocked by the app open gap rule', () async {
      final runtime = buildRuntime()
        ..lastOtherFullScreenAdClosedAt = now.subtract(
          const Duration(seconds: 1),
        );

      expect(await runtime.evaluateGates(EasyAdFormat.interstitial), isNull);
    });
  });

  group('cooldown', () {
    test('blocks a second app open ad inside the window', () async {
      final runtime = buildRuntime(
        const EasyAdsConfig(
          adUnitIds: EasyAdUnitIds.test(),
          appOpenCooldown: Duration(minutes: 2),
        ),
      );
      await runtime.noteShown(EasyAdFormat.appOpen);

      now = now.add(const Duration(seconds: 119));
      expect(
        await runtime.evaluateGates(EasyAdFormat.appOpen),
        EasyAdSkipReason.cooldown,
      );

      now = now.add(const Duration(seconds: 2));
      expect(await runtime.evaluateGates(EasyAdFormat.appOpen), isNull);
    });

    test('never blocks a user-initiated rewarded ad', () async {
      final runtime = buildRuntime(
        const EasyAdsConfig(
          adUnitIds: EasyAdUnitIds.test(),
          appOpenCooldown: Duration(hours: 4),
        ),
      );
      await runtime.noteShown(EasyAdFormat.rewarded);

      expect(await runtime.evaluateGates(EasyAdFormat.rewarded), isNull);
    });
  });

  group('daily cap', () {
    test('counts impressions and resets the next day', () async {
      final runtime = buildRuntime(
        const EasyAdsConfig(
          adUnitIds: EasyAdUnitIds.test(),
          appOpenCooldown: Duration.zero,
          appOpenDailyCap: 2,
        ),
      );

      await runtime.noteShown(EasyAdFormat.appOpen);
      expect(await runtime.evaluateGates(EasyAdFormat.appOpen), isNull);

      await runtime.noteShown(EasyAdFormat.appOpen);
      expect(
        await runtime.evaluateGates(EasyAdFormat.appOpen),
        EasyAdSkipReason.dailyCapReached,
      );

      now = now.add(const Duration(days: 1));
      expect(await runtime.evaluateGates(EasyAdFormat.appOpen), isNull);
    });
  });

  group('session counter', () {
    test('increments and persists through the store', () async {
      final store = MemoryEasyAdsStore();

      final first = AdRuntime(
        config: const EasyAdsConfig(adUnitIds: EasyAdUnitIds.test()),
        store: store,
        clock: clock,
      );
      await first.startSession();
      expect(first.sessionCount, 1);

      final second = AdRuntime(
        config: const EasyAdsConfig(adUnitIds: EasyAdUnitIds.test()),
        store: store,
        clock: clock,
      );
      await second.startSession();
      expect(second.sessionCount, 2);
    });
  });

  group('config', () {
    test('copyWith replaces only what it is given', () {
      const config = EasyAdsConfig(adUnitIds: EasyAdUnitIds.test());
      final updated = config.copyWith(enabled: false);

      expect(updated.enabled, isFalse);
      expect(updated.appOpenCooldown, config.appOpenCooldown);
      expect(updated.adUnitIds, config.adUnitIds);
    });

    test('nullable fields can be cleared explicitly', () {
      const config = EasyAdsConfig(
        adUnitIds: EasyAdUnitIds.test(),
        appOpenDailyCap: 5,
      );

      expect(config.copyWith().appOpenDailyCap, 5);
      expect(config.copyWith(clearAppOpenDailyCap: true).appOpenDailyCap, isNull);
    });
  });
}
