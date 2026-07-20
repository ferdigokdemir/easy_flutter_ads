import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/easy_ads_config.dart';
import 'easy_ad_event.dart';
import 'easy_ads_store.dart';

/// Shared state and policy gates for every ad manager.
///
/// This is the only place that knows *whether* an ad may be shown; managers
/// only know *how* to load and show one. Keeping the rules here is what makes
/// cross-format rules — "no App Open ad right after an interstitial" — possible
/// at all.
///
/// Internal: not exported from `package:easy_flutter_ads/easy_flutter_ads.dart`.
class AdRuntime {
  /// Creates the runtime. [clock] is injectable so the gates can be unit
  /// tested without waiting in real time.
  AdRuntime({
    required this.config,
    EasyAdsStore? store,
    DateTime Function()? clock,
  }) : store = store ?? MemoryEasyAdsStore(),
       _clock = clock ?? DateTime.now;

  static const _sessionCountKey = 'easy_ads.session_count';
  static const _capCountPrefix = 'easy_ads.cap_count.';
  static const _capDayPrefix = 'easy_ads.cap_day.';

  /// The live configuration. Replaced wholesale by `EasyAds.updateConfig`.
  EasyAdsConfig config;

  /// Persistence for session counts and daily caps.
  final EasyAdsStore store;

  final DateTime Function() _clock;

  /// Current time according to the injected clock.
  DateTime get now => _clock();

  /// True once `MobileAds.initialize()` has completed.
  bool get isInitialized => _initialized;
  bool _initialized = false;

  /// Set by [EasyAds]. Managers call this before every load so the SDK is
  /// guaranteed to be up — mediation adapters only join requests made after
  /// initialization completes.
  Future<bool> Function() ensureInitialized = () async => false;

  /// How many times the app has been started (persisted, so it survives
  /// restarts when a real [EasyAdsStore] is supplied).
  int get sessionCount => _sessionCount;
  int _sessionCount = 0;

  /// Whether UMP allows ad requests. Updated by [EasyAds] after consent is
  /// gathered; fail-open (true) when the consent SDK itself errors out.
  bool canRequestAds = true;

  /// True while any full screen ad (App Open, interstitial, rewarded) is on
  /// screen.
  bool isShowingFullScreenAd = false;

  /// The moment the last interstitial/rewarded ad closed.
  DateTime? lastOtherFullScreenAdClosedAt;

  /// When each format was last shown, for cooldowns.
  final Map<EasyAdFormat, DateTime> lastShownAt = {};

  /// Whether the one collapsible banner slot of this session was used.
  bool collapsibleConsumed = false;

  /// Loads the persisted session count and increments it. Called once per
  /// process from `EasyAds.initialize`.
  Future<void> startSession() async {
    _sessionCount = await store.readInt(_sessionCountKey) + 1;
    await store.writeInt(_sessionCountKey, _sessionCount);
  }

  /// Marks the SDK as initialized.
  void markInitialized() => _initialized = true;

  /// Emits [event] to the host app and to the debug log.
  void emit(EasyAdEvent event) {
    if (config.verboseLogging && kDebugMode) {
      debugPrint('📺 easy_flutter_ads: $event');
    }
    try {
      config.onEvent?.call(event);
    } catch (error, stackTrace) {
      logError(error, stackTrace);
    }
  }

  /// Reports a swallowed exception to the host app.
  void logError(Object error, StackTrace stackTrace) {
    if (config.verboseLogging && kDebugMode) {
      debugPrint('📺 easy_flutter_ads error: $error');
    }
    config.onError?.call(error, stackTrace);
  }

  /// Wraps the SDK's paid event into an [EasyAdRevenue] and forwards it.
  void reportPaidEvent(
    EasyAdFormat format,
    String adUnitId,
    double value,
    PrecisionType precision,
    String currencyCode,
  ) {
    final callback = config.onPaidEvent;
    if (callback == null) return;
    try {
      callback(
        EasyAdRevenue(
          format: format,
          adUnitId: adUnitId,
          valueMicros: value.round(),
          currencyCode: currencyCode,
          precision: precision.index,
        ),
      );
    } catch (error, stackTrace) {
      logError(error, stackTrace);
    }
  }

  /// The ad request used for every load.
  AdRequest buildRequest() => AdRequest(keywords: config.requestKeywords);

  /// Applies targeting/test-device settings. These are global SDK settings, so
  /// they are applied before the first request and again on every
  /// `updateConfig`.
  Future<void> applyRequestConfiguration({
    required List<String> testDeviceIds,
  }) async {
    try {
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(
          testDeviceIds: testDeviceIds,
          maxAdContentRating: config.maxAdContentRating,
          tagForChildDirectedTreatment: config.tagForChildDirectedTreatment,
          tagForUnderAgeOfConsent: config.tagForUnderAgeOfConsent,
        ),
      );
    } catch (error, stackTrace) {
      logError(error, stackTrace);
    }
  }

  /// Returns the kill switch for [format].
  bool isFormatEnabled(EasyAdFormat format) {
    switch (format) {
      case EasyAdFormat.appOpen:
        return config.appOpenColdStartEnabled || config.appOpenResumeEnabled;
      case EasyAdFormat.interstitial:
        return config.interstitialEnabled;
      case EasyAdFormat.rewarded:
        return config.rewardedEnabled;
      case EasyAdFormat.rewardedInterstitial:
        return config.rewardedInterstitialEnabled;
      case EasyAdFormat.banner:
        return config.bannerEnabled;
    }
  }

  /// The cooldown configured for [format].
  Duration cooldownFor(EasyAdFormat format) {
    switch (format) {
      case EasyAdFormat.appOpen:
        return config.appOpenCooldown;
      case EasyAdFormat.interstitial:
        return config.interstitialCooldown;
      case EasyAdFormat.rewarded:
      case EasyAdFormat.rewardedInterstitial:
      case EasyAdFormat.banner:
        return Duration.zero;
    }
  }

  /// The per-day cap configured for [format], if any.
  int? dailyCapFor(EasyAdFormat format) {
    switch (format) {
      case EasyAdFormat.appOpen:
        return config.appOpenDailyCap;
      case EasyAdFormat.interstitial:
        return config.interstitialDailyCap;
      case EasyAdFormat.rewarded:
      case EasyAdFormat.rewardedInterstitial:
      case EasyAdFormat.banner:
        return null;
    }
  }

  /// Evaluates every gate that applies to showing [format] right now.
  ///
  /// Returns the reason the show must be skipped, or null when it may proceed.
  /// Rewarded ads deliberately skip the adjacency and cooldown gates: they are
  /// user-initiated in exchange for a reward, so suppressing one would break a
  /// promise the app already made to the user.
  Future<EasyAdSkipReason?> evaluateGates(EasyAdFormat format) async {
    if (!config.enabled) return EasyAdSkipReason.adsDisabled;
    if (!isFormatEnabled(format)) return EasyAdSkipReason.formatDisabled;

    final isUserInitiated =
        format == EasyAdFormat.rewarded ||
        format == EasyAdFormat.rewardedInterstitial;

    if (!isUserInitiated) {
      if (isShowingFullScreenAd) return EasyAdSkipReason.alreadyShowing;

      if (format == EasyAdFormat.appOpen) {
        final closedAt = lastOtherFullScreenAdClosedAt;
        if (closedAt != null &&
            now.difference(closedAt) < config.minGapAfterFullScreenAd) {
          return EasyAdSkipReason.adjacentToAnotherAd;
        }
      }

      final cooldown = cooldownFor(format);
      final shownAt = lastShownAt[format];
      if (cooldown > Duration.zero &&
          shownAt != null &&
          now.difference(shownAt) < cooldown) {
        return EasyAdSkipReason.cooldown;
      }

      final cap = dailyCapFor(format);
      if (cap != null && await _dailyCount(format) >= cap) {
        return EasyAdSkipReason.dailyCapReached;
      }
    }

    return null;
  }

  /// Records a successful impression: resets the cooldown clock and advances
  /// the daily counter.
  Future<void> noteShown(EasyAdFormat format) async {
    lastShownAt[format] = now;
    if (dailyCapFor(format) == null) return;
    final today = _todayOrdinal;
    final storedDay = await store.readInt('$_capDayPrefix${format.name}');
    final count = storedDay == today
        ? await store.readInt('$_capCountPrefix${format.name}')
        : 0;
    await store.writeInt('$_capDayPrefix${format.name}', today);
    await store.writeInt('$_capCountPrefix${format.name}', count + 1);
  }

  Future<int> _dailyCount(EasyAdFormat format) async {
    final storedDay = await store.readInt('$_capDayPrefix${format.name}');
    if (storedDay != _todayOrdinal) return 0;
    return store.readInt('$_capCountPrefix${format.name}');
  }

  int get _todayOrdinal {
    final today = now;
    return today.year * 10000 + today.month * 100 + today.day;
  }
}
