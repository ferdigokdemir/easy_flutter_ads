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
          const Duration(seconds: 121),
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

  group('host initiated external activity', () {
    test('the whole suppression window is blocked, not just one return',
        () async {
      // The picker case: the camera permission dialog produces its own
      // foreground event before the picker's, and both must be suppressed.
      final runtime = buildRuntime()
        ..appOpenSuppressedUntil = now.add(const Duration(minutes: 5));

      expect(
        await runtime.evaluateGates(EasyAdFormat.appOpen),
        EasyAdSkipReason.resumeSuppressed,
      );

      now = now.add(const Duration(seconds: 30));
      expect(
        await runtime.evaluateGates(EasyAdFormat.appOpen),
        EasyAdSkipReason.resumeSuppressed,
      );
    });

    test('the window expires on its own', () async {
      final runtime = buildRuntime()
        ..appOpenSuppressedUntil = now.add(const Duration(minutes: 5));

      now = now.add(const Duration(minutes: 5, seconds: 1));
      expect(await runtime.evaluateGates(EasyAdFormat.appOpen), isNull);
    });

    test('other formats are untouched', () async {
      final runtime = buildRuntime()
        ..appOpenSuppressedUntil = now.add(const Duration(minutes: 5));

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

    test('interstitials are gated by the three minute default', () async {
      final runtime = buildRuntime();
      await runtime.noteShown(EasyAdFormat.interstitial);

      now = now.add(const Duration(seconds: 179));
      expect(
        await runtime.evaluateGates(EasyAdFormat.interstitial),
        EasyAdSkipReason.cooldown,
      );

      now = now.add(const Duration(seconds: 2));
      expect(await runtime.evaluateGates(EasyAdFormat.interstitial), isNull);
    });

    test('a zero cooldown opts out of the gate', () async {
      final runtime = buildRuntime(
        const EasyAdsConfig(
          adUnitIds: EasyAdUnitIds.test(),
          interstitialCooldown: Duration.zero,
        ),
      );
      await runtime.noteShown(EasyAdFormat.interstitial);

      expect(await runtime.evaluateGates(EasyAdFormat.interstitial), isNull);
    });

    test('survives a restart through the store', () async {
      const config = EasyAdsConfig(
        adUnitIds: EasyAdUnitIds.test(),
        appOpenCooldown: Duration(hours: 4),
      );
      final store = MemoryEasyAdsStore();

      final first = AdRuntime(config: config, store: store, clock: clock);
      await first.startSession();
      await first.noteShown(EasyAdFormat.appOpen);

      // The user kills the app and relaunches it an hour later.
      now = now.add(const Duration(hours: 1));
      final second = AdRuntime(config: config, store: store, clock: clock);
      await second.startSession();
      expect(
        await second.evaluateGates(EasyAdFormat.appOpen),
        EasyAdSkipReason.cooldown,
      );

      now = now.add(const Duration(hours: 3, seconds: 1));
      expect(await second.evaluateGates(EasyAdFormat.appOpen), isNull);
    });

    test('a stored timestamp from the future is ignored', () async {
      const config = EasyAdsConfig(
        adUnitIds: EasyAdUnitIds.test(),
        appOpenCooldown: Duration(hours: 4),
      );
      final store = MemoryEasyAdsStore();

      final first = AdRuntime(config: config, store: store, clock: clock);
      await first.startSession();
      await first.noteShown(EasyAdFormat.appOpen);

      // The device clock moved backwards; an honoured future timestamp would
      // freeze the format until the clock caught up.
      now = now.subtract(const Duration(days: 30));
      final second = AdRuntime(config: config, store: store, clock: clock);
      await second.startSession();
      expect(await second.evaluateGates(EasyAdFormat.appOpen), isNull);
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

    test('App Open ads default to three a day', () async {
      final runtime = buildRuntime();

      for (var i = 0; i < 3; i++) {
        expect(await runtime.evaluateGates(EasyAdFormat.appOpen), isNull);
        await runtime.noteShown(EasyAdFormat.appOpen);
      }

      expect(
        await runtime.evaluateGates(EasyAdFormat.appOpen),
        EasyAdSkipReason.dailyCapReached,
      );
    });

    test('interstitials default to six a day', () async {
      // The hourly cap is cleared so the daily one is what bites; the two are
      // exercised separately.
      final runtime = buildRuntime(
        const EasyAdsConfig(
          adUnitIds: EasyAdUnitIds.test(),
          interstitialHourlyCap: null,
        ),
      );

      for (var i = 0; i < 6; i++) {
        expect(await runtime.evaluateGates(EasyAdFormat.interstitial), isNull);
        await runtime.noteShown(EasyAdFormat.interstitial);
        // Step past the 180 second cooldown so the cap is what bites.
        now = now.add(const Duration(seconds: 181));
      }

      expect(
        await runtime.evaluateGates(EasyAdFormat.interstitial),
        EasyAdSkipReason.dailyCapReached,
      );
    });
  });

  group('hourly cap', () {
    test('blocks the third interstitial of the hour', () async {
      final runtime = buildRuntime();

      await runtime.noteShown(EasyAdFormat.interstitial);
      now = now.add(const Duration(seconds: 181));
      expect(await runtime.evaluateGates(EasyAdFormat.interstitial), isNull);

      await runtime.noteShown(EasyAdFormat.interstitial);
      now = now.add(const Duration(seconds: 181));
      expect(
        await runtime.evaluateGates(EasyAdFormat.interstitial),
        EasyAdSkipReason.hourlyCapReached,
      );
    });

    test('the window slides instead of resetting on the hour', () async {
      final runtime = buildRuntime();

      await runtime.noteShown(EasyAdFormat.interstitial); // t = 0
      now = now.add(const Duration(minutes: 30));
      await runtime.noteShown(EasyAdFormat.interstitial); // t = 30

      // t = 59: the first impression is still inside the hour.
      now = now.add(const Duration(minutes: 29));
      expect(
        await runtime.evaluateGates(EasyAdFormat.interstitial),
        EasyAdSkipReason.hourlyCapReached,
      );

      // t = 61: it has aged out, freeing one slot. A fixed "since the top of
      // the hour" window would have freed both.
      now = now.add(const Duration(minutes: 2));
      expect(await runtime.evaluateGates(EasyAdFormat.interstitial), isNull);
    });

    test('survives a restart through the store', () async {
      const config = EasyAdsConfig(adUnitIds: EasyAdUnitIds.test());
      final store = MemoryEasyAdsStore();

      final first = AdRuntime(config: config, store: store, clock: clock);
      await first.startSession();
      await first.noteShown(EasyAdFormat.interstitial);
      now = now.add(const Duration(minutes: 5));
      await first.noteShown(EasyAdFormat.interstitial);

      // The user kills the app and relaunches it ten minutes later.
      now = now.add(const Duration(minutes: 10));
      final second = AdRuntime(config: config, store: store, clock: clock);
      await second.startSession();
      expect(
        await second.evaluateGates(EasyAdFormat.interstitial),
        EasyAdSkipReason.hourlyCapReached,
      );
    });

    test('other formats are untouched by it', () async {
      final runtime = buildRuntime(
        const EasyAdsConfig(
          adUnitIds: EasyAdUnitIds.test(),
          appOpenCooldown: Duration.zero,
        ),
      );

      for (var i = 0; i < 3; i++) {
        expect(await runtime.evaluateGates(EasyAdFormat.appOpen), isNull);
        await runtime.noteShown(EasyAdFormat.appOpen);
      }

      // Three App Open ads in one hour: stopped by the daily cap, never by an
      // hourly one — the cap is interstitial-only.
      expect(
        await runtime.evaluateGates(EasyAdFormat.appOpen),
        EasyAdSkipReason.dailyCapReached,
      );
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

  group('request gate', () {
    test('stays shut until both the SDK and consent are ready', () {
      final runtime = buildRuntime()..canRequestAds = false;
      var openings = 0;
      runtime.requestGateOpened.addListener(() => openings++);

      runtime.markInitialized();
      expect(openings, 0, reason: 'consent has not arrived yet');

      runtime.canRequestAds = true;
      expect(openings, 1, reason: 'a late consent must reopen the gate');
    });

    test('reopens when a timed-out SDK init finishes later', () {
      final runtime = buildRuntime();
      var openings = 0;
      runtime.requestGateOpened.addListener(() => openings++);

      runtime.markInitialized();
      runtime.markInitialized();

      expect(openings, 2);
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
