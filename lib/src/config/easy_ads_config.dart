import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/easy_ad_event.dart';
import 'easy_ad_unit_ids.dart';

/// Everything the package needs to know, in one immutable object.
///
/// Every field is safe to change at runtime through
/// `EasyAds.instance.updateConfig(...)`, which is how you drive the package
/// from Firebase Remote Config: fetch, build a new config, push it in. Ads
/// already cached stay cached; the new values apply to the next decision.
class EasyAdsConfig {
  /// Creates a configuration. The defaults are the conservative,
  /// policy-safe ones described on each field.
  const EasyAdsConfig({
    required this.adUnitIds,
    this.enabled = true,
    this.appOpenColdStartEnabled = true,
    this.appOpenResumeEnabled = true,
    this.interstitialEnabled = true,
    this.rewardedEnabled = true,
    this.rewardedInterstitialEnabled = true,
    this.bannerEnabled = true,
    this.loadTimeout = const Duration(seconds: 15),
    this.sdkInitTimeout = const Duration(seconds: 5),
    this.fullScreenAdTtl = const Duration(minutes: 50),
    this.appOpenAdTtl = const Duration(hours: 3, minutes: 30),
    this.maxLoadRetries = 4,
    this.retryBaseDelay = const Duration(seconds: 2),
    this.maxRetryDelay = const Duration(seconds: 32),
    this.appOpenCooldown = const Duration(minutes: 2),
    this.interstitialCooldown = Duration.zero,
    this.minGapAfterFullScreenAd = const Duration(seconds: 30),
    this.appOpenSplashMaxWait = const Duration(seconds: 5),
    this.appOpenMinSessions = 3,
    this.appOpenDailyCap,
    this.interstitialDailyCap,
    this.collapsibleBannerOncePerSession = true,
    this.testDeviceIds = const [],
    this.allowTestDevicesInRelease = false,
    this.forceConsentDebugGeographyEea = false,
    this.maxAdContentRating,
    this.tagForChildDirectedTreatment,
    this.tagForUnderAgeOfConsent,
    this.requestKeywords,
    this.verboseLogging = false,
    this.onEvent,
    this.onPaidEvent,
    this.onError,
  });

  /// Ad unit IDs per platform.
  final EasyAdUnitIds adUnitIds;

  /// Master switch. Set to `false` for paying users — every show and preload
  /// turns into a no-op, and no requests are sent.
  final bool enabled;

  /// Allows the cold start (splash) App Open ad.
  final bool appOpenColdStartEnabled;

  /// Allows the App Open ad when the app returns from the background.
  final bool appOpenResumeEnabled;

  /// Kill switch for interstitials.
  final bool interstitialEnabled;

  /// Kill switch for rewarded ads.
  final bool rewardedEnabled;

  /// Kill switch for rewarded interstitials.
  final bool rewardedInterstitialEnabled;

  /// Kill switch for banners.
  final bool bannerEnabled;

  /// How long a single load attempt may take before it is abandoned. The SDK
  /// itself has no timeout: without this a request on a dead network can stay
  /// pending indefinitely and block the retry loop.
  final Duration loadTimeout;

  /// How long to wait for `MobileAds.initialize()` before loading anyway.
  ///
  /// Waiting for initialization is what lets every mediation adapter bid on
  /// the first request, but a slow adapter must not hold the first impression
  /// hostage. Google publishes the same tradeoff as a "reduce first impression
  /// latency" snippet: race initialization against a five second timer and
  /// load when either finishes.
  final Duration sdkInitTimeout;

  /// How long a cached interstitial/rewarded ad stays usable.
  ///
  /// Google expires these roughly one hour after the request; the 50 minute
  /// default keeps a safety margin, because showing an expired ad fails at
  /// `show()` time — the worst possible moment.
  final Duration fullScreenAdTtl;

  /// How long a cached App Open ad stays usable.
  ///
  /// "App open ads will time out after four hours" — the 3h30m default keeps
  /// a margin. https://developers.google.com/admob/flutter/app-open
  final Duration appOpenAdTtl;

  /// How many extra attempts the background preloader makes after a no-fill.
  final int maxLoadRetries;

  /// First retry delay; doubles per attempt up to [maxRetryDelay].
  final Duration retryBaseDelay;

  /// Ceiling for the exponential retry backoff.
  final Duration maxRetryDelay;

  /// Minimum time between two App Open ads.
  ///
  /// AdMob publishes no numeric frequency rule for this format, so this is a
  /// UX/revenue tuning knob rather than a compliance one. Prefer enforcing it
  /// here over AdMob's dashboard frequency cap: a capped request comes back as
  /// a no-fill, whereas this gate never sends the request at all.
  final Duration appOpenCooldown;

  /// Minimum time between two interstitials. Defaults to zero: interstitials
  /// are usually gated by your own app flow.
  final Duration interstitialCooldown;

  /// How long after any other full screen ad closes the App Open ad stays
  /// suppressed.
  ///
  /// This exists because of a real trap: when a user taps an interstitial or
  /// rewarded ad, the app is backgrounded (Play Store/browser opens). On
  /// return, the SDK reports a foreground transition and a naive
  /// implementation shows an App Open ad right on top of the ad the user just
  /// came back from — which AdMob's placement policy prohibits.
  final Duration minGapAfterFullScreenAd;

  /// How long the splash screen may wait for the cold start App Open ad.
  ///
  /// The ad must fill time the user was already going to wait, not create new
  /// waiting. If the ad is not ready in time the show is cancelled outright —
  /// it must never appear once app content is visible.
  final Duration appOpenSplashMaxWait;

  /// Number of app sessions before the first App Open ad is allowed.
  ///
  /// Google's guidance: "Show your first app open ad after your users have
  /// used your app a few times." Requires a persistent [EasyAdsStore].
  final int appOpenMinSessions;

  /// Optional per-day cap for App Open ads. Requires a persistent
  /// [EasyAdsStore].
  final int? appOpenDailyCap;

  /// Optional per-day cap for interstitials. Requires a persistent
  /// [EasyAdsStore].
  final int? interstitialDailyCap;

  /// Requests a collapsible banner at most once per app session.
  ///
  /// Collapsible banners start expanded and cover content, so repeatedly
  /// re-expanding them across a session invites accidental clicks.
  final bool collapsibleBannerOncePerSession;

  /// Device IDs that should always receive test ads. Find yours in the device
  /// log after the first ad request.
  ///
  /// Ignored in release builds unless [allowTestDevicesInRelease] is set: a
  /// production device left on this list stops earning, and the reverse
  /// mistake — a developer clicking live ads — is invalid activity.
  final List<String> testDeviceIds;

  /// Applies [testDeviceIds] even in release builds. Only for a staged
  /// release-mode QA pass.
  final bool allowTestDevicesInRelease;

  /// Makes the UMP SDK treat the device as if it were in the EEA so the
  /// consent form can be tested. Debug builds only; requires the device to be
  /// listed in [testDeviceIds].
  final bool forceConsentDebugGeographyEea;

  /// Maximum content rating for served ads. Use the [MaxAdContentRating]
  /// constants (`MaxAdContentRating.g`, `.pg`, `.t`, `.ma`).
  final String? maxAdContentRating;

  /// COPPA tag — set it if your app is child-directed. Use the
  /// [TagForChildDirectedTreatment] constants.
  final int? tagForChildDirectedTreatment;

  /// GDPR under-age-of-consent tag. Use the [TagForUnderAgeOfConsent]
  /// constants.
  final int? tagForUnderAgeOfConsent;

  /// Keywords attached to every ad request, for contextual targeting.
  final List<String>? requestKeywords;

  /// Prints every lifecycle event with `debugPrint`. Debug builds only.
  final bool verboseLogging;

  /// Called for every lifecycle event — forward to analytics.
  final void Function(EasyAdEvent event)? onEvent;

  /// Called for every impression-level revenue event.
  final void Function(EasyAdRevenue revenue)? onPaidEvent;

  /// Called for every swallowed exception — forward to Crashlytics/Sentry.
  /// The package never rethrows: a broken ad must not crash the host app.
  final void Function(Object error, StackTrace stackTrace)? onError;

  /// Returns a copy with the given fields replaced.
  ///
  /// Pass `clearAppOpenDailyCap: true` (and friends) to reset a nullable
  /// field back to null, which `copyWith` alone cannot express.
  EasyAdsConfig copyWith({
    EasyAdUnitIds? adUnitIds,
    bool? enabled,
    bool? appOpenColdStartEnabled,
    bool? appOpenResumeEnabled,
    bool? interstitialEnabled,
    bool? rewardedEnabled,
    bool? rewardedInterstitialEnabled,
    bool? bannerEnabled,
    Duration? loadTimeout,
    Duration? sdkInitTimeout,
    Duration? fullScreenAdTtl,
    Duration? appOpenAdTtl,
    int? maxLoadRetries,
    Duration? retryBaseDelay,
    Duration? maxRetryDelay,
    Duration? appOpenCooldown,
    Duration? interstitialCooldown,
    Duration? minGapAfterFullScreenAd,
    Duration? appOpenSplashMaxWait,
    int? appOpenMinSessions,
    int? appOpenDailyCap,
    bool clearAppOpenDailyCap = false,
    int? interstitialDailyCap,
    bool clearInterstitialDailyCap = false,
    bool? collapsibleBannerOncePerSession,
    List<String>? testDeviceIds,
    bool? allowTestDevicesInRelease,
    bool? forceConsentDebugGeographyEea,
    String? maxAdContentRating,
    int? tagForChildDirectedTreatment,
    int? tagForUnderAgeOfConsent,
    List<String>? requestKeywords,
    bool? verboseLogging,
    void Function(EasyAdEvent event)? onEvent,
    void Function(EasyAdRevenue revenue)? onPaidEvent,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    return EasyAdsConfig(
      adUnitIds: adUnitIds ?? this.adUnitIds,
      enabled: enabled ?? this.enabled,
      appOpenColdStartEnabled:
          appOpenColdStartEnabled ?? this.appOpenColdStartEnabled,
      appOpenResumeEnabled: appOpenResumeEnabled ?? this.appOpenResumeEnabled,
      interstitialEnabled: interstitialEnabled ?? this.interstitialEnabled,
      rewardedEnabled: rewardedEnabled ?? this.rewardedEnabled,
      rewardedInterstitialEnabled:
          rewardedInterstitialEnabled ?? this.rewardedInterstitialEnabled,
      bannerEnabled: bannerEnabled ?? this.bannerEnabled,
      loadTimeout: loadTimeout ?? this.loadTimeout,
      sdkInitTimeout: sdkInitTimeout ?? this.sdkInitTimeout,
      fullScreenAdTtl: fullScreenAdTtl ?? this.fullScreenAdTtl,
      appOpenAdTtl: appOpenAdTtl ?? this.appOpenAdTtl,
      maxLoadRetries: maxLoadRetries ?? this.maxLoadRetries,
      retryBaseDelay: retryBaseDelay ?? this.retryBaseDelay,
      maxRetryDelay: maxRetryDelay ?? this.maxRetryDelay,
      appOpenCooldown: appOpenCooldown ?? this.appOpenCooldown,
      interstitialCooldown: interstitialCooldown ?? this.interstitialCooldown,
      minGapAfterFullScreenAd:
          minGapAfterFullScreenAd ?? this.minGapAfterFullScreenAd,
      appOpenSplashMaxWait: appOpenSplashMaxWait ?? this.appOpenSplashMaxWait,
      appOpenMinSessions: appOpenMinSessions ?? this.appOpenMinSessions,
      appOpenDailyCap: clearAppOpenDailyCap
          ? null
          : (appOpenDailyCap ?? this.appOpenDailyCap),
      interstitialDailyCap: clearInterstitialDailyCap
          ? null
          : (interstitialDailyCap ?? this.interstitialDailyCap),
      collapsibleBannerOncePerSession:
          collapsibleBannerOncePerSession ??
          this.collapsibleBannerOncePerSession,
      testDeviceIds: testDeviceIds ?? this.testDeviceIds,
      allowTestDevicesInRelease:
          allowTestDevicesInRelease ?? this.allowTestDevicesInRelease,
      forceConsentDebugGeographyEea:
          forceConsentDebugGeographyEea ?? this.forceConsentDebugGeographyEea,
      maxAdContentRating: maxAdContentRating ?? this.maxAdContentRating,
      tagForChildDirectedTreatment:
          tagForChildDirectedTreatment ?? this.tagForChildDirectedTreatment,
      tagForUnderAgeOfConsent:
          tagForUnderAgeOfConsent ?? this.tagForUnderAgeOfConsent,
      requestKeywords: requestKeywords ?? this.requestKeywords,
      verboseLogging: verboseLogging ?? this.verboseLogging,
      onEvent: onEvent ?? this.onEvent,
      onPaidEvent: onPaidEvent ?? this.onPaidEvent,
      onError: onError ?? this.onError,
    );
  }
}
