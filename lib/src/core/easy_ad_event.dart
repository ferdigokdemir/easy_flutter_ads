/// The ad formats managed by this package.
enum EasyAdFormat {
  /// App Open ad.
  appOpen,

  /// Interstitial ad.
  interstitial,

  /// Rewarded ad.
  rewarded,

  /// Rewarded interstitial ad.
  rewardedInterstitial,

  /// Banner ad ([EasyBannerAd]).
  banner,
}

/// What happened to an ad.
enum EasyAdEventType {
  /// A load request was sent to the SDK.
  loadStarted,

  /// The ad object finished loading and is now cached.
  loaded,

  /// The load request failed or timed out.
  loadFailed,

  /// [Ad.show] was called.
  showStarted,

  /// The ad rendered full screen (or the banner rendered on screen).
  impression,

  /// The user clicked the ad.
  clicked,

  /// The user dismissed the ad and returned to the app.
  dismissed,

  /// The ad failed to render after [Ad.show].
  showFailed,

  /// The user earned the reward of a rewarded (interstitial) ad.
  rewardEarned,

  /// A show was requested but a policy or configuration gate blocked it.
  /// See [EasyAdEvent.skipReason].
  skipped,
}

/// Why a show request was skipped.
enum EasyAdSkipReason {
  /// Ads are globally disabled ([EasyAdsConfig.enabled] is false — e.g. the
  /// user is a paying subscriber).
  adsDisabled,

  /// This format's kill switch is off.
  formatDisabled,

  /// No ad unit ID is configured for this format on this platform.
  noAdUnitId,

  /// The SDK failed to initialize.
  notInitialized,

  /// UMP reports that the user has not given the consent needed to request
  /// ads. Requesting anyway would be a GDPR/DMA problem, not just a policy
  /// one.
  consentNotGranted,

  /// An ad of this format is already on screen.
  alreadyShowing,

  /// Another full screen ad is on screen, or one closed moments ago. Showing
  /// here would violate AdMob's "no ads immediately before or after other ads"
  /// placement rule.
  adjacentToAnotherAd,

  /// The per-format cooldown has not elapsed yet.
  cooldown,

  /// The per-day cap for this format has been reached.
  dailyCapReached,

  /// The user has not opened the app enough times yet
  /// ([EasyAdsConfig.appOpenMinSessions]).
  sessionThreshold,

  /// No cached ad was available and the caller opted out of loading, or the
  /// load did not finish within the allowed wait.
  notReady,
}

/// A lifecycle event emitted by the package.
///
/// Forward these to your analytics pipeline to see, per format, how often ads
/// load, fail, render and get skipped — the numbers AdMob's dashboard cannot
/// show you because they never left the device.
class EasyAdEvent {
  /// Creates an event.
  const EasyAdEvent({
    required this.format,
    required this.type,
    this.adUnitId,
    this.message,
    this.errorCode,
    this.skipReason,
  });

  /// The format the event belongs to.
  final EasyAdFormat format;

  /// What happened.
  final EasyAdEventType type;

  /// The ad unit involved, when known.
  final String? adUnitId;

  /// Human readable detail (SDK error message, skip explanation).
  final String? message;

  /// The AdMob error code for load/show failures, when available.
  final int? errorCode;

  /// Set when [type] is [EasyAdEventType.skipped].
  final EasyAdSkipReason? skipReason;

  @override
  String toString() {
    final buffer = StringBuffer('${format.name}.${type.name}');
    if (skipReason != null) buffer.write(' (${skipReason!.name})');
    if (errorCode != null) buffer.write(' code=$errorCode');
    if (message != null) buffer.write(' — $message');
    return buffer.toString();
  }
}

/// Impression-level ad revenue, reported by the SDK's paid event callback.
///
/// Wire [EasyAdsConfig.onPaidEvent] to forward this to Firebase Analytics,
/// AppsFlyer or Adjust. Without it you cannot compute real per-user LTV.
/// See https://developers.google.com/admob/flutter/impression-level-ad-revenue
class EasyAdRevenue {
  /// Creates a revenue record.
  const EasyAdRevenue({
    required this.format,
    required this.adUnitId,
    required this.valueMicros,
    required this.currencyCode,
    required this.precision,
  });

  /// The format that earned the revenue.
  final EasyAdFormat format;

  /// The ad unit that earned the revenue.
  final String adUnitId;

  /// Revenue in micros: divide by 1,000,000 to get [currencyCode] units.
  final int valueMicros;

  /// ISO-4217 currency code of [valueMicros].
  final String currencyCode;

  /// How precise the estimate is (unknown / estimated / publisher provided /
  /// precise).
  final int precision;

  /// [valueMicros] converted to whole currency units.
  double get value => valueMicros / 1000000;

  @override
  String toString() =>
      'EasyAdRevenue(${format.name}, $value $currencyCode, precision=$precision)';
}
