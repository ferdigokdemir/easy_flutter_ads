import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../app_open/app_open_ad_manager.dart';
import '../banner/easy_banner_ad.dart';
import '../config/easy_ads_config.dart';
import '../consent/consent_manager.dart';
import '../full_screen/interstitial_ad_manager.dart';
import '../full_screen/rewarded_ad_manager.dart';
import '../full_screen/rewarded_interstitial_ad_manager.dart';
import 'ad_runtime.dart';
import 'easy_ads_store.dart';

/// The package entry point.
///
/// ```dart
/// await EasyAds.instance.initialize(
///   config: EasyAdsConfig(adUnitIds: const EasyAdUnitIds.test()),
///   store: PrefsStore(),
/// );
/// EasyAds.instance.appOpen.startWatchingAppState();
/// EasyAds.instance.preloadAll();
/// ```
///
/// Initialization order is deliberate and matters: consent is gathered first,
/// then targeting settings are applied, then the SDK is initialized, and only
/// then may ads be requested. Requesting before consent costs EEA fill;
/// requesting before initialization finishes means mediation adapters miss the
/// first request.
class EasyAds {
  EasyAds._();

  /// The singleton instance.
  static final EasyAds instance = EasyAds._();

  AdRuntime? _runtime;
  ConsentManager? _consent;
  AppOpenAdManager? _appOpen;
  InterstitialAdManager? _interstitial;
  RewardedAdManager? _rewarded;
  RewardedInterstitialAdManager? _rewardedInterstitial;
  Future<bool>? _initFuture;

  /// True once [initialize] has been called (the SDK itself may still be
  /// starting up).
  bool get isConfigured => _runtime != null;

  /// True once the Google Mobile Ads SDK finished initializing.
  bool get isReady => _runtime?.isInitialized ?? false;

  /// The live configuration.
  EasyAdsConfig get config => _requireRuntime().config;

  /// UMP consent: privacy options entry point, reset for testing, and the
  /// `canRequestAds` state.
  ConsentManager get consent => _consent ?? (throw _notInitialized);

  /// App Open ads.
  AppOpenAdManager get appOpen => _appOpen ?? (throw _notInitialized);

  /// Interstitial ads.
  InterstitialAdManager get interstitial =>
      _interstitial ?? (throw _notInitialized);

  /// Rewarded ads.
  RewardedAdManager get rewarded => _rewarded ?? (throw _notInitialized);

  /// Rewarded interstitial ads.
  RewardedInterstitialAdManager get rewardedInterstitial =>
      _rewardedInterstitial ?? (throw _notInitialized);

  /// Configures the package and starts the SDK.
  ///
  /// Safe to await on your splash screen: every failure path is swallowed and
  /// reported through [EasyAdsConfig.onError], so a broken ad stack degrades
  /// to "no ads" instead of "no app".
  ///
  /// Supply a persistent [store] if you use session thresholds or daily caps —
  /// the in-memory default resets on every cold start.
  ///
  /// [clock] exists for tests.
  Future<bool> initialize({
    required EasyAdsConfig config,
    EasyAdsStore? store,
    DateTime Function()? clock,
  }) async {
    final runtime = _runtime ??= AdRuntime(
      config: config,
      store: store,
      clock: clock,
    );
    runtime.config = config;
    runtime.ensureInitialized = _ensureInitialized;

    _consent ??= ConsentManager(runtime);
    _appOpen ??= AppOpenAdManager(runtime);
    _interstitial ??= InterstitialAdManager(runtime);
    _rewarded ??= RewardedAdManager(runtime);
    _rewardedInterstitial ??= RewardedInterstitialAdManager(runtime);
    EasyBannerAd.runtime = runtime;

    await runtime.startSession();
    return _ensureInitialized();
  }

  /// Replaces the configuration at runtime — the hook for Firebase Remote
  /// Config. Cached ads are kept; the new values apply to the next decision.
  Future<void> updateConfig(EasyAdsConfig config) async {
    final runtime = _requireRuntime();
    runtime.config = config;
    if (runtime.isInitialized) await _applyRequestConfiguration(runtime);
  }

  /// Turns all ads on or off — call with `false` as soon as you know the user
  /// is a subscriber. No requests are sent while disabled.
  Future<void> setAdsEnabled(bool enabled) =>
      updateConfig(_requireRuntime().config.copyWith(enabled: enabled));

  /// Warms the cache for every full screen format.
  ///
  /// Call after startup and whenever the app returns to the foreground; ads
  /// expire, and a stale cache means a visible delay at show time.
  void preloadAll() {
    final runtime = _runtime;
    if (runtime == null || !runtime.config.enabled) return;
    unawaited(_interstitial?.preload() ?? Future<void>.value());
    unawaited(_rewarded?.preload() ?? Future<void>.value());
    unawaited(_appOpen?.preload() ?? Future<void>.value());
  }

  /// Awaits consent gathering and SDK initialization, starting them if they
  /// have not run yet. Returns false when initialization failed.
  ///
  /// Only needed if you render ads yourself — a custom banner widget, or a
  /// format this package does not wrap. The built-in managers already gate
  /// every load behind this.
  Future<bool> ensureInitialized() => _ensureInitialized();

  /// Takes this session's single collapsible banner slot.
  ///
  /// Returns true the first time and false afterwards, so a custom banner
  /// widget can apply the same accidental-click protection [EasyBannerAd]
  /// does. Resets when the app process restarts.
  bool consumeCollapsibleSlot() {
    final runtime = _requireRuntime();
    if (runtime.collapsibleConsumed) return false;
    runtime.collapsibleConsumed = true;
    return true;
  }

  /// Opens Google's Ad Inspector overlay.
  ///
  /// This is the supported way to debug fill and mediation on a real device:
  /// it shows the waterfall, which adapter answered, latency and the last
  /// request's response for every ad unit. Put it behind a hidden gesture in
  /// your debug menu.
  ///
  /// The device must be registered as a test device
  /// ([EasyAdsConfig.testDeviceIds]).
  Future<void> openAdInspector() async {
    if (!await _ensureInitialized()) return;
    MobileAds.instance.openAdInspector((error) {
      if (error == null) return;
      _requireRuntime().logError(
        StateError('Ad inspector error: ${error.message}'),
        StackTrace.current,
      );
    });
  }

  /// Mutes or unmutes video ad audio.
  ///
  /// Call this when your own audio is playing — a video ad blaring over the
  /// app's music is a common one-star review. Applies to ads shown afterwards.
  Future<void> setAppMuted(bool muted) async {
    try {
      await MobileAds.instance.setAppMuted(muted);
    } catch (error, stackTrace) {
      _requireRuntime().logError(error, stackTrace);
    }
  }

  /// Sets the relative volume of video ads, from 0 (silent) to 1 (full).
  ///
  /// Reducing this reduces revenue slightly, since some advertisers do not bid
  /// on muted inventory — worth it only when your app has its own audio.
  Future<void> setAppVolume(double volume) async {
    try {
      await MobileAds.instance.setAppVolume(volume.clamp(0, 1));
    } catch (error, stackTrace) {
      _requireRuntime().logError(error, stackTrace);
    }
  }

  /// Releases every cached ad and stops the app state listener.
  void dispose() {
    _appOpen?.dispose();
    _interstitial?.dispose();
    _rewarded?.dispose();
    _rewardedInterstitial?.dispose();
  }

  Future<bool> _ensureInitialized() {
    final runtime = _requireRuntime();
    if (runtime.isInitialized) return Future.value(true);
    return _initFuture ??= _startSdk(runtime);
  }

  Future<bool> _startSdk(AdRuntime runtime) async {
    try {
      // 1. Consent first. An ad requested before the consent string exists is
      // served without it, and AdMob then reports low consent coverage for
      // EEA/UK/CH traffic — which shows up as lost fill and eCPM.
      await _consent!.gather();
      runtime.canRequestAds = await _consent!.canRequestAds();

      // 2. Targeting/test-device settings are global and must be in place
      // before the first request.
      await _applyRequestConfiguration(runtime);

      // 3. Start the SDK. Mediation adapters only participate in requests made
      // after this completes.
      final status = await MobileAds.instance.initialize();
      if (kDebugMode && runtime.config.verboseLogging) {
        status.adapterStatuses.forEach((name, adapter) {
          debugPrint(
            '📺 easy_flutter_ads adapter $name: ${adapter.state.name} '
            '(${adapter.description})',
          );
        });
      }

      runtime.markInitialized();
      return true;
    } catch (error, stackTrace) {
      runtime.logError(error, stackTrace);
      _initFuture = null; // let the next call try again
      return false;
    }
  }

  Future<void> _applyRequestConfiguration(AdRuntime runtime) async {
    // Test device IDs must never reach production traffic: a real device
    // marked as a test device stops earning, and a real ad clicked during
    // development is invalid activity.
    final useTestDevices =
        !kReleaseMode || runtime.config.allowTestDevicesInRelease;
    await runtime.applyRequestConfiguration(
      testDeviceIds: useTestDevices ? runtime.config.testDeviceIds : const [],
    );
  }

  AdRuntime _requireRuntime() => _runtime ?? (throw _notInitialized);

  StateError get _notInitialized => StateError(
    'EasyAds.instance.initialize() must be awaited before using ads.',
  );
}
