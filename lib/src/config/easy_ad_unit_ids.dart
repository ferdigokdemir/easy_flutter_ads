import 'dart:io';

/// Per-platform AdMob ad unit IDs.
///
/// Only the IDs for the platform the app is running on are ever used, so it is
/// safe to leave the other platform's IDs empty. An empty ID makes the
/// corresponding format a no-op instead of throwing — this is what lets you
/// ship a build with, say, no rewarded inventory yet.
class EasyAdUnitIds {
  /// Creates a set of ad unit IDs.
  const EasyAdUnitIds({
    this.appOpenAndroid = '',
    this.appOpenIos = '',
    this.interstitialAndroid = '',
    this.interstitialIos = '',
    this.rewardedAndroid = '',
    this.rewardedIos = '',
    this.rewardedInterstitialAndroid = '',
    this.rewardedInterstitialIos = '',
    this.bannerAndroid = '',
    this.bannerIos = '',
  });

  /// Google's official test ad unit IDs.
  ///
  /// Use these while developing. Never ship them: they earn nothing and
  /// clicking live ads on a development device can get the account flagged.
  /// See https://developers.google.com/admob/flutter/test-ads
  const EasyAdUnitIds.test()
    : appOpenAndroid = 'ca-app-pub-3940256099942544/9257395921',
      appOpenIos = 'ca-app-pub-3940256099942544/5575463023',
      interstitialAndroid = 'ca-app-pub-3940256099942544/1033173712',
      interstitialIos = 'ca-app-pub-3940256099942544/4411468910',
      rewardedAndroid = 'ca-app-pub-3940256099942544/5224354917',
      rewardedIos = 'ca-app-pub-3940256099942544/1712485313',
      rewardedInterstitialAndroid = 'ca-app-pub-3940256099942544/5354046379',
      rewardedInterstitialIos = 'ca-app-pub-3940256099942544/6978759866',
      bannerAndroid = 'ca-app-pub-3940256099942544/6300978111',
      bannerIos = 'ca-app-pub-3940256099942544/2934735716';

  /// Android App Open ad unit ID.
  final String appOpenAndroid;

  /// iOS App Open ad unit ID.
  final String appOpenIos;

  /// Android interstitial ad unit ID.
  final String interstitialAndroid;

  /// iOS interstitial ad unit ID.
  final String interstitialIos;

  /// Android rewarded ad unit ID.
  final String rewardedAndroid;

  /// iOS rewarded ad unit ID.
  final String rewardedIos;

  /// Android rewarded interstitial ad unit ID.
  final String rewardedInterstitialAndroid;

  /// iOS rewarded interstitial ad unit ID.
  final String rewardedInterstitialIos;

  /// Android banner ad unit ID (the default for [EasyBannerAd]).
  final String bannerAndroid;

  /// iOS banner ad unit ID (the default for [EasyBannerAd]).
  final String bannerIos;

  bool get _isIos => Platform.isIOS;

  /// App Open ad unit ID for the current platform.
  String get appOpen => _isIos ? appOpenIos : appOpenAndroid;

  /// Interstitial ad unit ID for the current platform.
  String get interstitial => _isIos ? interstitialIos : interstitialAndroid;

  /// Rewarded ad unit ID for the current platform.
  String get rewarded => _isIos ? rewardedIos : rewardedAndroid;

  /// Rewarded interstitial ad unit ID for the current platform.
  String get rewardedInterstitial =>
      _isIos ? rewardedInterstitialIos : rewardedInterstitialAndroid;

  /// Banner ad unit ID for the current platform.
  String get banner => _isIos ? bannerIos : bannerAndroid;

  /// Returns a copy with the given fields replaced.
  EasyAdUnitIds copyWith({
    String? appOpenAndroid,
    String? appOpenIos,
    String? interstitialAndroid,
    String? interstitialIos,
    String? rewardedAndroid,
    String? rewardedIos,
    String? rewardedInterstitialAndroid,
    String? rewardedInterstitialIos,
    String? bannerAndroid,
    String? bannerIos,
  }) {
    return EasyAdUnitIds(
      appOpenAndroid: appOpenAndroid ?? this.appOpenAndroid,
      appOpenIos: appOpenIos ?? this.appOpenIos,
      interstitialAndroid: interstitialAndroid ?? this.interstitialAndroid,
      interstitialIos: interstitialIos ?? this.interstitialIos,
      rewardedAndroid: rewardedAndroid ?? this.rewardedAndroid,
      rewardedIos: rewardedIos ?? this.rewardedIos,
      rewardedInterstitialAndroid:
          rewardedInterstitialAndroid ?? this.rewardedInterstitialAndroid,
      rewardedInterstitialIos:
          rewardedInterstitialIos ?? this.rewardedInterstitialIos,
      bannerAndroid: bannerAndroid ?? this.bannerAndroid,
      bannerIos: bannerIos ?? this.bannerIos,
    );
  }
}
